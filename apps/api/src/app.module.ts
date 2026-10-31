import { Controller, Get, Inject, Module, ServiceUnavailableException } from '@nestjs/common';
import type { Redis } from 'ioredis';
import { AdminModule } from './admin/admin.module.js';
import { AiModule } from './ai/ai.module.js';
import { AuthModule } from './auth/auth.module.js';
import { APP_CONFIG, loadConfig } from './config.js';
import { ContributionsModule } from './contributions/contributions.module.js';
import { GroupsModule } from './groups/groups.module.js';
import { Db, DatabaseModule } from './infra/database.js';
import { RemindersModule } from './reminders/reminders.module.js';
import { REDIS, RedisModule } from './infra/redis.js';
import { SmsModule } from './infra/sms.js';

@Controller()
class HealthController {
  constructor(
    private readonly db: Db,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  /** Vivant : Node répond. Sert au contrôle de santé Docker (relance d'une API figée). */
  @Get('health')
  health() {
    return { status: 'ok' };
  }

  /**
   * Prêt : la base et Redis répondent aussi. Pour la surveillance externe (UptimeRobot), pas pour
   * la relance : redémarrer l'API ne réparerait pas une base arrêtée.
   */
  @Get('health/ready')
  async ready() {
    const check = (p: Promise<unknown>) =>
      Promise.race([p, new Promise((_, reject) => setTimeout(() => reject(new Error('délai')), 2000))])
        .then(() => 'ok' as const)
        .catch(() => 'down' as const);
    const [database, redis] = await Promise.all([check(this.db.query('SELECT 1')), check(this.redis.ping())]);
    const body = { status: database === 'ok' && redis === 'ok' ? 'ok' : 'degraded', database, redis };
    if (body.status !== 'ok') throw new ServiceUnavailableException(body);
    return body;
  }
}

@Module({
  providers: [{ provide: APP_CONFIG, useFactory: () => loadConfig() }],
  exports: [APP_CONFIG],
})
class ConfigModule {}

@Module({
  imports: [
    { module: ConfigModule, global: true },
    DatabaseModule,
    RedisModule,
    SmsModule,
    AuthModule,
    GroupsModule,
    ContributionsModule,
    RemindersModule,
    AdminModule,
    AiModule,
  ],
  controllers: [HealthController],
})
export class AppModule {}
