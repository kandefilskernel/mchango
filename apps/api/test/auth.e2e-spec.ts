import { randomInt, sign } from 'node:crypto';
import { challengeMessage } from '../src/auth/device-key.js';
import { GOOD_PIN, newDevice, newPhone, TestApi } from './helpers.js';

describe('Authentification (e2e)', () => {
  let api: TestApi;

  beforeAll(async () => {
    api = await TestApi.start();
  });

  afterAll(async () => {
    await api.close();
  });

  const http = () => api.http();
  const lastCode = (phone: string) => api.lastCode(phone);
  const verifiedOtpToken = (phone: string) => api.verifiedOtpToken(phone);
  const signUp = (phone?: string) => api.signUp(phone);
  const openSession = (...args: Parameters<TestApi['openSession']>) => api.openSession(...args);

  it("inscription complète, puis /me avec le jeton d'accès", async () => {
    const phone = newPhone();
    const first = await verifiedOtpToken(phone);
    expect(first.accountExists).toBe(false);

    const { session } = await signUp(phone);
    const me = await http().get('/me').set('Authorization', `Bearer ${session.accessToken}`).expect(200);
    expect(me.body).toMatchObject({ id: session.userId, phone, full_name: 'Mama Furaha', language: 'fr' });
  });

  it('langue : choisie à l\'inscription ou changée ensuite ; le code SMS suit la langue du compte', async () => {
    const phone = newPhone();
    const { session } = await signUp(phone);
    const auth = { Authorization: `Bearer ${session.accessToken}` };
    await http().put('/me/language').set(auth).send({ language: 'de' }).expect(400);
    await http().put('/me/language').set(auth).send({ language: 'ln' }).expect(200);
    expect((await http().get('/me').set(auth)).body.language).toBe('ln');
    await http().put('/me/language').send({ language: 'en' }).expect(401);

    await api.clearOtpLimit(phone);
    await http().post('/auth/otp/request').send({ phone }).expect(202);
    expect(api.sms.sent.filter((m) => m.phone === phone).at(-1)!.message).toMatch(/^Mchango: kode na yo ezali \d{6}\./);

    // Numéro inconnu : en français
    const stranger = newPhone();
    await http().post('/auth/otp/request').send({ phone: stranger }).expect(202);
    expect(api.sms.sent.filter((m) => m.phone === stranger).at(-1)!.message).toContain('votre code est');
  });

  it('accepte le format local 09… et le normalise', async () => {
    const national = `099${randomInt(0, 10_000_000).toString().padStart(7, '0')}`;
    await http().post('/auth/otp/request').send({ phone: national }).expect(202);
    expect(api.sms.sent.at(-1)!.phone).toBe(`+243${national.slice(1)}`);
  });

  it('refuse un numéro invalide', async () => {
    const res = await http().post('/auth/otp/request').send({ phone: '+33612345678' }).expect(400);
    expect(res.body.errors[0].message).toBe('Numéro de téléphone RDC invalide.');
  });

  it("le code ne passe plus après 5 essais faux, même s'il est bon", async () => {
    const phone = newPhone();
    await http().post('/auth/otp/request').send({ phone }).expect(202);
    const code = lastCode(phone);
    const wrong = code === '000000' ? '111111' : '000000';
    for (let i = 0; i < 5; i++) {
      await http().post('/auth/otp/verify').send({ phone, code: wrong }).expect(401);
    }
    await http().post('/auth/otp/verify').send({ phone, code }).expect(401);
  });

  it('un code ne sert qu’une fois', async () => {
    const phone = newPhone();
    await http().post('/auth/otp/request').send({ phone }).expect(202);
    const code = lastCode(phone);
    await http().post('/auth/otp/verify').send({ phone, code }).expect(200);
    await http().post('/auth/otp/verify').send({ phone, code }).expect(401);
  });

  it('limite à 3 codes par numéro sur 15 minutes', async () => {
    const phone = newPhone();
    for (let i = 0; i < 3; i++) await http().post('/auth/otp/request').send({ phone }).expect(202);
    await http().post('/auth/otp/request').send({ phone }).expect(429);
  });

  it('PIN faible refusé, et la vérification du numéro reste utilisable', async () => {
    const phone = newPhone();
    const { otpToken } = await verifiedOtpToken(phone);
    const device = newDevice();
    const body = { otpToken, fullName: 'Papa Jean', devicePublicKey: device.publicKey };
    await http().post('/auth/register').send({ ...body, pin: '123456' }).expect(400);
    await http().post('/auth/register').send({ ...body, pin: GOOD_PIN }).expect(201);
  });

  it('la vérification du numéro ne sert qu’une fois', async () => {
    const phone = newPhone();
    const { otpToken } = await verifiedOtpToken(phone);
    const send = () =>
      http()
        .post('/auth/register')
        .send({ otpToken, fullName: 'Papa Jean', pin: GOOD_PIN, devicePublicKey: newDevice().publicKey });
    await send().expect(201);
    await send().expect(401);
  });

  it('refuse une seconde inscription pour le même numéro', async () => {
    const { phone } = await signUp();
    const again = await verifiedOtpToken(phone);
    expect(again.accountExists).toBe(true);
    await http()
      .post('/auth/register')
      .send({ otpToken: again.otpToken, fullName: 'Imposteur', pin: GOOD_PIN, devicePublicKey: newDevice().publicKey })
      .expect(409);
  });

  it("session : l'appareil signe le défi ; signature fausse et défi rejoué refusés", async () => {
    const { device, session } = await signUp();
    const ok = await openSession(session.deviceId, device);
    expect(ok.status).toBe(200);
    expect(ok.body.userId).toBe(session.userId);

    const intruder = await openSession(session.deviceId, newDevice());
    expect(intruder.status).toBe(401);

    const { body } = await http().post('/auth/challenge').send({ deviceId: session.deviceId }).expect(200);
    const signature = sign(
      null,
      Buffer.from(challengeMessage(session.deviceId, body.nonce)),
      device.privateKey,
    ).toString('base64');
    const payload = { deviceId: session.deviceId, nonce: body.nonce, signature };
    await http().post('/auth/session').send(payload).expect(200);
    await http().post('/auth/session').send(payload).expect(401);
  });

  it("nouveau téléphone : code SMS + PIN, l'ancien appareil est révoqué", async () => {
    const { phone, device: oldDevice, session: oldSession } = await signUp();
    const { otpToken } = await verifiedOtpToken(phone);
    const newPhoneDevice = newDevice();
    const linked = await http()
      .post('/auth/devices')
      .send({ otpToken, pin: GOOD_PIN, devicePublicKey: newPhoneDevice.publicKey })
      .expect(201);
    expect(linked.body.userId).toBe(oldSession.userId);

    expect((await openSession(oldSession.deviceId, oldDevice)).status).toBe(401);
    expect((await openSession(linked.body.deviceId, newPhoneDevice)).status).toBe(200);
  });

  it('PIN faux 5 fois : bloqué 30 minutes, même avec le bon PIN', async () => {
    const { phone } = await signUp();
    const { otpToken } = await verifiedOtpToken(phone);
    const attempt = (pin: string) =>
      http().post('/auth/devices').send({ otpToken, pin, devicePublicKey: newDevice().publicKey });

    for (let remaining = 4; remaining >= 1; remaining--) {
      const res = await attempt('999990');
      expect(res.status).toBe(401);
      expect(res.body.message).toContain(`${remaining} essai`);
    }
    expect((await attempt('999990')).status).toBe(423);
    const locked = await attempt(GOOD_PIN);
    expect(locked.status).toBe(423);
    expect(new Date(locked.body.lockedUntil).getTime()).toBeGreaterThan(Date.now() + 29 * 60_000);
  });

  it('/me exige un vrai jeton d’accès (pas le jeton de vérification du numéro)', async () => {
    await http().get('/me').expect(401);
    const { otpToken } = await verifiedOtpToken(newPhone());
    await http().get('/me').set('Authorization', `Bearer ${otpToken}`).expect(401);
  });

  it('journalise inscription et changement de téléphone, chaîne « global » intacte', async () => {
    const { phone, session } = await signUp();
    const { otpToken } = await verifiedOtpToken(phone);
    await http()
      .post('/auth/devices')
      .send({ otpToken, pin: GOOD_PIN, devicePublicKey: newDevice().publicKey })
      .expect(201);

    const { rows } = await api.db.query<{ action: string; payload: string }>(
      `SELECT action, payload FROM audit_log
       WHERE chain_id = 'global' AND payload::jsonb ->> 'user_id' = $1 ORDER BY seq`,
      [session.userId],
    );
    expect(rows.map((r) => r.action)).toEqual(['auth.user_registered', 'auth.device_linked']);
    expect(JSON.parse(rows[1].payload).revoked_device_ids).toEqual([session.deviceId]);
    expect(rows.some((r) => r.payload.includes(GOOD_PIN))).toBe(false);

    const check = await api.db.query<{ broken: string | null }>(
      `SELECT audit_verify_chain('global') AS broken`,
    );
    expect(check.rows[0].broken).toBeNull();
  });
});
