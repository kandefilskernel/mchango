import { Inject, Injectable, Logger, Module, OnApplicationBootstrap, OnModuleDestroy } from '@nestjs/common';
import { APP_CONFIG, type AppConfig } from '../config.js';
import { RemindersService } from './reminders.service.js';

/**
 * Vérifie périodiquement les rappels à envoyer. Plusieurs serveurs peuvent tourner : la clé
 * d'unicité des notifications garantit qu'un rappel ne part qu'une fois.
 */
@Injectable()
class RemindersScheduler implements OnApplicationBootstrap, OnModuleDestroy {
  private readonly logger = new Logger('Rappels');
  private timer?: NodeJS.Timeout;
  private running = false;

  constructor(
    private readonly reminders: RemindersService,
    @Inject(APP_CONFIG) private readonly config: AppConfig,
  ) {}

  onApplicationBootstrap() {
    if (this.config.REMINDERS_ENABLED !== '1') return;
    const every = this.config.REMINDERS_INTERVAL_MINUTES * 60_000;
    this.timer = setInterval(() => void this.tick(), every);
    void this.tick();
  }

  onModuleDestroy() {
    clearInterval(this.timer);
  }

  private async tick() {
    if (this.running) return;
    this.running = true;
    try {
      await this.reminders.runOnce();
    } catch (e) {
      this.logger.error(`Vérification des rappels impossible : ${String(e)}`);
    } finally {
      this.running = false;
    }
  }
}

@Module({
  providers: [RemindersService, RemindersScheduler],
  exports: [RemindersService],
})
export class RemindersModule {}
