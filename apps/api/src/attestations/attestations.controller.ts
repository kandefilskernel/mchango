import { Body, Controller, Get, HttpCode, Ip, Param, ParseUUIDPipe, Post, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import { AccessGuard, CurrentAuth } from '../auth/access.guard.js';
import type { AccessTokenClaims } from '../auth/auth.service.js';
import { parseBody } from '../common/parse-body.js';
import { AttestationsService } from './attestations.service.js';

const Issue = z.object({
  includeAmounts: z.boolean().default(false),
  validDays: z.union([z.literal(30), z.literal(90), z.literal(180)]).default(90),
});

const actorOf = (auth: AccessTokenClaims) => ({ type: 'user' as const, id: auth.sub, deviceId: auth.did });

/** Mes attestations de régularité (spec/attestations.md). */
@Controller('me')
@UseGuards(AccessGuard)
export class MyAttestationsController {
  constructor(private readonly attestations: AttestationsService) {}

  @Get('attestation-stats')
  stats(@CurrentAuth() auth: AccessTokenClaims) {
    return this.attestations.stats(auth.sub);
  }

  @Get('attestations')
  list(@CurrentAuth() auth: AccessTokenClaims) {
    return this.attestations.listMine(auth.sub);
  }

  @Post('attestations')
  issue(@CurrentAuth() auth: AccessTokenClaims, @Body() body: unknown) {
    return this.attestations.issue(actorOf(auth), parseBody(Issue, body ?? {}));
  }

  @Post('attestations/:id/revoke')
  @HttpCode(200)
  revoke(@CurrentAuth() auth: AccessTokenClaims, @Param('id', ParseUUIDPipe) id: string) {
    return this.attestations.revoke(actorOf(auth), id);
  }
}

/** Vérification publique par code : pour l'IMF ou la coopec à qui le membre a donné le code. */
@Controller('attestations')
export class PublicAttestationsController {
  constructor(private readonly attestations: AttestationsService) {}

  @Get(':code')
  verify(@Param('code') code: string, @Ip() ip: string) {
    return this.attestations.verify(code.slice(0, 20), ip);
  }
}
