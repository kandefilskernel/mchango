import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { ContributionsController } from './contributions.controller.js';
import { ContributionsService } from './contributions.service.js';
import { PresidentFeesService } from './president-fees.service.js';

@Module({
  imports: [AuthModule],
  controllers: [ContributionsController],
  providers: [ContributionsService, PresidentFeesService],
})
export class ContributionsModule {}
