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
import { CATEGORY_PROFILES, DEFAULT_CATEGORY, GROUP_CATEGORIES } from './categories.js';
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
// Jour de paie (Travailleurs) : 1 à 31, 31 = dernier jour du mois
const payday = z.number().int().min(1).max(31);
const paydayShift = z.enum(['before', 'after']);
const PAYDAY_RULE = 'Le jour de paie ne concerne que les tontines mensuelles de la catégorie « Travailleurs ».';

const CreateGroup = z
  .object({
    name,
    type: z.enum(['formel', 'informel']).default('informel'),
    category: z.enum(GROUP_CATEGORIES).default(DEFAULT_CATEGORY),
    currency: z.enum(['CDF', 'USD']),
    contributionAmountMinor: amountMinor,
    frequency,
    startDate,
    maxMembers: maxMembers.default(30),
    payday: payday.nullable().optional(),
    paydayShift: paydayShift.optional(),
  })
  .refine((g) => g.payday == null || (g.category === 'workers' && g.frequency === 'monthly'), {
    message: PAYDAY_RULE,
    path: ['payday'],
  });

// La devise, le type et la catégorie ne changent pas : ce serait un autre groupe
const UpdateGroup = z
  .object({
    name,
    contributionAmountMinor: amountMinor,
    frequency,
    startDate,
    maxMembers,
    // null : retirer le calendrier de paie
    payday: payday.nullable(),
    paydayShift,
  })
  .partial()
  .refine((v) => Object.keys(v).length > 0, 'Aucune modification demandée.');

const ChosenOrder = z.object({ membershipIds: z.array(z.uuid()).min(2).max(100) });
const SignTerms = z.object({ termsHash: z.string().regex(/^[0-9a-f]{64}$/, 'Empreinte du règlement invalide.') });

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

/** Les catégories de tontine et leurs règles : l'app affiche ce qui est permis sans le coder en dur. */
@Controller('group-categories')
@UseGuards(AccessGuard)
export class GroupCategoriesController {
  @Get()
  list() {
    return CATEGORY_PROFILES;
  }
}

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

  /** Travailleurs : chaînes privées des cotisations que je peux lire et vérifier. */
  @Get(':id/private-history')
  privateHistory(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) id: string) {
    return this.historyService.privateHistory(auth.sub, id);
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

  /** Le membre signe le règlement affiché (empreinte), avant le démarrage. */
  @Post(':id/sign')
  @HttpCode(200)
  sign(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) id: string, @Body() body: unknown) {
    return this.lifecycle.sign(actorOf(auth), id, parseBody(SignTerms, body).termsHash);
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
