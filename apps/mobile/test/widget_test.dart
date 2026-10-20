import 'package:flutter_test/flutter_test.dart';

import 'package:mchango/main.dart';

void main() {
  testWidgets("l'accueil affiche le nom et l'avertissement sur les fonds", (tester) async {
    await tester.pumpWidget(const MchangoApp());

    expect(find.text('Mchango'), findsOneWidget);
    expect(find.textContaining('ne détient, ne transfère et ne garantit aucun fonds'),
        findsOneWidget);
  });
}
