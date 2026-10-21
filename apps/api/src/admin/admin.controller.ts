import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query, Res, UseGuards } from '@nestjs/common';
import type { Response } from 'express';
import { z } from 'zod';
import { PinResetService } from '../auth/pin-reset.service.js';
import { parseBody } from '../common/parse-body.js';
import { AdminService } from './admin.service.js';
import { StaffAuthService, STAFF_ROLES, type StaffMember } from './staff-auth.service.js';
import { CAN, CurrentStaff, Roles, StaffGuard } from './staff.guard.js';

const Login = z.object({
  email: z.string().trim().max(200),
  password: z.string().max(200),
  code: z.string().trim().max(6),
});
const Reason = z.object({ reason: z.string().max(500).default('') });
const Decision = z.object({ decision: z.enum(['reject', 'note']), note: z.string().max(1000) });
const NewStaff = z.object({ email: z.email(), fullName: z.string().trim().min(2).max(150), role: z.enum(STAFF_ROLES) });
const UpdateStaff = z
  .object({ role: z.enum(STAFF_ROLES), isActive: z.boolean() })
  .partial()
  .refine((v) => Object.keys(v).length > 0, 'Aucune modification demandée.');
const IdentityCheck = z.object({ note: z.string().max(1000) });
const Note = z.object({
  body: z.string().max(2000),
  followUp: z.boolean().default(false),
  closes: z.uuid().nullable().default(null),
});
const ExportQuery = z.object({
  kind: z.enum(['disputes', 'late', 'audit']),
  chain: z.string().regex(/^(global|group:[0-9a-f-]{36})$/, 'Chaîne inconnue.').default('global'),
});
const ChangePassword = z.object({ current: z.string().max(200), next: z.string().max(200) });
const Search = z.object({ q: z.string().max(100).default(''), status: z.string().max(20).default('') });
const AuditQuery = z.object({
  chain: z.string().max(60).default('global'),
  beforeSeq: z.coerce.number().int().positive().optional(),
  limit: z.coerce.number().int().min(1).max(200).default(100),
});
const ChainParam = z.object({ chainId: z.string().regex(/^(global|group:[0-9a-f-]{36})$/, 'Chaîne inconnue.') });

/** Points d'accès du back-office : réservés à l'équipe connectée (mot de passe + 2FA). */
@Controller('admin')
export class AdminController {
  constructor(
    private readonly auth: StaffAuthService,
    private readonly admin: AdminService,
    private readonly pinResets: PinResetService,
  ) {}

  @Post('auth/login')
  @HttpCode(200)
  login(@Body() body: unknown) {
    const input = parseBody(Login, body);
    return this.auth.login(input.email, input.password, input.code);
  }

  @Get('me')
  @UseGuards(StaffGuard)
  me(@CurrentStaff() staff: StaffMember) {
    return staff;
  }

  @Post('me/password')
  @HttpCode(200)
  @UseGuards(StaffGuard)
  changePassword(@CurrentStaff() staff: StaffMember, @Body() body: unknown) {
    const input = parseBody(ChangePassword, body);
    return this.auth.changePassword(staff, input.current, input.next);
  }

  @Get('dashboard')
  @UseGuards(StaffGuard)
  dashboard() {
    return this.admin.dashboard();
  }

  // ---------- À traiter (support) ----------

  @Get('inbox')
  @UseGuards(StaffGuard)
  inbox(@CurrentStaff() staff: StaffMember) {
    return this.admin.inbox(staff);
  }

  @Post('users/:id/unlock-pin')
  @HttpCode(200)
  @UseGuards(StaffGuard)
  @Roles(...CAN.unlockPins)
  unlockPin(@CurrentStaff() staff: StaffMember, @Param('id', ParseUUIDPipe) id: string) {
    return this.admin.unlockPin(staff, id);
  }

  @Post('pin-resets/:id/approve')
  @HttpCode(200)
  @UseGuards(StaffGuard)
  @Roles(...CAN.verifyIdentity)
  approvePinReset(@CurrentStaff() staff: StaffMember, @Param('id', ParseUUIDPipe) id: string, @Body() body: unknown) {
    return this.pinResets.approveByStaff(staff.id, id, parseBody(IdentityCheck, body).note);
  }

  @Post('users/:id/notes')
  @UseGuards(StaffGuard)
  @Roles(...CAN.supportMembers)
  addNote(@CurrentStaff() staff: StaffMember, @Param('id', ParseUUIDPipe) id: string, @Body() body: unknown) {
    const input = parseBody(Note, body);
    return this.admin.addNote(staff, id, input.body, input.followUp, input.closes);
  }

  @Post('notifications/:id/resend')
  @HttpCode(200)
  @UseGuards(StaffGuard)
  @Roles(...CAN.supportMembers)
  resendSms(@CurrentStaff() staff: StaffMember, @Param('id', ParseUUIDPipe) id: string) {
    return this.admin.resendSms(staff, id);
  }

  @Get('alerts')
  @UseGuards(StaffGuard)
  alerts(@CurrentStaff() staff: StaffMember) {
    return this.admin.alerts(staff);
  }

  @Get('export')
  @UseGuards(StaffGuard)
  @Roles(...CAN.exportData)
  async export(@CurrentStaff() staff: StaffMember, @Query() query: unknown, @Res({ passthrough: true }) res: Response) {
    const { kind, chain } = parseBody(ExportQuery, query);
    const { filename, csv } = await this.admin.exportCsv(staff, kind, chain);
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.setHeader('Cache-Control', 'no-store');
    return csv;
  }

  // ---------- Utilisateurs ----------

  @Get('users')
  @UseGuards(StaffGuard)
  users(@CurrentStaff() staff: StaffMember, @Query() query: unknown) {
    return this.admin.searchUsers(staff, parseBody(Search, query).q);
  }

  @Get('users/:id')
  @UseGuards(StaffGuard)
  user(@CurrentStaff() staff: StaffMember, @Param('id', ParseUUIDPipe) id: string) {
    return this.admin.user(staff, id);
  }

  @Post('users/:id/block')
  @HttpCode(200)
  @UseGuards(StaffGuard)
  @Roles(...CAN.blockUsers)
  block(@CurrentStaff() staff: StaffMember, @Param('id', ParseUUIDPipe) id: string, @Body() body: unknown) {
    return this.admin.setUserBlocked(staff, id, true, parseBody(Reason, body).reason);
  }

  @Post('users/:id/unblock')
  @HttpCode(200)
  @UseGuards(StaffGuard)
  @Roles(...CAN.blockUsers)
  unblock(@CurrentStaff() staff: StaffMember, @Param('id', ParseUUIDPipe) id: string, @Body() body: unknown) {
    return this.admin.setUserBlocked(staff, id, false, parseBody(Reason, body ?? {}).reason);
  }

  @Post('users/:id/devices/:deviceId/revoke')
  @HttpCode(200)
  @UseGuards(StaffGuard)
  @Roles(...CAN.blockUsers)
  revokeDevice(
    @CurrentStaff() staff: StaffMember,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('deviceId', ParseUUIDPipe) deviceId: string,
  ) {
    return this.admin.revokeDevice(staff, id, deviceId);
  }

  // ---------- Groupes ----------

  @Get('groups')
  @UseGuards(StaffGuard)
  groups(@Query() query: unknown) {
    const { q, status } = parseBody(Search, query);
    return this.admin.searchGroups(q, status);
  }

  @Get('groups/:id')
  @UseGuards(StaffGuard)
  group(@CurrentStaff() staff: StaffMember, @Param('id', ParseUUIDPipe) id: string) {
    return this.admin.group(staff, id);
  }

  @Post('groups/:id/suspend')
  @HttpCode(200)
  @UseGuards(StaffGuard)
  @Roles(...CAN.suspendGroups)
  suspend(@CurrentStaff() staff: StaffMember, @Param('id', ParseUUIDPipe) id: string, @Body() body: unknown) {
    return this.admin.setGroupSuspended(staff, id, true, parseBody(Reason, body).reason);
  }

  @Post('groups/:id/reactivate')
  @HttpCode(200)
  @UseGuards(StaffGuard)
  @Roles(...CAN.suspendGroups)
  reactivate(@CurrentStaff() staff: StaffMember, @Param('id', ParseUUIDPipe) id: string, @Body() body: unknown) {
    return this.admin.setGroupSuspended(staff, id, false, parseBody(Reason, body ?? {}).reason);
  }

  // ---------- Litiges ----------

  @Get('disputes')
  @UseGuards(StaffGuard)
  disputes(@CurrentStaff() staff: StaffMember, @Query() query: unknown) {
    return this.admin.disputes(staff, parseBody(Search, query).status);
  }

  @Post('disputes/:id/decide')
  @HttpCode(200)
  @UseGuards(StaffGuard)
  @Roles(...CAN.decideDisputes)
  decide(@CurrentStaff() staff: StaffMember, @Param('id', ParseUUIDPipe) id: string, @Body() body: unknown) {
    const input = parseBody(Decision, body);
    return this.admin.decideDispute(staff, id, input.decision, input.note);
  }

  // ---------- Audit ----------

  @Get('audit')
  @UseGuards(StaffGuard)
  audit(@Query() query: unknown) {
    const { chain, beforeSeq, limit } = parseBody(AuditQuery, query);
    parseBody(ChainParam, { chainId: chain });
    return this.admin.auditEvents(chain, beforeSeq ?? null, limit);
  }

  @Post('audit/verify')
  @HttpCode(200)
  @UseGuards(StaffGuard)
  verify(@Body() body: unknown) {
    return this.admin.verifyChain(parseBody(ChainParam, body).chainId);
  }

  @Get('audit/staff')
  @UseGuards(StaffGuard)
  staffActions() {
    return this.admin.staffActions(200);
  }

  // ---------- Équipe ----------

  @Get('staff')
  @UseGuards(StaffGuard)
  @Roles(...CAN.manageStaff)
  staff() {
    return this.auth.list();
  }

  @Post('staff')
  @UseGuards(StaffGuard)
  @Roles(...CAN.manageStaff)
  createStaff(@CurrentStaff() staff: StaffMember, @Body() body: unknown) {
    return this.auth.create(staff, parseBody(NewStaff, body));
  }

  @Post('staff/:id')
  @HttpCode(200)
  @UseGuards(StaffGuard)
  @Roles(...CAN.manageStaff)
  updateStaff(@CurrentStaff() staff: StaffMember, @Param('id', ParseUUIDPipe) id: string, @Body() body: unknown) {
    return this.auth.update(staff, id, parseBody(UpdateStaff, body));
  }
}
