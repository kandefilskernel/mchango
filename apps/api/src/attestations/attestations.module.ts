import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { MyAttestationsController, PublicAttestationsController } from './attestations.controller.js';
import { AttestationsService } from './attestations.service.js';

@Module({
  imports: [AuthModule],
  controllers: [MyAttestationsController, PublicAttestationsController],
  providers: [AttestationsService],
})
export class AttestationsModule {}
