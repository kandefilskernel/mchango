import { randomBytes } from 'node:crypto';
import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { z } from 'zod';
import { Db, type Actor } from '../infra/database.js';
import { hashToken } from './orders.service.js';
import { rows, toApi } from './sql.js';

const token = z.string().min(16).max(200);

export const createShareSchema = z.discriminatedUnion('channel', [
  z.strictObject({ channel: z.literal('whatsapp'), parentToken: token.optional() }),
  z.strictObject({ channel: z.literal('group'), groupId: z.uuid(), parentToken: token.optional() }),
]);
export type CreateShareInput = z.infer<typeof createShareSchema>;

@Injectable()
export class SharesService {
  constructor(private readonly db: Db) {}

  /**
   * Enregistre un partage. Ne touche à aucun compteur : inviter n'est pas commander.
   * WhatsApp : renvoie un jeton à mettre dans le lien (seul son hash est stocké).
   * Groupe : l'offre apparaît dans les « Achats proposés » du groupe.
   */
  async create(actor: Actor, userId: string, offerId: string, input: CreateShareInput) {
    const linkToken = input.channel === 'whatsapp' ? randomBytes(24).toString('base64url') : null;

    const id = await this.db.transaction(actor, async (q) => {
      // Origine : un jeton parent inconnu est ignoré plutôt que de bloquer le partage.
      const [parent] = input.parentToken
        ? await rows<{ id: string }>(q, 'SELECT id FROM shares WHERE token_hash = $1 AND offer_id = $2', [
            hashToken(input.parentToken),
            offerId,
          ])
        : [];
      const [share] = await rows<{ id: string }>(
        q,
        `INSERT INTO shares (offer_id, parent_share_id, shared_by_user_id, channel, group_id, token_hash)
         SELECT o.id, $2::uuid, $3::uuid, $4::share_channel, $5::uuid, $6::char(64)
         FROM offers o WHERE o.id = $1
         RETURNING id`,
        [
          offerId,
          parent?.id ?? null,
          userId,
          input.channel,
          input.channel === 'group' ? input.groupId : null,
          linkToken ? hashToken(linkToken) : null,
        ],
      );
      if (!share) throw new NotFoundException('Offre introuvable.');
      return share.id;
    });
    return { id, offerId, channel: input.channel, token: linkToken };
  }

  /** Lien d'invitation → offre. Public : un invité arrive sans compte. */
  async resolve(linkToken: string) {
    const [share] = await rows<{ offer_id: string }>(this.db, 'SELECT offer_id FROM shares WHERE token_hash = $1', [
      hashToken(linkToken),
    ]);
    if (!share) throw new NotFoundException('Lien inconnu.');
    return { offerId: share.offer_id };
  }

  /**
   * « Achats proposés » d'un groupe, réservés à ses membres actifs.
   * Un nombre de membres confirmés par offre, jamais de liste des « sans réponse ».
   */
  async groupProposals(userId: string, groupId: string) {
    const [membership] = await rows(
      this.db,
      `SELECT 1 FROM memberships WHERE group_id = $1 AND user_id = $2 AND status = 'active'`,
      [groupId, userId],
    );
    if (!membership) throw new ForbiddenException("Vous n'êtes pas membre de ce groupe.");
    return toApi(
      await rows(
        this.db,
        `SELECT gp.offer_id, gp.proposed_at, gp.confirmed_members,
                u.full_name AS proposed_by_name,
                o.title, o.unit_label, o.currency, o.regular_price_minor, o.ends_at, o.status,
                p.confirmed_units, p.threshold_units, p.missing_units, p.reached_unit_price_minor
         FROM group_offer_proposals gp
         JOIN offers o ON o.id = gp.offer_id
         JOIN offer_progress p ON p.offer_id = gp.offer_id
         JOIN users u ON u.id = gp.proposed_by_user_id
         WHERE gp.group_id = $1
         ORDER BY gp.proposed_at DESC
         LIMIT 100`,
        [groupId],
      ),
    );
  }
}
