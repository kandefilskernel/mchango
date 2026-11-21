import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import { AccessGuard, CurrentAuth } from '../auth/access.guard.js';
import type { AccessTokenClaims } from '../auth/auth.service.js';
import { parseBody } from '../common/parse-body.js';
import { SwapsService } from './swaps.service.js';

const RequestSwap = z.object({
  targetMembershipId: z.uuid(),
  reason: z.string().trim().max(200).optional(),
});

const actorOf = (auth: AccessTokenClaims) => ({ type: 'user' as const, id: auth.sub, deviceId: auth.did });

/** Échanges de tour entre membres (spec/swaps.md). */
@Controller()
@UseGuards(AccessGuard)
export class SwapsController {
  constructor(private readonly swaps: SwapsService) {}

  @Get('groups/:id/swaps')
  list(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) groupId: string) {
    return this.swaps.list(auth.sub, groupId);
  }

  @Post('groups/:id/swaps')
  request(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) groupId: string, @Body() body: unknown) {
    return this.swaps.request(actorOf(auth), groupId, parseBody(RequestSwap, body));
  }

  @Post('swaps/:id/accept')
  @HttpCode(200)
  accept(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) id: string) {
    return this.swaps.decide(actorOf(auth), id, 'accept');
  }

  @Post('swaps/:id/decline')
  @HttpCode(200)
  decline(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) id: string) {
    return this.swaps.decide(actorOf(auth), id, 'decline');
  }

  @Post('swaps/:id/cancel')
  @HttpCode(200)
  cancel(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) id: string) {
    return this.swaps.decide(actorOf(auth), id, 'cancel');
  }
}
