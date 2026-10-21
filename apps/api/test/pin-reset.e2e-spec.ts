import { GOOD_PIN, newDevice, TestApi, type Device, type TestSession } from './helpers.js';

const NEW_PIN = '270418';

interface Person {
  phone: string;
  device: Device;
  session: TestSession;
}

describe('PIN oublié (e2e)', () => {
  let api: TestApi;

  beforeAll(async () => {
    api = await TestApi.start();
  });

  afterAll(async () => {
    await api.close();
  });

  const http = () => api.http();
  const auth = (s: TestSession) => ({ Authorization: `Bearer ${s.accessToken}` });

  /** Tontine en préparation : un président et des membres. */
  async function group(names: string[]) {
    const people: Person[] = [];
    for (const n of names) people.push(await api.signUp(undefined, undefined, n));
    const [president, ...members] = people;
    const g = (
      await http()
        .post('/groups')
        .set(auth(president.session))
        .send({
          name: 'Kwetu',
          currency: 'CDF',
          contributionAmountMinor: 20000,
          frequency: 'weekly',
          startDate: new Date(Date.now() + 7 * 86_400_000).toISOString().slice(0, 10),
        })
        .expect(201)
    ).body as { id: string };
    const { code } = (await http().post(`/groups/${g.id}/invitations`).set(auth(president.session)).send({}))
      .body as { code: string };
    for (const m of members) {
      await http().post('/groups/join').set(auth(m.session)).send({ code, acceptRules: true }).expect(200);
    }
    return { groupId: g.id, president, members };
  }

  /** Le demandeur, sur un nouveau téléphone : code SMS, puis « PIN oublié ». */
  async function requestReset(phone: string, pin = NEW_PIN) {
    const device = newDevice();
    const { otpToken } = await api.verifiedOtpToken(phone);
    const res = await http().post('/auth/pin-reset').send({ otpToken, newPin: pin, devicePublicKey: device.publicKey });
    return { res, device };
  }

  /** Lier un téléphone avec code SMS + PIN : réussit seulement si le PIN est le bon. */
  async function linkWith(phone: string, pin: string) {
    await api.clearOtpLimit(phone);
    const { otpToken } = await api.verifiedOtpToken(phone);
    return http().post('/auth/devices').send({ otpToken, pin, devicePublicKey: newDevice().publicKey });
  }

  const smsTo = (phone: string) => api.sms.sent.filter((m) => m.phone === phone && m.message.includes('nouveau PIN'));

  it('sans tontine en cours : le code SMS suffit, nouveau PIN et téléphone actifs tout de suite', async () => {
    const me = await api.signUp();
    const { res, device } = await requestReset(me.phone);
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ status: 'completed', userId: me.session.userId });

    expect((await api.openSession(res.body.deviceId, device)).status).toBe(200);
    expect((await api.openSession(me.session.deviceId, me.device)).status).toBe(401);
    expect((await linkWith(me.phone, GOOD_PIN)).status).toBe(401);
    expect((await linkWith(me.phone, NEW_PIN)).status).toBe(201);
  });

  it("membre d'une tontine : le président doit confirmer ; il est prévenu par SMS", async () => {
    const g = await group(['Mama Furaha', 'Papa Jean', 'Mama Neema']);
    const [jean, neema] = g.members;
    const { res, device } = await requestReset(jean.phone);
    expect(res.body).toMatchObject({
      status: 'pending',
      guarantors: [{ fullName: 'Mama Furaha', groupName: 'Kwetu' }],
    });
    const requestId = res.body.requestId as string;

    // Le code SMS seul ne suffit pas : rien n'a changé
    expect((await linkWith(jean.phone, NEW_PIN)).status).toBe(401);
    expect(smsTo(g.president.phone)).toHaveLength(1);
    expect(smsTo(neema.phone)).toHaveLength(0);

    // Un simple membre n'est pas garant d'un autre membre
    expect((await http().get('/pin-resets/pending').set(auth(neema.session)).expect(200)).body).toEqual([]);
    await http().post(`/pin-resets/${requestId}/approve`).set(auth(neema.session)).expect(404);

    const pending = await http().get('/pin-resets/pending').set(auth(g.president.session)).expect(200);
    expect(pending.body).toEqual([expect.objectContaining({ requestId, fullName: 'Papa Jean', phone: jean.phone })]);
    expect((await http().get(`/auth/pin-reset/${requestId}`).expect(200)).body).toMatchObject({
      status: 'pending',
      deviceId: null,
    });

    await http().post(`/pin-resets/${requestId}/approve`).set(auth(g.president.session)).expect(200);
    const done = await http().get(`/auth/pin-reset/${requestId}`).expect(200);
    expect(done.body.status).toBe('completed');

    expect((await api.openSession(done.body.deviceId, device)).status).toBe(200);
    expect((await api.openSession(jean.session.deviceId, jean.device)).status).toBe(401);
    await http().post(`/pin-resets/${requestId}/approve`).set(auth(g.president.session)).expect(409);

    // Visible de tout le groupe, et chaîne intacte
    const { rows } = await api.db.query<{ action: string; broken: string | null }>(
      `SELECT action, audit_verify_chain(chain_id) AS broken FROM audit_log
       WHERE chain_id = $1 AND action LIKE 'auth.pin_reset%'`,
      [`group:${g.groupId}`],
    );
    expect(rows).toEqual([{ action: 'auth.pin_reset_approved', broken: null }]);
  });

  it('président qui oublie son PIN : un membre de sa tontine confirme', async () => {
    const g = await group(['Mama Furaha', 'Papa Jean']);
    const { res, device } = await requestReset(g.president.phone);
    expect(res.body.guarantors).toEqual([{ fullName: 'Papa Jean', groupName: 'Kwetu' }]);
    await http().post(`/pin-resets/${res.body.requestId}/approve`).set(auth(g.members[0].session)).expect(200);
    const done = await http().get(`/auth/pin-reset/${res.body.requestId}`).expect(200);
    expect((await api.openSession(done.body.deviceId, device)).status).toBe(200);
  });

  it('refus du garant : rien ne change, l\'ancien PIN reste valable', async () => {
    const g = await group(['Mama Furaha', 'Papa Jean']);
    const jean = g.members[0];
    const { res } = await requestReset(jean.phone);
    await http().post(`/pin-resets/${res.body.requestId}/reject`).set(auth(g.president.session)).expect(200);
    expect((await http().get(`/auth/pin-reset/${res.body.requestId}`)).body.status).toBe('rejected');
    expect((await linkWith(jean.phone, NEW_PIN)).status).toBe(401);
    expect((await linkWith(jean.phone, GOOD_PIN)).status).toBe(201);
  });

  it('une nouvelle demande remplace la précédente ; une demande expire', async () => {
    const g = await group(['Mama Furaha', 'Papa Jean']);
    const jean = g.members[0];
    const first = (await requestReset(jean.phone)).res.body.requestId as string;
    const second = (await requestReset(jean.phone, '583920')).res.body.requestId as string;
    expect((await http().get(`/auth/pin-reset/${first}`)).body.status).toBe('cancelled');

    await api.db.query(`UPDATE pin_reset_requests SET expires_at = now() - interval '1 minute' WHERE id = $1`, [second]);
    expect((await http().get(`/auth/pin-reset/${second}`)).body.status).toBe('expired');
    await http().post(`/pin-resets/${second}/approve`).set(auth(g.president.session)).expect(409);
    expect((await http().get('/pin-resets/pending').set(auth(g.president.session))).body).toEqual([]);
  });

  it('refuse : PIN faible, vérification du numéro réutilisée, numéro inconnu', async () => {
    const me = await api.signUp();
    expect((await requestReset(me.phone, '123456')).res.status).toBe(400);

    const { otpToken } = await api.verifiedOtpToken(me.phone);
    const send = () =>
      http().post('/auth/pin-reset').send({ otpToken, newPin: NEW_PIN, devicePublicKey: newDevice().publicKey });
    expect((await send()).status).toBe(200);
    expect((await send()).status).toBe(401);

    const stranger = `+24399${Math.floor(Math.random() * 1e7).toString().padStart(7, '0')}`;
    expect((await requestReset(stranger)).res.status).toBe(404);
  });
});
