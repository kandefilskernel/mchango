import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Response } from 'express';
import pg from 'pg';

const UNIQUE_MESSAGES: Record<string, string> = {
  uq_orders_active_per_buyer: 'Vous avez déjà une commande sur cette offre.',
  uq_shares_offer_group: 'Cette offre est déjà proposée à ce groupe.',
  uq_order_payments_confirmed: 'Cette commande est déjà payée.',
  uq_order_payments_txref:
    'Cet identifiant de transaction a déjà servi pour un autre paiement.',
};

/**
 * Traduit les refus de la base en réponses HTTP. Les règles métier vivent dans la base
 * (db/019_achats.sql) : un RAISE EXCEPTION y porte un message lisible, repris tel quel.
 */
@Catch(pg.DatabaseError)
export class PgExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(PgExceptionFilter.name);

  catch(error: pg.DatabaseError, host: ArgumentsHost): void {
    const response = host.switchToHttp().getResponse<Response>();
    const [status, message] = this.translate(error);
    if (status === HttpStatus.INTERNAL_SERVER_ERROR) {
      this.logger.error(error.message, error.stack);
    }
    response.status(status).json({ statusCode: status, message });
  }

  private translate(error: pg.DatabaseError): [number, string] {
    switch (error.code) {
      case 'P0001': // RAISE EXCEPTION d'un trigger métier
        return [HttpStatus.CONFLICT, error.message];
      case '23505':
        return [
          HttpStatus.CONFLICT,
          UNIQUE_MESSAGES[error.constraint ?? ''] ?? 'Cet élément existe déjà.',
        ];
      case '23503':
        return [HttpStatus.UNPROCESSABLE_ENTITY, 'Référence inconnue.'];
      case '23514':
      case '23502':
        return [HttpStatus.UNPROCESSABLE_ENTITY, 'Données refusées.'];
      default:
        return [HttpStatus.INTERNAL_SERVER_ERROR, 'Erreur interne.'];
    }
  }
}
