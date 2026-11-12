import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { appendAudit, Db, type Queryable } from '../infra/database.js';
import { SMS_SENDER, type SmsSender } from '../infra/sms.js';
import { toGsm7 } from '../infra/sms-text.js';
import { AuthService } from './auth.service.js';
import { hashPin } from './pin.js';

/** Une demande sans réponse expire au bout de ce délai. */
export const PIN_RESET_TTL_HOURS = 48;

/** Garants prévenus par SMS au plus (évite d'arroser un grand groupe). */
const MAX_GUARANTORS_NOTIFIED = 3;

export interface Guarantor {
  userId: string;
  fullName: string;
  phone: string;
  groupId: string;
  groupName: string;
}

/**
 * Garants possibles d'un utilisateur : dans chaque tontine en préparation ou en cours où il
 * est membre actif, le président ; et s'il est lui-même président, les autres membres.
 */
const GUARANTORS_SQL = `
  SELECT DISTINCT ON (au.id) au.id AS user_id, au.full_name, au.phone, g.id AS group_id, g.name AS group_name,
         am.role = 'president' AS is_president
  FROM memberships rm
  JOIN groups g ON g.id = rm.group_id AND g.status IN ('draft', 'active')
  JOIN memberships am ON am.group_id = g.id AND am.status = 'active' AND am.user_id <> rm.user_id
  JOIN users au ON au.id = am.user_id AND NOT au.is_blocked
  WHERE rm.user_id = $1 AND rm.status = 'active'
    AND (am.role = 'president' OR rm.role = 'president')`;

type RequestRow = {
  id: string;
  user_id: string;
  new_pin_hash: string;
  device_public_key: string;
  status: 'pending' | 'completed' | 'rejected' | 'cancelled';
  expired: boolean;
  expires_at: Date;
  device_id: string | null;
};

const REQUEST_COLUMNS = `id, user_id, new_pin_hash, device_public_key, status, expires_at, device_id,
  (status = 'pending' AND expires_at <= now()) AS expired`;

/**
 * « PIN oublié ». Le code SMS seul ne suffit jamais quand de l'argent circule : un vol de carte
 * SIM donnerait le compte. Un garant qui connaît le demandeur doit confirmer (spec/pin-reset.md).
 */
@Injectable()
export class PinResetService {
  private readonly logger = new Logger('PinOublie');

  constructor(
    private readonly db: Db,
    private readonly auth: AuthService,
    @Inject(SMS_SENDER) private readonly sms: SmsSender,
  ) {}

  /** Demande : numéro vérifié par code SMS, nouveau PIN, clé du téléphone à lier. */
  async request(input: { otpToken: string; newPin: string; devicePublicKey: string }) {
    const claims = await this.auth.readOtpToken(input.otpToken);
    this.auth.assertPinAcceptable(input.newPin);
    this.auth.assertPublicKey(input.devicePublicKey);
    const user = await this.db.query<{ id: string; full_name: string; is_blocked: boolean }>(
      'SELECT id, full_name, is_blocked FROM users WHERE phone = $1',
      [claims.phone],
    );
    const u = user.rows[0];
    if (!u) throw new NotFoundException('Aucun compte pour ce numéro. Inscrivez-vous.');
    if (u.is_blocked) throw new ForbiddenException('Ce compte est bloqué. Contactez le support Mchango.');
    const pinHash = await hashPin(input.newPin);
    await this.auth.consumeOtpToken(claims);

    const guarantors = await this.guarantorsOf(this.db, u.id);
    const result = await this.db
      .transaction({ type: 'user', id: u.id }, async (q) => {
        // Une nouvelle demande remplace l'ancienne
        await q.query(`UPDATE pin_reset_requests SET status = 'cancelled' WHERE user_id = $1 AND status = 'pending'`, [
          u.id,
        ]);
        const created = await q.query<{ id: string; expires_at: Date }>(
          `INSERT INTO pin_reset_requests (user_id, new_pin_hash, device_public_key, expires_at)
           VALUES ($1, $2, $3, now() + make_interval(hours => $4)) RETURNING id, expires_at`,
          [u.id, pinHash, input.devicePublicKey, PIN_RESET_TTL_HOURS],
        );
        const requestId = created.rows[0].id;
        await appendAudit(q, {
          groupId: null,
          actor: { type: 'user', id: u.id },
          action: 'auth.pin_reset_requested',
          payload: { request_id: requestId, user_id: u.id, guarantors: guarantors.length },
        });
        // Aucune tontine en préparation ou en cours : rien à protéger, le code SMS suffit
        if (guarantors.length === 0) {
          const deviceId = await this.complete(q, requestId, u.id, pinHash, input.devicePublicKey, null);
          return { requestId, expiresAt: created.rows[0].expires_at, deviceId };
        }
        return { requestId, expiresAt: created.rows[0].expires_at, deviceId: null };
      })
      .catch((e: unknown) => this.auth.rethrowDeviceConflict(e));

    if (result.deviceId) {
      return { requestId: result.requestId, status: 'completed' as const, ...(await this.auth.issueSession(u.id, result.deviceId)) };
    }
    await this.notifyGuarantors(u.full_name, guarantors);
    return {
      requestId: result.requestId,
      status: 'pending' as const,
      expiresAt: result.expiresAt.toISOString(),
      guarantors: guarantors.map((g) => ({ fullName: g.fullName, groupName: g.groupName })),
    };
  }

  /**
   * Où en est la demande. L'identifiant (UUID aléatoire, connu du seul téléphone demandeur) suffit :
   * la réponse ne contient rien de secret. Une fois acceptée, le téléphone ouvre sa session avec
   * sa clé (défi signé), comme d'habitude.
   */
  async status(requestId: string) {
    const r = await this.findRequest(this.db, requestId);
    if (!r) throw new NotFoundException('Demande introuvable.');
    const status = r.expired ? 'expired' : r.status;
    return {
      status,
      expiresAt: r.expires_at.toISOString(),
      deviceId: r.status === 'completed' ? r.device_id : null,
      guarantors:
        status === 'pending'
          ? (await this.guarantorsOf(this.db, r.user_id)).map((g) => ({ fullName: g.fullName, groupName: g.groupName }))
          : [],
    };
  }

  /** Demandes que cet utilisateur peut confirmer en tant que garant. */
  async pendingFor(approverId: string) {
    const { rows } = await this.db.query<{
      id: string;
      full_name: string;
      phone: string;
      created_at: Date;
      expires_at: Date;
      group_name: string;
    }>(
      `SELECT DISTINCT ON (r.id) r.id, u.full_name, u.phone, r.created_at, r.expires_at, g.name AS group_name
       FROM pin_reset_requests r
       JOIN users u ON u.id = r.user_id
       JOIN memberships rm ON rm.user_id = r.user_id AND rm.status = 'active'
       JOIN groups g ON g.id = rm.group_id AND g.status IN ('draft', 'active')
       JOIN memberships am ON am.group_id = g.id AND am.status = 'active' AND am.user_id = $1
       WHERE r.status = 'pending' AND r.expires_at > now() AND r.user_id <> $1
         AND (am.role = 'president' OR rm.role = 'president')
       ORDER BY r.id, r.created_at`,
      [approverId],
    );
    return rows.map((r) => ({
      requestId: r.id,
      fullName: r.full_name,
      phone: r.phone,
      groupName: r.group_name,
      createdAt: r.created_at.toISOString(),
      expiresAt: r.expires_at.toISOString(),
    }));
  }

  /** Le garant confirme : nouveau PIN actif, anciens téléphones déconnectés, journal du groupe. */
  async approve(approverId: string, requestId: string) {
    return this.db
      .transaction({ type: 'user', id: approverId }, async (q) => {
        const { r, guarantor } = await this.lockForGuarantor(q, approverId, requestId);
        await this.complete(q, r.id, r.user_id, r.new_pin_hash, r.device_public_key, { type: 'user', id: approverId });
        // Visible de tout le groupe du garant : personne ne change de PIN en cachette
        await appendAudit(q, {
          groupId: guarantor.groupId,
          actor: { type: 'user', id: approverId },
          action: 'auth.pin_reset_approved',
          payload: { request_id: r.id, user_id: r.user_id },
        });
        return { status: 'completed' as const };
      })
      .catch((e: unknown) => this.auth.rethrowDeviceConflict(e));
  }

  /**
   * Recours quand aucun garant ne répond : l'équipe valide APRÈS avoir vérifié l'identité
   * (appel au numéro + questions sur ses tontines, pièce d'identité…). Le motif décrit la
   * vérification faite ; il est inscrit au journal. Rôle conformité ou super admin (contrôlé par l'API).
   */
  async approveByStaff(staffId: string, requestId: string, note: string) {
    if (note.trim().length < 15) {
      throw new BadRequestException("Décrivez la vérification d'identité effectuée (au moins une phrase).");
    }
    return this.db
      .transaction({ type: 'staff', id: staffId }, async (q) => {
        const found = await q.query<RequestRow>(
          `SELECT ${REQUEST_COLUMNS} FROM pin_reset_requests WHERE id = $1 FOR UPDATE`,
          [requestId],
        );
        const r = found.rows[0];
        if (!r) throw new NotFoundException('Demande introuvable.');
        if (r.status !== 'pending' || r.expired) {
          throw new ConflictException('Cette demande est déjà traitée ou a expiré.');
        }
        await q.query('UPDATE pin_reset_requests SET staff_note = $2 WHERE id = $1', [r.id, note.trim()]);
        await this.complete(q, r.id, r.user_id, r.new_pin_hash, r.device_public_key, { type: 'staff', id: staffId });
        // Visible des tontines du demandeur : personne ne change de PIN en cachette, même par l'équipe
        const groups = await q.query<{ group_id: string }>(
          `SELECT DISTINCT m.group_id FROM memberships m JOIN groups g ON g.id = m.group_id
           WHERE m.user_id = $1 AND m.status = 'active' AND g.status IN ('draft', 'active', 'suspended')`,
          [r.user_id],
        );
        for (const g of groups.rows) {
          await appendAudit(q, {
            groupId: g.group_id,
            actor: { type: 'staff', id: staffId },
            action: 'staff.pin_reset_approved',
            payload: { request_id: r.id, user_id: r.user_id },
          });
        }
        return { status: 'completed' as const };
      })
      .catch((e: unknown) => this.auth.rethrowDeviceConflict(e));
  }

  async reject(approverId: string, requestId: string) {
    return this.db.transaction({ type: 'user', id: approverId }, async (q) => {
      const { r, guarantor } = await this.lockForGuarantor(q, approverId, requestId);
      await q.query(
        `UPDATE pin_reset_requests SET status = 'rejected', decided_by = $2, decided_at = now() WHERE id = $1`,
        [r.id, approverId],
      );
      await appendAudit(q, {
        groupId: guarantor.groupId,
        actor: { type: 'user', id: approverId },
        action: 'auth.pin_reset_rejected',
        payload: { request_id: r.id, user_id: r.user_id },
      });
      return { status: 'rejected' as const };
    });
  }

  private async lockForGuarantor(q: Queryable, approverId: string, requestId: string) {
    const found = await q.query<RequestRow>(
      `SELECT ${REQUEST_COLUMNS} FROM pin_reset_requests WHERE id = $1 FOR UPDATE`,
      [requestId],
    );
    const r = found.rows[0];
    const guarantor = r ? (await this.guarantorsOf(q, r.user_id)).find((g) => g.userId === approverId) : undefined;
    // 404 aussi pour qui n'est pas garant : ne pas révéler les demandes des autres
    if (!r || !guarantor) throw new NotFoundException('Demande introuvable.');
    if (r.status !== 'pending' || r.expired) {
      throw new ConflictException('Cette demande est déjà traitée ou a expiré.');
    }
    return { r, guarantor };
  }

  private async complete(
    q: Queryable,
    requestId: string,
    userId: string,
    pinHash: string,
    publicKey: string,
    approver: { type: 'user' | 'staff'; id: string } | null,
  ): Promise<string> {
    await q.query(
      'UPDATE users SET pin_hash = $2, pin_failed_attempts = 0, pin_locked_until = NULL WHERE id = $1',
      [userId, pinHash],
    );
    const revoked = await q.query<{ id: string }>(
      'UPDATE devices SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL RETURNING id',
      [userId],
    );
    const deviceId = await this.auth.insertDevice(q, userId, publicKey);
    await q.query(
      `UPDATE pin_reset_requests SET status = 'completed', device_id = $2, decided_by = $3, decided_by_staff = $4,
              decided_at = now()
       WHERE id = $1`,
      [requestId, deviceId, approver?.type === 'user' ? approver.id : null, approver?.type === 'staff' ? approver.id : null],
    );
    await appendAudit(q, {
      groupId: null,
      actor: approver ?? { type: 'user', id: userId },
      action: 'auth.pin_reset_completed',
      payload: {
        request_id: requestId,
        user_id: userId,
        device_id: deviceId,
        revoked_device_ids: revoked.rows.map((d) => d.id),
        approved_by: approver ? `${approver.type}:${approver.id}` : null,
      },
    });
    return deviceId;
  }

  private async findRequest(q: Queryable, requestId: string): Promise<RequestRow | undefined> {
    const { rows } = await q.query<RequestRow>(`SELECT ${REQUEST_COLUMNS} FROM pin_reset_requests WHERE id = $1`, [
      requestId,
    ]);
    return rows[0];
  }

  private async guarantorsOf(q: Queryable, userId: string): Promise<Guarantor[]> {
    const { rows } = await q.query<{
      user_id: string;
      full_name: string;
      phone: string;
      group_id: string;
      group_name: string;
      is_president: boolean;
    }>(`SELECT * FROM (${GUARANTORS_SQL}) x ORDER BY is_president DESC, full_name`, [userId]);
    return rows.map((r) => ({
      userId: r.user_id,
      fullName: r.full_name,
      phone: r.phone,
      groupId: r.group_id,
      groupName: r.group_name,
    }));
  }

  /** Prévient les garants sur LEUR numéro : un voleur de carte SIM ne contrôle pas ces numéros-là. */
  private async notifyGuarantors(requesterName: string, guarantors: Guarantor[]) {
    for (const g of guarantors.slice(0, MAX_GUARANTORS_NOTIFIED)) {
      const message = toGsm7(
        `Mchango : ${requesterName.slice(0, 20)} demande un nouveau PIN. Confirmez dans l'app seulement ` +
          `si vous lui avez parlé de vive voix.`,
      );
      await this.sms.send(g.phone, message).catch((e: unknown) => {
        this.logger.warn(`SMS au garant impossible : ${String(e)}`);
      });
    }
  }
}
