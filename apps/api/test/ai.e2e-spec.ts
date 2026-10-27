import { randomUUID } from 'node:crypto';
import { StaffAuthService, type StaffRole } from '../src/admin/staff-auth.service.js';
import { totpCode } from '../src/admin/totp.js';
import { AI_ANALYST, AnalystUnavailable, type Analyst, type FeedbackReview, type GroupReview } from '../src/ai/analyst.js';
import type { GroupDataset, Signal } from '../src/ai/signals.js';
import { TestApi, type TestSession } from './helpers.js';

/** Agent IA factice : enregistre ce qu'on lui envoie, ne contacte jamais Anthropic. */
class FakeAnalyst implements Analyst {
  readonly model = 'fake-model';
  enabled = true;
  failWith: Error | null = null;
  groupCalls: { dataset: GroupDataset; signals: Signal[] }[] = [];
  feedbackCalls: { ref: string; rating: number | null; text: string }[][] = [];

  async reviewGroup(dataset: GroupDataset, signals: Signal[]) {
    if (this.failWith) throw this.failWith;
    this.groupCalls.push({ dataset, signals });
    const result: GroupReview = {
      summary: 'Un paiement contesté.',
      risk_level: 'medium',
      findings: [
        { severity: 'attention', category: 'dispute_pattern', members: ['M2'], explanation: 'Paiement contesté.', evidence: ['Tour 1'], suggested_action: 'Demander la capture du SMS à M2.' },
      ],
    };
    return { model: this.model, result, inputTokens: 1200, outputTokens: 300 };
  }

  async reviewFeedback(items: { ref: string; rating: number | null; text: string }[]) {
    if (this.failWith) throw this.failWith;
    this.feedbackCalls.push(items);
    const result: FeedbackReview = { summary: 'Avis mitigés.', sentiment: 'mixed', themes: [], urgent: [{ ref: items[0].ref, reason: 'Argent non reçu.' }] };
    return { model: this.model, result, inputTokens: 500, outputTokens: 100 };
  }
}

describe('Avis des membres et agent IA (e2e)', () => {
  let api: TestApi;
  const fake = new FakeAnalyst();
  const AMOUNT = 20000;

  beforeAll(async () => {
    api = await TestApi.start([{ provide: AI_ANALYST, useValue: fake }]);
  });

  afterAll(async () => {
    await api.close();
  });

  beforeEach(() => {
    fake.enabled = true;
    fake.failWith = null;
  });

  const http = () => api.http();
  const asMember = (s: TestSession) => ({ Authorization: `Bearer ${s.accessToken}` });
  const asStaff = (token: string) => ({ Authorization: `Bearer ${token}` });

  async function staff(role: StaffRole) {
    const created = await api.app
      .get(StaffAuthService)
      .create(null, { email: `${role}-${randomUUID().slice(0, 8)}@mchango.test`, fullName: `Agent ${role}`, role });
    const res = await http()
      .post('/admin/auth/login')
      .send({ email: created.email, password: created.temporaryPassword, code: totpCode(created.totpSecret) })
      .expect(200);
    return res.body.token as string;
  }

  /** Tontine à 3 démarrée ; au tour 1, la bénéficiaire (Mama Furaha) conteste le paiement de Papa Jean. */
  async function groupWithAnomaly() {
    const names = ['Mama Furaha', 'Papa Jean', 'Mama Neema'];
    const sessions: TestSession[] = [];
    for (const n of names) sessions.push((await api.signUp(undefined, undefined, n)).session);
    const [president, jean, neema] = sessions;
    const startDate = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
    const g = (
      await http()
        .post('/groups')
        .set(asMember(president))
        .send({ name: 'Likelemba IA', currency: 'CDF', contributionAmountMinor: AMOUNT, frequency: 'weekly', startDate })
        .expect(201)
    ).body as { id: string };
    const { code } = (await http().post(`/groups/${g.id}/invitations`).set(asMember(president)).send({})).body;
    for (const s of [jean, neema]) await http().post('/groups/join').set(asMember(s)).send({ code, acceptRules: true }).expect(200);
    const detail = (await http().get(`/groups/${g.id}`).set(asMember(president))).body;
    const membershipOf = (s: TestSession) => detail.members.find((m: { userId: string }) => m.userId === s.userId).membershipId;
    await http().put(`/groups/${g.id}/turn-order`).set(asMember(president)).send({ membershipIds: sessions.map(membershipOf) }).expect(200);
    await api.signTerms(g.id, sessions);
    await http().post(`/groups/${g.id}/start`).set(asMember(president)).expect(200);
    const declared = await http()
      .post(`/groups/${g.id}/cycles/1/contributions`)
      .set(asMember(jean))
      .send({ method: 'mpesa', txReference: `MP${Date.now()}J`, amountMinor: AMOUNT, offlineId: randomUUID() })
      .expect(201);
    await http()
      .post(`/contributions/${declared.body.id}/decisions`)
      .set(asMember(president))
      .send({ decision: 'dispute', note: "Papa Jean, je n'ai rien reçu sur le 0990000002" })
      .expect(200);
    await http()
      .post(`/groups/${g.id}/cycles/1/contributions`)
      .set(asMember(neema))
      .send({ method: 'mpesa', txReference: `MP${Date.now()}N`, amountMinor: AMOUNT, offlineId: randomUUID() })
      .expect(201);
    return { groupId: g.id, president, jean, neema };
  }

  describe('avis des membres', () => {
    it('un membre donne son avis, sur Mchango ou sur sa tontine ; pas sur celle des autres', async () => {
      const { groupId, jean } = await groupWithAnomaly();
      const outsider = (await api.signUp()).session;
      await http().post('/feedback').set(asMember(jean)).send({ body: 'Très pratique.', rating: 5 }).expect(201);
      await http().post('/feedback').set(asMember(jean)).send({ groupId, body: 'Le trésorier ne confirme jamais.' }).expect(201);
      await http().post('/feedback').set(asMember(outsider)).send({ groupId, body: 'Je veux voir.' }).expect(403);
      await http().post('/feedback').set(asMember(jean)).send({ body: '  ' }).expect(400);
      await http().post('/feedback').set(asMember(jean)).send({ body: 'Note', rating: 9 }).expect(400);
      await http().post('/feedback').send({ body: 'Sans connexion' }).expect(401);
    });

    it("au plus 5 avis par jour et par membre", async () => {
      const member = (await api.signUp()).session;
      for (let i = 0; i < 5; i++) await http().post('/feedback').set(asMember(member)).send({ body: `Avis ${i}` }).expect(201);
      await http().post('/feedback').set(asMember(member)).send({ body: 'Encore un' }).expect(429);
    });
  });

  describe('analyse d’une tontine', () => {
    it('envoie des données pseudonymisées et rend les vrais noms à l’équipe', async () => {
      const { groupId, jean } = await groupWithAnomaly();
      await http()
        .post('/feedback')
        .set(asMember(jean))
        .send({ groupId, body: 'Mama Furaha dit que je dois payer au +243 990 000 001' })
        .expect(201);
      const support = await staff('support');
      const res = await http().post(`/admin/ai/groups/${groupId}/review`).set(asStaff(support)).expect(201);

      // Ce qui part chez le fournisseur d'IA : ni noms, ni numéros, ni identifiants internes
      const sent = JSON.stringify(fake.groupCalls.at(-1));
      for (const secret of ['Mama Furaha', 'Papa Jean', 'Mama Neema', '+243', '990 000 001', groupId, jean.userId]) {
        expect(sent).not.toContain(secret);
      }
      expect(sent).toContain('M1 dit que je dois payer au [numéro]');
      const dataset = fake.groupCalls.at(-1)!.dataset;
      expect(dataset.disputes).toEqual([
        { cycle: 1, openedBy: 'M1', against: 'M2', status: 'open', reason: "M2, je n'ai rien reçu sur le [numéro]" },
      ]);
      expect(dataset.contributions.map((c) => [c.payer, c.status])).toEqual([['M2', 'disputed'], ['M3', 'declared']]);

      expect(res.body.result).toMatchObject({ risk_level: 'medium' });
      expect(res.body.members.M2).toMatchObject({ fullName: 'Papa Jean', userId: jean.userId });
      expect(res.body.usage).toEqual({ inputTokens: 1200, outputTokens: 300 });

      const audit = await api.db.query(`SELECT 1 FROM audit_log WHERE action = 'staff.ai_review' AND payload::jsonb->>'review_id' = $1`, [res.body.id]);
      expect(audit.rowCount).toBe(1);
      const list = await http().get(`/admin/ai/reviews?groupId=${groupId}`).set(asStaff(support)).expect(200);
      expect(list.body[0]).toMatchObject({ id: res.body.id, riskLevel: 'medium', groupName: 'Likelemba IA' });
    });

    it('sans clé ou en cas de panne : les règles tournent quand même, l’erreur est notée', async () => {
      const { groupId } = await groupWithAnomaly();
      const support = await staff('compliance');
      fake.enabled = false;
      const off = await http().post(`/admin/ai/groups/${groupId}/review`).set(asStaff(support)).expect(201);
      expect(off.body).toMatchObject({ result: null, model: 'règles' });
      expect(off.body.error).toContain('non configuré');
      expect(off.body.rules).toEqual([]);

      fake.enabled = true;
      fake.failWith = new AnalystUnavailable('Agent IA saturé ; réessayez dans une minute.');
      const down = await http().post(`/admin/ai/groups/${groupId}/review`).set(asStaff(support)).expect(201);
      expect(down.body).toMatchObject({ result: null, error: 'Agent IA saturé ; réessayez dans une minute.' });
    });

    it('lire : toute l’équipe ; lancer une analyse (facturée) : support et conformité', async () => {
      const { groupId } = await groupWithAnomaly();
      const readOnly = await staff('read_only');
      await http().post(`/admin/ai/groups/${groupId}/review`).set(asStaff(readOnly)).expect(403);
      await http().get('/admin/ai/reviews').set(asStaff(readOnly)).expect(200);
      await http().get('/admin/ai/status').set(asStaff(readOnly)).expect(200);
      const support = await staff('support');
      await http().post(`/admin/ai/groups/${randomUUID()}/review`).set(asStaff(support)).expect(404);
    });
  });

  describe('synthèse des avis', () => {
    it('références F1, F2… à la place des auteurs, remises en clair pour l’équipe', async () => {
      const { neema } = await groupWithAnomaly();
      await http().post('/feedback').set(asMember(neema)).send({ body: 'Je suis Mama Neema et je n’ai rien reçu !', rating: 1 }).expect(201);
      const support = await staff('support');
      const res = await http().post('/admin/ai/feedback/review').set(asStaff(support)).expect(201);
      const items = fake.feedbackCalls.at(-1)!;
      expect(JSON.stringify(items)).not.toContain('Mama Neema');
      expect(items[0]).toMatchObject({ ref: 'F1', rating: 1, text: 'Je suis le membre et je n’ai rien reçu !' });
      expect(res.body.feedback.F1).toMatchObject({ fullName: 'Mama Neema', userId: neema.userId });
      const all = await http().get('/admin/ai/feedback').set(asStaff(support)).expect(200);
      expect(all.body[0]).toMatchObject({ fullName: 'Mama Neema', rating: 1 });
    });
  });
});
