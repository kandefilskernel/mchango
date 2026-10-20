import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { GroupsController } from './groups.controller.js';
import { GroupsService } from './groups.service.js';
import { GroupLifecycleService } from './lifecycle.service.js';

@Module({
  imports: [AuthModule],
  controllers: [GroupsController],
  providers: [GroupsService, GroupLifecycleService],
})
export class GroupsModule {}
