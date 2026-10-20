import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { generateKeyPairSync, randomInt, sign, type KeyObject } from 'node:crypto';
import request from 'supertest';
import { App } from 'supertest/types.js';
import { AppModule } from '../src/app.module.js';
import { challengeMessage } from '../src/auth/device-key.js';
import { Db } from '../src/infra/database.js';
import { ConsoleSmsSender, SMS_SENDER } from '../src/infra/sms.js';

const GOOD_PIN = '482915';

interface Device {
  publicKey: string;
  privateKey: KeyObject;
}

function newDevice(): Device {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  const raw = publicKey.export({ format: 'der', type: 'spki' }).subarray(12);
  return { publicKey: raw.toString('base64'), privateKey };
}

/** Numéro unique par test : la base de développement n'est pas vidée entre deux lancements. */
function newPhone(): string {
  return `+24399${randomInt(0, 10_000_000).toString().padStart(7, '0')}`;
}

describe('Authentification (e2e)', () => {
  let app: INestApplication<App>;
  let sms: ConsoleSmsSender;
  let db: Db;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    await app.init();
    sms = app.get(SMS_SENDER);
    db = app.get(Db);
  });

  afterAll(async () => {
    await app.close();
  });

  const http = () => request(app.getHttpServer());

  function lastCode(phone: string): string {
    const message = sms.sent.filter((m) => m.phone === phone).at(-1)?.message ?? '';
    return /code est (\d{6})/.exec(message)![1];
  }

  async function verifiedOtpToken(phone: string) {
    await http().post('/auth/otp/request').send({ phone }).expect(202);
    const res = await http()
      .post('/auth/otp/verify')
      .send({ phone, code: lastCode(phone) })
      .expect(200);
    return res.body as { otpToken: string; accountExists: boolean };
  }

  async function signUp(phone = newPhone(), device = newDevice()) {
    const { otpToken } = await verifiedOtpToken(phone);
    const res = await http()
      .post('/auth/register')
      .send({ otpToken, fullName: 'Mama Furaha', pin: GOOD_PIN, devicePublicKey: device.publicKey })
      .expect(201);
    return { phone, device, session: res.body as { userId: string; deviceId: string; accessToken: string } };
  }

  async function openSession(deviceId: string, device: Device) {
    const { body } = await http().post('/auth/challenge').send({ deviceId }).expect(200);
    const signature = sign(null, Buffer.from(challengeMessage(deviceId, body.nonce)), device.privateKey);
    return http()
      .post('/auth/session')
      .send({ deviceId, nonce: body.nonce, signature: signature.toString('base64') });
  }

  it("inscription complète, puis /me avec le jeton d'accès", async () => {
    const phone = newPhone();
    const first = await verifiedOtpToken(phone);
    expect(first.accountExists).toBe(false);

    const { session } = await signUp(phone);
    const me = await http().get('/me').set('Authorization', `Bearer ${session.accessToken}`).expect(200);
    expect(me.body).toMatchObject({ id: session.userId, phone, full_name: 'Mama Furaha', language: 'fr' });
  });

  it('accepte le format local 09… et le normalise', async () => {
    const national = `099${randomInt(0, 10_000_000).toString().padStart(7, '0')}`;
    await http().post('/auth/otp/request').send({ phone: national }).expect(202);
    expect(sms.sent.at(-1)!.phone).toBe(`+243${national.slice(1)}`);
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

    const { rows } = await db.query<{ action: string; payload: string }>(
      `SELECT action, payload FROM audit_log
       WHERE chain_id = 'global' AND payload::jsonb ->> 'user_id' = $1 ORDER BY seq`,
      [session.userId],
    );
    expect(rows.map((r) => r.action)).toEqual(['auth.user_registered', 'auth.device_linked']);
    expect(JSON.parse(rows[1].payload).revoked_device_ids).toEqual([session.deviceId]);
    expect(rows.some((r) => r.payload.includes(GOOD_PIN))).toBe(false);

    const check = await db.query<{ broken: string | null }>(
      `SELECT audit_verify_chain('global') AS broken`,
    );
    expect(check.rows[0].broken).toBeNull();
  });
});
