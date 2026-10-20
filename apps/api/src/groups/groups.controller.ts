import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import { AccessGuard, CurrentAuth } from '../auth/access.guard.js';
import type { AccessTokenClaims } from '../auth/auth.service.js';
import { parseBody } from '../common/parse-body.js';
import { GroupsService } from './groups.service.js';

/** Date du jour à Lubumbashi (UTC+2), au format AAAA-MM-JJ. */
function todayInDrc(): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Lubumbashi' }).format(new Date());
}

const CreateGroup = z.object({
  name: z.string().trim().min(2).max(150),
  type: z.enum(['formel', 'informel']).default('informel'),
  currency: z.enum(['CDF', 'USD']),
  // Unités mineures : francs pour CDF, cents pour USD
  contributionAmountMinor: z.number().int().positive().max(1_000_000_000_000),
  frequency: z.enum(['daily', 'weekly', 'monthly']),
  startDate: z.iso
    .date()
    .refine((d) => d >= todayInDrc(), 'La date de début ne peut pas être dans le passé.'),
  maxMembers: z.number().int().min(2).max(100).default(30),
});

const CreateInvitation = z.object({
  validHours: z.number().int().min(1).max(24 * 14).default(72),
  maxUses: z.number().int().min(1).max(100).nullable().default(null),
});

const JoinGroup = z.object({
  code: z.string().max(20),
  acceptRules: z.boolean(),
});

const actorOf = (auth: AccessTokenClaims) => ({ type: 'user' as const, id: auth.sub, deviceId: auth.did });

@Controller('groups')
@UseGuards(AccessGuard)
export class GroupsController {
  constructor(private readonly groups: GroupsService) {}

  @Post()
  create(@CurrentAuth() auth: AccessTokenClaims, @Body() body: unknown) {
    return this.groups.create(actorOf(auth), parseBody(CreateGroup, body));
  }

  @Get()
  listMine(@CurrentAuth() auth: AccessTokenClaims) {
    return this.groups.listMine(auth.sub);
  }

  /** Déclaré avant ':id' pour que « join » ne soit pas pris pour un identifiant. */
  @Post('join')
  @HttpCode(200)
  join(@CurrentAuth() auth: AccessTokenClaims, @Body() body: unknown) {
    return this.groups.join(actorOf(auth), parseBody(JoinGroup, body));
  }

  @Get(':id')
  get(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) id: string) {
    return this.groups.getForMember(auth.sub, id);
  }

  @Post(':id/invitations')
  createInvitation(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: unknown,
  ) {
    return this.groups.createInvitation(actorOf(auth), id, parseBody(CreateInvitation, body ?? {}));
  }
}
