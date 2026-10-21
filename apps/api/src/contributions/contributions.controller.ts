import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  ParseIntPipe,
  ParseUUIDPipe,
  Post,
  UseGuards,
} from '@nestjs/common';
import { z } from 'zod';
import { AccessGuard, CurrentAuth } from '../auth/access.guard.js';
import type { AccessTokenClaims } from '../auth/auth.service.js';
import { parseBody } from '../common/parse-body.js';
import { ContributionsService } from './contributions.service.js';

const Declare = z.object({
  method: z.enum(['mpesa', 'airtel', 'orange', 'cash', 'other']),
  txReference: z.string().max(40).optional(),
  amountMinor: z.number().int().positive(),
  witnessMembershipId: z.uuid().optional(),
  offlineId: z.uuid(),
});

const Decide = z.object({
  decision: z.enum(['confirm', 'witness', 'dispute']),
  note: z.string().max(500).optional(),
});

const actorOf = (auth: AccessTokenClaims) => ({ type: 'user' as const, id: auth.sub, deviceId: auth.did });

@Controller()
@UseGuards(AccessGuard)
export class ContributionsController {
  constructor(private readonly contributions: ContributionsService) {}

  @Get('me/carnet')
  carnet(@CurrentAuth() auth: AccessTokenClaims) {
    return this.contributions.carnet(auth.sub);
  }

  @Get('groups/:id/cycles')
  board(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) groupId: string) {
    return this.contributions.board(auth.sub, groupId);
  }

  @Get('groups/:id/cycles/:number')
  cycle(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) groupId: string,
    @Param('number', ParseIntPipe) cycleNumber: number,
  ) {
    return this.contributions.cycle(auth.sub, groupId, cycleNumber);
  }

  @Post('groups/:id/cycles/:number/contributions')
  declare(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) groupId: string,
    @Param('number', ParseIntPipe) cycleNumber: number,
    @Body() body: unknown,
  ) {
    return this.contributions.declare(actorOf(auth), groupId, cycleNumber, parseBody(Declare, body));
  }

  @Get('contributions/:id/receipt')
  receipt(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) contributionId: string) {
    return this.contributions.receipt(auth.sub, contributionId);
  }

  @Post('contributions/:id/decisions')
  @HttpCode(200)
  decide(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) contributionId: string,
    @Body() body: unknown,
  ) {
    return this.contributions.decide(actorOf(auth), contributionId, parseBody(Decide, body));
  }
}
