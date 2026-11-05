import {
  CanActivate,
  createParamDecorator,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  SetMetadata,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { StaffAuthService, type StaffMember, type StaffRole } from './staff-auth.service.js';

const ROLES_KEY = 'staffRoles';

/** Rôles autorisés pour une action. Sans @Roles, tout membre de l'équipe connecté peut lire. */
export const Roles = (...roles: StaffRole[]) => SetMetadata(ROLES_KEY, roles);

/** Qui peut quoi (spec/backoffice.md). */
export const CAN = {
  blockUsers: ['super_admin', 'support', 'compliance'] as StaffRole[],
  suspendGroups: ['super_admin', 'compliance'] as StaffRole[],
  decideDisputes: ['super_admin', 'compliance'] as StaffRole[],
  manageStaff: ['super_admin'] as StaffRole[],
  /** Débloquer un PIN bloqué après trop d'essais (après avoir parlé à la personne). */
  unlockPins: ['super_admin', 'support', 'compliance'] as StaffRole[],
  /** Valider un « PIN oublié » sans garant, après vérification d'identité : risque de prise de compte. */
  verifyIdentity: ['super_admin', 'compliance'] as StaffRole[],
  /** Notes de suivi et renvoi d'un rappel SMS en échec (coûte un SMS). */
  supportMembers: ['super_admin', 'support', 'compliance'] as StaffRole[],
  /** Exports CSV : données personnelles hors de l'outil, chaque export est journalisé. */
  exportData: ['super_admin', 'compliance', 'finance'] as StaffRole[],
};

/** Rôles qui voient les numéros de téléphone en entier (les autres les voient masqués). */
export const SEES_PHONE_NUMBERS: StaffRole[] = ['super_admin', 'support', 'compliance'];

type StaffRequest = Request & { staff?: StaffMember };

@Injectable()
export class StaffGuard implements CanActivate {
  constructor(
    private readonly auth: StaffAuthService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<StaffRequest>();
    const [scheme, token] = (request.headers.authorization ?? '').split(' ');
    if (scheme !== 'Bearer' || !token) throw new UnauthorizedException('Connexion requise.');
    request.staff = await this.auth.authenticate(token);
    const roles = this.reflector.getAllAndOverride<StaffRole[] | undefined>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (roles && !roles.includes(request.staff.role)) {
      throw new ForbiddenException("Votre rôle ne permet pas cette action.");
    }
    return true;
  }
}

export const CurrentStaff = createParamDecorator(
  (_: unknown, context: ExecutionContext) => context.switchToHttp().getRequest<StaffRequest>().staff!,
);
