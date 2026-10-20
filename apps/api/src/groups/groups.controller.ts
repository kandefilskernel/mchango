import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import { z } from 'zod';
import { AccessGuard, CurrentAuth } from '../auth/access.guard.js';
import type { AccessTokenClaims } from '../auth/auth.service.js';
import { parseBody } from '../common/parse-body.js';
import { GroupsService } from './groups.service.js';
import { HistoryService } from './history.service.js';
import { GroupLifecycleService } from './lifecycle.service.js';

/** Date du jour à Lubumbashi (UTC+2), au format AAAA-MM-JJ. */
function todayInDrc(): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Lubumbashi' }).format(new Date());
}

const name = z.string().trim().min(2).max(150);
// Unités mineures : francs pour CDF, cents pour USD
const amountMinor = z.number().int().positive().max(1_000_000_000_000);
const frequency = z.enum(['daily', 'weekly', 'monthly']);
const startDate = z.iso
  .date()
  .refine((d) => d >= todayInDrc(), 'La date de début ne peut pas être dans le passé.');
const maxMembers = z.number().int().min(2).max(100);

const CreateGroup = z.object({
  name,
  type: z.enum(['formel', 'informel']).default('informel'),
  currency: z.enum(['CDF', 'USD']),
  contributionAmountMinor: amountMinor,
  frequency,
  startDate,
  maxMembers: maxMembers.default(30),
});

// La devise et le type ne changent pas : ce serait un autre groupe
const UpdateGroup = z
  .object({
    name,
    contributionAmountMinor: amountMinor,
    frequency,
    startDate,
    maxMembers,
  })
  .partial()
  .refine((v) => Object.keys(v).length > 0, 'Aucune modification demandée.');

const ChosenOrder = z.object({ membershipIds: z.array(z.uuid()).min(2).max(100) });

const CreateInvitation = z.object({
  validHours: z.number().int().min(1).max(24 * 14).default(72),
  maxUses: z.number().int().min(1).max(100).nullable().default(null),
});

const PreviewGroup = z.object({ code: z.string().max(20) });

const HistoryQuery = z.object({
  afterSeq: z.coerce.number().int().min(0).default(0),
  limit: z.coerce.number().int().min(1).max(500).default(500),
});

const JoinGroup = z.object({
  code: z.string().max(20),
  acceptRules: z.boolean(),
});

const actorOf = (auth: AccessTokenClaims) => ({ type: 'user' as const, id: auth.sub, deviceId: auth.did });

@Controller('groups')
@UseGuards(AccessGuard)
export class GroupsController {
  constructor(
    private readonly groups: GroupsService,
    private readonly lifecycle: GroupLifecycleService,
    private readonly historyService: HistoryService,
  ) {}

  @Post()
  create(@CurrentAuth() auth: AccessTokenClaims, @Body() body: unknown) {
    return this.groups.create(actorOf(auth), parseBody(CreateGroup, body));
  }

  @Get()
  listMine(@CurrentAuth() auth: AccessTokenClaims) {
    return this.groups.listMine(auth.sub);
  }

  @Post('preview')
  @HttpCode(200)
  preview(@CurrentAuth() auth: AccessTokenClaims, @Body() body: unknown) {
    return this.groups.preview(auth.sub, parseBody(PreviewGroup, body).code);
  }

  @Get(':id/history')
  history(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Query() query: unknown,
  ) {
    const { afterSeq, limit } = parseBody(HistoryQuery, query);
    return this.historyService.history(auth.sub, id, afterSeq, limit);
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

  @Patch(':id')
  update(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: unknown,
  ) {
    return this.lifecycle.update(actorOf(auth), id, parseBody(UpdateGroup, body));
  }

  @Put(':id/turn-order')
  setChosenOrder(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: unknown,
  ) {
    return this.lifecycle.setChosenOrder(actorOf(auth), id, parseBody(ChosenOrder, body).membershipIds);
  }

  @Post(':id/turn-order/draw')
  @HttpCode(200)
  draw(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) id: string) {
    return this.lifecycle.draw(actorOf(auth), id);
  }

  @Post(':id/start')
  @HttpCode(200)
  start(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) id: string) {
    return this.lifecycle.start(actorOf(auth), id);
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
