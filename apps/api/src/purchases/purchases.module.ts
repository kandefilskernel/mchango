import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { PurchaseLifecycleService, PurchaseScheduler } from './lifecycle.service.js';
import { MerchantsService } from './merchants.service.js';
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
    OrdersService,
    SharesService,
    PurchaseLifecycleService,
    PurchaseScheduler,
  ],
})
export class PurchasesModule {}
