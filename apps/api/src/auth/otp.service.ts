import { HttpException, HttpStatus, Inject, Injectable } from '@nestjs/common';
import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';
import type { Redis } from 'ioredis';
import { APP_CONFIG, type AppConfig } from '../config.js';
import { REDIS } from '../infra/redis.js';
import { SMS_SENDER, type SmsSender } from '../infra/sms.js';
import {
  OTP_MAX_ATTEMPTS,
  OTP_MAX_PER_PHONE,
  OTP_PHONE_WINDOW_SECONDS,
  OTP_TTL_SECONDS,
} from './auth.constants.js';

/**
 * Codes SMS à 6 chiffres. Le code n'est jamais stocké en clair : seulement son HMAC
 * (avec un secret serveur), dans Redis, avec expiration.
 */
@Injectable()
export class OtpService {
  constructor(
    @Inject(REDIS) private readonly redis: Redis,
    @Inject(APP_CONFIG) private readonly config: AppConfig,
    @Inject(SMS_SENDER) private readonly sms: SmsSender,
  ) {}

  async request(phone: string, ip: string): Promise<void> {
    await this.limit(`rl:otp:ip:${ip}`, this.config.OTP_MAX_PER_IP_PER_HOUR, 3600);
    await this.limit(`rl:otp:phone:${phone}`, OTP_MAX_PER_PHONE, OTP_PHONE_WINDOW_SECONDS);

    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    await this.redis
      .multi()
      .set(this.codeKey(phone), this.digest(phone, code), 'EX', OTP_TTL_SECONDS)
      .del(this.attemptsKey(phone))
      .exec();
    await this.sms.send(
      phone,
      `Mchango : votre code est ${code}. Il expire dans 5 minutes. ` +
        `Ne le donnez à personne, même pas à l'équipe Mchango.`,
    );
  }

  /** Vrai si le code est bon. Un code ne sert qu'une fois et brûle après trop d'essais. */
  async verify(phone: string, code: string): Promise<boolean> {
    const attempts = await this.redis.incr(this.attemptsKey(phone));
    if (attempts === 1) await this.redis.expire(this.attemptsKey(phone), OTP_TTL_SECONDS);
    if (attempts > OTP_MAX_ATTEMPTS) {
      await this.redis.del(this.codeKey(phone));
      return false;
    }

    const stored = await this.redis.get(this.codeKey(phone));
    if (!stored || !/^\d{6}$/.test(code)) return false;
    const matches = timingSafeEqual(
      Buffer.from(stored, 'hex'),
      Buffer.from(this.digest(phone, code), 'hex'),
    );
    // del() === 1 : seule la première vérification concurrente l'emporte
    return matches && (await this.redis.del(this.codeKey(phone))) === 1;
  }

  private async limit(key: string, max: number, windowSeconds: number) {
    const count = await this.redis.incr(key);
    if (count === 1) await this.redis.expire(key, windowSeconds);
    if (count > max) {
      throw new HttpException(
        'Trop de demandes de code. Réessayez dans quelques minutes.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }

  private digest(phone: string, code: string): string {
    return createHmac('sha256', this.config.OTP_PEPPER).update(`${phone}:${code}`).digest('hex');
  }

  private codeKey(phone: string) {
    return `otp:code:${phone}`;
  }

  private attemptsKey(phone: string) {
    return `otp:attempts:${phone}`;
  }
}
