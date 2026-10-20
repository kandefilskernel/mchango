import 'dart:convert';
import 'dart:io';

import 'package:mchango_audit/mchango_audit.dart';
import 'package:test/test.dart';

/// Vecteurs produits par PostgreSQL et recoupés en Python (spec/tools/).
final _vectors = jsonDecode(
  File('../../spec/test-vectors/audit_chain.json').readAsStringSync(),
) as Map<String, dynamic>;

List<AuditEvent> _events(Map<String, dynamic> chain) => [
      for (final e in chain['events'] as List)
        AuditEvent.fromJson(e as Map<String, dynamic>),
    ];

void main() {
  final chains = (_vectors['chains'] as List).cast<Map<String, dynamic>>();
  final invalidCases =
      (_vectors['invalid_cases'] as List).cast<Map<String, dynamic>>();
  final groupChain =
      chains.firstWhere((c) => (c['chain_id'] as String).startsWith('group:'));

  test('format attendu', () {
    expect(_vectors['format'], formatVersion);
    expect(_vectors['genesis_prev_hash'], genesisPrevHash);
  });

  group('hash identique à PostgreSQL', () {
    for (final chain in chains) {
      for (final e in _events(chain)) {
        test('${e.chainId} seq ${e.seq} (${e.action})', () {
          expect(computeHash(e), e.hash);
        });
      }
    }
  });

  group('chaînes valides', () {
    for (final chain in chains) {
      test(chain['chain_id'], () {
        final events = _events(chain);
        final result = verifyChain(chain['chain_id'] as String, events);
        expect(result.isValid, isTrue);
        expect(result.head, ChainHead(seq: events.last.seq, hash: events.last.hash));
      });
    }
  });

  group('falsifications détectées', () {
    for (final c in invalidCases) {
      test(c['description'], () {
        final result = verifyChain(c['chain_id'] as String, _events(c));
        expect(result.isValid, isFalse);
        expect(result.firstInvalidSeq, c['first_invalid_seq']);
      });
    }
  });

  group('synchronisation incrémentale', () {
    final chainId = groupChain['chain_id'] as String;
    final events = _events(groupChain);

    test('reprend depuis une tête mémorisée', () {
      final first = verifyChain(chainId, events.sublist(0, 2));
      final rest = verifyChain(chainId, events.sublist(2), from: first.head);
      expect(rest.isValid, isTrue);
      expect(rest.head.seq, events.last.seq);
    });

    test('refuse une suite qui ne se raccroche pas à la tête', () {
      final wrongHead = ChainHead(seq: 2, hash: 'f' * 64);
      final result = verifyChain(chainId, events.sublist(2), from: wrongHead);
      expect(result.failure, ChainFailure.prevHashMismatch);
      expect(result.firstInvalidSeq, 3);
    });

    test("refuse un événement d'une autre chaîne", () {
      final result = verifyChain('group:autre', events);
      expect(result.failure, ChainFailure.wrongChain);
    });
  });

  test('détecte un historique réécrit pour un seq déjà vérifié', () {
    final e = _events(groupChain)[1];
    final known = ChainHead(seq: e.seq, hash: e.hash);
    expect(isRewrite(known, e), isFalse);
    expect(isRewrite(ChainHead(seq: e.seq, hash: '0' * 64), e), isTrue);
  });
}
