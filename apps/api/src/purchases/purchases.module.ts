import { type MiddlewareConsumer, Module, type NestModule, RequestMethod } from '@nestjs/common';
import express from 'express';
import { AuthModule } from '../auth/auth.module.js';
import { PurchaseLifecycleService, PurchaseScheduler } from './lifecycle.service.js';
import { MerchantsService } from './merchants.service.js';
import { OfferDiscussionService } from './offer-discussion.service.js';
import { OffersService } from './offers.service.js';
import { OrdersService } from './orders.service.js';
import { BuyerController, MerchantController, PublicOffersController } from './purchases.controller.js';
import { SharesService } from './shares.service.js';

/** Achats groupés : offres, commandes, encaissement et retrait en boutique, partages. */
@Module({
  imports: [AuthModule],
  controllers: [PublicOffersController, BuyerController, MerchantController],
  providers: [
    MerchantsService,
    OffersService,
    OfferDiscussionService,
    OrdersService,
    SharesService,
    PurchaseLifecycleService,
    PurchaseScheduler,
  ],
})
export class PurchasesModule implements NestModule {
  /** Les photos arrivent en octets bruts (pas en JSON), 600 Ko au plus. */
  configure(consumer: MiddlewareConsumer) {
    consumer
      .apply(express.raw({ type: ['image/jpeg', 'image/png', 'image/webp'], limit: '600kb' }))
      .forRoutes({ path: 'merchants/:merchantId/offers/:offerId/photos', method: RequestMethod.POST });
  }
}
