import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { AppModule } from './app.module.js';
import { APP_CONFIG, type AppConfig } from './config.js';

async function bootstrap() {
  if (process.env.NODE_ENV !== 'production') {
    try {
      process.loadEnvFile('.env');
    } catch {
      // pas de .env : les variables viennent de l'environnement
    }
  }
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  const config = app.get<AppConfig>(APP_CONFIG);
  // Derrière un proxy (load balancer), l'IP réelle vient de X-Forwarded-For :
  // à n'activer que si le proxy est de confiance, sinon l'IP est falsifiable.
  if (config.TRUST_PROXY === '1') app.set('trust proxy', 1);
  app.disable('x-powered-by');
  const origins = config.CORS_ORIGINS.split(',').map((o) => o.trim()).filter(Boolean);
  if (origins.length > 0) app.enableCors({ origin: origins });
  app.enableShutdownHooks();
  await app.listen(config.PORT);
}
await bootstrap();
