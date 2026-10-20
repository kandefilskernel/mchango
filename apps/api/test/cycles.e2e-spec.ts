import { randomUUID } from 'node:crypto';
import { drawTurnOrder } from '../src/groups/draw.js';
import { TestApi, type TestSession } from './helpers.js';

const AMOUNT = 20000;

function inDays(days: number): string {
  return new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);
}

interface Member {
  session: TestSession;
  membershipId: string;
  name: string;
}

describe('Tours, cycles et cotisations (e2e)', () => {
  let api: TestApi;

  beforeAll(async () => {
    api = await TestApi.start();
  });

  afterAll(async () => {
    await api.close();
  });

  const auth = (s: TestSession) => ({ Authorization: `Bearer ${s.accessToken}` });
  const http = () => api.http();

  /** Groupe en brouillon avec un président et n - 1 membres ayant rejoint par code. */
  async function draftGroup(n: number, overrides: object = {}) {
    const names = ['Mama Furaha', 'Papa Jean', 'Mama Neema', 'Papa Kabila', 'Mama Zawadi'];
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
      membershipId: detail.body.members.find((m: { userId: string }) => m.userId === session.userId)
        .membershipId,
    }));
    return { groupId: group.id, code, members, president: members[0] };
  }

  /** Groupe démarré, ordre des tours = ordre des membres (le président reçoit au tour 1). */
  async function startedGroup(n: number, overrides: object = {}) {
    const g = await draftGroup(n, overrides);
    await http()
      .put(`/groups/${g.groupId}/turn-order`)
      .set(auth(g.president.session))
      .send({ membershipIds: g.members.map((m) => m.membershipId) })
      .expect(200);
    await http().post(`/groups/${g.groupId}/start`).set(auth(g.president.session)).expect(200);
    return g;
  }

  const declare = (groupId: string, cycle: number, payer: Member, body: object) =>
    http()
      .post(`/groups/${groupId}/cycles/${cycle}/contributions`)
      .set(auth(payer.session))
      .send({ amountMinor: AMOUNT, offlineId: randomUUID(), ...body });

  const decide = (contributionId: string, who: Member, decision: string, note?: string) =>
    http().post(`/contributions/${contributionId}/decisions`).set(auth(who.session)).send({ decision, note });

  let txCounter = 0;
  const txRef = () => `MP${Date.now()}${txCounter++}`;

  describe('ordre des tours', () => {
    it('ordre choisi par le président', async () => {
      const g = await draftGroup(3);
      const order = [g.members[2], g.members[0], g.members[1]].map((m) => m.membershipId);
      const res = await http()
        .put(`/groups/${g.groupId}/turn-order`)
        .set(auth(g.president.session))
        .send({ membershipIds: order })
        .expect(200);
      expect(res.body.mode).toBe('chosen');
      expect(res.body.order.map((o: { membershipId: string }) => o.membershipId)).toEqual(order);

      const detail = await http().get(`/groups/${g.groupId}`).set(auth(g.members[1].session)).expect(200);
      expect(detail.body.turnOrderMode).toBe('chosen');
      expect(detail.body.members.map((m: { turnOrder: number }) => m.turnOrder)).toEqual([1, 2, 3]);
    });

    it('refuse une liste incomplète, et un non-président', async () => {
      const g = await draftGroup(3);
      const ids = g.members.map((m) => m.membershipId);
      const put = (who: Member, membershipIds: string[]) =>
        http().put(`/groups/${g.groupId}/turn-order`).set(auth(who.session)).send({ membershipIds });
      await put(g.president, ids.slice(0, 2)).expect(400);
      await put(g.president, [ids[0], ids[0], ids[1]]).expect(400);
      await put(g.members[1], ids).expect(403);
    });

    it('tirage vérifiable : chacun recalcule le même ordre avec la graine publiée', async () => {
      const g = await draftGroup(4);
      const res = await http().post(`/groups/${g.groupId}/turn-order/draw`).set(auth(g.president.session)).expect(200);
      expect(res.body.seed).toMatch(/^[0-9a-f]{64}$/);
      const recomputed = drawTurnOrder(
        g.members.map((m) => m.membershipId),
        res.body.seed,
      );
      expect(res.body.order.map((o: { membershipId: string }) => o.membershipId)).toEqual(recomputed);

      const detail = await http().get(`/groups/${g.groupId}`).set(auth(g.members[3].session)).expect(200);
      expect(detail.body.drawSeed).toBe(res.body.seed);
    });

    it('pas de second tirage avec les mêmes membres, même en passant par un ordre choisi', async () => {
      const g = await draftGroup(3);
      const draw = () => http().post(`/groups/${g.groupId}/turn-order/draw`).set(auth(g.president.session));
      const first = await draw().expect(200);
      await draw().expect(409);

      await http()
        .put(`/groups/${g.groupId}/turn-order`)
        .set(auth(g.president.session))
        .send({ membershipIds: g.members.map((m) => m.membershipId) })
        .expect(200);
      await draw().expect(409);
      // Le tirage remplacé reste visible
      const detail = await http().get(`/groups/${g.groupId}`).set(auth(g.members[1].session)).expect(200);
      expect(detail.body).toMatchObject({ turnOrderMode: 'chosen', drawSeed: first.body.seed });

      // Un nouveau membre change la liste : nouveau tirage possible
      const newcomer = (await api.signUp()).session;
      await http().post('/groups/join').set(auth(newcomer)).send({ code: g.code, acceptRules: true }).expect(200);
      await draw().expect(200);
    });
  });

  describe('démarrage', () => {
    it("refuse de démarrer sans ordre complet", async () => {
      const g = await draftGroup(3);
      await http().post(`/groups/${g.groupId}/start`).set(auth(g.president.session)).expect(409);
    });

    it('un cycle par membre, échéances hebdomadaires ; ensuite tout est figé', async () => {
      const g = await startedGroup(3);
      const board = await http().get(`/groups/${g.groupId}/cycles`).set(auth(g.members[1].session)).expect(200);
      expect(board.body.cycles).toEqual([
        expect.objectContaining({ cycleNumber: 1, dueDate: inDays(1), status: 'open', confirmedCount: 0, expectedCount: 2 }),
        expect.objectContaining({ cycleNumber: 2, dueDate: inDays(8), status: 'upcoming' }),
        expect.objectContaining({ cycleNumber: 3, dueDate: inDays(15), status: 'upcoming' }),
      ]);
      expect(board.body.cycles.map((c: { beneficiary: { fullName: string } }) => c.beneficiary.fullName)).toEqual([
        'Mama Furaha',
        'Papa Jean',
        'Mama Neema',
      ]);

      const p = auth(g.president.session);
      await http().put(`/groups/${g.groupId}/turn-order`).set(p).send({ membershipIds: g.members.map((m) => m.membershipId) }).expect(409);
      await http().patch(`/groups/${g.groupId}`).set(p).send({ name: 'Autre nom' }).expect(409);
      await http().post(`/groups/${g.groupId}/start`).set(p).expect(409);
      // Les invitations sont closes
      const late = (await api.signUp()).session;
      await http().post('/groups/join').set(auth(late)).send({ code: g.code, acceptRules: true }).expect(404);
    });

    it('mensuel : 31 janvier → fin février → 31 mars', async () => {
      const year = new Date().getUTCFullYear() + 1;
      const leap = (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
      const g = await startedGroup(3, { frequency: 'monthly', startDate: `${year}-01-31` });
      const board = await http().get(`/groups/${g.groupId}/cycles`).set(auth(g.president.session)).expect(200);
      expect(board.body.cycles.map((c: { dueDate: string }) => c.dueDate)).toEqual([
        `${year}-01-31`,
        `${year}-02-${leap ? '29' : '28'}`,
        `${year}-03-31`,
      ]);
    });

    it('le président peut corriger le brouillon avant de démarrer', async () => {
      const g = await draftGroup(2);
      const res = await http()
        .patch(`/groups/${g.groupId}`)
        .set(auth(g.president.session))
        .send({ startDate: inDays(10), contributionAmountMinor: 50000 })
        .expect(200);
      expect(res.body).toMatchObject({ startDate: inDays(10), contributionAmountMinor: 50000, currency: 'CDF' });
      await http().patch(`/groups/${g.groupId}`).set(auth(g.members[1].session)).send({ name: 'X' + 'y'.repeat(3) }).expect(403);
      await http().patch(`/groups/${g.groupId}`).set(auth(g.president.session)).send({ maxMembers: 1 }).expect(400);
    });
  });

  describe('déclaration et confirmation', () => {
    it('mobile money : déclarée par le payeur, confirmée par le bénéficiaire', async () => {
      const g = await startedGroup(3);
      const [beneficiary, payer] = g.members;
      const tx = txRef();
      const declared = await declare(g.groupId, 1, payer, { method: 'mpesa', txReference: tx.toLowerCase() }).expect(201);
      expect(declared.body).toMatchObject({ status: 'declared', txReference: tx, isLate: false, replayed: false });

      let cycle = await http().get(`/groups/${g.groupId}/cycles/1`).set(auth(beneficiary.session)).expect(200);
      expect(cycle.body.payers.map((p: { fullName: string; status: string }) => [p.fullName, p.status])).toEqual([
        ['Papa Jean', 'declared'],
        ['Mama Neema', 'expected'],
      ]);

      await decide(declared.body.id, g.members[2], 'confirm').expect(403);
      const confirmed = await decide(declared.body.id, beneficiary, 'confirm').expect(200);
      expect(confirmed.body).toMatchObject({ status: 'confirmed', cycleStatus: 'open' });
      await decide(declared.body.id, beneficiary, 'confirm').expect(409);

      cycle = await http().get(`/groups/${g.groupId}/cycles/1`).set(auth(payer.session)).expect(200);
      expect(cycle.body.payers[0]).toMatchObject({ status: 'confirmed', decisions: [expect.objectContaining({ decision: 'confirm', membershipId: beneficiary.membershipId })] });
    });

    it('refuse : bénéficiaire qui cotise, mauvais montant, ID manquant, ID déjà utilisé, double déclaration', async () => {
      const g = await startedGroup(3);
      const [beneficiary, a, b] = g.members;
      const tx = txRef();
      await declare(g.groupId, 1, beneficiary, { method: 'mpesa', txReference: txRef() }).expect(400);
      await declare(g.groupId, 1, a, { method: 'mpesa', txReference: txRef(), amountMinor: AMOUNT - 1 }).expect(400);
      await declare(g.groupId, 1, a, { method: 'airtel' }).expect(400);
      await declare(g.groupId, 1, a, { method: 'mpesa', txReference: tx }).expect(201);
      const reused = await declare(g.groupId, 1, b, { method: 'mpesa', txReference: tx }).expect(409);
      expect(reused.body.message).toContain('déjà été utilisé');
      await declare(g.groupId, 1, a, { method: 'orange', txReference: txRef() }).expect(409);
      await declare(g.groupId, 9, b, { method: 'mpesa', txReference: txRef() }).expect(404);
    });

    it('renvoyer la même déclaration (même offlineId) ne crée pas de doublon', async () => {
      const g = await startedGroup(2);
      const offlineId = randomUUID();
      const body = { method: 'mpesa', txReference: txRef(), offlineId };
      const first = await declare(g.groupId, 1, g.members[1], body).expect(201);
      const again = await declare(g.groupId, 1, g.members[1], body).expect(201);
      expect(again.body).toMatchObject({ id: first.body.id, replayed: true });
    });

    it('espèces : il faut le bénéficiaire ET le témoin', async () => {
      const g = await startedGroup(3);
      const [beneficiary, payer, witness] = g.members;
      await declare(g.groupId, 1, payer, { method: 'cash' }).expect(400);
      await declare(g.groupId, 1, payer, { method: 'cash', witnessMembershipId: beneficiary.membershipId }).expect(400);
      const declared = await declare(g.groupId, 1, payer, { method: 'cash', witnessMembershipId: witness.membershipId }).expect(201);

      const afterReceiver = await decide(declared.body.id, beneficiary, 'confirm').expect(200);
      expect(afterReceiver.body.status).toBe('declared');
      await decide(declared.body.id, payer, 'witness').expect(403);
      const afterWitness = await decide(declared.body.id, witness, 'witness').expect(200);
      expect(afterWitness.body.status).toBe('confirmed');
    });

    it('contestation avec motif, puis confirmation qui la clôt', async () => {
      const g = await startedGroup(3);
      const [beneficiary, payer] = g.members;
      const declared = await declare(g.groupId, 1, payer, { method: 'mpesa', txReference: txRef() }).expect(201);
      await decide(declared.body.id, payer, 'dispute', 'test').expect(403);
      await decide(declared.body.id, beneficiary, 'dispute').expect(400);
      const disputed = await decide(declared.body.id, beneficiary, 'dispute', "Je n'ai rien reçu").expect(200);
      expect(disputed.body.status).toBe('disputed');

      const confirmed = await decide(declared.body.id, beneficiary, 'confirm').expect(200);
      expect(confirmed.body.status).toBe('confirmed');
      const { rows } = await api.db.query<{ status: string }>(
        'SELECT status FROM disputes WHERE contribution_id = $1',
        [declared.body.id],
      );
      expect(rows.map((r) => r.status)).toEqual(['resolved_confirmed']);
    });

    it('en retard : signalé avant déclaration, et marqué sur la déclaration', async () => {
      const g = await startedGroup(2);
      await api.db.transaction({ type: 'system' }, (q) =>
        q.query(`UPDATE cycles SET due_date = current_date - 3 WHERE group_id = $1 AND cycle_number = 1`, [g.groupId]),
      );
      const before = await http().get(`/groups/${g.groupId}/cycles/1`).set(auth(g.president.session)).expect(200);
      expect(before.body.payers[0].status).toBe('late');
      const declared = await declare(g.groupId, 1, g.members[1], { method: 'mpesa', txReference: txRef() }).expect(201);
      expect(declared.body.isLate).toBe(true);
    });

    it("rotation complète : chaque tour se clôt, le suivant s'ouvre, puis le groupe est terminé", async () => {
      const g = await startedGroup(3);
      for (let cycle = 1; cycle <= 3; cycle++) {
        const beneficiary = g.members[cycle - 1];
        const payers = g.members.filter((m) => m !== beneficiary);
        let last: { cycleStatus: string } | undefined;
        for (const payer of payers) {
          const d = await declare(g.groupId, cycle, payer, { method: 'mpesa', txReference: txRef() }).expect(201);
          last = (await decide(d.body.id, beneficiary, 'confirm').expect(200)).body;
        }
        expect(last!.cycleStatus).toBe('completed');
      }
      const board = await http().get(`/groups/${g.groupId}/cycles`).set(auth(g.president.session)).expect(200);
      expect(board.body.cycles.map((c: { status: string }) => c.status)).toEqual(['completed', 'completed', 'completed']);
      const detail = await http().get(`/groups/${g.groupId}`).set(auth(g.president.session)).expect(200);
      expect(detail.body.status).toBe('closed');
      await declare(g.groupId, 1, g.members[1], { method: 'mpesa', txReference: txRef() }).expect(409);

      const check = await api.db.query<{ broken: string | null; events: number }>(
        `SELECT audit_verify_chain($1) AS broken,
                (SELECT count(*)::int FROM audit_log WHERE chain_id = $1) AS events`,
        [`group:${g.groupId}`],
      );
      expect(check.rows[0].broken).toBeNull();
      expect(check.rows[0].events).toBeGreaterThan(20);
    });

    it("un non-membre ne voit ni le tableau ni les cotisations", async () => {
      const g = await startedGroup(2);
      const d = await declare(g.groupId, 1, g.members[1], { method: 'mpesa', txReference: txRef() }).expect(201);
      const outsider = (await api.signUp()).session;
      await http().get(`/groups/${g.groupId}/cycles`).set(auth(outsider)).expect(404);
      await http().post(`/contributions/${d.body.id}/decisions`).set(auth(outsider)).send({ decision: 'dispute', note: 'x' }).expect(404);
    });
  });
});
