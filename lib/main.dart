import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chess/chess_engine.dart';

/// URL del backend (Express + Socket.IO) desplegado en Render.
/// El plan gratuito "duerme" tras ~15 min sin tráfico: la primera
/// petición después de eso puede tardar 30-50s en responder.
const String backendBaseUrl = 'https://chessfortuneapp.onrender.com';

/// Proyecto Supabase (misma base de datos que usa el backend). La clave
/// "publishable" es segura para embeber en la app: solo permite operaciones
/// de autenticación; los saldos de SEED solo los toca el backend con su
/// propia clave privada (service_role), que nunca viaja al cliente.
const String supabaseUrl = 'https://zbswjvubxbnethdemelo.supabase.co';
const String supabaseAnonKey = 'sb_publishable_rNGKmrRjqRehf2fC9RGBow_yrV_A7CB';

SupabaseClient get supabase => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(const ChessSeedApp());
}

class ChessSeedApp extends StatelessWidget {
  const ChessSeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess SEED',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      ),
      routes: {
        '/lobby': (context) => const LobbyScreen(),
        // '/game' ya no es una ruta con nombre: GameScreen ahora requiere
        // el socket, la sala y el color asignado, así que se navega con
        // Navigator.push(MaterialPageRoute(...)) desde el lobby.
      },
      home: supabase.auth.currentSession != null ? const LobbyScreen() : const LoginScreen(),
    );
  }
}

// === 1. PANTALLA DE INICIO DE SESIÓN / REGISTRO (Supabase Auth) ===
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();

  bool _modoRegistro = false;
  bool _cargando = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _mostrarError('Completa correo y contraseña');
      return;
    }
    if (_modoRegistro && _usernameController.text.trim().isEmpty) {
      _mostrarError('Elige un nombre de usuario');
      return;
    }

    setState(() => _cargando = true);
    try {
      if (_modoRegistro) {
        final respuesta = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {'username': _usernameController.text.trim()},
        );
        if (!mounted) return;
        if (respuesta.session == null) {
          await _mostrarConfirmacionPendiente(email);
          if (!mounted) return;
          setState(() => _modoRegistro = false);
          return;
        }
      } else {
        await supabase.auth.signInWithPassword(email: email, password: password);
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/lobby');
    } on AuthException catch (e) {
      _mostrarError(_traducirErrorAuth(e));
    } catch (e) {
      _mostrarError('No se pudo conectar con el servidor de autenticación');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _traducirErrorAuth(AuthException e) {
    switch (e.code) {
      case 'email_not_confirmed':
        return 'Todavía no confirmaste tu correo. Revisa tu bandeja de entrada.';
      case 'invalid_credentials':
        return 'Correo o contraseña incorrectos.';
      case 'email_address_invalid':
        return 'Ese correo no es válido.';
      case 'user_already_exists':
      case 'email_exists':
        return 'Ya existe una cuenta con ese correo.';
      case 'weak_password':
        return 'La contraseña es muy débil (mínimo 6 caracteres).';
      default:
        return e.message;
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _mostrarConfirmacionPendiente(String email) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text('Confirma tu correo', style: TextStyle(color: Colors.white)),
        content: Text(
          'Te enviamos un enlace de confirmación a $email. Ábrelo desde ese '
          'correo y después vuelve aquí a iniciar sesión.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.casino, size: 72, color: Colors.amber),
                const SizedBox(height: 16),
                const Text(
                  'CHESS SEED',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Juega, gana y acumula tokens',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 40),
                if (_modoRegistro) ...[
                  TextField(
                    controller: _usernameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Nombre de usuario'),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  style: const TextStyle(color: Colors.white),
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña'),
                  onSubmitted: (_) => _enviar(),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: _cargando ? null : _enviar,
                  child: _cargando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _modoRegistro ? 'Crear cuenta' : 'Iniciar sesión',
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                        ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _cargando ? null : () => setState(() => _modoRegistro = !_modoRegistro),
                  child: Text(
                    _modoRegistro
                        ? '¿Ya tienes cuenta? Inicia sesión'
                        : '¿No tienes cuenta? Regístrate',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// === 2. PANTALLA DEL LOBBY DE JUGADORES (CONECTADA AL BACKEND) ===
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  double saldoSeed = 0;
  bool cargandoVideo = false;
  bool _identidadLista = false;

  late String _userId;
  late String _username;
  late socket_io.Socket _socket;

  List<Map<String, dynamic>> _salasDisponibles = [];
  String? _miSalaId; // sala que yo creé y sigue esperando rival
  bool _conectando = true;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    final usuario = supabase.auth.currentUser;
    if (usuario == null) {
      // No debería pasar (solo se llega aquí ya autenticado), pero por las
      // dudas mandamos de vuelta al login en vez de dejar la pantalla rota.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _userId = usuario.id;
      _username = (usuario.userMetadata?['username'] as String?)?.trim().isNotEmpty == true
          ? usuario.userMetadata!['username'] as String
          : (usuario.email ?? 'Jugador');
      _identidadLista = true;
    });
    _conectarSocket();
    _cargarSaldo();
  }

  Future<void> _cargarSaldo() async {
    try {
      final respuesta = await http.get(Uri.parse('$backendBaseUrl/api/saldo/$_userId'));
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        final datos = jsonDecode(respuesta.body);
        setState(() => saldoSeed = (datos['seed_gratis'] as num).toDouble());
      }
    } catch (_) {
      // Si falla, se queda en 0 y se actualizará al ver un anuncio o jugar.
    }
  }

  void _conectarSocket() {
    _socket = socket_io.io(
      backendBaseUrl,
      socket_io.OptionBuilder()
          .setTransports(['websocket'])
          .enableForceNew()
          .build(),
    );

    _socket.onConnect((_) {
      if (mounted) setState(() => _conectando = false);
    });

    _socket.on('salas_actualizadas', (data) {
      if (!mounted) return;
      setState(() {
        _salasDisponibles = List<Map<String, dynamic>>.from(
          (data as List).map((sala) => Map<String, dynamic>.from(sala)),
        );
      });
    });

    _socket.on('sala_creada', (data) {
      if (!mounted) return;
      setState(() => _miSalaId = data['salaId'] as String);
    });

    _socket.on('partida_iniciada', (data) {
      if (!mounted) return;
      final jugadores = List<Map<String, dynamic>>.from(
        (data['jugadores'] as List).map((j) => Map<String, dynamic>.from(j)),
      );
      final miIndice = jugadores.indexWhere((j) => j['userId'] == _userId);
      if (miIndice == -1) return; // partida de otra sala, no es la mía

      final miColor = miIndice == 0 ? PieceColor.white : PieceColor.black;
      final oponente = jugadores[miIndice == 0 ? 1 : 0]['username'] as String?;
      final costo = ((data['costo'] as num?) ?? 0).toDouble();

      setState(() => _miSalaId = null);
      Navigator.push<double>(
        context,
        MaterialPageRoute(
          builder: (_) => GameScreen(
            socket: _socket,
            salaId: data['salaId'] as String,
            miColor: miColor,
            userId: _userId,
            costo: costo,
            oponenteNombre: oponente,
          ),
        ),
      ).then((nuevoSaldo) {
        if (nuevoSaldo != null && mounted) {
          setState(() => saldoSeed = nuevoSaldo);
        } else {
          _cargarSaldo(); // por si acaso, sincronizamos con el servidor
        }
      });
    });

    _socket.on('error_sala', (data) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message'] ?? 'Error en el lobby')),
      );
    });

    _socket.connect();
  }

  @override
  void dispose() {
    _socket.dispose();
    super.dispose();
  }

  Future<void> _crearPartida() async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _CrearSalaDialog(nombreSugerido: 'Sala de $_username'),
    );
    if (resultado == null) return;

    _socket.emit('crear_sala', {
      'userId': _userId,
      'username': _username,
      'nombre': resultado['nombre'],
      'costo': resultado['costo'],
    });
  }

  void _unirseAPartida(String salaId) {
    _socket.emit('unirse_sala', {
      'salaId': salaId,
      'userId': _userId,
      'username': _username,
    });
  }

  void _cancelarMiSala() {
    if (_miSalaId == null) return;
    _socket.emit('cancelar_sala', {'salaId': _miSalaId, 'userId': _userId});
    setState(() => _miSalaId = null);
  }

  // Función que llama al servidor Node.js de tu PC
  Future<void> simularVideoAd() async {
    setState(() {
      cargandoVideo = true;
    });

    try {
      // Hacemos la petición POST al backend desplegado en Render
      final url = Uri.parse('$backendBaseUrl/api/reward-ad');
      final respuesta = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _userId, 'username': _username}),
      );

      if (!mounted) return;

      if (respuesta.statusCode == 200) {
        final datos = jsonDecode(respuesta.body);
        setState(() {
          // Actualizamos el saldo visual con la respuesta real del servidor
          saldoSeed = datos['nuevo_saldo'].toDouble();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(datos['message'])),
        );
      } else {
        throw Exception('Error en el servidor');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al conectar con el servidor backend')),
      );
    } finally {
      setState(() {
        cargandoVideo = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_identidadLista) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Hola, $_username'),
        backgroundColor: const Color(0xFF2C2C2C),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Chip(
              avatar: const Icon(Icons.monetization_on, color: Colors.amber, size: 20),
              label: Text(
                '${saldoSeed.toStringAsFixed(2)} SEED',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.black54,
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearPartida,
        icon: const Icon(Icons.add),
        label: const Text('Crear partida'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Salas Disponibles',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                if (_conectando)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _salasDisponibles.isEmpty
                  ? Center(
                      child: Text(
                        _conectando
                            ? 'Conectando al lobby...'
                            : 'No hay salas abiertas. ¡Crea una!',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _salasDisponibles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final sala = _salasDisponibles[index];
                        return _buildRoomCard(sala);
                      },
                    ),
            ),
            Card(
              color: const Color(0xFF2C2C2C),
              child: ListTile(
                leading: const Icon(Icons.video_library, color: Colors.redAccent),
                title: const Text('¿Te quedaste sin SEED?'),
                subtitle: const Text('Mira 2 videos cortos para recargar 1.0 SEED'),
                trailing: ElevatedButton(
                  onPressed: cargandoVideo ? null : simularVideoAd,
                  child: cargandoVideo
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Ver'),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRoomCard(Map<String, dynamic> sala) {
    final esMiSala = sala['id'] == _miSalaId;
    final costo = (sala['costo'] as num?) ?? 0;
    final costoTexto = costo > 0 ? '$costo SEED' : 'Gratis';
    final costoColor = costo > 0 ? Colors.amber : Colors.green;

    return Card(
      color: const Color(0xFF2C2C2C),
      child: ListTile(
        title: Text(sala['nombre'] ?? 'Sala', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Creada por ${sala['creadorNombre'] ?? 'Jugador'}'),
        trailing: esMiSala
            ? TextButton.icon(
                onPressed: _cancelarMiSala,
                icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                label: const Text('Cancelar', style: TextStyle(color: Colors.redAccent)),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(costoTexto, style: TextStyle(color: costoColor, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _unirseAPartida(sala['id'] as String),
                    child: const Text('Unirse'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CrearSalaDialog extends StatefulWidget {
  final String nombreSugerido;

  const _CrearSalaDialog({required this.nombreSugerido});

  @override
  State<_CrearSalaDialog> createState() => _CrearSalaDialogState();
}

class _CrearSalaDialogState extends State<_CrearSalaDialog> {
  late final TextEditingController _controller;
  double _costo = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.nombreSugerido);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2C2C2C),
      title: const Text('Crear partida', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Nombre de la sala'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Costo:', style: TextStyle(color: Colors.white70)),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('Gratis'),
                selected: _costo == 0,
                onSelected: (_) => setState(() => _costo = 0),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('1.0 SEED'),
                selected: _costo == 1,
                onSelected: (_) => setState(() => _costo = 1),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final nombre = _controller.text.trim();
            if (nombre.isEmpty) return;
            Navigator.of(context).pop({'nombre': nombre, 'costo': _costo});
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}


// === 3. PANTALLA DEL JUEGO (TABLERO CON REGLAS DE AJEDREZ REALES) ===
class GameScreen extends StatefulWidget {
  final socket_io.Socket socket;
  final String salaId;
  final PieceColor miColor;
  final String userId;
  final double costo;
  final String? oponenteNombre;

  const GameScreen({
    super.key,
    required this.socket,
    required this.salaId,
    required this.miColor,
    required this.userId,
    this.costo = 0,
    this.oponenteNombre,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final ChessEngine _engine = ChessEngine();
  int? selectedIndex;
  List<ChessMove> _legalMovesFromSelection = [];
  String? _avisoRival;

  @override
  void initState() {
    super.initState();
    // El servidor es la autoridad: toda jugada (mía o del rival) solo se
    // aplica al tablero cuando él la confirma por "pieza_movida", y el fin
    // de la partida (con el resultado y el reparto del pozo, si había
    // apuesta) también lo decide y anuncia el servidor.
    widget.socket.on('pieza_movida', _onMovimientoConfirmado);
    widget.socket.on('movimiento_rechazado', _onMovimientoRechazado);
    widget.socket.on('rival_desconectado', _onRivalDesconectado);
    widget.socket.on('partida_terminada', _onPartidaTerminada);
  }

  @override
  void dispose() {
    widget.socket.off('pieza_movida', _onMovimientoConfirmado);
    widget.socket.off('movimiento_rechazado', _onMovimientoRechazado);
    widget.socket.off('rival_desconectado', _onRivalDesconectado);
    widget.socket.off('partida_terminada', _onPartidaTerminada);
    super.dispose();
  }

  void _onMovimientoConfirmado(dynamic data) {
    if (!mounted) return;
    final datos = Map<String, dynamic>.from(data as Map);
    final from = datos['from'] as int;
    final to = datos['to'] as int;
    final promoNombre = datos['promotion'] as String?;
    final promotion = promoNombre == null
        ? null
        : PieceType.values.firstWhere((t) => t.name == promoNombre);
    _aplicarMovimiento(ChessMove(from, to, promotion: promotion));
  }

  void _onMovimientoRechazado(dynamic data) {
    if (!mounted) return;
    final datos = Map<String, dynamic>.from(data as Map);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(datos['message'] ?? 'Jugada rechazada por el servidor')),
    );
  }

  void _onRivalDesconectado(dynamic _) {
    if (!mounted) return;
    setState(() => _avisoRival = 'Tu rival se desconectó de la partida');
  }

  void _onSquareTap(int index) {
    // Partida terminada, o no es mi turno: no se permiten jugadas.
    final currentStatus = _engine.status;
    if (currentStatus == GameStatus.checkmate ||
        currentStatus == GameStatus.stalemate ||
        _engine.turn != widget.miColor) {
      return;
    }

    final tappedPiece = _engine.pieceAt(index);
    final esPiezaPropia = tappedPiece != null &&
        tappedPiece.color == _engine.turn &&
        tappedPiece.color == widget.miColor;

    if (selectedIndex == null) {
      if (esPiezaPropia) {
        setState(() {
          selectedIndex = index;
          _legalMovesFromSelection = _engine.legalMovesFrom(index);
        });
      }
      return;
    }

    if (index == selectedIndex) {
      setState(() {
        selectedIndex = null;
        _legalMovesFromSelection = [];
      });
      return;
    }

    final movesToTarget =
        _legalMovesFromSelection.where((m) => m.to == index).toList();

    if (movesToTarget.isEmpty) {
      // No es un destino legal: si es otra pieza propia, cambiamos selección.
      if (esPiezaPropia) {
        setState(() {
          selectedIndex = index;
          _legalMovesFromSelection = _engine.legalMovesFrom(index);
        });
      } else {
        setState(() {
          selectedIndex = null;
          _legalMovesFromSelection = [];
        });
      }
      return;
    }

    if (movesToTarget.length > 1) {
      // Varias opciones = promoción de peón: preguntamos qué pieza elegir.
      _askPromotion().then((promotion) {
        if (promotion == null) return;
        final move = movesToTarget.firstWhere((m) => m.promotion == promotion);
        _playMove(move);
      });
      return;
    }

    _playMove(movesToTarget.first);
  }

  /// Jugada hecha por mí: se la mando al servidor para que la valide.
  /// No se aplica al tablero aquí — se aplica cuando llega confirmada por
  /// "pieza_movida" (ver [_onMovimientoConfirmado]).
  void _playMove(ChessMove move) {
    setState(() {
      selectedIndex = null;
      _legalMovesFromSelection = [];
    });
    widget.socket.emit('mover_pieza', {
      'salaId': widget.salaId,
      'from': move.from,
      'to': move.to,
      'promotion': move.promotion?.name,
    });
  }

  /// Aplica una jugada al tablero (propia o recibida del rival). El fin de
  /// la partida lo anuncia el servidor aparte, vía "partida_terminada"
  /// (ver [_onPartidaTerminada]), junto con el reparto del pozo si había
  /// apuesta — no se decide localmente.
  void _aplicarMovimiento(ChessMove move) {
    setState(() {
      _engine.makeMove(move);
      selectedIndex = null;
      _legalMovesFromSelection = [];
    });
  }

  void _onPartidaTerminada(dynamic data) {
    if (!mounted) return;
    final datos = Map<String, dynamic>.from(data as Map);
    final resultado = datos['resultado'] as String; // 'jaque_mate' | 'ahogado'
    final ganadorUserId = datos['ganadorUserId'] as String?;
    final saldos = datos['saldos'] == null
        ? null
        : Map<String, dynamic>.from(datos['saldos'] as Map);
    final miNuevoSaldo = saldos?[widget.userId] as num?;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showGameOverDialog(
        resultado: resultado,
        gane: ganadorUserId == widget.userId,
        empate: ganadorUserId == null,
        miNuevoSaldo: miNuevoSaldo?.toDouble(),
      );
    });
  }

  Future<PieceType?> _askPromotion() {
    return showDialog<PieceType>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final color = _engine.turn;
        const options = [
          (PieceType.queen, 'Dama'),
          (PieceType.rook, 'Torre'),
          (PieceType.bishop, 'Alfil'),
          (PieceType.knight, 'Caballo'),
        ];
        return AlertDialog(
          backgroundColor: const Color(0xFF2C2C2C),
          title: const Text('Promoción de peón', style: TextStyle(color: Colors.white)),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: options.map((option) {
              final symbol = ChessPiece(option.$1, color).unicodeSymbol;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(option.$1),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(symbol, style: const TextStyle(fontSize: 22, color: Colors.amber)),
                      const SizedBox(height: 4),
                      Text(option.$2, style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showGameOverDialog({
    required String resultado,
    required bool gane,
    required bool empate,
    double? miNuevoSaldo,
  }) {
    final resultadoTexto = resultado == 'jaque_mate'
        ? (gane ? 'Jaque mate. ¡Ganaste!' : 'Jaque mate. Perdiste.')
        : 'Tablas por ahogado.';

    String? mensajeFinanciero;
    if (widget.costo > 0) {
      if (empate) {
        mensajeFinanciero = 'Se te devolvió tu apuesta de ${widget.costo.toStringAsFixed(2)} SEED.';
      } else if (gane) {
        mensajeFinanciero = 'Ganaste el pozo (se descontó la comisión de la casa).';
      } else {
        mensajeFinanciero = 'Perdiste tu apuesta de ${widget.costo.toStringAsFixed(2)} SEED.';
      }
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text('Partida finalizada', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(resultadoTexto, style: const TextStyle(color: Colors.white70)),
            if (mensajeFinanciero != null) ...[
              const SizedBox(height: 8),
              Text(
                mensajeFinanciero,
                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // cierra el diálogo
              Navigator.of(context).pop(miNuevoSaldo); // vuelve al lobby con el saldo actualizado
            },
            child: const Text('Volver al lobby'),
          ),
        ],
      ),
    );
  }

  String _statusLabel(GameStatus status) {
    final esMiTurno = _engine.turn == widget.miColor;
    final quien = esMiTurno ? 'Tu turno' : 'Turno de tu rival';
    switch (status) {
      case GameStatus.checkmate:
        return 'Jaque mate';
      case GameStatus.stalemate:
        return 'Tablas por ahogado';
      case GameStatus.check:
        return 'Jaque — $quien';
      case GameStatus.playing:
        return quien;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _engine.status;
    final legalTargets = _legalMovesFromSelection.map((m) => m.to).toSet();
    final kingInCheckIndex = (status == GameStatus.check || status == GameStatus.checkmate)
        ? _findKingIndex(_engine.turn)
        : null;

    final miColorLabel = widget.miColor == PieceColor.white ? 'Blancas' : 'Negras';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.oponenteNombre != null
              ? 'vs ${widget.oponenteNombre} · Tú: $miColorLabel'
              : 'Partida en Curso',
        ),
        backgroundColor: const Color(0xFF2C2C2C),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_avisoRival != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    _avisoRival!,
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                  ),
                ),
              Text(
                _statusLabel(status),
                style: const TextStyle(fontSize: 18, color: Colors.amber, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.amber, width: 2),
                ),
                child: GridView.builder(
                  itemCount: 64,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                  ),
                  itemBuilder: (context, displayIndex) {
                    // Para las negras volteamos el tablero 180° (su propia
                    // fila queda abajo), rotando índice de casilla visual a
                    // índice real del tablero: la lógica del juego siempre
                    // trabaja con el índice real (boardIndex).
                    final boardIndex = widget.miColor == PieceColor.black
                        ? 63 - displayIndex
                        : displayIndex;

                    final row = ChessEngine.row(boardIndex);
                    final col = ChessEngine.col(boardIndex);
                    final isDarkSquare = (row + col) % 2 == 1;
                    final isSelected = selectedIndex == boardIndex;
                    final isLegalTarget = legalTargets.contains(boardIndex);
                    final isKingInCheck = kingInCheckIndex == boardIndex;
                    final piece = _engine.pieceAt(boardIndex);

                    Color squareColor = isDarkSquare
                        ? const Color(0xFF769656)
                        : const Color(0xFFEEFEED);
                    if (isKingInCheck) {
                      squareColor = Colors.red.withOpacity(0.7);
                    } else if (isSelected) {
                      squareColor = Colors.blue.withOpacity(0.6);
                    }

                    return GestureDetector(
                      onTap: () => _onSquareTap(boardIndex),
                      child: Container(
                        color: squareColor,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (piece != null)
                              Text(
                                piece.unicodeSymbol,
                                style: TextStyle(
                                  fontSize: 34,
                                  color: piece.color == PieceColor.white ? Colors.white : Colors.black,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 2,
                                      color: piece.color == PieceColor.white
                                          ? Colors.black45
                                          : Colors.white38,
                                    ),
                                  ],
                                ),
                              ),
                            if (isLegalTarget)
                              Container(
                                width: piece == null ? 14 : 36,
                                height: piece == null ? 14 : 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: piece == null ? Colors.black26 : Colors.transparent,
                                  border: piece != null
                                      ? Border.all(color: Colors.black45, width: 3)
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              _buildCapturedRow('Capturadas por blancas', _engine.capturedByWhite),
              _buildCapturedRow('Capturadas por negras', _engine.capturedByBlack),
              const SizedBox(height: 10),
              TextButton.icon(
                icon: const Icon(Icons.exit_to_app),
                label: const Text('Salir de la partida'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int? _findKingIndex(PieceColor color) {
    for (int i = 0; i < 64; i++) {
      final p = _engine.pieceAt(i);
      if (p != null && p.type == PieceType.king && p.color == color) return i;
    }
    return null;
  }

  Widget _buildCapturedRow(String label, List<ChessPiece> pieces) {
    if (pieces.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text(
            pieces.map((p) => p.unicodeSymbol).join(' '),
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
