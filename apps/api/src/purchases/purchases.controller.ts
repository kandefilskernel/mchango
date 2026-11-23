import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  Res,
  UseFilters,
  UseGuards,
} from '@nestjs/common';
import type { Response } from 'express';
import { z } from 'zod';
import { AccessGuard, CurrentAuth } from '../auth/access.guard.js';
import type { AccessTokenClaims } from '../auth/auth.service.js';
import { parseBody } from '../common/parse-body.js';
import type { Actor } from '../infra/database.js';
import { MerchantsService } from './merchants.service.js';
import { OfferDiscussionService } from './offer-discussion.service.js';
import { OffersService, createOfferSchema, listOffersQuery } from './offers.service.js';
import {
  OrdersService,
  merchantOrdersQuery,
  merchantPaymentSchema,
  paymentSchema,
  pickupSchema,
  reserveSchema,
  updateOrderSchema,
} from './orders.service.js';
import { PgExceptionFilter } from './pg-exception.filter.js';
import { SharesService, createShareSchema } from './shares.service.js';

const actorOf = (auth: AccessTokenClaims) => ({ type: 'user' as const, id: auth.sub, deviceId: auth.did }) satisfies Actor;

const messageSchema = z.strictObject({ body: z.string().trim().min(1).max(500) });

/** Sans compte : on regarde les offres et on ouvre un lien d'invitation. */
@Controller()
@UseFilters(PgExceptionFilter)
export class PublicOffersController {
  constructor(
    private readonly offers: OffersService,
    private readonly shares: SharesService,
    private readonly discussion: OfferDiscussionService,
  ) {}

  /** Photo de la marchandise, servie telle quelle (mise en cache : elle ne change jamais). */
  @Get('offers/:offerId/photos/:position')
  async photo(
    @Param('offerId', ParseUUIDPipe) offerId: string,
    @Param('position') position: string,
    @Res() res: Response,
  ) {
    const n = Number(position);
    const p = await this.discussion.photo(offerId, Number.isInteger(n) ? n : 0);
    res.set({ 'Content-Type': p.content_type, 'Cache-Control': 'public, max-age=604800, immutable', ETag: `"${p.sha256}"` });
    res.send(p.bytes);
  }

  @Get('zones')
  zones() {
    return this.offers.listZones();
  }

  @Get('offers')
  list(@Query() query: unknown) {
    return this.offers.listOpen(parseBody(listOffersQuery, query).zoneId);
  }

  @Get('offers/:offerId')
  get(@Param('offerId', ParseUUIDPipe) offerId: string) {
    return this.offers.getPublic(offerId);
  }

  @Get('shares/:token')
  resolveShare(@Param('token') token: string) {
    return this.shares.resolve(token);
  }
}

/** Acheteur : on ne s'identifie qu'au moment de confirmer sa quantité. */
@Controller()
@UseGuards(AccessGuard)
@UseFilters(PgExceptionFilter)
export class BuyerController {
  constructor(
    private readonly orders: OrdersService,
    private readonly shares: SharesService,
    private readonly discussion: OfferDiscussionService,
  ) {}

  /** La discussion sous une offre : questions des membres, réponses de la boutique. */
  @Get('offers/:offerId/messages')
  messages(@CurrentAuth() auth: AccessTokenClaims, @Param('offerId', ParseUUIDPipe) offerId: string) {
    return this.discussion.messages(auth.sub, offerId);
  }

  @Post('offers/:offerId/messages')
  postMessage(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('offerId', ParseUUIDPipe) offerId: string,
    @Body() body: unknown,
  ) {
    return this.discussion.post(actorOf(auth), offerId, parseBody(messageSchema, body).body);
  }

  @Post('offers/:offerId/orders')
  reserve(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('offerId', ParseUUIDPipe) offerId: string,
    @Body() body: unknown,
  ) {
    return this.orders.reserve(actorOf(auth), auth.sub, offerId, parseBody(reserveSchema, body));
  }

  @Get('me/orders')
  mine(@CurrentAuth() auth: AccessTokenClaims) {
    return this.orders.listMine(auth.sub);
  }

  @Patch('orders/:orderId')
  update(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('orderId', ParseUUIDPipe) orderId: string,
    @Body() body: unknown,
  ) {
    return this.orders.update(actorOf(auth), auth.sub, orderId, parseBody(updateOrderSchema, body));
  }

  @Post('orders/:orderId/cancel')
  @HttpCode(200)
  cancel(@CurrentAuth() auth: AccessTokenClaims, @Param('orderId', ParseUUIDPipe) orderId: string) {
    return this.orders.cancel(actorOf(auth), auth.sub, orderId);
  }

  @Post('orders/:orderId/payments')
  declarePayment(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('orderId', ParseUUIDPipe) orderId: string,
    @Body() body: unknown,
  ) {
    return this.orders.declarePayment(actorOf(auth), auth.sub, orderId, parseBody(paymentSchema, body));
  }

  @Post('offers/:offerId/shares')
  share(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('offerId', ParseUUIDPipe) offerId: string,
    @Body() body: unknown,
  ) {
    return this.shares.create(actorOf(auth), auth.sub, offerId, parseBody(createShareSchema, body));
  }

  @Get('groups/:groupId/proposals')
  proposals(@CurrentAuth() auth: AccessTokenClaims, @Param('groupId', ParseUUIDPipe) groupId: string) {
    return this.shares.groupProposals(auth.sub, groupId);
  }
}

/** Boutique : chaque route vérifie que l'utilisateur agit pour cette boutique. */
@Controller()
@UseGuards(AccessGuard)
@UseFilters(PgExceptionFilter)
export class MerchantController {
  constructor(
    private readonly merchants: MerchantsService,
    private readonly offers: OffersService,
    private readonly orders: OrdersService,
    private readonly discussion: OfferDiscussionService,
  ) {}

  /** Photo de la marchandise (octets bruts : image/jpeg, image/png ou image/webp), avant publication. */
  @Post('merchants/:merchantId/offers/:offerId/photos')
  async addPhoto(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('merchantId', ParseUUIDPipe) merchantId: string,
    @Param('offerId', ParseUUIDPipe) offerId: string,
    @Body() body: unknown,
  ) {
    const memberId = await this.merchants.requireMember(auth.sub, merchantId);
    return this.discussion.addPhoto(actorOf(auth), merchantId, memberId, offerId, body as Buffer);
  }

  @Get('me/merchants')
  myMerchants(@CurrentAuth() auth: AccessTokenClaims) {
    return this.merchants.listMine(auth.sub);
  }

  @Get('merchants/:merchantId/offers')
  async listOffers(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('merchantId', ParseUUIDPipe) merchantId: string,
  ) {
    await this.merchants.requireMember(auth.sub, merchantId);
    return this.offers.listForMerchant(merchantId);
  }

  @Post('merchants/:merchantId/offers')
  async createOffer(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('merchantId', ParseUUIDPipe) merchantId: string,
    @Body() body: unknown,
  ) {
    const memberId = await this.merchants.requireMember(auth.sub, merchantId);
    return this.offers.create(actorOf(auth), merchantId, memberId, parseBody(createOfferSchema, body));
  }

  @Post('merchants/:merchantId/offers/:offerId/publish')
  @HttpCode(200)
  async publish(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('merchantId', ParseUUIDPipe) merchantId: string,
    @Param('offerId', ParseUUIDPipe) offerId: string,
  ) {
    await this.merchants.requireMember(auth.sub, merchantId);
    return this.offers.publish(actorOf(auth), merchantId, offerId);
  }

  @Post('merchants/:merchantId/offers/:offerId/cancel')
  @HttpCode(200)
  async cancelOffer(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('merchantId', ParseUUIDPipe) merchantId: string,
    @Param('offerId', ParseUUIDPipe) offerId: string,
  ) {
    await this.merchants.requireMember(auth.sub, merchantId);
    return this.offers.cancel(actorOf(auth), merchantId, offerId);
  }

  @Get('merchants/:merchantId/orders')
  async listOrders(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('merchantId', ParseUUIDPipe) merchantId: string,
    @Query() query: unknown,
  ) {
    await this.merchants.requireMember(auth.sub, merchantId);
    return this.orders.listForMerchant(merchantId, parseBody(merchantOrdersQuery, query).status);
  }

  @Post('merchants/:merchantId/orders/:orderId/confirm-payment')
  @HttpCode(200)
  async confirmPayment(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('merchantId', ParseUUIDPipe) merchantId: string,
    @Param('orderId', ParseUUIDPipe) orderId: string,
    @Body() body: unknown,
  ) {
    const memberId = await this.merchants.requireMember(auth.sub, merchantId);
    return this.orders.confirmPayment(
      actorOf(auth),
      merchantId,
      memberId,
      orderId,
      parseBody(merchantPaymentSchema, body ?? {}),
    );
  }

  @Post('merchants/:merchantId/orders/:orderId/confirm-pickup')
  @HttpCode(200)
  async confirmPickup(
    @CurrentAuth() auth: AccessTokenClaims,
    @Param('merchantId', ParseUUIDPipe) merchantId: string,
    @Param('orderId', ParseUUIDPipe) orderId: string,
    @Body() body: unknown,
  ) {
    const memberId = await this.merchants.requireMember(auth.sub, merchantId);
    return this.orders.confirmPickup(
      actorOf(auth),
      merchantId,
      memberId,
      orderId,
      parseBody(pickupSchema, body).pickupCode,
    );
  }
}
