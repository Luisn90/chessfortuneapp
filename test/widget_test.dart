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

  testWidgets('App arranca en la pantalla de login', (WidgetTester tester) async {
    await tester.pumpWidget(const ChessSeedApp());

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
