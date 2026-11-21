import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { GoalsController } from './goals.controller.js';
import { GoalsService } from './goals.service.js';

@Module({
  imports: [AuthModule],
  controllers: [GoalsController],
  providers: [GoalsService],
})
export class GoalsModule {}
