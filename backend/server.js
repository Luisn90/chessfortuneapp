require('dotenv').config();

const express = require('express');
const http = require('http');
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

// === SOCKET.IO: Gestión de partidas de Ajedrez en Tiempo Real ===
io.on('connection', (socket) => {
    console.log(`Usuario conectado al servidor: ${socket.id}`);

    // Cuando un jugador busca partida
    socket.on('buscar_partida', (datos) => {
        console.log(`Usuario ${datos.userId} buscando rival en sala: ${datos.sala}`);
        // Aquí la IA programará el emparejamiento automático (Matchmaking)
        socket.join(datos.sala);
        socket.emit('estado_busqueda', { status: "Buscando oponente..." });
    });

    socket.on('disconnect', () => {
        console.log(`Usuario desconectado: ${socket.id}`);
    });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`🚀 Servidor de ajedrez corriendo localmente en http://localhost:${PORT}`);
});
