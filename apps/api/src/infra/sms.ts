import { Global, Injectable, Logger, Module } from '@nestjs/common';

export const SMS_SENDER = Symbol('SMS_SENDER');

export interface SmsSender {
  send(phone: string, message: string): Promise<void>;
}

/**
 * Développement et tests uniquement : écrit le SMS dans les logs au lieu de l'envoyer.
 * Refusé en production par loadConfig(). Le vrai fournisseur (agrégateur SMS) viendra
 * implémenter SmsSender.
 */
@Injectable()
export class ConsoleSmsSender implements SmsSender {
  private readonly logger = new Logger('SMS');
  readonly sent: { phone: string; message: string }[] = [];

  async send(phone: string, message: string) {
    this.sent.push({ phone, message });
    this.logger.log(`→ ${phone} : ${message}`);
  }
}

@Global()
@Module({
  providers: [{ provide: SMS_SENDER, useClass: ConsoleSmsSender }],
  exports: [SMS_SENDER],
})
export class SmsModule {}
