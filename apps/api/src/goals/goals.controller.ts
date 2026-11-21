import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Put, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import { AccessGuard, CurrentAuth } from '../auth/access.guard.js';
import type { AccessTokenClaims } from '../auth/auth.service.js';
import { parseBody } from '../common/parse-body.js';
import { GOAL_KINDS, GoalsService } from './goals.service.js';

const SetGoal = z.object({
  kind: z.enum(GOAL_KINDS),
  label: z.string().trim().min(2).max(80),
  targetAmountMinor: z.number().int().positive().max(1_000_000_000_000).nullable().optional(),
  targetDate: z.iso.date().nullable().optional(),
  sharedWithGroup: z.boolean().default(false),
});

const actorOf = (auth: AccessTokenClaims) => ({ type: 'user' as const, id: auth.sub, deviceId: auth.did });

/** Mon objectif d'épargne dans une tontine (spec/goals.md). */
@Controller('groups/:id/goal')
@UseGuards(AccessGuard)
export class GoalsController {
  constructor(private readonly goals: GoalsService) {}

  @Get()
  get(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) groupId: string) {
    return this.goals.get(auth.sub, groupId);
  }

  @Put()
  set(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) groupId: string, @Body() body: unknown) {
    return this.goals.set(actorOf(auth), groupId, parseBody(SetGoal, body));
  }

  @Delete()
  @HttpCode(204)
  async archive(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) groupId: string) {
    await this.goals.archive(actorOf(auth), groupId);
  }
}
