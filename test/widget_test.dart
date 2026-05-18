import 'package:flutter_test/flutter_test.dart';

import 'package:vodovod_bd_flutter/main.dart';

void main() {
  testWidgets('shows startup update check', (WidgetTester tester) async {
    await tester.pumpWidget(const VodovodApp());

    expect(find.text('Provjera verzije'), findsOneWidget);
    expect(
      find.text(
        'Provjeravam da li je instalirana najnovija verzija aplikacije.',
      ),
      findsOneWidget,
    );
  });
}
