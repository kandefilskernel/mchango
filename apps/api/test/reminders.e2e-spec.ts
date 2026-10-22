import { randomUUID } from 'node:crypto';
import { RemindersService } from '../src/reminders/reminders.service.js';
import { TestApi, type TestSession } from './helpers.js';

const TZ = 'Africa/Lubumbashi';
const todayDrc = () => new Intl.DateTimeFormat('en-CA', { timeZone: TZ }).format(new Date());
const plusDays = (iso: string, days: number) =>
  new Date(Date.parse(`${iso}T00:00:00Z`) + days * 86_400_000).toISOString().slice(0, 10);
/** Aujourd'hui à Lubumbashi, à l'heure donnée. */
const atDrc = (hour: number) => new Date(`${todayDrc()}T${String(hour).padStart(2, '0')}:00:00+02:00`);

describe('Rappels avant échéance (e2e)', () => {
  let api: TestApi;
  let reminders: RemindersService;

  beforeAll(async () => {
    api = await TestApi.start();
    reminders = api.app.get(RemindersService);
  });

  afterAll(async () => {
    await api.close();
  });

  const auth = (s: TestSession) => ({ Authorization: `Bearer ${s.accessToken}` });

  /** Tontine démarrée à 3 : le président reçoit au tour 1, dont l'échéance est startDate. */
  async function startedGroup(frequency: string, startDate: string, start = true) {
    const people = [];
    for (const name of ['Mama Furaha', 'Papa Jean', 'Mama Neema']) people.push(await api.signUp(undefined, undefined, name));
    const [president, ...others] = people;
    const group = (
      await api
        .http()
        .post('/groups')
        .set(auth(president.session))
        .send({ name: 'Kwetu', currency: 'CDF', contributionAmountMinor: 20000, frequency, startDate })
        .expect(201)
    ).body as { id: string };
    const { code } = (await api.http().post(`/groups/${group.id}/invitations`).set(auth(president.session)).send({}))
      .body as { code: string };
    for (const p of others) {
      await api.http().post('/groups/join').set(auth(p.session)).send({ code, acceptRules: true }).expect(200);
    }
    const detail = (await api.http().get(`/groups/${group.id}`).set(auth(president.session))).body as {
      members: { userId: string; membershipId: string }[];
    };
    const membershipOf = (s: TestSession) => detail.members.find((m) => m.userId === s.userId)!.membershipId;
    await api
      .http()
      .put(`/groups/${group.id}/turn-order`)
      .set(auth(president.session))
      .send({ membershipIds: people.map((p) => membershipOf(p.session)) })
      .expect(200);
    if (start) await api.http().post(`/groups/${group.id}/start`).set(auth(president.session)).expect(200);
    return { groupId: group.id, president, payers: others };
  }

  /** Rappels reçus par ce numéro (sans le SMS du code de connexion de l'inscription). */
  const smsTo = (phone: string) => api.sms.sent.filter((m) => m.phone === phone && m.message.includes('Payez'));

  it('hebdomadaire : la veille, un SMS à chaque payeur, rien au bénéficiaire, et une seule fois', async () => {
    const g = await startedGroup('weekly', plusDays(todayDrc(), 1));
    await reminders.runOnce(atDrc(10));

    for (const p of g.payers) {
      const sms = smsTo(p.phone);
      expect(sms).toHaveLength(1);
      expect(sms[0].message).toContain('Kwetu, tour 1. Payez 20 000 FC à Mama Furaha');
      expect(sms[0].message).toContain(g.president.phone);
    }
    expect(smsTo(g.president.phone)).toHaveLength(0);

    await reminders.runOnce(atDrc(14));
    for (const p of g.payers) expect(smsTo(p.phone)).toHaveLength(1);

    const { rows } = await api.db.query<{ status: string; n: number }>(
      `SELECT n.status, count(*)::int AS n FROM notifications n
       WHERE n.template = 'contribution_reminder' AND n.user_id = ANY($1::uuid[]) GROUP BY n.status`,
      [g.payers.map((p) => p.session.userId)],
    );
    expect(rows).toEqual([{ status: 'sent', n: 2 }]);
  });

  it('chaque payeur reçoit le rappel dans sa langue', async () => {
    const g = await startedGroup('weekly', plusDays(todayDrc(), 1));
    const [sw, en] = g.payers;
    await api.db.query(`UPDATE users SET language = 'sw' WHERE id = $1`, [sw.session.userId]);
    await api.db.query(`UPDATE users SET language = 'en' WHERE id = $1`, [en.session.userId]);
    await reminders.runOnce(atDrc(10));
    const last = (phone: string) => api.sms.sent.filter((m) => m.phone === phone).at(-1)!.message;
    expect(last(sw.phone)).toContain('Mchango: Kwetu, zamu 1. Lipa 20 000 FC kwa Mama Furaha');
    expect(last(en.phone)).toContain('Mchango: Kwetu, turn 1. Pay 20 000 FC to Mama Furaha');
  });

  it('pas de rappel à qui a déjà déclaré son paiement', async () => {
    const g = await startedGroup('weekly', plusDays(todayDrc(), 1));
    const [early, late] = g.payers;
    await api
      .http()
      .post(`/groups/${g.groupId}/cycles/1/contributions`)
      .set(auth(early.session))
      .send({ method: 'mpesa', txReference: `MP${Date.now()}R`, amountMinor: 20000, offlineId: randomUUID() })
      .expect(201);
    await reminders.runOnce(atDrc(10));
    expect(smsTo(early.phone)).toHaveLength(0);
    expect(smsTo(late.phone)).toHaveLength(1);
  });

  it('pas de SMS la nuit', async () => {
    const g = await startedGroup('weekly', plusDays(todayDrc(), 1));
    await reminders.runOnce(atDrc(6));
    await reminders.runOnce(atDrc(21));
    for (const p of g.payers) expect(smsTo(p.phone)).toHaveLength(0);
    await reminders.runOnce(atDrc(8));
    for (const p of g.payers) expect(smsTo(p.phone)).toHaveLength(1);
  });

  it("quotidienne : le matin même, avec « aujourd'hui »", async () => {
    const g = await startedGroup('daily', todayDrc());
    await reminders.runOnce(atDrc(9));
    for (const p of g.payers) {
      expect(smsTo(p.phone)).toHaveLength(1);
      expect(smsTo(p.phone)[0].message).toContain("aujourd'hui");
    }
  });

  it('ni trop tôt, ni pour une tontine pas encore démarrée', async () => {
    const later = await startedGroup('weekly', plusDays(todayDrc(), 3));
    const draft = await startedGroup('weekly', plusDays(todayDrc(), 1), false);
    await reminders.runOnce(atDrc(10));
    for (const p of [...later.payers, ...draft.payers]) expect(smsTo(p.phone)).toHaveLength(0);
  });
});
