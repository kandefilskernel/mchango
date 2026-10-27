import { Module } from '@nestjs/common';
import { AdminModule } from '../admin/admin.module.js';
import { AuthModule } from '../auth/auth.module.js';
import { StaffGuard } from '../admin/staff.guard.js';
import { APP_CONFIG, type AppConfig } from '../config.js';
import { AiAdminController, FeedbackController } from './ai.controller.js';
import { AiService } from './ai.service.js';
import { AI_ANALYST, ClaudeAnalyst } from './analyst.js';

/** Avis des membres et agent IA d'aide à l'équipe (détection d'anomalies, synthèse des avis). */
@Module({
  imports: [AuthModule, AdminModule],
  controllers: [FeedbackController, AiAdminController],
  providers: [
    AiService,
    StaffGuard,
    { provide: AI_ANALYST, inject: [APP_CONFIG], useFactory: (c: AppConfig) => new ClaudeAnalyst(c.ANTHROPIC_API_KEY) },
  ],
})
export class AiModule {}
