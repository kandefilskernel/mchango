import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mchango/api/api_client.dart';
import 'package:mchango/auth/device_identity.dart';
import 'package:mchango/auth/local_pin.dart';
import 'package:mchango/util/format.dart';

void main() {
  group("clé de l'appareil", () {
    // Vecteur calculé par Node, avec le même code que l'API
    final vector = jsonDecode(
      File('../../spec/test-vectors/device_signature.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    test('même clé publique et même signature que Node (Ed25519 déterministe)', () async {
      final identity = await DeviceIdentity.fromSeed(base64.decode(vector['seed'] as String));
      expect(identity.publicKeyBase64, vector['public_key']);
      expect(await identity.sign(vector['message'] as String), vector['signature']);
    });

    test('message du défi', () {
      expect(challengeMessage('6f1c2a5e-0000-4000-8000-000000000001', 'nonce-abc'), vector['message']);
    });

    test('la graine sauvegardée redonne la même clé', () async {
      final a = await DeviceIdentity.generate();
      final b = await DeviceIdentity.fromSeed(base64.decode(await a.seedBase64()));
      expect(b.publicKeyBase64, a.publicKeyBase64);
      expect(base64.decode(a.publicKeyBase64), hasLength(32));
    });
  });

  group('PIN local', () {
    test('mêmes règles que le serveur', () {
      for (final ok in ['482915', '102938', '774411']) {
        expect(pinWeakness(ok), isNull, reason: ok);
      }
      for (final bad in ['1234', '1234567', '12a456', '000000', '123456', '654321', '890123']) {
        expect(pinWeakness(bad), isNotNull, reason: bad);
      }
    });

    test('empreinte salée, vérifiable, sans le PIN en clair', () async {
      final h = await LocalPin.hash('482915');
      expect(h, startsWith(r'pbkdf2-sha256$60000$'));
      expect(h, isNot(contains('482915')));
      expect(await LocalPin.verify(h, '482915'), isTrue);
      expect(await LocalPin.verify(h, '482916'), isFalse);
      expect(await LocalPin.hash('482915'), isNot(h), reason: 'sel aléatoire');
    });
  });

  group('montants et dates', () {
    test('formatAmount', () {
      expect(formatAmount(20000, 'CDF'), '20 000 FC');
      expect(formatAmount(1500000, 'CDF'), '1 500 000 FC');
      expect(formatAmount(2050, 'USD'), '20,50 \$');
      expect(formatAmount(5, 'USD'), '0,05 \$');
    });

    test('parseAmount', () {
      expect(parseAmount('20 000', 'CDF'), 20000);
      expect(parseAmount('20,5', 'USD'), 2050);
      expect(parseAmount('20.05', 'USD'), 2005);
      expect(parseAmount('20', 'USD'), 2000);
      expect(parseAmount('20,5', 'CDF'), isNull);
      expect(parseAmount('abc', 'CDF'), isNull);
      expect(parseAmount('1,234', 'USD'), isNull);
    });

    test('formatDate', () => expect(formatDate('2026-11-02'), '02/11/2026'));

    test('uuidV4', () {
      expect(uuidV4(), matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(uuidV4(), isNot(uuidV4()));
    });
  });

  group('ApiClient', () {
    ApiClient clientReturning(int status, Object body) => ApiClient('http://api',
        client: MockClient((_) async => http.Response(jsonEncode(body), status,
            headers: {'content-type': 'application/json; charset=utf-8'})));

    test("message d'erreur du serveur, en français", () async {
      final c = clientReturning(409, {'message': 'Le groupe est complet.', 'statusCode': 409});
      expect(
        () => c.post('/groups/join'),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.message, 'message', 'Le groupe est complet.')),
      );
    });

    test('erreur de validation : le premier champ fautif', () async {
      final c = clientReturning(400, {
        'message': 'Requête invalide.',
        'errors': [
          {'field': 'phone', 'message': 'Numéro de téléphone RDC invalide.'},
        ],
      });
      expect(() => c.post('/auth/otp/request'),
          throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Numéro de téléphone RDC invalide.')));
    });

    test('pas de réseau', () async {
      final c = ApiClient('http://api', client: MockClient((_) => throw const SocketException('down')));
      expect(() => c.get('/groups'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)));
    });

    test('401 : rouvre la session une fois puis rejoue la requête', () async {
      var calls = 0;
      final c = ApiClient('http://api', client: MockClient((req) async {
        calls++;
        final ok = req.headers['Authorization'] == 'Bearer nouveau';
        return http.Response(ok ? '[]' : '{"message":"Session expirée."}', ok ? 200 : 401);
      }))
        ..accessToken = 'ancien';
      c.onUnauthorized = () async {
        c.accessToken = 'nouveau';
        return true;
      };
      expect(await c.get('/groups'), isEmpty);
      expect(calls, 2);
    });
  });
}
