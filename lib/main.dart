import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
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

/// Dibuja el glifo Unicode de una pieza con relleno + contorno real (no una
/// sombra difusa): dos Text superpuestos, uno solo con trazo (el borde) y
/// otro con relleno encima. Da un contraste mucho más nítido, sobre todo
/// para las negras, que necesitan un borde blanco marcado para no perderse
/// contra las casillas oscuras.
class ChessPieceGlyph extends StatelessWidget {
  final String simbolo;
  final bool esBlanca;
  final double fontSize;

  const ChessPieceGlyph({
    super.key,
    required this.simbolo,
    required this.esBlanca,
    this.fontSize = 34,
  });

  @override
  Widget build(BuildContext context) {
    final colorBorde = esBlanca ? Colors.black87 : Colors.white;
    final anchoBorde = esBlanca ? 1.6 : 3.2;

    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          simbolo,
          style: TextStyle(
            fontSize: fontSize,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = anchoBorde
              ..color = colorBorde,
          ),
        ),
        Text(
          simbolo,
          style: TextStyle(
            fontSize: fontSize,
            color: esBlanca ? Colors.white : Colors.black,
          ),
        ),
      ],
    );
  }
}

/// Color de fondo de toda la app.
const Color appBackgroundColor = Color(0xFF050518);

/// Dorado de marca (el mismo del logo) para acentos, botones y foco.
const Color goldAccent = Color(0xFFE0A957);

/// Caja de los inputs: un poco más oscura que el fondo general.
const Color inputFillColor = Color(0xFF030310);

const double _cornerRadius = 12;

/// Tema de texto: Rubik para texto de párrafo/cuerpo, Young Serif para
/// títulos y encabezados.
TextTheme _buildTextTheme() {
  final base = GoogleFonts.rubikTextTheme(ThemeData.dark().textTheme);
  final serif = GoogleFonts.youngSerifTextTheme(ThemeData.dark().textTheme);
  return base.copyWith(
    displayLarge: serif.displayLarge,
    displayMedium: serif.displayMedium,
    displaySmall: serif.displaySmall,
    headlineLarge: serif.headlineLarge,
    headlineMedium: serif.headlineMedium,
    headlineSmall: serif.headlineSmall,
    titleLarge: serif.titleLarge,
    titleMedium: serif.titleMedium,
  );
}

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
        scaffoldBackgroundColor: appBackgroundColor,
        textTheme: _buildTextTheme(),
        colorScheme: ColorScheme.fromSeed(
          seedColor: goldAccent,
          brightness: Brightness.dark,
        ).copyWith(primary: goldAccent),
        appBarTheme: AppBarTheme(titleTextStyle: GoogleFonts.youngSerif(fontSize: 20, color: Colors.white)),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: inputFillColor,
          labelStyle: const TextStyle(color: Colors.white60),
          floatingLabelStyle: const TextStyle(color: goldAccent),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_cornerRadius),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_cornerRadius),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_cornerRadius),
            borderSide: const BorderSide(color: goldAccent, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: goldAccent,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cornerRadius)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: goldAccent,
            side: const BorderSide(color: goldAccent),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cornerRadius)),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: goldAccent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cornerRadius)),
        ),
      ),
      routes: {
        '/lobby': (context) => const LobbyScreen(),
        // '/game' ya no es una ruta con nombre: GameScreen ahora requiere
        // el socket, la sala y el color asignado, así que se navega con
        // Navigator.push(MaterialPageRoute(...)) desde el lobby.
      },
      home: const SplashScreen(),
      // Flutter Web (CanvasKit) resuelve cada glifo Unicode nuevo de forma
      // perezosa la primera vez que se pinta, y hasta que termina muestra
      // el glifo equivocado (se corrige recién en el próximo repintado).
      // Precalentamos aquí, fuera de la vista, todos los símbolos de
      // piezas para que ya estén listos cuando se abra el tablero.
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          const Positioned(
            left: -1000,
            top: -1000,
            // El tamaño debe coincidir con el de las piezas reales del
            // tablero (34): CanvasKit cachea el glifo rasterizado por
            // combinación de fuente+tamaño, así que precalentar a un
            // tamaño distinto (antes: 1) no evitaba el flash al tamaño real.
            child: Text('♔♕♖♗♘♙♚♛♜♝♞♟', style: TextStyle(fontSize: 34)),
          ),
        ],
      ),
    );
  }
}

// === 0. SPLASH ANIMADO DE INTRO ===
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _iconFade;
  late final Animation<double> _iconScale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

    _iconFade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _iconScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _controller.forward();
    _irALaSiguientePantalla();
  }

  Future<void> _irALaSiguientePantalla() async {
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    final siguiente = supabase.auth.currentSession != null ? const LobbyScreen() : const LoginScreen();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => siguiente));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBackgroundColor,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _iconFade.value,
              child: Transform.scale(
                scale: _iconScale.value,
                child: SvgPicture.asset('assets/images/icon.svg', width: 160),
              ),
            );
          },
        ),
      ),
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

  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    // El login con Google es un flujo OAuth: en Android, el navegador
    // vuelve a esta misma instancia de la app por un enlace (deep link),
    // no por un valor de retorno directo como email/contraseña. Por eso
    // hay que escuchar el cambio de sesión en vez de esperarlo del await.
    _authSub = supabase.auth.onAuthStateChange.listen((estado) {
      if (estado.event == AuthChangeEvent.signedIn && mounted) {
        Navigator.pushReplacementNamed(context, '/lobby');
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesionConGoogle() async {
    setState(() => _cargando = true);
    try {
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        // En web, mandamos explícitamente el origen actual (protocolo+host+
        // puerto) en vez de dejarlo en null: si no coincide con nada, Supabase
        // cae de vuelta al "Site URL" configurado en el dashboard, que puede
        // no coincidir con el puerto real que estemos usando en desarrollo.
        redirectTo: kIsWeb ? Uri.base.origin : 'chessfortune://login-callback',
      );
      // La navegación al lobby ocurre en el listener de onAuthStateChange
      // de arriba, cuando el flujo OAuth termine y vuelva a la app.
    } on AuthException catch (e) {
      _mostrarError(_traducirErrorAuth(e));
    } catch (e) {
      _mostrarError('No se pudo iniciar sesión con Google');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
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
                SvgPicture.asset('assets/images/logo.svg', width: 260),
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
                  onPressed: _cargando ? null : _enviar,
                  child: _cargando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text(
                          _modoRegistro ? 'Crear cuenta' : 'Iniciar sesión',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(child: Divider(color: Colors.white24)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('o', style: TextStyle(color: Colors.white38)),
                    ),
                    Expanded(child: Divider(color: Colors.white24)),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _cargando ? null : _iniciarSesionConGoogle,
                  icon: const Icon(Icons.g_mobiledata, size: 26),
                  label: const Text('Iniciar sesión con Google'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    minimumSize: const Size(double.infinity, 0),
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
            miNombre: _username,
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearPartida,
        icon: const Icon(Icons.add),
        label: const Text('Crear Partida'),
      ),
      bottomNavigationBar: _buildBottomNav(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildPromoBanner(),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Hola, $_username',
                    style: GoogleFonts.youngSerif(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      const Text('Salas disponibles ', style: TextStyle(color: Colors.white60, fontSize: 13)),
                      Text(
                        '${_salasDisponibles.length}',
                        style: const TextStyle(color: goldAccent, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      if (_conectando) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final sala = _salasDisponibles[index];
                          return _buildRoomCard(sala);
                        },
                      ),
              ),
              const SizedBox(height: 76), // deja espacio libre para el FAB flotante
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        SvgPicture.asset('assets/images/logo.svg', width: 130),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: inputFillColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset('assets/images/coin.svg', width: 18, height: 18),
              const SizedBox(width: 6),
              Text(
                saldoSeed.toStringAsFixed(0),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        PopupMenuButton<String>(
          tooltip: 'Cuenta',
          offset: const Offset(0, 45),
          color: const Color(0xFF14142C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cornerRadius)),
          onSelected: (valor) async {
            if (valor == 'salir') {
              await supabase.auth.signOut();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'salir',
              child: Row(
                children: [
                  Icon(Icons.logout, color: Colors.redAccent, size: 18),
                  SizedBox(width: 8),
                  Text('Cerrar sesión', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
          child: const CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white12,
            child: Icon(Icons.person, color: Colors.white70),
          ),
        ),
      ],
    );
  }

  Widget _buildPromoBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: const Color(0xFF1B1B3A),
        child: InkWell(
          onTap: cargandoVideo ? null : simularVideoAd,
          child: SizedBox(
            height: 108,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: -18,
                  bottom: -22,
                  child: Transform.rotate(
                    angle: 0.35,
                    child: SvgPicture.asset('assets/images/coin.svg', width: 66),
                  ),
                ),
                Positioned(
                  left: 26,
                  top: -14,
                  child: Transform.rotate(
                    angle: -0.25,
                    child: SvgPicture.asset('assets/images/coin.svg', width: 60),
                  ),
                ),
                Positioned(
                  left: 46,
                  bottom: 6,
                  child: Transform.rotate(
                    angle: 0.1,
                    child: SvgPicture.asset('assets/images/coin.svg', width: 46),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 118, right: 16, top: 16, bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '¿Te quedaste sin seeds?',
                        style: GoogleFonts.youngSerif(color: goldAccent, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Mira 2 videos cortos para recargar 1.0 Seeds',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      if (cargandoVideo) ...[
                        const SizedBox(height: 8),
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: goldAccent),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: 0,
      backgroundColor: const Color(0xFF0A0A20),
      selectedItemColor: goldAccent,
      unselectedItemColor: Colors.white54,
      type: BottomNavigationBarType.fixed,
      onTap: (indice) {
        if (indice == 0) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Próximamente')),
        );
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Salas'),
        BottomNavigationBarItem(icon: Icon(Icons.emoji_events_outlined), label: 'Tournament'),
        BottomNavigationBarItem(icon: Icon(Icons.flag_outlined), label: 'Configuración'),
      ],
    );
  }

  String _tiempoRelativo(dynamic creadaEnMs) {
    final ms = (creadaEnMs as num?)?.toInt();
    if (ms == null) return '';
    final diferencia = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diferencia.inMinutes < 1) return 'Now';
    if (diferencia.inMinutes < 60) return '${diferencia.inMinutes} min';
    if (diferencia.inHours < 24) return '${diferencia.inHours} h';
    return '${diferencia.inDays} d';
  }

  Widget _buildRoomCard(Map<String, dynamic> sala) {
    final esMiSala = sala['id'] == _miSalaId;
    final costo = (sala['costo'] as num?) ?? 0;
    final creadoPor = sala['creadorNombre'] ?? 'Jugador';

    return Material(
      color: const Color(0xFF12122A),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: esMiSala ? null : () => _unirseAPartida(sala['id'] as String),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white12,
                child: Icon(Icons.person, color: Colors.white54, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(creadoPor, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(
                      sala['nombre'] ?? 'Sala',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (esMiSala)
                IconButton(
                  tooltip: 'Cancelar sala',
                  icon: const Icon(Icons.close, color: Colors.redAccent),
                  onPressed: _cancelarMiSala,
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _tiempoRelativo(sala['creadaEn']),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset('assets/images/coin.svg', width: 14, height: 14),
                        const SizedBox(width: 4),
                        Text(
                          costo > 0 ? costo.toStringAsFixed(costo == costo.roundToDouble() ? 0 : 2) : 'Gratis',
                          style: const TextStyle(color: goldAccent, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
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
  final String miNombre;
  final double costo;
  final String? oponenteNombre;

  const GameScreen({
    super.key,
    required this.socket,
    required this.salaId,
    required this.miColor,
    required this.userId,
    required this.miNombre,
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
  // El motor local no sabe de rendiciones (no son un estado del tablero), así
  // que necesitamos esta bandera aparte para bloquear más jugadas cuando el
  // servidor anuncia el fin de la partida por cualquier motivo.
  bool _partidaTerminada = false;

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
    if (_partidaTerminada ||
        currentStatus == GameStatus.checkmate ||
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

  Future<void> _confirmarRendicion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text('¿Rendirte?', style: TextStyle(color: Colors.white)),
        content: Text(
          widget.costo > 0
              ? 'Perderás la partida y tu apuesta de ${widget.costo.toStringAsFixed(2)} SEED.'
              : 'Perderás la partida.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rendirse'),
          ),
        ],
      ),
    );
    if (confirmar == true) {
      widget.socket.emit('rendirse', {'salaId': widget.salaId});
    }
  }

  void _onPartidaTerminada(dynamic data) {
    if (!mounted) return;
    final datos = Map<String, dynamic>.from(data as Map);
    final resultado = datos['resultado'] as String; // 'jaque_mate' | 'ahogado' | 'rendicion'
    final ganadorUserId = datos['ganadorUserId'] as String?;
    final saldos = datos['saldos'] == null
        ? null
        : Map<String, dynamic>.from(datos['saldos'] as Map);
    final miNuevoSaldo = saldos?[widget.userId] as num?;

    setState(() => _partidaTerminada = true);

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
    final String resultadoTexto;
    switch (resultado) {
      case 'jaque_mate':
        resultadoTexto = gane ? 'Jaque mate. ¡Ganaste!' : 'Jaque mate. Perdiste.';
        break;
      case 'rendicion':
        resultadoTexto = gane ? 'Tu rival se rindió. ¡Ganaste!' : 'Te rendiste.';
        break;
      default:
        resultadoTexto = 'Tablas por ahogado.';
    }

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

    final terminada =
        _partidaTerminada || status == GameStatus.checkmate || status == GameStatus.stalemate;
    final esMiTurno = _engine.turn == widget.miColor;

    return Scaffold(
      bottomNavigationBar: _buildBottomNav(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(child: SvgPicture.asset('assets/images/logo.svg', width: 160)),
                  const SizedBox(width: 48), // balancea el ancho del ícono de volver
                ],
              ),
              const SizedBox(height: 12),
              if (_avisoRival != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    _avisoRival!,
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                  ),
                ),
              _buildPlayerBar(nombre: widget.oponenteNombre ?? 'Rival'),
              const SizedBox(height: 10),
              AspectRatio(
                aspectRatio: 1,
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
                        ? const Color(0xFF16162F)
                        : const Color(0xFF0B0B1F);
                    if (isKingInCheck) {
                      squareColor = Colors.redAccent.withOpacity(0.55);
                    } else if (isSelected) {
                      squareColor = goldAccent.withOpacity(0.4);
                    }

                    return GestureDetector(
                      onTap: () => _onSquareTap(boardIndex),
                      child: Container(
                        color: squareColor,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (piece != null)
                              ChessPieceGlyph(
                                simbolo: piece.unicodeSymbol,
                                esBlanca: piece.color == PieceColor.white,
                                fontSize: 36,
                              ),
                            if (isLegalTarget)
                              Container(
                                width: piece == null ? 14 : 36,
                                height: piece == null ? 14 : 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: piece == null ? Colors.white24 : Colors.transparent,
                                  border: piece != null
                                      ? Border.all(color: Colors.white54, width: 3)
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
              const SizedBox(height: 10),
              _buildPlayerBar(
                nombre: widget.miNombre,
                estado: _statusLabel(status),
                estadoDestacado: esMiTurno || status == GameStatus.check,
              ),
              const SizedBox(height: 12),
              _buildCapturedRow(
                'Capturaste',
                widget.miColor == PieceColor.white ? _engine.capturedByWhite : _engine.capturedByBlack,
              ),
              _buildCapturedRow(
                'Te capturaron',
                widget.miColor == PieceColor.white ? _engine.capturedByBlack : _engine.capturedByWhite,
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: terminada ? null : _confirmarRendicion,
                      child: const Text('Surrender'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Próximamente'))),
                      child: const Text('Table'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Próximamente'))),
                      child: const Text('Report'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerBar({required String nombre, String? estado, bool estadoDestacado = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFF12122A), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white12,
            child: Icon(Icons.person, color: Colors.white54, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          if (estado != null)
            Text(
              estado,
              style: TextStyle(
                color: estadoDestacado ? goldAccent : Colors.white54,
                fontWeight: estadoDestacado ? FontWeight.bold : FontWeight.normal,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: 0,
      backgroundColor: const Color(0xFF0A0A20),
      selectedItemColor: goldAccent,
      unselectedItemColor: Colors.white54,
      type: BottomNavigationBarType.fixed,
      onTap: (indice) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Próximamente')),
      ),
      items: const [
        BottomNavigationBarItem(
          icon: Badge(label: Text('1'), child: Icon(Icons.chat_bubble_outline)),
          label: 'Chat',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
      ],
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
