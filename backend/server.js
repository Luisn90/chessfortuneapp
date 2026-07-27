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

// === ENDPOINT: Simulación de recompensa por ver un video ===
app.post('/api/reward-ad', async (req, res) => {
    const { userId } = req.body;
    if (!userId) {
        return res.status(400).json({ success: false, message: 'Falta userId' });
    }

    try {
        const usuario = await obtenerOCrearUsuario(userId);
        const nuevoSaldo = Number(usuario.seed_gratis) + 0.5;

        const { data: actualizado, error } = await supabase
            .from('users')
            .update({ seed_gratis: nuevoSaldo })
            .eq('id', userId)
            .select()
            .single();

        if (error) throw error;

        console.log(`[Anuncio] Usuario ${userId} vio un video. Nuevo saldo: ${actualizado.seed_gratis} SEED`);

        return res.json({
            success: true,
            nuevo_saldo: Number(actualizado.seed_gratis),
            message: "0.5 SEED acreditados correctamente."
        });
    } catch (error) {
        console.error('[Anuncio] Error:', error.message);
        return res.status(500).json({ success: false, message: 'Error al acreditar SEED' });
    }
});

// === SOCKET.IO: Lobby de salas en tiempo real ===
// Estado en memoria (se reinicia si el servidor se reinicia/duerme).
// sala: { id, nombre, costo, creadorId, estado: 'esperando'|'en_curso', jugadores: [{ userId, username, socketId }] }
const salas = new Map();

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
    });

    socket.on('unirse_sala', (datos) => {
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

        sala.jugadores.push({ userId, username: username || 'Jugador', socketId: socket.id });
        socket.join(sala.id);

        if (sala.jugadores.length >= 2) {
            sala.estado = 'en_curso';
            io.to(sala.id).emit('partida_iniciada', {
                salaId: sala.id,
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

    socket.on('disconnect', () => {
        console.log(`Usuario desconectado: ${socket.id}`);
        let huboCambios = false;
        for (const [salaId, sala] of salas.entries()) {
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
