import { Body, Controller, Get, HttpCode, Ip, Post, Put, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import { parseBody } from '../common/parse-body.js';
import { Db } from '../infra/database.js';
import { LANGUAGES } from '../infra/languages.js';
import { AccessGuard, CurrentAuth } from './access.guard.js';
import { AuthService, type AccessTokenClaims } from './auth.service.js';
import { normalizeDrcPhone } from './phone.js';

const phone = z
  .string()
  .transform((value, ctx) => {
    const normalized = normalizeDrcPhone(value);
    if (!normalized) {
      ctx.addIssue({ code: 'custom', message: 'Numéro de téléphone RDC invalide.' });
      return z.NEVER;
    }
    return normalized;
  });
const publicKey = z.string().max(64);
const uuid = z.uuid();

const RequestOtp = z.object({ phone });
const VerifyOtp = z.object({ phone, code: z.string().max(6) });
const Register = z.object({
  otpToken: z.string().max(2048),
  fullName: z.string().trim().min(2).max(150),
  pin: z.string().max(6),
  devicePublicKey: publicKey,
  language: z.enum(LANGUAGES).default('fr'),
});
const SetLanguage = z.object({ language: z.enum(LANGUAGES) });
const LinkDevice = z.object({
  otpToken: z.string().max(2048),
  pin: z.string().max(6),
  devicePublicKey: publicKey,
});
const Challenge = z.object({ deviceId: uuid });
const OpenSession = z.object({
  deviceId: uuid,
  nonce: z.string().max(64),
  signature: z.string().max(128),
});

@Controller()
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly db: Db,
  ) {}

  /** Répond 202 dans tous les cas où le numéro est bien formé : ne révèle pas s'il a un compte. */
  @Post('auth/otp/request')
  @HttpCode(202)
  async requestOtp(@Body() body: unknown, @Ip() ip: string) {
    const input = parseBody(RequestOtp, body);
    await this.auth.requestOtp(input.phone, ip);
    return { message: 'Un code a été envoyé par SMS.' };
  }

  @Post('auth/otp/verify')
  @HttpCode(200)
  verifyOtp(@Body() body: unknown) {
    const input = parseBody(VerifyOtp, body);
    return this.auth.verifyOtp(input.phone, input.code);
  }

  @Post('auth/register')
  register(@Body() body: unknown) {
    return this.auth.register(parseBody(Register, body));
  }

  @Post('auth/devices')
  linkDevice(@Body() body: unknown) {
    return this.auth.linkDevice(parseBody(LinkDevice, body));
  }

  @Post('auth/challenge')
  @HttpCode(200)
  challenge(@Body() body: unknown) {
    return this.auth.createChallenge(parseBody(Challenge, body).deviceId);
  }

  @Post('auth/session')
  @HttpCode(200)
  openSession(@Body() body: unknown) {
    return this.auth.openSession(parseBody(OpenSession, body));
  }

  @Get('me')
  @UseGuards(AccessGuard)
  async me(@CurrentAuth() auth: AccessTokenClaims) {
    const { rows } = await this.db.query<{
      id: string;
      phone: string;
      full_name: string;
      language: string;
    }>('SELECT id, phone, full_name, language FROM users WHERE id = $1', [auth.sub]);
    return { ...rows[0], deviceId: auth.did };
  }

  /** Langue de l'app, reprise pour les SMS (code de connexion, rappels). */
  @Put('me/language')
  @UseGuards(AccessGuard)
  async setLanguage(@CurrentAuth() auth: AccessTokenClaims, @Body() body: unknown) {
    const { language } = parseBody(SetLanguage, body);
    await this.db.query('UPDATE users SET language = $2 WHERE id = $1', [auth.sub, language]);
    return { language };
  }
}
