import {
  CanActivate,
  createParamDecorator,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';
import { AuthService, type AccessTokenClaims } from './auth.service.js';

type AuthenticatedRequest = Request & { auth?: AccessTokenClaims };

/**
 * Exige un jeton d'accès valide. Les jetons durent 15 minutes : un appareil révoqué
 * garde l'accès au plus jusqu'à l'expiration du sien.
 */
@Injectable()
export class AccessGuard implements CanActivate {
  constructor(private readonly auth: AuthService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const [scheme, token] = (request.headers.authorization ?? '').split(' ');
    if (scheme !== 'Bearer' || !token) throw new UnauthorizedException('Connexion requise.');
    request.auth = await this.auth.verifyAccessToken(token);
    return true;
  }
}

/** Utilisateur et appareil de la requête (après AccessGuard). */
export const CurrentAuth = createParamDecorator(
  (_: unknown, context: ExecutionContext) =>
    context.switchToHttp().getRequest<AuthenticatedRequest>().auth!,
);
