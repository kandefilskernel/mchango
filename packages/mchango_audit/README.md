# mchango_audit

Vérification, côté téléphone, du journal d'audit chaîné de Mchango (format `mchango-v1`, voir [`spec/audit-hash.md`](../../spec/audit-hash.md)).

Paquet Dart pur : testable sans émulateur, utilisé par `apps/mobile`.

```dart
final result = verifyChain(chainId, events, from: derniereTeteMemorisee);
if (!result.isValid) {
  // result.firstInvalidSeq, result.failure
}
```

Tests (sur les vecteurs de `spec/test-vectors/`) :

```bash
dart test
```
