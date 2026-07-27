import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Identidad del jugador en este dispositivo: se genera una sola vez y se
/// guarda localmente, para que el saldo de SEED (ganado viendo anuncios o
/// jugando) sea el mismo sin importar cuántas veces se reinicie la app.
/// El login con Google sigue siendo simulado; esto no reemplaza una cuenta
/// real, solo evita que cada sesión empiece "de cero" con un usuario distinto.
class IdentidadJugador {
  final String userId;
  final String username;

  const IdentidadJugador({required this.userId, required this.username});

  static const _claveUserId = 'chess_seed_user_id';
  static const _claveUsername = 'chess_seed_username';

  static Future<IdentidadJugador> obtener() async {
    final prefs = await SharedPreferences.getInstance();
    var userId = prefs.getString(_claveUserId);
    var username = prefs.getString(_claveUsername);

    if (userId == null || username == null) {
      final sufijo = Random().nextInt(90000) + 10000;
      userId = 'jugador_$sufijo';
      username = 'Jugador$sufijo';
      await prefs.setString(_claveUserId, userId);
      await prefs.setString(_claveUsername, username);
    }

    return IdentidadJugador(userId: userId, username: username);
  }
}
