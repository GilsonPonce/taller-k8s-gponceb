const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const pool = new Pool({
  host: process.env.DB_HOST || 'postgres-service',
  user: process.env.DB_USER || 'admin_user',
  password: process.env.DB_PASSWORD || 'SuperSecretPassword2026!',
  database: process.env.DB_NAME || 'tienda_db',
  port: process.env.DB_PORT || 5432,
});

// Endpoint de Salud para Liveness/Readiness Probes
app.get('/healthz', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.status(200).send('OK');
  } catch (err) {
    res.status(500).send('DB Unreachable');
  }
});

// API CRUD
app.get('/api/productos', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM productos ORDER BY id ASC');
    console.log(JSON.stringify({ level: 'info', action: 'GET_PRODUCTS', count: result.rowCount, timestamp: new Date() }));
    res.json(result.rows);
  } catch (err) {
    console.log(JSON.stringify({ level: 'error', action: 'GET_PRODUCTS_FAILED', error: err.message }));
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/productos', async (req, res) => {
  const { nombre, precio } = req.body;
  try {
    const result = await pool.query(
      'INSERT INTO productos (nombre, precio) VALUES ($1, $2) RETURNING *',
      [nombre, precio]
    );
    console.log(JSON.stringify({ level: 'info', action: 'CREATE_PRODUCT', item: nombre, timestamp: new Date() }));
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.delete('/api/productos/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM productos WHERE id = $1', [req.params.id]);
    console.log(JSON.stringify({ level: 'info', action: 'DELETE_PRODUCT', id: req.params.id, timestamp: new Date() }));
    res.json({ message: 'Producto eliminado' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 5678;
app.listen(PORT, () => console.log(`Backend API escuchando en el puerto ${PORT}`));
