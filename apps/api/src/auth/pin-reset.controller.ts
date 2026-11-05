import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import { parseBody } from '../common/parse-body.js';
import { AccessGuard, CurrentAuth } from './access.guard.js';
import type { AccessTokenClaims } from './auth.service.js';
import { PinResetService } from './pin-reset.service.js';

const RequestReset = z.object({
  otpToken: z.string().max(2048),
  newPin: z.string().max(6),
  devicePublicKey: z.string().max(64),
});

@Controller()
export class PinResetController {
  constructor(private readonly pinReset: PinResetService) {}

  /** Le demandeur (sans session : il a oublié son PIN). */
  @Post('auth/pin-reset')
  @HttpCode(200)
  request(@Body() body: unknown) {
    return this.pinReset.request(parseBody(RequestReset, body));
  }

  @Get('auth/pin-reset/:id')
  status(@Param('id', ParseUUIDPipe) id: string) {
    return this.pinReset.status(id);
  }

  /** Les garants (connectés). */
  @Get('pin-resets/pending')
  @UseGuards(AccessGuard)
  pending(@CurrentAuth() auth: AccessTokenClaims) {
    return this.pinReset.pendingFor(auth.sub);
  }

  @Post('pin-resets/:id/approve')
  @HttpCode(200)
  @UseGuards(AccessGuard)
  approve(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) id: string) {
    return this.pinReset.approve(auth.sub, id);
  }

  @Post('pin-resets/:id/reject')
  @HttpCode(200)
  @UseGuards(AccessGuard)
  reject(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) id: string) {
    return this.pinReset.reject(auth.sub, id);
  }
}
