import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ajedrez_seed_app/main.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
    );
  });

  testWidgets('App arranca en el splash y pasa a la pantalla de login', (WidgetTester tester) async {
    await tester.pumpWidget(const ChessSeedApp());

    // Splash: ícono + logo animados, ninguna sesión activa todavía.
    expect(find.byType(SvgPicture), findsWidgets);
    expect(find.text('Iniciar sesión'), findsNothing);

    // Tras el delay del splash, navega sola al login.
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pumpAndSettle();

    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
