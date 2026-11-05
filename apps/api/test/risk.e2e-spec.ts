import { randomUUID } from 'node:crypto';
import { StaffAuthService } from '../src/admin/staff-auth.service.js';
import { totpCode } from '../src/admin/totp.js';
import { TestApi, type TestSession } from './helpers.js';

describe('Score de risque des déclarations (e2e)', () => {
  let api: TestApi;
  const AMOUNT = 20000;

  beforeAll(async () => {
    api = await TestApi.start();
  });

  afterAll(async () => {
    await api.close();
  });

  const http = () => api.http();
  const auth = (s: TestSession) => ({ Authorization: `Bearer ${s.accessToken}` });

  /** Tontine démarrée : la présidente reçoit le tour 1, les autres paient. */
  async function started(n: number) {
    const sessions: TestSession[] = [];
    for (let i = 0; i < n; i++) sessions.push((await api.signUp(undefined, undefined, `Membre ${i + 1}`)).session);
    const [president] = sessions;
    const startDate = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
    const g = (
      await http()
        .post('/groups')
        .set(auth(president))
        .send({ name: 'Likelemba risque', currency: 'CDF', contributionAmountMinor: AMOUNT, frequency: 'weekly', startDate })
        .expect(201)
    ).body as { id: string };
    const { code } = (await http().post(`/groups/${g.id}/invitations`).set(auth(president)).send({})).body;
    for (const s of sessions.slice(1)) await http().post('/groups/join').set(auth(s)).send({ code, acceptRules: true }).expect(200);
    const detail = (await http().get(`/groups/${g.id}`).set(auth(president))).body;
    const ids = sessions.map((s) => detail.members.find((m: { userId: string }) => m.userId === s.userId).membershipId);
    await http().put(`/groups/${g.id}/turn-order`).set(auth(president)).send({ membershipIds: ids }).expect(200);
    await api.signTerms(g.id, sessions);
    await http().post(`/groups/${g.id}/start`).set(auth(president)).expect(200);
    return { groupId: g.id, president, payers: sessions.slice(1) };
  }

  const declare = (groupId: string, s: TestSession, extra: object) =>
    http()
      .post(`/groups/${groupId}/cycles/1/contributions`)
      .set(auth(s))
      .send({ method: 'airtel', amountMinor: AMOUNT, offlineId: randomUUID(), ...extra })
      .expect(201)
      .then((r) => r.body as { id: string; txReference: string });

  const confirm = (s: TestSession, id: string, extra: object = {}) =>
    http().post(`/contributions/${id}/decisions`).set(auth(s)).send({ decision: 'confirm', ...extra });

  const today = () => new Date().toISOString().slice(2, 10).replace(/-/g, '');

  it('vert, orange, rouge : ce que le bénéficiaire doit faire avant de confirmer', async () => {
    const { groupId, president, payers } = await started(4);
    const [a, b, c] = payers;
    // Vert : SMS collé, bon montant, ID Airtel du jour → seul « premier paiement »
    const green = await declare(groupId, a, {
      txReference: `CO${today()}.1034.T${Date.now() % 100000}`,
      smsCheck: { pasted: true, format: 'airtel', amountMatches: true },
    });
    // Orange : le SMS collé ne donne pas le montant de la cotisation
    const orange = await declare(groupId, b, {
      txReference: `CO${today()}.1035.T${(Date.now() + 1) % 100000}`,
      smsCheck: { pasted: true, format: 'airtel', amountMatches: false },
    });
    // Rouge : ID Airtel daté de 2020, tapé à la main
    const red = await declare(groupId, c, { txReference: `CO200101.1036.T${(Date.now() + 2) % 100000}` });

    // Le bénéficiaire voit le niveau et les raisons ; le payeur, rien
    const seen = (await http().get(`/groups/${groupId}/cycles/1`).set(auth(president)).expect(200)).body;
    const riskOf = (id: string) => seen.payers.find((p: { contribution: { id: string } | null }) => p.contribution?.id === id).contribution.risk;
    expect(riskOf(green.id)).toEqual({ level: 'green', reasons: ['first_payment'] });
    expect(riskOf(orange.id)).toEqual({ level: 'orange', reasons: ['sms_amount_mismatch', 'first_payment'] });
    expect(riskOf(red.id)).toEqual({ level: 'red', reasons: ['tx_date_mismatch', 'sms_not_pasted', 'first_payment'] });
    const byPayer = (await http().get(`/groups/${groupId}/cycles/1`).set(auth(c)).expect(200)).body;
    for (const p of byPayer.payers) if (p.contribution) expect(p.contribution.risk).toBeNull();

    await confirm(president, green.id).expect(200);

    const noAck = await confirm(president, orange.id).expect(409);
    expect(noAck.body).toMatchObject({ code: 'risk_check_required', level: 'orange' });
    await confirm(president, orange.id, { riskAcknowledged: true }).expect(200);

    const redAckOnly = await confirm(president, red.id, { riskAcknowledged: true }).expect(409);
    expect(redAckOnly.body.message).toContain('Collez le SMS');
    const wrongId = await confirm(president, red.id, { riskAcknowledged: true, receivedTxReference: 'CO261019.1034.T99999' }).expect(409);
    expect(wrongId.body.message).toContain('ne correspond pas');
    await confirm(president, red.id, { riskAcknowledged: true, receivedTxReference: red.txReference.toLowerCase() }).expect(200);

    // La vérification est journalisée hors de la chaîne du groupe (que le payeur peut lire)
    const audit = await api.db.query<{ group_id: string | null; payload: string }>(
      `SELECT group_id, payload FROM audit_log WHERE action = 'contribution.risk_checked' AND payload::jsonb->>'contribution_id' = $1`,
      [red.id],
    );
    expect(audit.rows).toHaveLength(1);
    expect(audit.rows[0].group_id).toBeNull();
    expect(JSON.parse(audit.rows[0].payload)).toMatchObject({ level: 'red', sms_verified: true });
    const history = await api.db.query(`SELECT 1 FROM audit_log WHERE group_id = $1 AND payload LIKE '%risk%'`, [groupId]);
    expect(history.rowCount).toBe(0);

    // L'équipe retrouve les déclarations orange et rouges dans « Alertes »
    const created = await api.app
      .get(StaffAuthService)
      .create(null, { email: `risk-${randomUUID().slice(0, 8)}@mchango.test`, fullName: 'Agent', role: 'support' });
    const login = await http()
      .post('/admin/auth/login')
      .send({ email: created.email, password: created.temporaryPassword, code: totpCode(created.totpSecret) })
      .expect(200);
    const alerts = await http().get('/admin/alerts').set({ Authorization: `Bearer ${login.body.token}` }).expect(200);
    const mine = alerts.body.riskyContributions.filter((x: { group: { id: string } }) => x.group.id === groupId);
    expect(mine.map((x: { level: string; status: string }) => [x.level, x.status])).toEqual([
      ['red', 'confirmed'],
      ['orange', 'confirmed'],
    ]);
  });
});
