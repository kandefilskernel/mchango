import { Controller, Get, Module } from '@nestjs/common';
import { AuthModule } from './auth/auth.module.js';
import { APP_CONFIG, loadConfig } from './config.js';
import { ContributionsModule } from './contributions/contributions.module.js';
import { GroupsModule } from './groups/groups.module.js';
import { DatabaseModule } from './infra/database.js';
import { RedisModule } from './infra/redis.js';
import { SmsModule } from './infra/sms.js';

@Controller()
class HealthController {
  @Get('health')
  health() {
    return { status: 'ok' };
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
  ],
  controllers: [HealthController],
})
export class AppModule {}
