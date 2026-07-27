import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'chess/chess_engine.dart';

/// URL del backend (Express + Socket.IO) desplegado en Render.
/// El plan gratuito "duerme" tras ~15 min sin tráfico: la primera
/// petición después de eso puede tardar 30-50s en responder.
const String backendBaseUrl = 'https://chessfortuneapp.onrender.com';

void main() {
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
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(),
        '/lobby': (context) => const LobbyScreen(),
        '/game': (context) => const GameScreen(),
      },
    );
  }
}

// === 1. PANTALLA DE INICIO DE SESIÓN ===
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.casino, size: 80, color: Colors.amber),
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
              const SizedBox(height: 48),
              ElevatedButton.icon(
                icon: const Icon(Icons.login, color: Colors.black),
                label: const Text('Iniciar Sesión con Google', style: TextStyle(color: Colors.black)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/lobby');
                },
              ),
            ],
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
  double saldoSeed = 5.0; // Saldo inicial en la app
  bool cargandoVideo = false;

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
        body: jsonEncode({'userId': 'google_123'}), // ID simulado por ahora
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lobby Principal'),
        backgroundColor: const Color(0xFF2C2C2C),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Chip(
              avatar: const Icon(Icons.monetization_on, color: Colors.amber, size: 20),
              label: Text('$saldoSeed SEED', style: const TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.black54,
            ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Salas Disponibles',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildRoomCard(
              context: context,
              title: 'Sala de Práctica',
              subtitle: 'Ideal para calentar y mejorar tu nivel',
              cost: 'Gratis',
              color: Colors.green,
            ),
            const SizedBox(height: 12),
            _buildRoomCard(
              context: context,
              title: 'Sala Competitiva Alpha',
              subtitle: 'El ganador se lleva el pozo de SEED',
              cost: '1.0 SEED',
              color: Colors.amber,
            ),
            const Spacer(),
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

  Widget _buildRoomCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String cost,
    required Color color,
  }) {
    return Card(
      color: const Color(0xFF2C2C2C),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: Text(cost, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        onTap: () {
          Navigator.pushNamed(context, '/game');
        },
      ),
    );
  }
}


// === 3. PANTALLA DEL JUEGO (TABLERO CON REGLAS DE AJEDREZ REALES) ===
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final ChessEngine _engine = ChessEngine();
  int? selectedIndex;
  List<ChessMove> _legalMovesFromSelection = [];

  void _resetGame() {
    setState(() {
      _engine.reset();
      selectedIndex = null;
      _legalMovesFromSelection = [];
    });
  }

  void _onSquareTap(int index) {
    // Partida terminada: no se permiten más jugadas hasta reiniciar.
    final currentStatus = _engine.status;
    if (currentStatus == GameStatus.checkmate ||
        currentStatus == GameStatus.stalemate) {
      return;
    }

    final tappedPiece = _engine.pieceAt(index);

    if (selectedIndex == null) {
      if (tappedPiece != null && tappedPiece.color == _engine.turn) {
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
      if (tappedPiece != null && tappedPiece.color == _engine.turn) {
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

  void _playMove(ChessMove move) {
    setState(() {
      _engine.makeMove(move);
      selectedIndex = null;
      _legalMovesFromSelection = [];
    });

    final newStatus = _engine.status;
    if (newStatus == GameStatus.checkmate || newStatus == GameStatus.stalemate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showGameOverDialog(newStatus));
    }
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
              final symbol = ChessPiece(option.$1, color).symbol;
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

  void _showGameOverDialog(GameStatus finalStatus) {
    final loserColor = _engine.turn; // El jugador sin movimientos.
    final message = finalStatus == GameStatus.checkmate
        ? 'Jaque mate. Ganan las ${loserColor == PieceColor.white ? 'negras' : 'blancas'}.'
        : 'Ahogado (tablas): ${loserColor == PieceColor.white ? 'blancas' : 'negras'} no tienen movimientos legales.';

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: const Text('Partida finalizada', style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _resetGame();
            },
            child: const Text('Nueva partida'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  String _statusLabel(GameStatus status) {
    final turnLabel = _engine.turn == PieceColor.white ? 'Blancas' : 'Negras';
    switch (status) {
      case GameStatus.checkmate:
        return 'Jaque mate';
      case GameStatus.stalemate:
        return 'Tablas por ahogado';
      case GameStatus.check:
        return 'Jaque a $turnLabel — turno de $turnLabel';
      case GameStatus.playing:
        return 'Turno de $turnLabel';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _engine.status;
    final legalTargets = _legalMovesFromSelection.map((m) => m.to).toSet();
    final kingInCheckIndex = (status == GameStatus.check || status == GameStatus.checkmate)
        ? _findKingIndex(_engine.turn)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Partida en Curso'),
        backgroundColor: const Color(0xFF2C2C2C),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
                  itemBuilder: (context, index) {
                    final row = index ~/ 8;
                    final col = index % 8;
                    final isDarkSquare = (row + col) % 2 == 1;
                    final isSelected = selectedIndex == index;
                    final isLegalTarget = legalTargets.contains(index);
                    final isKingInCheck = kingInCheckIndex == index;
                    final piece = _engine.pieceAt(index);

                    Color squareColor = isDarkSquare
                        ? const Color(0xFF769656)
                        : const Color(0xFFEEFEED);
                    if (isKingInCheck) {
                      squareColor = Colors.red.withOpacity(0.7);
                    } else if (isSelected) {
                      squareColor = Colors.blue.withOpacity(0.6);
                    }

                    return GestureDetector(
                      onTap: () => _onSquareTap(index),
                      child: Container(
                        color: squareColor,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (piece != null)
                              Text(
                                piece.symbol,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: piece.color == PieceColor.white ? Colors.white : Colors.black,
                                  shadows: const [Shadow(blurRadius: 2, color: Colors.black45)],
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
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Nueva partida'),
                onPressed: _resetGame,
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
            pieces.map((p) => p.symbol).join(' '),
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
