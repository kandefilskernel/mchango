import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import type { StaffMember } from '../admin/staff-auth.service.js';
import { CAN, CurrentStaff, Roles, StaffGuard } from '../admin/staff.guard.js';
import { AccessGuard, CurrentAuth } from '../auth/access.guard.js';
import type { AccessTokenClaims } from '../auth/auth.service.js';
import { parseBody } from '../common/parse-body.js';
import { AiService } from './ai.service.js';

const Feedback = z.object({
  groupId: z.uuid().optional(),
  rating: z.number().int().min(1).max(5).optional(),
  body: z.string().max(2000),
});
const GroupFilter = z.object({ groupId: z.uuid().optional() });

/** Un membre donne son avis sur Mchango ou sur une de ses tontines. */
@Controller('feedback')
@UseGuards(AccessGuard)
export class FeedbackController {
  constructor(private readonly ai: AiService) {}

  @Post()
  submit(@CurrentAuth() auth: AccessTokenClaims, @Body() body: unknown) {
    return this.ai.submitFeedback({ userId: auth.sub, deviceId: auth.did }, parseBody(Feedback, body));
  }
}

/** Agent IA du back-office : lire est ouvert à toute l'équipe, lancer une analyse (facturée) au support. */
@Controller('admin/ai')
@UseGuards(StaffGuard)
export class AiAdminController {
  constructor(private readonly ai: AiService) {}

  @Get('status')
  status() {
    return this.ai.status();
  }

  @Get('reviews')
  reviews(@Query() query: unknown) {
    return this.ai.reviews(parseBody(GroupFilter, query).groupId);
  }

  @Get('reviews/:id')
  review(@Param('id', ParseUUIDPipe) id: string) {
    return this.ai.review(id);
  }

  @Get('feedback')
  feedback(@Query() query: unknown) {
    return this.ai.feedbackList(parseBody(GroupFilter, query).groupId);
  }

  @Post('groups/:id/review')
  @HttpCode(201)
  @Roles(...CAN.supportMembers)
  reviewGroup(@CurrentStaff() staff: StaffMember, @Param('id', ParseUUIDPipe) groupId: string) {
    return this.ai.reviewGroup(staff, groupId);
  }

  @Post('feedback/review')
  @HttpCode(201)
  @Roles(...CAN.supportMembers)
  reviewFeedback(@CurrentStaff() staff: StaffMember) {
    return this.ai.reviewFeedback(staff);
  }
}
