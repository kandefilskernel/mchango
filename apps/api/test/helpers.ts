import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { generateKeyPairSync, randomInt, sign, type KeyObject } from 'node:crypto';
import request from 'supertest';
import { App } from 'supertest/types.js';
import { AppModule } from '../src/app.module.js';
import { challengeMessage } from '../src/auth/device-key.js';
import { Db } from '../src/infra/database.js';
import { ConsoleSmsSender, SMS_SENDER } from '../src/infra/sms.js';

export const GOOD_PIN = '482915';

export interface Device {
  publicKey: string;
  privateKey: KeyObject;
}

export interface TestSession {
  userId: string;
  deviceId: string;
  accessToken: string;
}

export function newDevice(): Device {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  const raw = publicKey.export({ format: 'der', type: 'spki' }).subarray(12);
  return { publicKey: raw.toString('base64'), privateKey };
}

/** Numéro unique par test : la base de développement n'est pas vidée entre deux lancements. */
export function newPhone(): string {
  return `+24399${randomInt(0, 10_000_000).toString().padStart(7, '0')}`;
}

/** Application complète branchée sur PostgreSQL et Redis de docker compose. */
export class TestApi {
  private constructor(
    readonly app: INestApplication<App>,
    readonly sms: ConsoleSmsSender,
    readonly db: Db,
  ) {}

  static async start(): Promise<TestApi> {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    const app = moduleRef.createNestApplication<INestApplication<App>>();
    await app.init();
    return new TestApi(app, app.get(SMS_SENDER), app.get(Db));
  }

  close() {
    return this.app.close();
  }

  http() {
    return request(this.app.getHttpServer());
  }

  lastCode(phone: string): string {
    const message = this.sms.sent.filter((m) => m.phone === phone).at(-1)?.message ?? '';
    return /code est (\d{6})/.exec(message)![1];
  }

  async verifiedOtpToken(phone: string) {
    await this.http().post('/auth/otp/request').send({ phone }).expect(202);
    const res = await this.http()
      .post('/auth/otp/verify')
      .send({ phone, code: this.lastCode(phone) })
      .expect(200);
    return res.body as { otpToken: string; accountExists: boolean };
  }

  async signUp(phone = newPhone(), device = newDevice(), fullName = 'Mama Furaha') {
    const { otpToken } = await this.verifiedOtpToken(phone);
    const res = await this.http()
      .post('/auth/register')
      .send({ otpToken, fullName, pin: GOOD_PIN, devicePublicKey: device.publicKey })
      .expect(201);
    return { phone, device, session: res.body as TestSession };
  }

  async openSession(deviceId: string, device: Device) {
    const { body } = await this.http().post('/auth/challenge').send({ deviceId }).expect(200);
    const signature = sign(null, Buffer.from(challengeMessage(deviceId, body.nonce)), device.privateKey);
    return this.http()
      .post('/auth/session')
      .send({ deviceId, nonce: body.nonce, signature: signature.toString('base64') });
  }
}
