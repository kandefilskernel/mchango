import { randomUUID } from 'node:crypto';
import { StaffAuthService, type StaffRole } from '../src/admin/staff-auth.service.js';
import { totpCode } from '../src/admin/totp.js';
import { newDevice, TestApi, type TestSession } from './helpers.js';

interface Staff {
  email: string;
  password: string;
  secret: string;
  token: string;
  id: string;
}

describe('Back-office (e2e)', () => {
  let api: TestApi;

  beforeAll(async () => {
    api = await TestApi.start();
  });

  afterAll(async () => {
    await api.close();
  });

  const http = () => api.http();
  const asStaff = (s: Staff) => ({ Authorization: `Bearer ${s.token}` });
  const asMember = (s: TestSession) => ({ Authorization: `Bearer ${s.accessToken}` });

  async function staff(role: StaffRole): Promise<Staff> {
    const created = await api.app
      .get(StaffAuthService)
      .create(null, { email: `${role}-${randomUUID().slice(0, 8)}@mchango.test`, fullName: `Agent ${role}`, role });
    const res = await http()
      .post('/admin/auth/login')
      .send({ email: created.email, password: created.temporaryPassword, code: totpCode(created.totpSecret) })
      .expect(200);
    return { email: created.email, password: created.temporaryPassword, secret: created.totpSecret, token: res.body.token, id: created.id };
  }

  /** Tontine démarrée à 2, une déclaration contestée par le bénéficiaire. */
  async function disputedContribution() {
    const president = (await api.signUp(undefined, undefined, 'Mama Furaha')).session;
    const member = (await api.signUp(undefined, undefined, 'Papa Jean')).session;
    const startDate = new Date(Date.now() + 2 * 86_400_000).toISOString().slice(0, 10);
    const g = (
      await http()
        .post('/groups')
        .set(asMember(president))
        .send({ name: 'Kwetu', currency: 'CDF', contributionAmountMinor: 20000, frequency: 'weekly', startDate })
        .expect(201)
    ).body as { id: string };
    const { code } = (await http().post(`/groups/${g.id}/invitations`).set(asMember(president)).send({})).body;
    await http().post('/groups/join').set(asMember(member)).send({ code, acceptRules: true }).expect(200);
    const detail = (await http().get(`/groups/${g.id}`).set(asMember(president))).body;
    await http()
      .put(`/groups/${g.id}/turn-order`)
      .set(asMember(president))
      .send({ membershipIds: [president, member].map((s) => detail.members.find((m: { userId: string }) => m.userId === s.userId).membershipId) })
      .expect(200);
    await api.signTerms(g.id, [president, member]);
    await http().post(`/groups/${g.id}/start`).set(asMember(president)).expect(200);
    const tx = `MP${Date.now()}A`;
    const declared = await http()
      .post(`/groups/${g.id}/cycles/1/contributions`)
      .set(asMember(member))
      .send({ method: 'mpesa', txReference: tx, amountMinor: 20000, offlineId: randomUUID() })
      .expect(201);
    await http()
      .post(`/contributions/${declared.body.id}/decisions`)
      .set(asMember(president))
      .send({ decision: 'dispute', note: "Je n'ai rien reçu" })
      .expect(200);
    const dispute = await api.db.query<{ id: string }>('SELECT id FROM disputes WHERE contribution_id = $1', [declared.body.id]);
    return { groupId: g.id, president, member, contributionId: declared.body.id as string, disputeId: dispute.rows[0].id, tx };
  }

  describe('connexion', () => {
    it('exige e-mail, mot de passe ET code 2FA ; même message en cas d’erreur', async () => {
      const created = await api.app.get(StaffAuthService).create(null, { email: `x-${randomUUID().slice(0, 6)}@mchango.test`, fullName: 'X', role: 'support' });
      const send = (password: string, code: string) =>
        http().post('/admin/auth/login').send({ email: created.email, password, code });
      // « 000000 » n'ouvre rien quand le contournement de développement est désactivé (défaut)
      const bad1 = await send(created.temporaryPassword, '000000');
      const bad2 = await send('mauvais-mot-de-passe', totpCode(created.totpSecret));
      expect([bad1.status, bad2.status]).toEqual([401, 401]);
      expect(bad1.body.message).toBe(bad2.body.message);
      const ok = await send(created.temporaryPassword, totpCode(created.totpSecret)).expect(200);
      expect(ok.body).toMatchObject({ mustChangePassword: true, staff: { email: created.email, role: 'support' } });
    });

    it('bloque après 5 échecs', async () => {
      const created = await api.app.get(StaffAuthService).create(null, { email: `y-${randomUUID().slice(0, 6)}@mchango.test`, fullName: 'Y', role: 'support' });
      for (let i = 0; i < 5; i++) {
        await http().post('/admin/auth/login').send({ email: created.email, password: 'faux', code: '000000' }).expect(401);
      }
      await http()
        .post('/admin/auth/login')
        .send({ email: created.email, password: created.temporaryPassword, code: totpCode(created.totpSecret) })
        .expect(429);
    });

    it("un jeton de membre n'ouvre pas le back-office", async () => {
      const member = (await api.signUp()).session;
      await http().get('/admin/dashboard').expect(401);
      await http().get('/admin/dashboard').set(asMember(member)).expect(401);
    });

    it('changement du mot de passe provisoire', async () => {
      const s = await staff('support');
      await http().post('/admin/me/password').set(asStaff(s)).send({ current: s.password, next: 'court1' }).expect(400);
      await http().post('/admin/me/password').set(asStaff(s)).send({ current: 'faux', next: 'nouveau-mot-2026' }).expect(401);
      await http().post('/admin/me/password').set(asStaff(s)).send({ current: s.password, next: 'nouveau-mot-2026' }).expect(200);
      const again = await http()
        .post('/admin/auth/login')
        .send({ email: s.email, password: 'nouveau-mot-2026', code: totpCode(s.secret) })
        .expect(200);
      expect(again.body.mustChangePassword).toBe(false);
    });
  });

  describe('rôles', () => {
    it('lecture seule : voit le tableau de bord, numéros masqués, ne peut rien modifier', async () => {
      const ro = await staff('read_only');
      const member = await api.signUp();
      const dash = await http().get('/admin/dashboard').set(asStaff(ro)).expect(200);
      expect(dash.body).toEqual(expect.objectContaining({ users_total: expect.any(Number), groups_active: expect.any(Number) }));
      const found = await http().get(`/admin/users?q=${member.phone.slice(-7)}`).set(asStaff(ro)).expect(200);
      expect(found.body[0].phone).toMatch(/^\+243 \d\d \*\*\* \*\*\d\d$/);
      await http().post(`/admin/users/${member.session.userId}/block`).set(asStaff(ro)).send({ reason: 'test test' }).expect(403);
      await http().get('/admin/staff').set(asStaff(ro)).expect(403);
    });

    it('support : bloque un compte (sessions coupées), voit les numéros, débloque', async () => {
      const support = await staff('support');
      const member = await api.signUp();
      const found = await http().get(`/admin/users?q=${member.phone.slice(-7)}`).set(asStaff(support)).expect(200);
      expect(found.body[0].phone).toBe(member.phone);

      await http().post(`/admin/users/${member.session.userId}/block`).set(asStaff(support)).send({ reason: '' }).expect(400);
      await http()
        .post(`/admin/users/${member.session.userId}/block`)
        .set(asStaff(support))
        .send({ reason: 'Fraude signalée par le groupe' })
        .expect(200);
      expect((await api.openSession(member.session.deviceId, member.device)).status).toBe(403);

      await http().post(`/admin/users/${member.session.userId}/unblock`).set(asStaff(support)).send({}).expect(200);
      expect((await api.openSession(member.session.deviceId, member.device)).status).toBe(200);

      const detail = await http().get(`/admin/users/${member.session.userId}`).set(asStaff(support)).expect(200);
      expect(detail.body.events.map((e: { action: string }) => e.action)).toEqual(
        expect.arrayContaining(['staff.user_blocked', 'staff.user_unblocked']),
      );
    });

    it('support ne suspend pas une tontine et ne tranche pas un litige', async () => {
      const support = await staff('support');
      const d = await disputedContribution();
      await http().post(`/admin/groups/${d.groupId}/suspend`).set(asStaff(support)).send({ reason: 'test test' }).expect(403);
      await http()
        .post(`/admin/disputes/${d.disputeId}/decide`)
        .set(asStaff(support))
        .send({ decision: 'reject', note: 'test test' })
        .expect(403);
    });
  });

  describe('décisions', () => {
    it('suspension : plus de déclaration ; inscrite dans le journal du groupe ; réactivation', async () => {
      const compliance = await staff('compliance');
      const d = await disputedContribution();
      await http()
        .post(`/admin/groups/${d.groupId}/suspend`)
        .set(asStaff(compliance))
        .send({ reason: 'Enquête sur des déclarations suspectes' })
        .expect(200);
      await http()
        .post(`/groups/${d.groupId}/cycles/1/contributions`)
        .set(asMember(d.member))
        .send({ method: 'mpesa', txReference: `MP${Date.now()}B`, amountMinor: 20000, offlineId: randomUUID() })
        .expect(409);

      const group = await http().get(`/admin/groups/${d.groupId}`).set(asStaff(compliance)).expect(200);
      expect(group.body).toMatchObject({ status: 'suspended', suspendedReason: 'Enquête sur des déclarations suspectes' });
      expect(group.body.chain.intact).toBe(true);
      expect(group.body.events[0]).toMatchObject({ action: 'staff.group_suspended', actorType: 'staff' });

      const back = await http().post(`/admin/groups/${d.groupId}/reactivate`).set(asStaff(compliance)).send({}).expect(200);
      expect(back.body.status).toBe('active');
    });

    it('litige : rejet par la conformité ; le payeur peut redéclarer ; visible des membres', async () => {
      const compliance = await staff('compliance');
      const d = await disputedContribution();
      const list = await http().get('/admin/disputes?status=open').set(asStaff(compliance)).expect(200);
      expect(list.body.map((x: { id: string }) => x.id)).toContain(d.disputeId);

      await http()
        .post(`/admin/disputes/${d.disputeId}/decide`)
        .set(asStaff(compliance))
        .send({ decision: 'reject', note: '' })
        .expect(400);
      await http()
        .post(`/admin/disputes/${d.disputeId}/decide`)
        .set(asStaff(compliance))
        .send({ decision: 'reject', note: "L'ID de transaction n'apparaît pas chez le bénéficiaire" })
        .expect(200);
      await http()
        .post(`/admin/disputes/${d.disputeId}/decide`)
        .set(asStaff(compliance))
        .send({ decision: 'reject', note: 'deuxième fois' })
        .expect(409);

      const cycle = await http().get(`/groups/${d.groupId}/cycles/1`).set(asMember(d.member)).expect(200);
      expect(cycle.body.payers[0].status).toBe('expected');
      await http()
        .post(`/groups/${d.groupId}/cycles/1/contributions`)
        .set(asMember(d.member))
        .send({ method: 'mpesa', txReference: `MP${Date.now()}C`, amountMinor: 20000, offlineId: randomUUID() })
        .expect(201);

      const history = await http().get(`/groups/${d.groupId}/history`).set(asMember(d.president)).expect(200);
      expect(history.body.events.map((e: { action: string }) => e.action)).toContain('staff.dispute_rejected');
    });
  });

  describe('support (« À traiter »)', () => {
    it('PIN bloqué : apparaît à traiter ; le support le débloque, pas la lecture seule', async () => {
      const support = await staff('support');
      const ro = await staff('read_only');
      const member = await api.signUp();
      await api.db.query(`UPDATE users SET pin_locked_until = now() + interval '30 minutes' WHERE id = $1`, [
        member.session.userId,
      ]);

      const inbox = await http().get('/admin/inbox').set(asStaff(support)).expect(200);
      expect(inbox.body.pinLocked.map((u: { userId: string }) => u.userId)).toContain(member.session.userId);
      expect(inbox.body.counts.total).toBeGreaterThan(0);

      await http().post(`/admin/users/${member.session.userId}/unlock-pin`).set(asStaff(ro)).expect(403);
      await http().post(`/admin/users/${member.session.userId}/unlock-pin`).set(asStaff(support)).expect(200);
      await http().post(`/admin/users/${member.session.userId}/unlock-pin`).set(asStaff(support)).expect(404);
      const after = await http().get('/admin/inbox').set(asStaff(support)).expect(200);
      expect(after.body.pinLocked.map((u: { userId: string }) => u.userId)).not.toContain(member.session.userId);
    });

    it("« PIN oublié » sans réponse du garant : la conformité valide après vérification d'identité", async () => {
      const support = await staff('support');
      const compliance = await staff('compliance');
      const d = await disputedContribution(); // tontine en cours : le code SMS seul ne suffit pas
      const jean = d.member;
      const jeanPhone = (await http().get('/me').set(asMember(jean))).body.phone as string;

      const device = newDevice();
      await api.clearOtpLimit(jeanPhone);
      const { otpToken } = await api.verifiedOtpToken(jeanPhone);
      const request = await http()
        .post('/auth/pin-reset')
        .send({ otpToken, newPin: '270418', devicePublicKey: device.publicKey })
        .expect(200);
      expect(request.body.status).toBe('pending');
      const requestId = request.body.requestId as string;

      const inbox = await http().get('/admin/inbox').set(asStaff(support)).expect(200);
      expect(inbox.body.pinResets.map((r: { requestId: string }) => r.requestId)).toContain(requestId);

      const approve = (who: Staff, note: string) =>
        http().post(`/admin/pin-resets/${requestId}/approve`).set(asStaff(who)).send({ note });
      await approve(support, "Appel au numéro, questions sur la tontine Kwetu : identité confirmée").expect(403);
      await approve(compliance, 'ok').expect(400);
      await approve(compliance, 'Appel au +243, la personne a décrit sa tontine et ses tours : identité confirmée').expect(200);
      await approve(compliance, 'Deuxième validation de la même demande, refusée').expect(409);

      const done = await http().get(`/auth/pin-reset/${requestId}`).expect(200);
      expect(done.body.status).toBe('completed');
      expect((await api.openSession(done.body.deviceId, device)).status).toBe(200);

      const history = await http().get(`/groups/${d.groupId}/history`).set(asMember(d.president)).expect(200);
      expect(history.body.events.map((e: { action: string }) => e.action)).toContain('staff.pin_reset_approved');
    });
  });

  describe('suivi des membres, SMS, alertes, exports', () => {
    it('notes de suivi : « à suivre » apparaît à traiter, se clôture une seule fois ; lecture seule refusée', async () => {
      const support = await staff('support');
      const ro = await staff('read_only');
      const member = await api.signUp();
      const id = member.session.userId;
      const note = (who: Staff, body: object) => http().post(`/admin/users/${id}/notes`).set(asStaff(who)).send(body);

      await note(ro, { body: 'Essai' }).expect(403);
      await note(support, { body: '  ' }).expect(400);
      const open = await note(support, { body: 'Appelé à 14 h, rappeler demain', followUp: true }).expect(201);
      const inbox = await http().get('/admin/inbox').set(asStaff(support)).expect(200);
      expect(inbox.body.followUps.map((f: { noteId: string }) => f.noteId)).toContain(open.body.id);

      await note(support, { body: 'Rappelé : problème réglé', closes: open.body.id }).expect(201);
      await note(support, { body: 'Encore une clôture', closes: open.body.id }).expect(409);
      const after = await http().get('/admin/inbox').set(asStaff(support)).expect(200);
      expect(after.body.followUps.map((f: { noteId: string }) => f.noteId)).not.toContain(open.body.id);

      const detail = await http().get(`/admin/users/${id}`).set(asStaff(ro)).expect(200);
      expect(detail.body.notes).toHaveLength(2);
      expect(detail.body.notes.find((n: { id: string }) => n.id === open.body.id).closed).toBe(true);
    });

    it('renvoi d’un rappel en échec : seulement s’il sert encore, une fois, dans la limite du jour', async () => {
      const support = await staff('support');
      const compliance = await staff('compliance');
      const d = await disputedContribution();
      const { rows } = await api.db.query<{ membership_id: string; cycle_id: string; phone: string }>(
        `SELECT m.id AS membership_id, c.id AS cycle_id, u.phone FROM memberships m
         JOIN users u ON u.id = m.user_id JOIN cycles c ON c.group_id = m.group_id AND c.cycle_number = 1
         WHERE m.group_id = $1 AND m.user_id = $2`,
        [d.groupId, d.member.userId],
      );
      const { membership_id, cycle_id, phone } = rows[0];
      const failed = async (template = 'contribution_reminder') =>
        (
          await api.db.query<{ id: string }>(
            `INSERT INTO notifications (user_id, channel, template, payload, status, error)
             VALUES ($1, 'sms', $2, $3, 'failed', 'fournisseur indisponible') RETURNING id`,
            [d.member.userId, template, JSON.stringify({ cycle_id, membership_id, message: 'Mchango : rappel de test' })],
          )
        ).rows[0].id;
      const resend = (id: string, who = support) => http().post(`/admin/notifications/${id}/resend`).set(asStaff(who));

      const reminder = await failed();
      await resend(reminder).expect(409); // paiement déjà déclaré (contesté)
      await resend(await failed('otp_login')).expect(409); // jamais un code de connexion

      await http()
        .post(`/admin/disputes/${d.disputeId}/decide`)
        .set(asStaff(compliance))
        .send({ decision: 'reject', note: 'Aucune trace du paiement chez M-Pesa' })
        .expect(200);
      const before = api.sms.sent.length;
      const ok = await resend(reminder).expect(200);
      expect(ok.body.status).toBe('sent');
      expect(api.sms.sent.slice(before)).toEqual([{ phone, message: 'Mchango : rappel de test' }]);
      await resend(reminder).expect(409);

      const detail = await http().get(`/admin/users/${d.member.userId}`).set(asStaff(support)).expect(200);
      expect(detail.body.sms.find((s: { id: string }) => s.id === reminder).resendable).toBe(false);

      await resend(await failed()).expect(200);
      await resend(await failed()).expect(200);
      await resend(await failed()).expect(429);
    });

    it('alerte : ID de transaction réutilisé après un rejet', async () => {
      const compliance = await staff('compliance');
      const d = await disputedContribution();
      await http()
        .post(`/admin/disputes/${d.disputeId}/decide`)
        .set(asStaff(compliance))
        .send({ decision: 'reject', note: 'Aucune trace du paiement chez M-Pesa' })
        .expect(200);
      await http()
        .post(`/groups/${d.groupId}/cycles/1/contributions`)
        .set(asMember(d.member))
        .send({ method: 'mpesa', txReference: d.tx, amountMinor: 20000, offlineId: randomUUID() })
        .expect(201);
      const alerts = await http().get('/admin/alerts').set(asStaff(compliance)).expect(200);
      const hit = alerts.body.reusedTxReferences.find((a: { txReference: string }) => a.txReference === d.tx);
      expect(hit).toMatchObject({ method: 'mpesa', count: 2, payers: ['Papa Jean'], groups: ['Kwetu'] });
    });

    it('export CSV : finance oui (numéros masqués), support non ; chaque export est journalisé', async () => {
      const finance = await staff('finance');
      const support = await staff('support');
      const d = await disputedContribution();
      await http().get('/admin/export?kind=disputes').set(asStaff(support)).expect(403);
      await http().get('/admin/export?kind=nope').set(asStaff(finance)).expect(400);

      const res = await http().get('/admin/export?kind=disputes').set(asStaff(finance)).expect(200);
      expect(res.headers['content-type']).toContain('text/csv');
      expect(res.headers['content-disposition']).toMatch(/attachment; filename="mchango-disputes-\d{4}-\d{2}-\d{2}\.csv"/);
      expect(res.text.startsWith('﻿Ouvert le;Statut;Tontine')).toBe(true);
      const line = res.text.split('\r\n').find((l) => l.includes(d.tx))!;
      expect(line).toContain('Papa Jean');
      expect(line).toMatch(/\*\*\*/);

      const audit = await http().get(`/admin/export?kind=audit&chain=group:${d.groupId}`).set(asStaff(finance)).expect(200);
      expect(audit.text).toContain('contribution');
      await http().get('/admin/export?kind=late').set(asStaff(finance)).expect(200);

      const actions = await http().get('/admin/audit/staff').set(asStaff(finance)).expect(200);
      const exports = actions.body.filter((a: { action: string; staff: string }) => a.action === 'staff.data_exported' && a.staff.includes(finance.email));
      expect(exports).toHaveLength(3);
    });
  });

  describe('équipe et audit', () => {
    it('super admin : crée un compte, change un rôle, désactive (effet immédiat)', async () => {
      const admin = await staff('super_admin');
      const created = await http()
        .post('/admin/staff')
        .set(asStaff(admin))
        .send({ email: `new-${randomUUID().slice(0, 6)}@mchango.test`, fullName: 'Nouvel agent', role: 'read_only' })
        .expect(201);
      expect(created.body.temporaryPassword).toHaveLength(16);
      expect(created.body.otpauthUrl).toMatch(/^otpauth:\/\/totp\/Mchango/);

      const login = await http()
        .post('/admin/auth/login')
        .send({ email: created.body.email, password: created.body.temporaryPassword, code: totpCode(created.body.totpSecret) })
        .expect(200);
      await http().post(`/admin/staff/${created.body.id}`).set(asStaff(admin)).send({ role: 'support' }).expect(200);
      await http().post(`/admin/staff/${created.body.id}`).set(asStaff(admin)).send({ isActive: false }).expect(200);
      await http().get('/admin/dashboard').set({ Authorization: `Bearer ${login.body.token}` }).expect(401);

      await http().post(`/admin/staff/${admin.id}`).set(asStaff(admin)).send({ isActive: false }).expect(400);
    });

    it('nouveaux identifiants (ligne de commande) : les anciens ne marchent plus, les nouveaux oui', async () => {
      const s = await staff('compliance');
      const fresh = await api.app.get(StaffAuthService).resetCredentials(s.email.toUpperCase());
      expect(fresh.temporaryPassword).not.toBe(s.password);
      await http()
        .post('/admin/auth/login')
        .send({ email: s.email, password: s.password, code: totpCode(s.secret) })
        .expect(401);
      const ok = await http()
        .post('/admin/auth/login')
        .send({ email: s.email, password: fresh.temporaryPassword, code: totpCode(fresh.totpSecret) })
        .expect(200);
      expect(ok.body.mustChangePassword).toBe(true);
      await expect(api.app.get(StaffAuthService).resetCredentials('personne@mchango.test')).rejects.toThrow();
    });

    it('audit : vérification de la chaîne globale et actions de l’équipe', async () => {
      const admin = await staff('super_admin');
      const verify = await http().post('/admin/audit/verify').set(asStaff(admin)).send({ chainId: 'global' }).expect(200);
      expect(verify.body).toMatchObject({ chainId: 'global', intact: true });
      await http().post('/admin/audit/verify').set(asStaff(admin)).send({ chainId: 'n importe quoi' }).expect(400);

      const actions = await http().get('/admin/audit/staff').set(asStaff(admin)).expect(200);
      expect(actions.body[0]).toMatchObject({ action: 'staff.login', staff: expect.stringContaining(admin.email) });
      const events = await http().get('/admin/audit?chain=global&limit=5').set(asStaff(admin)).expect(200);
      expect(events.body).toHaveLength(5);
    });
  });
});
