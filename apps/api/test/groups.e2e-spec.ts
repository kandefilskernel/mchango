import { TestApi, type TestSession } from './helpers.js';

function inDays(days: number): string {
  const d = new Date(Date.now() + days * 86_400_000);
  return d.toISOString().slice(0, 10);
}

const newGroup = (overrides: object = {}) => ({
  name: 'Likelemba Kenya',
  currency: 'CDF',
  contributionAmountMinor: 20000,
  frequency: 'weekly',
  startDate: inDays(7),
  ...overrides,
});

describe('Groupes et invitations (e2e)', () => {
  let api: TestApi;

  beforeAll(async () => {
    api = await TestApi.start();
  });

  afterAll(async () => {
    await api.close();
  });

  const auth = (s: TestSession) => ({ Authorization: `Bearer ${s.accessToken}` });

  async function user(name = 'Membre') {
    return (await api.signUp(undefined, undefined, name)).session;
  }

  async function createGroup(president: TestSession, overrides: object = {}) {
    const res = await api.http().post('/groups').set(auth(president)).send(newGroup(overrides)).expect(201);
    return res.body as { id: string; myRole: string };
  }

  async function invite(president: TestSession, groupId: string, body: object = {}) {
    const res = await api
      .http()
      .post(`/groups/${groupId}/invitations`)
      .set(auth(president))
      .send(body)
      .expect(201);
    return res.body as { code: string; shareText: string; expiresAt: string };
  }

  const join = (member: TestSession, code: string, acceptRules = true) =>
    api.http().post('/groups/join').set(auth(member)).send({ code, acceptRules });

  it('crée un groupe en brouillon ; son créateur en est le président', async () => {
    const president = await user('Mama Furaha');
    const res = await api.http().post('/groups').set(auth(president)).send(newGroup()).expect(201);
    expect(res.body).toMatchObject({
      name: 'Likelemba Kenya',
      type: 'informel',
      currency: 'CDF',
      contributionAmountMinor: 20000,
      payoutMode: 'direct_to_beneficiary',
      status: 'draft',
      maxMembers: 30,
      myRole: 'president',
      memberCount: 1,
    });

    const mine = await api.http().get('/groups').set(auth(president)).expect(200);
    expect(mine.body.map((g: { id: string }) => g.id)).toContain(res.body.id);
  });

  it.each([
    [{ startDate: inDays(-2) }, 'date de début passée'],
    [{ contributionAmountMinor: 1500.5 }, 'montant non entier'],
    [{ contributionAmountMinor: 0 }, 'montant nul'],
    [{ currency: 'EUR' }, 'devise non prise en charge'],
    [{ frequency: 'custom' }, 'fréquence personnalisée (pas encore)'],
    [{ maxMembers: 1 }, 'groupe d’une personne'],
  ])('refuse un groupe invalide : %o (%s)', async (overrides: object, _reason: string) => {
    const president = await user();
    await api.http().post('/groups').set(auth(president)).send(newGroup(overrides)).expect(400);
  });

  it('invitation par code : le membre rejoint et voit les autres membres', async () => {
    const president = await user('Mama Furaha');
    const group = await createGroup(president);
    const { code, shareText } = await invite(president, group.id);
    expect(code).toMatch(/^[2-9A-Z]{4}-[2-9A-Z]{4}$/);
    expect(shareText).toContain(code);
    expect(shareText).toContain('Likelemba Kenya');

    const member = await user('Papa Jean');
    // saisie en minuscules et sans tiret acceptée
    await join(member, code.toLowerCase().replace('-', '')).expect(200);

    const detail = await api.http().get(`/groups/${group.id}`).set(auth(member)).expect(200);
    expect(detail.body.myRole).toBe('member');
    expect(detail.body.members.map((m: { fullName: string }) => m.fullName)).toEqual([
      'Mama Furaha',
      'Papa Jean',
    ]);
  });

  it("un non-membre ne voit pas le groupe (404, pas 403 : n'en révèle pas l'existence)", async () => {
    const president = await user();
    const group = await createGroup(president);
    const outsider = await user();
    await api.http().get(`/groups/${group.id}`).set(auth(outsider)).expect(404);
  });

  it('seul le président invite', async () => {
    const president = await user();
    const group = await createGroup(president);
    const member = await user();
    await join(member, (await invite(president, group.id)).code).expect(200);
    await api.http().post(`/groups/${group.id}/invitations`).set(auth(member)).send({}).expect(403);
  });

  it('rejoindre exige d’accepter le règlement', async () => {
    const president = await user();
    const group = await createGroup(president);
    const { code } = await invite(president, group.id);
    await join(await user(), code, false).expect(400);
  });

  it('refuse de rejoindre deux fois', async () => {
    const president = await user();
    const group = await createGroup(president);
    const { code } = await invite(president, group.id);
    const member = await user();
    await join(member, code).expect(200);
    await join(member, code).expect(409);
  });

  it("respecte le nombre d'utilisations du code", async () => {
    const president = await user();
    const group = await createGroup(president);
    const { code } = await invite(president, group.id, { maxUses: 1 });
    await join(await user(), code).expect(200);
    await join(await user(), code).expect(409);
  });

  it('respecte la taille maximale du groupe', async () => {
    const president = await user();
    const group = await createGroup(president, { maxMembers: 2 });
    const { code } = await invite(president, group.id);
    await join(await user(), code).expect(200);
    const full = await join(await user(), code).expect(409);
    expect(full.body.message).toBe('Le groupe est complet.');
  });

  it('on ne rejoint plus un groupe qui a démarré', async () => {
    const president = await user();
    const group = await createGroup(president);
    const { code } = await invite(president, group.id);
    await api.db.transaction({ type: 'system' }, (q) =>
      q.query(`UPDATE groups SET status = 'active' WHERE id = $1`, [group.id]),
    );
    await join(await user(), code).expect(409);
    await api.http().post(`/groups/${group.id}/invitations`).set(auth(president)).send({}).expect(409);
  });

  it('code inconnu : 404 ; plus de 10 essais en une heure : 429', async () => {
    const member = await user();
    for (let i = 0; i < 10; i++) await join(member, 'ZZZZ-ZZZZ').expect(404);
    await join(member, 'ZZZZ-ZZZZ').expect(429);
  });

  it('journal du groupe : création, adhésions par leurs auteurs, invitation sans le code', async () => {
    const president = await user();
    const group = await createGroup(president);
    const { code } = await invite(president, group.id);
    const member = await user();
    await join(member, code).expect(200);

    const { rows } = await api.db.query<{ action: string; actor_id: string; payload: string }>(
      `SELECT action, actor_id, payload FROM audit_log WHERE chain_id = $1 ORDER BY seq`,
      [`group:${group.id}`],
    );
    expect(rows.map((r) => [r.action, r.actor_id])).toEqual([
      ['groups.insert', president.userId],
      ['memberships.insert', president.userId],
      ['group.invitation_created', president.userId],
      ['memberships.insert', member.userId],
    ]);
    const normalized = code.replace('-', '');
    expect(rows.some((r) => r.payload.includes(code) || r.payload.includes(normalized))).toBe(false);

    const check = await api.db.query<{ broken: string | null }>(
      'SELECT audit_verify_chain($1) AS broken',
      [`group:${group.id}`],
    );
    expect(check.rows[0].broken).toBeNull();
  });
});
