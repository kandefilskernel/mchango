import { createHash, randomUUID } from 'node:crypto';
import { TestApi, type TestSession } from './helpers.js';

// Échange de tour, objectifs d'épargne, attestation de régularité, calendrier de paie
// (spec/swaps.md, spec/goals.md, spec/attestations.md, spec/categories.md §3.5).

const AMOUNT = 20000;

function inDays(days: number): string {
  return new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);
}

interface Member {
  session: TestSession;
  membershipId: string;
  name: string;
}

describe('Échanges de tour, objectifs, attestations, calendrier de paie (e2e)', () => {
  let api: TestApi;

  beforeAll(async () => {
    api = await TestApi.start();
  });

  afterAll(async () => {
    await api.close();
  });

  const auth = (s: TestSession) => ({ Authorization: `Bearer ${s.accessToken}` });
  const http = () => api.http();

  async function startedGroup(n: number, overrides: object = {}) {
    const names = ['Mama Furaha', 'Papa Jean', 'Mama Neema', 'Papa Kabila'];
    const sessions: TestSession[] = [];
    for (let i = 0; i < n; i++) sessions.push((await api.signUp(undefined, undefined, names[i])).session);
    const president = sessions[0];
    const group = (
      await http()
        .post('/groups')
        .set(auth(president))
        .send({
          name: 'Likelemba Kenya',
          currency: 'CDF',
          contributionAmountMinor: AMOUNT,
          frequency: 'weekly',
          startDate: inDays(1),
          ...overrides,
        })
        .expect(201)
    ).body as { id: string };
    const { code } = (await http().post(`/groups/${group.id}/invitations`).set(auth(president)).send({}).expect(201))
      .body as { code: string };
    for (const s of sessions.slice(1)) {
      await http().post('/groups/join').set(auth(s)).send({ code, acceptRules: true }).expect(200);
    }
    const detail = await http().get(`/groups/${group.id}`).set(auth(president)).expect(200);
    const members: Member[] = sessions.map((session, i) => ({
      session,
      name: names[i],
      membershipId: detail.body.members.find((m: { userId: string }) => m.userId === session.userId).membershipId,
    }));
    await http()
      .put(`/groups/${group.id}/turn-order`)
      .set(auth(president))
      .send({ membershipIds: members.map((m) => m.membershipId) })
      .expect(200);
    await api.signTerms(group.id, sessions);
    await http().post(`/groups/${group.id}/start`).set(auth(president)).expect(200);
    return { groupId: group.id, members };
  }

  let txCounter = 0;
  const txRef = () => `MP${Date.now()}${txCounter++}`;

  const declare = (groupId: string, cycle: number, payer: Member) =>
    http()
      .post(`/groups/${groupId}/cycles/${cycle}/contributions`)
      .set(auth(payer.session))
      .send({ amountMinor: AMOUNT, offlineId: randomUUID(), method: 'mpesa', txReference: txRef() });

  async function payAndConfirm(groupId: string, cycle: number, payer: Member, beneficiary: Member) {
    const { body } = await declare(groupId, cycle, payer).expect(201);
    await http()
      .post(`/contributions/${body.id}/decisions`)
      .set(auth(beneficiary.session))
      .send({ decision: 'confirm', riskAcknowledged: true, receivedTxReference: body.txReference })
      .expect(200);
  }

  const board = async (groupId: string, who: Member) =>
    (await http().get(`/groups/${groupId}/cycles`).set(auth(who.session)).expect(200)).body as {
      cycles: { cycleNumber: number; beneficiary: { membershipId: string; goal: { label: string } | null } }[];
    };

  describe('fréquence choisie par le président', () => {
    it.each([
      ['daily', 1],
      ['weekly', 7],
      ['monthly', 0],
    ])('« %s » : change avant le démarrage, et les tours suivent', async (frequency, days) => {
      const s = (await api.signUp()).session;
      const created = await http()
        .post('/groups')
        .set(auth(s))
        .send({ name: 'Likelemba', currency: 'CDF', contributionAmountMinor: AMOUNT, frequency: 'weekly', startDate: inDays(2) })
        .expect(201);
      const changed = await http().patch(`/groups/${created.body.id}`).set(auth(s)).send({ frequency }).expect(200);
      expect(changed.body.frequency).toBe(frequency);

      // Un autre membre ne change pas les règles
      const other = (await api.signUp()).session;
      await http().patch(`/groups/${created.body.id}`).set(auth(other)).send({ frequency: 'daily' }).expect(404);

      // Démarrage à deux : l'écart entre les deux tours est celui de la fréquence choisie
      const { code } = (await http().post(`/groups/${created.body.id}/invitations`).set(auth(s)).send({}).expect(201)).body;
      await http().post('/groups/join').set(auth(other)).send({ code, acceptRules: true }).expect(200);
      const detail = (await http().get(`/groups/${created.body.id}`).set(auth(s)).expect(200)).body;
      await http()
        .put(`/groups/${created.body.id}/turn-order`)
        .set(auth(s))
        .send({ membershipIds: detail.members.map((m: { membershipId: string }) => m.membershipId) })
        .expect(200);
      await api.signTerms(created.body.id, [s, other]);
      await http().post(`/groups/${created.body.id}/start`).set(auth(s)).expect(200);
      const board = (await http().get(`/groups/${created.body.id}/cycles`).set(auth(s)).expect(200)).body.cycles as { dueDate: string }[];
      const gap = (new Date(board[1].dueDate).getTime() - new Date(board[0].dueDate).getTime()) / 86_400_000;
      if (days > 0) expect(gap).toBe(days);
      else expect(gap).toBeGreaterThanOrEqual(28);
    });
  });

  describe('échange de tour', () => {
    it('demande, acceptation : les bénéficiaires des deux tours sont échangés, dates inchangées', async () => {
      const g = await startedGroup(3);
      const [, jean, neema] = g.members;
      const before = await board(g.groupId, jean);

      const req = await http()
        .post(`/groups/${g.groupId}/swaps`)
        .set(auth(jean.session))
        .send({ targetMembershipId: neema.membershipId, reason: 'Minerval à payer avant la rentrée' })
        .expect(201);
      expect(req.body).toMatchObject({ status: 'pending', requesterCycleNumber: 2, targetCycleNumber: 3 });

      // Un seul en attente par demandeur ; le demandeur ne peut pas accepter à la place de l'autre
      await http()
        .post(`/groups/${g.groupId}/swaps`)
        .set(auth(jean.session))
        .send({ targetMembershipId: g.members[0].membershipId })
        .expect(409);
      await http().post(`/swaps/${req.body.id}/accept`).set(auth(jean.session)).expect(403);

      const accepted = await http().post(`/swaps/${req.body.id}/accept`).set(auth(neema.session)).expect(200);
      expect(accepted.body.status).toBe('accepted');

      const after = await board(g.groupId, jean);
      expect(after.cycles[1].beneficiary.membershipId).toBe(neema.membershipId);
      expect(after.cycles[2].beneficiary.membershipId).toBe(jean.membershipId);
      expect(after.cycles.map((c) => (c as unknown as { dueDate: string }).dueDate)).toEqual(
        before.cycles.map((c) => (c as unknown as { dueDate: string }).dueDate),
      );

      // L'écran du groupe montre le nouveau tour de chacun ; l'échange est dans le journal du groupe
      const detail = await http().get(`/groups/${g.groupId}`).set(auth(jean.session)).expect(200);
      expect(detail.body.members.find((m: { membershipId: string }) => m.membershipId === jean.membershipId).turnOrder).toBe(3);
      const history = await http().get(`/groups/${g.groupId}/history`).set(auth(g.members[0].session)).expect(200);
      const actions = history.body.events.map((e: { action: string }) => e.action);
      expect(actions).toContain('turn_swaps.insert');
      expect(actions).toContain('turn_swaps.update');

      const list = await http().get(`/groups/${g.groupId}/swaps`).set(auth(g.members[0].session)).expect(200);
      expect(list.body[0]).toMatchObject({ status: 'accepted', requester: { fullName: 'Papa Jean' } });
      await http().post(`/swaps/${req.body.id}/decline`).set(auth(neema.session)).expect(409);
    });

    it('refusé si un paiement est déjà déclaré pour l\'un des tours', async () => {
      const g = await startedGroup(3);
      const [furaha, jean] = g.members;
      await declare(g.groupId, 1, jean).expect(201);
      // Le tableau dit qu'un paiement est déclaré (pas encore confirmé) : l'app n'offre plus l'échange
      const b = await http().get(`/groups/${g.groupId}/cycles`).set(auth(furaha.session)).expect(200);
      expect(b.body.cycles[0]).toMatchObject({ confirmedCount: 0, declaredCount: 1 });
      const res = await http()
        .post(`/groups/${g.groupId}/swaps`)
        .set(auth(furaha.session))
        .send({ targetMembershipId: jean.membershipId })
        .expect(409);
      expect(res.body.message).toMatch(/paiements sont déjà déclarés/);
    });

    it('refus et retrait ; la base refuse tout changement de bénéficiaire hors échange', async () => {
      const g = await startedGroup(3);
      const [furaha, jean, neema] = g.members;
      const a = await http()
        .post(`/groups/${g.groupId}/swaps`)
        .set(auth(jean.session))
        .send({ targetMembershipId: neema.membershipId })
        .expect(201);
      await http().post(`/swaps/${a.body.id}/cancel`).set(auth(neema.session)).expect(403);
      expect((await http().post(`/swaps/${a.body.id}/decline`).set(auth(neema.session)).expect(200)).body.status).toBe(
        'declined',
      );
      const b = await http()
        .post(`/groups/${g.groupId}/swaps`)
        .set(auth(jean.session))
        .send({ targetMembershipId: furaha.membershipId })
        .expect(201);
      expect((await http().post(`/swaps/${b.body.id}/cancel`).set(auth(jean.session)).expect(200)).body.status).toBe(
        'cancelled',
      );

      await expect(
        api.db.transaction({ type: 'system' }, (q) =>
          q.query(`UPDATE cycles SET beneficiary_membership_id = $2 WHERE group_id = $1 AND cycle_number = 3`, [
            g.groupId,
            jean.membershipId,
          ]),
        ),
      ).rejects.toThrow(/échange accepté|uq_cycles_beneficiary/);
    });
  });

  describe('objectif d\'épargne', () => {
    it('fixé, partagé ou non, visible dans le carnet avec sa progression, puis retiré', async () => {
      const g = await startedGroup(3);
      const [furaha, jean, neema] = g.members;
      const set = await http()
        .put(`/groups/${g.groupId}/goal`)
        .set(auth(furaha.session))
        .send({ kind: 'school', label: 'Minerval des enfants', targetAmountMinor: 30000, sharedWithGroup: true })
        .expect(200);
      expect(set.body.goal).toMatchObject({ kind: 'school', label: 'Minerval des enfants', sharedWithGroup: true });
      await http()
        .put(`/groups/${g.groupId}/goal`)
        .set(auth(jean.session))
        .send({ kind: 'business', label: 'Stock de pagnes' })
        .expect(200);

      // Le groupe voit l'objectif partagé de Furaha, pas celui de Jean
      const b = await board(g.groupId, neema);
      expect(b.cycles[0].beneficiary.goal).toEqual({ kind: 'school', label: 'Minerval des enfants' });
      expect(b.cycles[1].beneficiary.goal).toBeNull();

      await payAndConfirm(g.groupId, 1, jean, furaha);
      const carnet = await http().get('/me/carnet').set(auth(furaha.session)).expect(200);
      const line = carnet.body.groups.find((x: { groupId: string }) => x.groupId === g.groupId);
      expect(line.goal).toMatchObject({ effectiveTargetMinor: 30000, progressMinor: AMOUNT, progressPercent: 66, reached: false });
      // Sans montant visé, la cible est la mise complète attendue (2 × 20 000)
      const jeanCarnet = await http().get('/me/carnet').set(auth(jean.session)).expect(200);
      expect(jeanCarnet.body.groups[0].goal).toMatchObject({ targetAmountMinor: null, effectiveTargetMinor: 40000, progressPercent: 0 });

      // Personnel : pas dans le journal du groupe
      const history = await http().get(`/groups/${g.groupId}/history`).set(auth(neema.session)).expect(200);
      expect(history.body.events.some((e: { action: string }) => e.action.startsWith('savings_goals'))).toBe(false);

      await http().delete(`/groups/${g.groupId}/goal`).set(auth(furaha.session)).expect(204);
      expect((await http().get(`/groups/${g.groupId}/goal`).set(auth(furaha.session)).expect(200)).body.goal).toBeNull();
      await http().put(`/groups/${g.groupId}/goal`).set(auth(furaha.session)).send({ kind: 'nope', label: 'x' }).expect(400);
    });
  });

  describe('attestation de régularité', () => {
    it('émise après des paiements confirmés, vérifiable par code, puis retirée', async () => {
      const g = await startedGroup(3);
      const [furaha, jean, neema] = g.members;
      await http().post('/me/attestations').set(auth(jean.session)).send({}).expect(409);

      await payAndConfirm(g.groupId, 1, jean, furaha);
      const stats = await http().get('/me/attestation-stats').set(auth(jean.session)).expect(200);
      expect(stats.body).toMatchObject({
        tontines: { joined: 1, active: 1 },
        contributions: { confirmed: 1, onTime: 1, late: 0 },
        onTimeRatePercent: 100,
      });

      const issued = await http().post('/me/attestations').set(auth(jean.session)).send({ includeAmounts: true }).expect(201);
      expect(issued.body.status).toBe('valid');
      expect(issued.body.content.holder.fullName).toBe('Papa Jean');
      expect(issued.body.content.holder.phone).toMatch(/\*{4,}/);
      expect(issued.body.content.amounts).toEqual([{ currency: 'CDF', paidMinor: AMOUNT }]);
      expect(issued.body.qrPayload).toBe(`MCHANGO-ATT1|${issued.body.code}|${issued.body.contentHash}`);
      // L'empreinte est celle du texte du contenu : n'importe qui peut la recalculer
      expect(createHash('sha256').update(JSON.stringify(issued.body.content)).digest('hex')).toBe(issued.body.contentHash);

      // Vérification par un tiers, sans compte ; le code se saisit avec ou sans tiret
      const code: string = issued.body.code;
      const verified = await http().get(`/attestations/${code.slice(0, 5)}-${code.slice(5).toLowerCase()}`).expect(200);
      expect(verified.body).toMatchObject({ status: 'valid', contentHash: issued.body.contentHash });
      await http().get('/attestations/ZZZZZZZZZZ').expect(404);

      // Seul le titulaire retire son attestation ; ensuite le contenu n'est plus montré
      await http().post(`/me/attestations/${issued.body.id}/revoke`).set(auth(neema.session)).expect(404);
      await http().post(`/me/attestations/${issued.body.id}/revoke`).set(auth(jean.session)).expect(200);
      const revoked = await http().get(`/attestations/${code}`).expect(200);
      expect(revoked.body).toMatchObject({ status: 'revoked', content: null });
      const mine = await http().get('/me/attestations').set(auth(jean.session)).expect(200);
      expect(mine.body[0].status).toBe('revoked');

      await expect(
        api.db.transaction({ type: 'user', id: jean.session.userId }, (q) =>
          q.query(`UPDATE attestations SET content = '{}' WHERE id = $1`, [issued.body.id]),
        ),
      ).rejects.toThrow(/figé|content_hash/);
    });
  });

  describe('calendrier de paie (Travailleurs)', () => {
    it('jour de paie : avancé ou reporté si dimanche ou jour férié', async () => {
      const due = async (start: string, offset: number, day: number, shift: string) =>
        (await api.db.query<{ d: string }>(`SELECT payday_due_date($1, $2, $3, $4)::text AS d`, [start, offset, day, shift]))
          .rows[0].d;
      expect(await due('2027-01-01', 0, 31, 'before')).toBe('2027-01-30'); // dimanche 31 → samedi 30
      expect(await due('2027-01-01', 0, 31, 'after')).toBe('2027-02-01');
      expect(await due('2027-01-01', 1, 30, 'before')).toBe('2027-02-27'); // février : 28 (dimanche) → 27
      expect(await due('2027-05-01', 0, 17, 'after')).toBe('2027-05-18'); // 17 mai férié
      expect(await due('2027-05-01', 0, 17, 'before')).toBe('2027-05-15'); // 16 dimanche → 15
      expect(await due('2027-08-01', 0, 1, 'after')).toBe('2027-08-03'); // 1er (dimanche, férié), 2 férié
      expect(await due('2027-01-26', 0, 25, 'before')).toBe('2027-02-25'); // paie de janvier déjà passée
    });

    it('réservé aux tontines mensuelles « Travailleurs » ; échéances sur la paie ; règlement re-signé', async () => {
      const s = (await api.signUp()).session;
      const base = { name: 'Collègues DGI', currency: 'USD', contributionAmountMinor: 5000, startDate: inDays(1) };
      await http().post('/groups').set(auth(s)).send({ ...base, frequency: 'monthly', payday: 25 }).expect(400);
      await http()
        .post('/groups')
        .set(auth(s))
        .send({ ...base, category: 'workers', frequency: 'weekly', payday: 25 })
        .expect(400);
      const created = await http()
        .post('/groups')
        .set(auth(s))
        .send({ ...base, category: 'workers', frequency: 'monthly', payday: 25 })
        .expect(201);
      expect(created.body).toMatchObject({ payday: 25, paydayShift: 'before' });
      await http().patch(`/groups/${created.body.id}`).set(auth(s)).send({ frequency: 'weekly' }).expect(400);
      const shifted = await http().patch(`/groups/${created.body.id}`).set(auth(s)).send({ paydayShift: 'after' }).expect(200);
      expect(shifted.body).toMatchObject({ payday: 25, paydayShift: 'after' });
      const removed = await http().patch(`/groups/${created.body.id}`).set(auth(s)).send({ payday: null }).expect(200);
      expect(removed.body).toMatchObject({ payday: null, paydayShift: null });
      // Une règle de report sans jour de paie est ignorée (plus de 400 trompeur)
      const ignored = await http().patch(`/groups/${created.body.id}`).set(auth(s)).send({ paydayShift: 'after' }).expect(200);
      expect(ignored.body).toMatchObject({ payday: null, paydayShift: null });

      const g = await startedGroup(3, { category: 'workers', frequency: 'monthly', payday: 25, paydayShift: 'after' });
      const cycles = (await http().get(`/groups/${g.groupId}/cycles`).set(auth(g.members[1].session)).expect(200)).body
        .cycles as { dueDate: string }[];
      for (const c of cycles) {
        const d = new Date(`${c.dueDate}T12:00:00Z`);
        expect(d.getUTCDay()).not.toBe(0);
        expect(d.getUTCDate()).toBeGreaterThanOrEqual(25);
      }
      const months = cycles.map((c) => Number(c.dueDate.slice(5, 7)));
      expect(new Set(months).size).toBe(3);
    });

    it('confidentialité : un collègue ne voit pas l\'état des autres ; payeur, bénéficiaire et président oui', async () => {
      const g = await startedGroup(4, { category: 'workers' });
      const [furaha, jean, neema, kabila] = g.members;
      // Tour 2 : Jean reçoit. Neema déclare.
      await payAndConfirm(g.groupId, 1, jean, furaha);
      await payAndConfirm(g.groupId, 1, neema, furaha);
      await payAndConfirm(g.groupId, 1, kabila, furaha);
      await declare(g.groupId, 2, neema).expect(201);

      const view = async (who: Member) =>
        (await http().get(`/groups/${g.groupId}/cycles/2`).set(auth(who.session)).expect(200)).body as {
          privateStatuses: boolean;
          payers: { membershipId: string; status: string }[];
        };
      const statusOf = (v: Awaited<ReturnType<typeof view>>, m: Member) =>
        v.payers.find((p) => p.membershipId === m.membershipId)!.status;

      const colleague = await view(kabila);
      expect(colleague.privateStatuses).toBe(true);
      expect(statusOf(colleague, neema)).toBe('private');
      expect(statusOf(colleague, kabila)).toBe('expected');
      expect(statusOf(await view(neema), neema)).toBe('declared');
      expect(statusOf(await view(jean), neema)).toBe('declared');
      expect(statusOf(await view(furaha), neema)).toBe('declared');

      // Le journal du groupe, lu par tous, ne contient plus aucune cotisation
      const history = await http().get(`/groups/${g.groupId}/history`).set(auth(kabila.session)).expect(200);
      const actions: string[] = history.body.events.map((e: { action: string }) => e.action);
      expect(actions.some((a) => /^(contributions|confirmations|disputes)\./.test(a))).toBe(false);
      expect(actions).toContain('cycles.update'); // la clôture du tour 1 reste visible

      type Chain = { chainId: string; cycleNumber: number; payer: { membershipId: string }; events: { seq: number; prev_hash: string; hash: string; action: string }[] };
      const chainsOf = async (who: Member) =>
        ((await http().get(`/groups/${g.groupId}/private-history`).set(auth(who.session)).expect(200)).body.chains as Chain[]);
      const keys = (cs: Chain[]) => cs.map((c) => `${c.cycleNumber}:${c.payer.membershipId}`).sort();

      // Kabila : seulement sa propre case (tour 1)
      expect(keys(await chainsOf(kabila))).toEqual([`1:${kabila.membershipId}`]);
      // Jean : sa case du tour 1, et la case de Neema au tour 2 dont il est bénéficiaire
      expect(keys(await chainsOf(jean))).toEqual([`1:${jean.membershipId}`, `2:${neema.membershipId}`].sort());
      // Le président voit tout
      expect(await chainsOf(furaha)).toHaveLength(4);

      // Chaque chaîne privée est complète et vérifiable : seq continu, chaînage, et la base confirme
      for (const c of await chainsOf(furaha)) {
        expect(c.chainId).toBe(`group:${g.groupId}:slot:${c.cycleNumber}:${c.payer.membershipId}`);
        c.events.forEach((e, i) => {
          expect(e.seq).toBe(i + 1);
          expect(e.prev_hash).toBe(i === 0 ? '0'.repeat(64) : c.events[i - 1].hash);
        });
        expect(c.events[0].action).toBe('contributions.insert');
        const v = await api.db.query<{ broken: string | null }>('SELECT audit_verify_chain($1) AS broken', [c.chainId]);
        expect(v.rows[0].broken).toBeNull();
      }

      // Le reçu renvoie à l'événement de la chaîne privée
      const cycle1 = (await http().get(`/groups/${g.groupId}/cycles/1`).set(auth(jean.session)).expect(200)).body;
      const mine = cycle1.payers.find((p: { membershipId: string }) => p.membershipId === jean.membershipId);
      const receipt = await http().get(`/contributions/${mine.contribution.id}/receipt`).set(auth(jean.session)).expect(200);
      expect(receipt.body.audit.chainId).toBe(`group:${g.groupId}:slot:1:${jean.membershipId}`);

      // Une écriture ne peut pas viser la chaîne privée d'un autre groupe
      const other = await startedGroup(2);
      await expect(
        api.db.transaction({ type: 'system' }, (q) =>
          q.query(
            `INSERT INTO audit_log (chain_id, group_id, actor_type, action, payload) VALUES ($1, $2, 'system', 'x', '{}')`,
            [`group:${g.groupId}:slot:1:${jean.membershipId}`, other.groupId],
          ),
        ),
      ).resolves.toBeDefined();
      const forged = await api.db.query<{ chain_id: string }>(
        `SELECT chain_id FROM audit_log WHERE group_id = $1 AND action = 'x'`,
        [other.groupId],
      );
      expect(forged.rows[0].chain_id).toBe(`group:${other.groupId}`);
    });

    it('une tontine communautaire garde ses cotisations dans la chaîne du groupe', async () => {
      const g = await startedGroup(2);
      await payAndConfirm(g.groupId, 1, g.members[1], g.members[0]);
      const history = await http().get(`/groups/${g.groupId}/history`).set(auth(g.members[0].session)).expect(200);
      expect(history.body.events.map((e: { action: string }) => e.action)).toContain('contributions.insert');
      const priv = await http().get(`/groups/${g.groupId}/private-history`).set(auth(g.members[0].session)).expect(200);
      expect(priv.body.chains).toEqual([]);
    });
  });
});
