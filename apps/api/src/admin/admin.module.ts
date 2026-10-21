import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AdminController } from './admin.controller.js';
import { AdminService } from './admin.service.js';
import { StaffAuthService } from './staff-auth.service.js';
import { StaffGuard } from './staff.guard.js';

/** Back-office de l'équipe (les jetons de l'équipe ont leur propre secret, STAFF_JWT_SECRET). */
@Module({
  imports: [JwtModule.register({})],
  controllers: [AdminController],
  providers: [AdminService, StaffAuthService, StaffGuard],
  exports: [StaffAuthService],
})
export class AdminModule {}
