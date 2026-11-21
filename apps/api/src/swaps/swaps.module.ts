import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { SwapsController } from './swaps.controller.js';
import { SwapsService } from './swaps.service.js';

@Module({
  imports: [AuthModule],
  controllers: [SwapsController],
  providers: [SwapsService],
})
export class SwapsModule {}
