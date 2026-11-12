import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { randomBytes, randomUUID } from 'node:crypto';
import type { Redis } from 'ioredis';
import { appendAudit, Db, isUniqueViolation, type Queryable } from '../infra/database.js';
import { REDIS } from '../infra/redis.js';
import {
  ACCESS_TOKEN_TTL_SECONDS,
  CHALLENGE_TTL_SECONDS,
  OTP_TOKEN_TTL_SECONDS,
  PIN_LOCK_MINUTES,
  PIN_MAX_ATTEMPTS,
} from './auth.constants.js';
import { challengeMessage, parseEd25519PublicKey, verifyDeviceSignature } from './device-key.js';
import { type Language } from '../infra/languages.js';
import { OtpService } from './otp.service.js';
import { hashPin, pinWeakness, verifyPin } from './pin.js';

export interface Session {
  userId: string;
  deviceId: string;
  accessToken: string;
  expiresIn: number;
}

export interface OtpTokenClaims {
  typ: 'otp';
  phone: string;
  jti: string;
}

export interface AccessTokenClaims {
  typ: 'access';
  sub: string;
  did: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly db: Db,
    private readonly otp: OtpService,
    private readonly jwt: JwtService,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  requestOtp(phone: string, ip: string) {
    return this.otp.request(phone, ip);
  }

  async verifyOtp(phone: string, code: string) {
    if (!(await this.otp.verify(phone, code))) {
      throw new UnauthorizedException('Code invalide ou expiré.');
    }
    const { rowCount } = await this.db.query('SELECT 1 FROM users WHERE phone = $1', [phone]);
    const claims: OtpTokenClaims = { typ: 'otp', phone, jti: randomUUID() };
    const otpToken = await this.jwt.signAsync(claims, { expiresIn: OTP_TOKEN_TTL_SECONDS });
    return { otpToken, accountExists: rowCount === 1 };
  }

  /** Nouveau compte : numéro prouvé par le code SMS, PIN choisi, appareil enregistré. */
  async register(input: {
    otpToken: string;
    fullName: string;
    pin: string;
    devicePublicKey: string;
    language: Language;
  }): Promise<Session> {
    const claims = await this.readOtpToken(input.otpToken);
    this.assertPinAcceptable(input.pin);
    this.assertPublicKey(input.devicePublicKey);
    const pinHash = await hashPin(input.pin);
    await this.consumeOtpToken(claims);

    const ids = await this.db
      .transaction({ type: 'system' }, async (q) => {
        const user = await q.query<{ id: string }>(
          `INSERT INTO users (phone, full_name, pin_hash, language) VALUES ($1, $2, $3, $4)
           ON CONFLICT (phone) DO NOTHING RETURNING id`,
          [claims.phone, input.fullName, pinHash, input.language],
        );
        if (user.rowCount !== 1) {
          throw new ConflictException('Un compte existe déjà pour ce numéro.');
        }
        const userId = user.rows[0].id;
        const deviceId = await this.insertDevice(q, userId, input.devicePublicKey);
        await appendAudit(q, {
          groupId: null,
          actor: { type: 'user', id: userId, deviceId },
          action: 'auth.user_registered',
          payload: { user_id: userId, device_id: deviceId },
        });
        return { userId, deviceId };
      })
      .catch((e: unknown) => this.rethrowDeviceConflict(e));

    return this.issueSession(ids.userId, ids.deviceId);
  }

  /**
   * Compte existant sur un nouveau téléphone : code SMS ET PIN. Un vol de carte SIM
   * seul ne suffit pas. L'ancien appareil est révoqué, et c'est journalisé.
   */
  async linkDevice(input: { otpToken: string; pin: string; devicePublicKey: string }) {
    const claims = await this.readOtpToken(input.otpToken);
    this.assertPublicKey(input.devicePublicKey);

    const outcome = await this.db
      .transaction({ type: 'system' }, async (q) => {
        const found = await q.query<{
          id: string;
          pin_hash: string;
          pin_failed_attempts: number;
          locked: boolean;
          pin_locked_until: Date | null;
          is_blocked: boolean;
        }>(
          `SELECT id, pin_hash, pin_failed_attempts, pin_locked_until, is_blocked,
                  coalesce(pin_locked_until > now(), false) AS locked
           FROM users WHERE phone = $1 FOR UPDATE`,
          [claims.phone],
        );
        const user = found.rows[0];
        if (!user) return { kind: 'no_account' as const };
        if (user.is_blocked) return { kind: 'blocked' as const };
        if (user.locked) return { kind: 'locked' as const, until: user.pin_locked_until! };

        if (!(await verifyPin(user.pin_hash, input.pin))) {
          const attempts = user.pin_failed_attempts + 1;
          if (attempts < PIN_MAX_ATTEMPTS) {
            await q.query('UPDATE users SET pin_failed_attempts = $2 WHERE id = $1', [
              user.id,
              attempts,
            ]);
            return { kind: 'wrong_pin' as const, remaining: PIN_MAX_ATTEMPTS - attempts };
          }
          const locked = await q.query<{ pin_locked_until: Date }>(
            `UPDATE users SET pin_failed_attempts = 0,
                    pin_locked_until = now() + make_interval(mins => $2)
             WHERE id = $1 RETURNING pin_locked_until`,
            [user.id, PIN_LOCK_MINUTES],
          );
          await appendAudit(q, {
            groupId: null,
            actor: { type: 'system' },
            action: 'auth.pin_locked',
            payload: { user_id: user.id, minutes: PIN_LOCK_MINUTES },
          });
          return { kind: 'locked' as const, until: locked.rows[0].pin_locked_until };
        }

        await this.consumeOtpToken(claims);
        await q.query('UPDATE users SET pin_failed_attempts = 0 WHERE id = $1', [user.id]);
        const revoked = await q.query<{ id: string }>(
          `UPDATE devices SET revoked_at = now()
           WHERE user_id = $1 AND revoked_at IS NULL RETURNING id`,
          [user.id],
        );
        const deviceId = await this.insertDevice(q, user.id, input.devicePublicKey);
        await appendAudit(q, {
          groupId: null,
          actor: { type: 'user', id: user.id, deviceId },
          action: 'auth.device_linked',
          payload: {
            user_id: user.id,
            device_id: deviceId,
            revoked_device_ids: revoked.rows.map((r) => r.id),
          },
        });
        return { kind: 'linked' as const, userId: user.id, deviceId };
      })
      .catch((e: unknown) => this.rethrowDeviceConflict(e));

    // Les échecs sont enregistrés (transaction validée) avant de répondre par une erreur.
    switch (outcome.kind) {
      case 'linked':
        return this.issueSession(outcome.userId, outcome.deviceId);
      case 'no_account':
        throw new NotFoundException('Aucun compte pour ce numéro. Inscrivez-vous.');
      case 'blocked':
        throw new ForbiddenException('Ce compte est bloqué. Contactez le support Mchango.');
      case 'wrong_pin':
        throw new UnauthorizedException(
          `PIN incorrect. Il vous reste ${outcome.remaining} essai(s).`,
        );
      case 'locked':
        throw new HttpException(
          {
            message: `PIN bloqué après trop d'essais. Réessayez après ${outcome.until.toISOString()}.`,
            lockedUntil: outcome.until.toISOString(),
          },
          HttpStatus.LOCKED,
        );
    }
  }

  /** Défi à signer par l'appareil. Ne révèle pas si l'appareil existe. */
  async createChallenge(deviceId: string) {
    const nonce = randomBytes(32).toString('base64url');
    await this.redis.set(this.challengeKey(nonce), deviceId, 'EX', CHALLENGE_TTL_SECONDS);
    return { nonce, expiresIn: CHALLENGE_TTL_SECONDS };
  }

  /** Ouvre une session si l'appareil a signé le défi avec sa clé privée. */
  async openSession(input: { deviceId: string; nonce: string; signature: string }) {
    const refused = new UnauthorizedException('Appareil non reconnu. Reconnectez-vous avec un code SMS.');
    // getdel : un défi ne sert qu'une fois, même en cas de requêtes concurrentes
    const challengedDevice = await this.redis.getdel(this.challengeKey(input.nonce));
    if (challengedDevice !== input.deviceId) throw refused;

    const found = await this.db.query<{ user_id: string; public_key: string; is_blocked: boolean }>(
      `SELECT d.user_id, d.public_key, u.is_blocked
       FROM devices d JOIN users u ON u.id = d.user_id
       WHERE d.id = $1 AND d.revoked_at IS NULL`,
      [input.deviceId],
    );
    const device = found.rows[0];
    if (
      !device ||
      !verifyDeviceSignature(
        device.public_key,
        challengeMessage(input.deviceId, input.nonce),
        input.signature,
      )
    ) {
      throw refused;
    }
    if (device.is_blocked) {
      throw new ForbiddenException('Ce compte est bloqué. Contactez le support Mchango.');
    }
    await this.db.query('UPDATE devices SET last_seen_at = now() WHERE id = $1', [input.deviceId]);
    return this.issueSession(device.user_id, input.deviceId);
  }

  async verifyAccessToken(token: string): Promise<AccessTokenClaims> {
    const claims = await this.jwt
      .verifyAsync<AccessTokenClaims>(token, { algorithms: ['HS256'] })
      .catch(() => null);
    if (claims?.typ !== 'access') throw new UnauthorizedException('Session expirée.');
    return claims;
  }

  async issueSession(userId: string, deviceId: string): Promise<Session> {
    const claims: AccessTokenClaims = { typ: 'access', sub: userId, did: deviceId };
    const accessToken = await this.jwt.signAsync(claims, { expiresIn: ACCESS_TOKEN_TTL_SECONDS });
    return { userId, deviceId, accessToken, expiresIn: ACCESS_TOKEN_TTL_SECONDS };
  }

  async readOtpToken(token: string): Promise<OtpTokenClaims> {
    const claims = await this.jwt
      .verifyAsync<OtpTokenClaims>(token, { algorithms: ['HS256'] })
      .catch(() => null);
    if (claims?.typ !== 'otp') {
      throw new UnauthorizedException('Vérification du numéro expirée. Demandez un nouveau code.');
    }
    return claims;
  }

  /** À n'appeler qu'une fois toutes les vérifications passées : le jeton ne resservira pas. */
  async consumeOtpToken(claims: OtpTokenClaims) {
    const first = await this.redis.set(
      `otp:token-used:${claims.jti}`,
      '1',
      'EX',
      OTP_TOKEN_TTL_SECONDS,
      'NX',
    );
    if (first !== 'OK') {
      throw new UnauthorizedException('Vérification du numéro déjà utilisée. Demandez un nouveau code.');
    }
  }

  assertPinAcceptable(pin: string) {
    const weakness = pinWeakness(pin);
    if (weakness) throw new BadRequestException(weakness);
  }

  assertPublicKey(publicKey: string) {
    if (!parseEd25519PublicKey(publicKey)) {
      throw new BadRequestException("Clé publique de l'appareil invalide (Ed25519, 32 octets, base64).");
    }
  }

  async insertDevice(
    q: Queryable,
    userId: string,
    publicKey: string,
  ): Promise<string> {
    const device = await q.query<{ id: string }>(
      'INSERT INTO devices (user_id, public_key) VALUES ($1, $2) RETURNING id',
      [userId, publicKey],
    );
    return device.rows[0].id;
  }

  rethrowDeviceConflict(e: unknown): never {
    if (isUniqueViolation(e, 'devices_public_key_unique')) {
      throw new ConflictException('Cette clé est déjà liée à un appareil.');
    }
    throw e;
  }

  private challengeKey(nonce: string) {
    return `auth:challenge:${nonce}`;
  }
}
