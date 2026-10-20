// Parcours complet du code de l'app contre la VRAIE API (PostgreSQL + Redis de docker compose).
// Ignoré sauf si ces variables sont définies :
//   MCHANGO_API_URL  ex. http://localhost:3000
//   MCHANGO_API_LOG  fichier où l'API de développement écrit ses logs (codes SMS en console)
// Voir apps/mobile/README.md.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mchango/api/api_client.dart';
import 'package:mchango/services.dart';
import 'package:mchango/storage/key_value_store.dart';
import 'package:mchango/ui/history/history_screen.dart';
import 'package:mchango/util/format.dart';

final apiUrl = Platform.environment['MCHANGO_API_URL'];
final apiLog = Platform.environment['MCHANGO_API_LOG'];

String newPhone() => '+24399${Random().nextInt(10000000).toString().padLeft(7, '0')}';

/// Dernier code SMS envoyé à [phone], lu dans les logs de l'API (SMS_DRIVER=console).
Future<String> smsCode(String phone) async {
  for (var i = 0; i < 50; i++) {
    final matches = RegExp('→ ${RegExp.escape(phone)} : Mchango : votre code est (\\d{6})')
        .allMatches(await File(apiLog!).readAsString());
    if (matches.isNotEmpty) return matches.last.group(1)!;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('code SMS introuvable pour $phone');
}

/// Un « téléphone » : ses propres services et son propre stockage sécurisé.
Future<AppServices> signUp(String name) async {
  final services = AppServices(client: ApiClient(apiUrl!), store: MemoryKeyValueStore());
  await services.auth.load();
  final phone = newPhone();
  await services.auth.requestOtp(phone);
  final otp = await services.auth.verifyOtp(phone, await smsCode(phone));
  expect(otp.accountExists, isFalse);
  await services.auth.register(otpToken: otp.otpToken, fullName: name, pin: '482915');
  return services;
}

String inDays(int days) => DateTime.now().add(Duration(days: days)).toIso8601String().substring(0, 10);

void main() {
  final skip = apiUrl == null || apiLog == null ? 'MCHANGO_API_URL / MCHANGO_API_LOG non définis' : null;

  test('rotation complète à 3 avec le code de l\'app, contre la vraie API', () async {
    final furaha = await signUp('Mama Furaha');
    final jean = await signUp('Papa Jean');
    final neema = await signUp('Mama Neema');

    // Session signée par la clé Ed25519 générée en Dart, vérifiée par Node
    furaha.auth.lock();
    expect(await furaha.auth.unlock('000001'), isFalse);
    expect(await furaha.auth.unlock('482915'), isTrue);

    final group = await furaha.api.createGroup(
      name: 'Likelemba Kenya',
      currency: 'CDF',
      contributionAmountMinor: 20000,
      frequency: 'weekly',
      startDate: inDays(1),
      maxMembers: 10,
    );
    final invitation = await furaha.api.createInvitation(group.id);
    final preview = await jean.api.preview(invitation.code.toLowerCase());
    expect(preview.presidentName, 'Mama Furaha');
    await jean.api.join(invitation.code);
    await neema.api.join(invitation.code);

    final draw = await furaha.api.draw(group.id);
    expect(draw.order, hasLength(3));
    await furaha.api.start(group.id);

    final byUser = {
      for (final m in (await furaha.api.group(group.id)).members) m.fullName: m.membershipId,
    };
    final phoneOf = {'Mama Furaha': furaha, 'Papa Jean': jean, 'Mama Neema': neema};
    final board = await neema.api.board(group.id);
    expect(board.cycles, hasLength(3));

    var tx = 0;
    for (final c in board.cycles) {
      final beneficiary = phoneOf[c.beneficiaryName]!;
      final payers = phoneOf.entries.where((e) => e.key != c.beneficiaryName).toList();
      for (final (i, payer) in payers.indexed) {
        // Le premier paie en espèces devant l'autre payeur, le second par M-Pesa
        final cash = i == 0;
        final declared = await payer.value.api.declare(
          groupId: group.id,
          cycleNumber: c.cycleNumber,
          method: cash ? 'cash' : 'mpesa',
          amountMinor: 20000,
          offlineId: uuidV4(),
          txReference: cash ? null : 'MP${DateTime.now().millisecondsSinceEpoch}${tx++}',
          witnessMembershipId: cash ? byUser[payers[1].key] : null,
        );
        await beneficiary.api.decide(declared.id, 'confirm');
        if (cash) await payers[1].value.api.decide(declared.id, 'witness');
        final receipt = await payer.value.api.receipt(declared.id);
        expect(receipt.receiptNumber, matches(RegExp(r'^MCH-\d{8}$')));
        expect(receipt.witnessName, cash ? payers[1].key : isNull);
      }
    }

    final finished = await jean.api.group(group.id);
    expect(finished.status, 'closed');

    // Le journal du serveur, vérifié par le paquet Dart de l'app
    final store = MemoryKeyValueStore();
    final check = await checkHistory(store, group.id, await neema.api.history(group.id));
    expect(check.trusted, isTrue);
    expect(check.events.length, greaterThan(30));
    expect(store.data['chain_head:${group.id}'], startsWith('${check.events.length}:'));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

  test("une erreur de l'API arrive en français jusqu'à l'app", () async {
    final services = AppServices(client: ApiClient(apiUrl!), store: MemoryKeyValueStore());
    expect(
      () => services.auth.requestOtp('+33612345678'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Numéro de téléphone RDC invalide.')),
    );
  }, skip: skip);
}
