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

  group('nombreVisible', () {
    test('usa el nombre elegido cuando existe', () {
      expect(
        nombreVisible(username: 'Gabo', email: 'luisgabrielnavast90@gmail.com'),
        'Gabo',
      );
    });

    test('nunca expone el correo completo: usa lo anterior a la @', () {
      final nombre = nombreVisible(email: 'luisgabrielnavast90@gmail.com');
      expect(nombre.contains('@'), isFalse);
      expect(nombre.contains('gmail'), isFalse);
    });

    test('recorta los nombres demasiado largos', () {
      final nombre = nombreVisible(email: 'luisgabrielnavast90@gmail.com');
      expect(nombre.length, lessThanOrEqualTo(maxLargoUsername + 1)); // +1 por el "…"
      expect(nombre.endsWith('…'), isTrue);
    });

    test('un correo corto se usa entero, sin recortar', () {
      expect(nombreVisible(email: 'gabo@gmail.com'), 'gabo');
    });

    test('cae en "Jugador" si no hay nombre ni correo', () {
      expect(nombreVisible(), 'Jugador');
      expect(nombreVisible(username: '   ', email: ''), 'Jugador');
    });
  });
}
