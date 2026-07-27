require('dotenv').config();

// Node 18 no trae WebSocket nativo, y el cliente de Supabase lo requiere
// para su módulo de Realtime (aunque no lo usemos aquí). Node 22+ no
// necesitaría esto; mientras tanto usamos el paquete `ws` como polyfill.
if (typeof globalThis.WebSocket === 'undefined') {
    globalThis.WebSocket = require('ws');
}

const express = require('express');
const http = require('http');
const { randomUUID } = require('crypto');
const { Server } = require('socket.io');
const cors = require('cors');
const { createClient } = require('@supabase/supabase-js');
const { ChessEngine, PieceColor } = require('./chessEngine');

const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY } = process.env;
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error(
        'Faltan SUPABASE_URL y/o SUPABASE_SERVICE_ROLE_KEY. Copia backend/.env.example a backend/.env y completa los valores.'
    );
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const app = express();
app.use(cors());
app.use(express.json());

const server = http.createServer(app);
const io = new Server(server, {
    cors: {
        origin: "*", // Permite conexiones desde tu app de Flutter Web o celular
        methods: ["GET", "POST"]
    }
});

// Porcentaje que se queda la app de cada pozo cuando una partida con apuesta
// termina en jaque mate. En empate (ahogado) no se cobra comisión: se le
// devuelve su apuesta a cada jugador tal cual.
const RAKE_PORCENTAJE = 0.10;

async function obtenerOCrearUsuario(userId) {
    const { data: existente, error: errorLectura } = await supabase
        .from('users')
        .select('*')
        .eq('id', userId)
        .maybeSingle();

    if (errorLectura) throw errorLectura;
    if (existente) return existente;

    const { data: nuevo, error: errorInsercion } = await supabase
        .from('users')
        .insert({ id: userId, username: 'UsuarioNuevo', seed_gratis: 0, seed_real: 0 })
        .select()
        .single();

    if (errorInsercion) throw errorInsercion;
    return nuevo;
}

// Suma (delta positivo) o resta (delta negativo) SEED de forma atómica.
// Lanza si el usuario no existe o si restar dejaría el saldo en negativo.
async function ajustarSaldo(userId, delta) {
    const { data, error } = await supabase.rpc('increment_seed', {
        p_user_id: userId,
        p_delta: delta,
    });
    if (error) throw error;
    return Number(data);
}

// === ENDPOINT: Simulación de recompensa por ver un video ===
app.post('/api/reward-ad', async (req, res) => {
    const { userId } = req.body;
    if (!userId) {
        return res.status(400).json({ success: false, message: 'Falta userId' });
    }

    try {
        await obtenerOCrearUsuario(userId);
        const nuevoSaldo = await ajustarSaldo(userId, 0.5);

        console.log(`[Anuncio] Usuario ${userId} vio un video. Nuevo saldo: ${nuevoSaldo} SEED`);

        return res.json({
            success: true,
            nuevo_saldo: nuevoSaldo,
            message: "0.5 SEED acreditados correctamente."
        });
    } catch (error) {
        console.error('[Anuncio] Error:', error.message);
        return res.status(500).json({ success: false, message: 'Error al acreditar SEED' });
    }
});

// === ENDPOINT: Consultar saldo actual ===
app.get('/api/saldo/:userId', async (req, res) => {
    try {
        const usuario = await obtenerOCrearUsuario(req.params.userId);
        return res.json({
            success: true,
            seed_gratis: Number(usuario.seed_gratis),
            seed_real: Number(usuario.seed_real),
        });
    } catch (error) {
        console.error('[Saldo] Error:', error.message);
        return res.status(500).json({ success: false, message: 'Error al consultar saldo' });
    }
});

// === SOCKET.IO: Lobby de salas en tiempo real ===
// Estado en memoria (se reinicia si el servidor se reinicia/duerme).
// sala: { id, nombre, costo, creadorId, estado: 'esperando'|'en_curso', jugadores: [{ userId, username, socketId }] }
const salas = new Map();

// Autoridad de cada partida en curso: salaId -> ChessEngine.
// jugadores[0] siempre juega con blancas, jugadores[1] con negras
// (mismo criterio que usa el cliente al recibir "partida_iniciada").
const partidas = new Map();

function listaSalasPublicas() {
    return Array.from(salas.values())
        .filter((sala) => sala.estado === 'esperando')
        .map((sala) => ({
            id: sala.id,
            nombre: sala.nombre,
            costo: sala.costo,
            creadorId: sala.creadorId,
            creadorNombre: sala.jugadores[0]?.username ?? 'Jugador',
        }));
}

function difundirSalas() {
    io.emit('salas_actualizadas', listaSalasPublicas());
}

// Liquida una partida terminada: si tenía apuesta, le paga al ganador el
// pozo menos la comisión de la casa (jaque mate) o devuelve la apuesta a
// cada quien sin comisión (ahogado/tablas). Sin apuesta, solo se avisa el
// resultado. jugadores[0] siempre es blancas, jugadores[1] siempre negras.
async function finalizarPartida(sala, partida, estado) {
    const [blancas, negras] = sala.jugadores;
    let ganadorUserId = null;
    let saldos = null;

    if (estado === 'checkmate') {
        // partida.turn quedó en el color que no pudo mover: ese perdió.
        const ganador = partida.turn === PieceColor.WHITE ? negras : blancas;
        ganadorUserId = ganador.userId;
    }

    if (sala.costo > 0) {
        try {
            if (estado === 'checkmate') {
                const pozo = sala.costo * 2;
                const pago = Math.round(pozo * (1 - RAKE_PORCENTAJE) * 100) / 100;
                const nuevoSaldo = await ajustarSaldo(ganadorUserId, pago);
                saldos = { [ganadorUserId]: nuevoSaldo };
            } else {
                const nuevoSaldoBlancas = await ajustarSaldo(blancas.userId, sala.costo);
                const nuevoSaldoNegras = await ajustarSaldo(negras.userId, sala.costo);
                saldos = { [blancas.userId]: nuevoSaldoBlancas, [negras.userId]: nuevoSaldoNegras };
            }
        } catch (error) {
            console.error('[Partida] Error al liquidar el pozo:', error.message);
        }
    }

    sala.estado = 'finalizada';
    partidas.delete(sala.id);

    io.to(sala.id).emit('partida_terminada', {
        resultado: estado === 'checkmate' ? 'jaque_mate' : 'ahogado',
        ganadorUserId,
        costo: sala.costo,
        saldos,
    });

    console.log(`[Partida] Sala "${sala.nombre}" terminó (${estado})`);
}

io.on('connection', (socket) => {
    console.log(`Usuario conectado al servidor: ${socket.id}`);

    // Le mandamos el estado actual del lobby solo a quien se acaba de conectar.
    socket.emit('salas_actualizadas', listaSalasPublicas());

    socket.on('crear_sala', (datos) => {
        const { userId, username, nombre, costo } = datos || {};
        if (!userId || !nombre) {
            socket.emit('error_sala', { message: 'Faltan datos para crear la sala' });
            return;
        }

        const sala = {
            id: randomUUID(),
            nombre: String(nombre).slice(0, 40),
            costo: Number(costo) || 0,
            creadorId: userId,
            estado: 'esperando',
            jugadores: [{ userId, username: username || 'Jugador', socketId: socket.id }],
        };
        salas.set(sala.id, sala);
        socket.join(sala.id);

        console.log(`[Lobby] ${username} creó la sala "${sala.nombre}" (${sala.id})`);
        socket.emit('sala_creada', { salaId: sala.id });
        difundirSalas();

        if (sala.costo > 0) obtenerOCrearUsuario(userId).catch(() => {});
    });

    socket.on('unirse_sala', async (datos) => {
        const { salaId, userId, username } = datos || {};
        const sala = salas.get(salaId);

        if (!sala || sala.estado !== 'esperando') {
            socket.emit('error_sala', { message: 'Esa sala ya no está disponible' });
            return;
        }
        if (sala.jugadores.some((j) => j.userId === userId)) {
            socket.emit('error_sala', { message: 'Ya estás en esa sala' });
            return;
        }

        if (sala.costo > 0) {
            try {
                await obtenerOCrearUsuario(userId);
            } catch (error) {
                socket.emit('error_sala', { message: 'No se pudo verificar tu cuenta' });
                return;
            }
        }

        sala.jugadores.push({ userId, username: username || 'Jugador', socketId: socket.id });
        socket.join(sala.id);

        if (sala.jugadores.length >= 2) {
            if (sala.costo > 0) {
                const [creador, retador] = sala.jugadores;
                try {
                    await ajustarSaldo(creador.userId, -sala.costo);
                } catch (error) {
                    sala.jugadores = sala.jugadores.filter((j) => j.userId !== userId);
                    const mensaje = { message: 'El creador de la sala ya no tiene saldo suficiente' };
                    io.to(creador.socketId).emit('error_sala', mensaje);
                    socket.emit('error_sala', mensaje);
                    difundirSalas();
                    return;
                }
                try {
                    await ajustarSaldo(retador.userId, -sala.costo);
                } catch (error) {
                    await ajustarSaldo(creador.userId, sala.costo); // devolver lo cobrado
                    sala.jugadores = sala.jugadores.filter((j) => j.userId !== userId);
                    socket.emit('error_sala', { message: 'No tienes saldo suficiente para esta sala' });
                    difundirSalas();
                    return;
                }
            }

            sala.estado = 'en_curso';
            partidas.set(sala.id, new ChessEngine());
            io.to(sala.id).emit('partida_iniciada', {
                salaId: sala.id,
                costo: sala.costo,
                jugadores: sala.jugadores.map((j) => ({ userId: j.userId, username: j.username })),
            });
            console.log(`[Lobby] Sala "${sala.nombre}" completa, partida iniciada`);
        }

        difundirSalas();
    });

    socket.on('cancelar_sala', (datos) => {
        const { salaId, userId } = datos || {};
        const sala = salas.get(salaId);
        if (sala && sala.creadorId === userId && sala.estado === 'esperando') {
            salas.delete(salaId);
            console.log(`[Lobby] Sala "${sala.nombre}" cancelada por su creador`);
            difundirSalas();
        }
    });

    // El servidor es la autoridad de la partida: valida la jugada contra su
    // propio motor antes de aplicarla. Si es legal, la difunde a AMBOS
    // jugadores (incluido quien la envió); si no, solo avisa al remitente y
    // el tablero de nadie cambia (evita que un cliente modificado haga trampa
    // y evita desincronizar a los dos jugadores).
    socket.on('mover_pieza', async (datos) => {
        const { salaId, from, to, promotion } = datos || {};
        if (!salaId || from === undefined || to === undefined) return;

        const sala = salas.get(salaId);
        const partida = partidas.get(salaId);
        if (!sala || !partida || sala.estado !== 'en_curso') return;

        const jugador = sala.jugadores.find((j) => j.socketId === socket.id);
        if (!jugador) return;

        const miColor = sala.jugadores.indexOf(jugador) === 0 ? PieceColor.WHITE : PieceColor.BLACK;
        if (partida.turn !== miColor) {
            socket.emit('movimiento_rechazado', { message: 'No es tu turno' });
            return;
        }

        const promocionSolicitada = promotion || null;
        const movimiento = partida
            .legalMovesFrom(from)
            .find((m) => m.to === to && (m.promotion || null) === promocionSolicitada);

        if (!movimiento) {
            socket.emit('movimiento_rechazado', { message: 'Jugada ilegal' });
            return;
        }

        partida.makeMove(movimiento);
        io.to(salaId).emit('pieza_movida', { from, to, promotion: promocionSolicitada });

        const estadoPartida = partida.status;
        if (estadoPartida === 'checkmate' || estadoPartida === 'stalemate') {
            await finalizarPartida(sala, partida, estadoPartida);
        }
    });

    socket.on('disconnect', () => {
        console.log(`Usuario desconectado: ${socket.id}`);
        let huboCambios = false;
        for (const [salaId, sala] of salas.entries()) {
            if (sala.estado === 'en_curso') {
                const seguiaAqui = sala.jugadores.some((j) => j.socketId === socket.id);
                if (seguiaAqui) {
                    socket.to(salaId).emit('rival_desconectado');
                }
                continue;
            }
            if (sala.estado !== 'esperando') continue;
            const seguiaAqui = sala.jugadores.some((j) => j.socketId === socket.id);
            if (seguiaAqui) {
                salas.delete(salaId);
                huboCambios = true;
            }
        }
        if (huboCambios) difundirSalas();
    });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`🚀 Servidor de ajedrez corriendo localmente en http://localhost:${PORT}`);
});
