CREATE TABLE IF NOT EXISTS productos (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    precio NUMERIC(10, 2) NOT NULL,
    creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO productos (nombre, precio) VALUES
('Servidor Rack Dell PowerEdge', 4500.00),
('Switch Gestionable Cisco 48p', 1200.00),
('UPS APC 3000VA Enterprise', 890.00);
