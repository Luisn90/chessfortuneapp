import 'package:flutter_test/flutter_test.dart';

import 'package:ajedrez_seed_app/main.dart';

void main() {
  testWidgets('App arranca en la pantalla de login', (WidgetTester tester) async {
    await tester.pumpWidget(const ChessSeedApp());

    expect(find.text('CHESS SEED'), findsOneWidget);
    expect(find.text('Iniciar Sesión con Google'), findsOneWidget);
  });
}
