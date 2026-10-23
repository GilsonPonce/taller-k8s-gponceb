# 📝 GUÍA DE TALLER PRÁCTICO: KUBERNETES (WINDOWS & DOCKER DESKTOP)

## *Edición Enterprise Extended: Identificación Estudiantil, Isolation por Namespace Personalizado, Manifiestos Comentados, Escalado HPA (Min/Max), Patrones Multicontenedor, Zero-Trust y Matriz Completa de Troubleshooting*

---
### 👤 DATOS DEL ESTUDIANTE
* **Nombre del Alumno:** Gilson Ponce Briones
* **Apellido del Alumno (Namespace de K8s):** `gponceb`
* **Fecha de Entrega:** 23 de octubre de 2026
---

**Asignatura / Curso:** Administración Avanzada de Contenedores y Orquestación con Kubernetes

**Módulos:** 3 a 8 (Workloads, Patterns, Config, Networking Zero-Trust, Storage & Backups, Autoscaling HPA, Production Hardening & Full Diagnostics)

**Entorno de Trabajo:** Windows + Docker Desktop (Kubernetes Habilitado) + PowerShell / CMD

**Arquitectura Target:** NGINX Ingress Controller → Multi-container Pod (Frontend Web + NGINX Static) → Multi-container Pod (InitContainer DB-Check + Backend API REST + Log Adapter Sidecar) → High Availability PostgreSQL StatefulSet → HPA Horizontal Autoscaler → Dedicated Backup PVC

**Duración Estimada:** 6 Horas

---

## ⚙️ Prerrequisitos y Configuración del Entorno en Windows

1. **Docker Desktop:**
   * Tener Docker Desktop ejecutándose en Windows con integración WSL2 o Hyper-V.
   * Ir a `Settings -> Kubernetes` y activar **Enable Kubernetes**.
   * Activar **Metrics Server** o instalarlo si vas a utilizar escalado automático localmente (`kubectl top nodes`).

2. **Terminal:** **PowerShell** ejecutado en modo Administrador.

3. **Verificación de Herramientas:**
   ```powershell
   docker --version
   kubectl cluster-info
   kubectl get nodes
   ```

---

## 📂 Estructura Completa del Proyecto

Crea la carpeta de trabajo `taller-k8s-prod` en tu sistema con la siguiente distribución de archivos manifest e imágenes:

```text
taller-k8s-prod/
├── 00-namespace.yaml
├── app-src/
│   ├── backend/
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   └── server.js
│   ├── frontend/
│   │   ├── Dockerfile
│   │   └── index.html
│   └── db/
│       └── init.sql
├── mod3-workloads/
│   ├── 01-db-secret.yaml
│   ├── 02-db-init-configmap.yaml
│   ├── 03-db-statefulset.yaml
│   ├── 04-backend-configmap.yaml
│   ├── 05-backend-deployment-multicontainer.yaml
│   ├── 06-frontend-deployment-sidecar.yaml
│   ├── 07-fluentd-daemonset.yaml
│   ├── 08-db-migration-job.yaml
│   ├── 09-db-backup-cronjob-pvc.yaml
│   └── 10-hpa-autoscaler.yaml
├── mod4-config/
│   └── 01-production-probes-resources.yaml
├── mod5-networking/
│   ├── 01-db-service.yaml
│   ├── 02-backend-service.yaml
│   ├── 03-frontend-service.yaml
│   ├── 04-ingress-nginx.yaml
│   ├── 05-default-deny-networkpolicy.yaml
│   ├── 06-frontend-networkpolicy.yaml
│   └── 07-backend-networkpolicy.yaml
├── mod6-storage/
│   ├── 01-db-pvc.yaml
│   ├── 02-backup-pvc.yaml
│   └── 03-statefulset-volume-claim-template.yaml
├── mod7-production-hardening/
│   ├── 01-backend-pdb.yaml
│   └── 02-namespace-quota.yaml
└── mod8-troubleshooting/
    ├── 01-error-imagepullbackoff.yaml
    ├── 02-error-crashloopbackoff.yaml
    ├── 03-error-oomkilled.yaml
    ├── 04-error-pvc-pending.yaml
    ├── 05-error-ingress-502-bad-gateway.yaml
    └── 06-error-networkpolicy-blocked.yaml
```

---

## 🏷️ MÓDULO 0: CREACIÓN DEL NAMESPACE PERSONALIZADO

> **REGLA OBLIGATORIA:** Reemplaza `<apellido-alumno>` por tu primer apellido en minúsculas (ejemplo: `manzaba`, `perez`, `gomez`).

### 📄 Archivo: `00-namespace.yaml`
```yaml
apiVersion: v1 # API principal de Kubernetes
kind: Namespace # Recurso para aislamiento lógico dentro del clúster
metadata:
  name: <apellido-alumno> # Reemplazar con el apellido del estudiante
  labels:
    environment: workshop
    student: <apellido-alumno>
```

### 💻 Configuración Inicial en PowerShell:
```powershell
# 1. Crear el Namespace en el clúster
kubectl apply -f 00-namespace.yaml

# 2. Configurar el contexto actual de kubectl para usar tu Namespace por defecto
kubectl config set-context --current --namespace=<apellido-alumno>

# 3. Verificar que el contexto apunta a tu Namespace
kubectl config view --minify | Select-String "namespace:"
```

---

## 🐳 CONSTRUCCIÓN DE IMÁGENES DOCKER (DOCKER BUILDS)

En entornos de producción no inyectamos código vía `ConfigMaps` para runtime principal; creamos imágenes Docker optimizadas e inmutables.

### 📄 Archivo 1: `app-src/backend/package.json`
```json
{
  "name": "k8s-backend-api",
  "version": "1.0.0",
  "description": "API REST Node.js para Kubernetes Workshop",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "express": "^4.18.2",
    "pg": "^8.11.3"
  }
}
```

### 📄 Archivo 2: `app-src/backend/server.js`
```javascript
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
```

### 📄 Archivo 3: `app-src/backend/Dockerfile`
```dockerfile
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY server.js ./
USER node
EXPOSE 5678
CMD ["node", "server.js"]
```

### 📄 Archivo 4: `app-src/frontend/index.html`
```html
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Enterprise CRUD - Kubernetes Cluster</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 40px; background-color: #0f172a; color: #f8fafc; }
        .card { background: #1e293b; padding: 25px; border-radius: 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.3); margin-bottom: 25px; border: 1px solid #334155; }
        h1 { color: #38bdf8; text-align: center; }
        input { padding: 12px; margin-right: 10px; border: 1px solid #475569; border-radius: 6px; background: #0f172a; color: white; }
        button { padding: 12px 20px; background-color: #0284c7; color: white; border: none; border-radius: 6px; cursor: pointer; font-weight: bold; }
        button:hover { background-color: #0369a1; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { padding: 14px; border-bottom: 1px solid #334155; text-align: left; }
        th { background-color: #0f172a; color: #38bdf8; }
        .btn-danger { background-color: #e11d48; }
        .btn-danger:hover { background-color: #be123c; }
    </style>
</head>
<body>
    <h1>🚀 Sistema CRUD Enterprise K8s (Docker Desktop)</h1>
    
    <div class="card">
        <h3>Agregar Producto a Producción</h3>
        <input type="text" id="nombre" placeholder="Nombre del Producto">
        <input type="number" id="precio" placeholder="Precio ($)" step="0.01">
        <button onclick="crearProducto()">Guardar Registro</button>
    </div>

    <div class="card">
        <h3>Inventario en Base de Datos Persistente</h3>
        <table>
            <thead>
                <tr><th>ID</th><th>Nombre</th><th>Precio</th><th>Acciones</th></tr>
            </thead>
            <tbody id="tabla-productos"></tbody>
        </table>
    </div>

    <script>
        const API_URL = '/api/productos';

        async function cargarProductos() {
            try {
                const res = await fetch(API_URL);
                const productos = await res.json();
                const tbody = document.getElementById('tabla-productos');
                tbody.innerHTML = '';
                productos.forEach(p => {
                    tbody.innerHTML += `
                        <tr>
                            <td>${p.id}</td>
                            <td>${p.nombre}</td>
                            <td>$${parseFloat(p.precio).toFixed(2)}</td>
                            <td><button class="btn-danger" onclick="eliminarProducto(${p.id})">Eliminar</button></td>
                        </tr>
                    `;
                });
            } catch (err) {
                console.error('Error cargando datos:', err);
            }
        }

        async function crearProducto() {
            const nombre = document.getElementById('nombre').value;
            const precio = document.getElementById('precio').value;
            if(!nombre || !precio) return alert('Campos obligatorios');

            await fetch(API_URL, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ nombre, precio })
            });

            document.getElementById('nombre').value = '';
            document.getElementById('precio').value = '';
            cargarProductos();
        }

        async function eliminarProducto(id) {
            if(confirm('¿Confirmar eliminación?')) {
                await fetch(`${API_URL}/${id}`, { method: 'DELETE' });
                cargarProductos();
            }
        }

        cargarProductos();
    </script>
</body>
</html>
```

### 📄 Archivo 5: `app-src/frontend/Dockerfile`
```dockerfile
FROM nginx:1.25-alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### 💻 Pasos de Construcción de Imágenes en PowerShell
```powershell
# Navegar a la carpeta contenedora
cd app-src

# Build de la imagen Backend
docker build -t k8s-backend:v1.0 ./backend

# Build de la imagen Frontend
docker build -t k8s-frontend:v1.0 ./frontend

# Verificar que las imágenes están en el Docker Daemon local accesible por Kubernetes
docker images | Select-String "k8s-"
```

---

## 🚀 MÓDULO 3: Workloads Avanzados, Patrones y Autoscaling (HPA)

### 📄 Archivo 1: `mod3-workloads/01-db-secret.yaml`
```yaml
apiVersion: v1 # Versión de la API principal de Kubernetes
kind: Secret # Objeto para almacenar datos sensibles codificados
metadata:
  name: db-secret # Nombre único del recurso
  namespace: <apellido-alumno> # Namespace del estudiante
type: Opaque # Tipo genérico para pares clave-valor arbitrarios
stringData: # Permite definir variables de texto plano; K8s las convierte a base64 internamente
  POSTGRES_DB: "tienda_db" # Nombre de la base de datos PostgreSQL
  POSTGRES_USER: "admin_user" # Usuario administrador de PostgreSQL
  POSTGRES_PASSWORD: "SuperSecretPassword2026!" # Contraseña de acceso a la BD
```

### 📄 Archivo 2: `mod3-workloads/02-db-init-configmap.yaml`
```yaml
apiVersion: v1 # Versión de la API principal
kind: ConfigMap # Objeto para inyectar datos de configuración no sensibles
metadata:
  name: db-init-script # Identificador para montar el script de inicio
  namespace: <apellido-alumno> # Namespace del estudiante
data:
  init.sql: | # Llave de archivo que contiene el DDL inicial
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
```

### 📄 Archivo 3: `mod3-workloads/03-db-statefulset.yaml`
```yaml
apiVersion: apps/v1 # API de controladores de carga de trabajo
kind: StatefulSet # Administrador de estado para pods con almacenamiento persistente único
metadata:
  name: postgres-db # Nombre del StatefulSet
  namespace: <apellido-alumno> # Namespace del estudiante
  labels:
    tier: database # Etiqueta organizacional para agrupación y políticas
spec:
  serviceName: postgres-service # Nombre del Headless/ClusterIP Service asociado
  replicas: 1 # Número inicial fija de pods persistentes
  selector:
    matchLabels:
      app: postgres # Selector de concordancia con las etiquetas del template
  template:
    metadata:
      labels:
        app: postgres # Etiqueta del pod resultante
        tier: database
    spec:
      containers:
      - name: postgres # Nombre del contenedor principal
        image: postgres:15-alpine # Imagen oficial optimizada para PostgreSQL
        envFrom:
        - secretRef:
            name: db-secret # Inyecta las variables de entorno definidas en el Secret
        ports:
        - containerPort: 5432 # Puerto nativo expuesto por PostgreSQL
          name: postgres
        volumeMounts:
        - name: postgres-storage # Punto de montaje del PVC dinámico
          mountPath: /var/lib/postgresql/data # Ruta oficial de almacenamiento en PostgreSQL
        - name: init-script # Montaje del ConfigMap DDL
          mountPath: /docker-entrypoint-initdb.d # Carpeta de auto-ejecución al iniciar la BD
      volumes:
      - name: init-script
        configMap:
          name: db-init-script # Referencia al ConfigMap del script SQL
  volumeClaimTemplates: # Genera un PVC individual por cada pod del StatefulSet
  - metadata:
      name: postgres-storage # Nombre base del volumen solicitado
    spec:
      accessModes: [ "ReadWriteOnce" ] # El volumen solo puede ser montado en lectura/escritura por un solo nodo
      resources:
        requests:
          storage: 2Gi # Tamaño solicitado de disco persistente
```

### 📄 Archivo 4: `mod3-workloads/05-backend-deployment-multicontainer.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment # Controlador para aplicaciones sin estado (Stateless)
metadata:
  name: backend-api
  namespace: <apellido-alumno> # Namespace del estudiante
  labels:
    tier: backend
spec:
  replicas: 2 # Configuración base de 2 instancias paralelas
  selector:
    matchLabels:
      app: backend-api
  template:
    metadata:
      labels:
        app: backend-api
        tier: backend
    spec:
      # PATRÓN INITCONTAINER: Bloquea el inicio del pod hasta validar dependencias
      initContainers:
      - name: check-db-ready # Contenedor de inicialización
        image: busybox:1.36 # Imagen ligera con utilidades de red
        command: ['sh', '-c', 'until nc -z -w 2 postgres-service 5432; do echo "Esperando a la Base de Datos..."; sleep 2; done;'] # Bucle de verificación de socket TCP
      
      containers:
      # CONTENEDOR PRINCIPAL: API REST Node.js
      - name: api
        image: k8s-backend:v1.0 # Imagen construida localmente
        imagePullPolicy: Never # Fuerza a K8s a usar la imagen local del daemon de Docker Desktop
        resources:
          requests: # Recursos mínimos garantizados para el Scheduler
            cpu: "100m" # 0.1 de core CPU
            memory: "128Mi"
          limits: # Techo máximo permitido antes de aplicar límites
            cpu: "500m" # 0.5 de core CPU
            memory: "256Mi"
        env:
        - name: DB_HOST
          value: "postgres-service"
        - name: DB_NAME
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: POSTGRES_DB
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: POSTGRES_USER
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: POSTGRES_PASSWORD
        ports:
        - containerPort: 5678 # Puerto expuesto por la API Express
        volumeMounts:
        - name: shared-logs # Volumen efímero compartido con el Sidecar
          mountPath: /app/logs

      # PATRÓN SIDECAR: Adapter/Collector de logs
      - name: log-adapter-sidecar
        image: busybox:1.36
        command: ["sh", "-c", "touch /app/logs/app.log && tail -f /app/logs/app.log"] # Reenvía registros a stdout
        volumeMounts:
        - name: shared-logs
          mountPath: /app/logs

      volumes:
      - name: shared-logs
        emptyDir: {} # Volumen no persistente que vive y muere con el pod
```

### 📄 Archivo 5: `mod3-workloads/06-frontend-deployment-sidecar.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-web
  namespace: <apellido-alumno> # Namespace del estudiante
  labels:
    tier: frontend
spec:
  replicas: 2 # Configuración base de 2 réplicas
  selector:
    matchLabels:
      app: frontend-web
  template:
    metadata:
      labels:
        app: frontend-web
        tier: frontend
    spec:
      containers:
      - name: web
        image: k8s-frontend:v1.0
        imagePullPolicy: Never # Utiliza la imagen local compilada con Docker Desktop
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "250m"
            memory: "128Mi"
        ports:
        - containerPort: 80 # Puerto de NGINX estático
```

### 📄 Archivo 6: `mod3-workloads/07-fluentd-daemonset.yaml`
```yaml
apiVersion: apps/v1
kind: DaemonSet # Asegura que una copia de este Pod corra en TODOS los nodos del cluster
metadata:
  name: fluentd-logging
  namespace: <apellido-alumno> # Namespace del estudiante
  labels:
    tier: logging
spec:
  selector:
    matchLabels:
      name: fluentd
  template:
    metadata:
      labels:
        name: fluentd
        tier: logging
    spec:
      containers:
      - name: fluentd
        image: fluent/fluentd:v1.14-1 # Agente recolector de logs
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 100m
            memory: 100Mi
```

### 📄 Archivo 7: `mod3-workloads/08-db-migration-job.yaml`
```yaml
apiVersion: batch/v1
kind: Job # Recurso para ejecutar tareas puntuales hasta su finalización exitosa (Exit Code 0)
metadata:
  name: db-migration-job
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  template:
    spec:
      containers:
      - name: migration
        image: postgres:15-alpine
        envFrom:
        - secretRef:
            name: db-secret
        command:
        - sh
        - -c
        - |
          PGPASSWORD=$POSTGRES_PASSWORD psql -h postgres-service -U $POSTGRES_USER -d $POSTGRES_DB -c "INSERT INTO productos (nombre, precio) VALUES ('Audífonos Canceling Sony', 320.00);"
      restartPolicy: Never # No reinicia el contenedor en caso de éxito; lo deja finalizado (Completed)
  backoffLimit: 3 # Reintentos máximos si el comando falla antes de marcar el Job como Failed
```

### 📄 Archivo 8: `mod3-workloads/09-db-backup-cronjob-pvc.yaml`
```yaml
apiVersion: batch/v1
kind: CronJob # Programa la ejecución de Jobs basándose en expresiones Cron
metadata:
  name: db-backup-cronjob
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  schedule: "*/5 * * * *" # Expresión cron: Se ejecuta cada 5 minutos
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:15-alpine
            envFrom:
            - secretRef:
                name: db-secret
            command:
            - sh
            - -c
            - |
              FILENAME="/backups/backup-$(date +%Y%m%d-%H%M%S).sql"
              echo "=== GENERANDO BACKUP EN VOLUMEN PERSISTENTE ==="
              PGPASSWORD=$POSTGRES_PASSWORD pg_dump -h postgres-service -U $POSTGRES_USER $POSTGRES_DB > $FILENAME
              echo "Backup guardado exitosamente en: $FILENAME"
            volumeMounts:
            - name: backup-volume
              mountPath: /backups # Punto de montaje donde escribe el Dump
          restartPolicy: OnFailure
          volumes:
          - name: backup-volume
            persistentVolumeClaim:
              claimName: backup-pvc # Volumen persistente dedicado para almacenamiento de respaldos
```

### 📄 Archivo 9: `mod3-workloads/10-hpa-autoscaler.yaml`
```yaml
apiVersion: autoscaling/v2 # API para autoscaling dinámico basado en métricas
kind: HorizontalPodAutoscaler # Ajusta automáticamente el número de pods de un Deployment
metadata:
  name: backend-hpa
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  scaleTargetRef: # Recurso objetivo a escalar
    apiVersion: apps/v1
    kind: Deployment
    name: backend-api # Apunta al Deployment de la API
  minReplicas: 2 # CONFIGURACIÓN MÍNIMA: Nunca habrá menos de 2 pods corriendo (Alta Disponibilidad)
  maxReplicas: 10 # CONFIGURACIÓN MÁXIMA: Límite superior para proteger los recursos del nodo/cluster
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70 # Dispara el escalado horizontal cuando la CPU promedio supere el 70%
```

---

## ⚙️ MÓDULO 4: Configuration, Probes y Resource Hardening

### 📄 Archivo 1: `mod4-config/01-production-probes-resources.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-api
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend-api
  template:
    metadata:
      labels:
        app: backend-api
        tier: backend
    spec:
      initContainers:
      - name: check-db-ready
        image: busybox:1.36
        command: ['sh', '-c', 'until nc -z -w 2 postgres-service 5432; do echo "Esperando DB..."; sleep 2; done;']
      containers:
      - name: api
        image: k8s-backend:v1.0
        imagePullPolicy: Never
        resources: # Garantías de cómputo necesarias para la recolección de métricas de HPA
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        livenessProbe: # Sonda para comprobar la salud del proceso interno del contenedor
          httpGet:
            path: /healthz # Ruta de verificación HTTP
            port: 5678
          initialDelaySeconds: 15 # Espera inicial para permitir arranque de dependencias
          periodSeconds: 10 # Intervalo de tiempo entre sondeos
          failureThreshold: 3 # Número de fallos consecutivos antes de reiniciar el Pod
        readinessProbe: # Sonda que controla si el Pod recibe tráfico del Service
          httpGet:
            path: /healthz
            port: 5678
          initialDelaySeconds: 5
          periodSeconds: 5
          successThreshold: 1 # Éxitos necesarios para agregar la IP del pod al Endpoint del Service
        env:
        - name: DB_HOST
          value: "postgres-service"
        - name: DB_NAME
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: POSTGRES_DB
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: POSTGRES_USER
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: POSTGRES_PASSWORD
        ports:
        - containerPort: 5678
```

---

## 🌐 MÓDULO 5: Kubernetes Networking y Modelo Zero-Trust

### 📄 Archivo 1: `mod5-networking/01-db-service.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-service # Nombre con el que se resuelve en el DNS interno del cluster (CoreDNS)
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  type: ClusterIP # Tipo por defecto: Solo accesible desde el interior del cluster
  ports:
  - port: 5432 # Puerto en el que escucha el Service
    targetPort: 5432 # Puerto interno del contenedor de la BD
  selector:
    app: postgres # Enruta tráfico a pods con esta etiqueta
```

### 📄 Archivo 2: `mod5-networking/02-backend-service.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  type: ClusterIP # Exposición privada exclusiva para comunicación intra-cluster
  ports:
  - port: 5678
    targetPort: 5678
  selector:
    app: backend-api
```

### 📄 Archivo 3: `mod5-networking/03-frontend-service.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  type: NodePort # Expone el servicio en un puerto estático en la IP de cada nodo
  ports:
  - port: 80 # Puerto interno expuesto a Ingress/Cluster
    targetPort: 80 # Puerto del contenedor NGINX
    nodePort: 30080 # Puerto estático expuesto en el host Windows
  selector:
    app: frontend-web
```

### 📄 Archivo 4: `mod5-networking/04-ingress-nginx.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress # Enrutador Capa 7 (HTTP/HTTPS) basado en reglas
metadata:
  name: app-ingress
  namespace: <apellido-alumno> # Namespace del estudiante
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2 # Reescribe la URL removiendo el prefijo /api al reenviar al backend
spec:
  ingressClassName: nginx # Vincula este Ingress con el controlador Ingress de NGINX
  rules:
  - http:
      paths:
      - path: /api(/|$)(.*) # Coincidencia mediante expresión regular para rutas API
        pathType: ImplementationSpecific
        backend:
          service:
            name: backend-service
            port:
              number: 5678
      - path: /(.*) # Enruta cualquier otra petición hacia la interfaz web
        pathType: ImplementationSpecific
        backend:
          service:
            name: frontend-service
            port:
              number: 80
```

### 📄 Archivo 5: `mod5-networking/05-default-deny-networkpolicy.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy # Regla de firewall L3/L4 para la red interna de Pods
metadata:
  name: default-deny-all
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  podSelector: {} # Un selector vacío selecciona TODOS los pods del Namespace
  policyTypes:
  - Ingress # Bloquea todo el tráfico entrante
  - Egress # Bloquea todo el tráfico saliente
```

### 📄 Archivo 6: `mod5-networking/06-frontend-networkpolicy.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  podSelector:
    matchLabels:
      app: frontend-web # Aplica estas excepciones exclusivamente al Frontend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {} # Autoriza el tráfico desde cualquier origen externo (Ingress Controller)
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: backend-api # Habilita la salida estricta únicamente hacia el Pod del Backend API
    ports:
    - protocol: TCP
      port: 5678
```

### 📄 Archivo 7: `mod5-networking/07-backend-networkpolicy.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  podSelector:
    matchLabels:
      app: backend-api # Aplica estas reglas al Backend API
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend-web # Acepta conexiones entrantes únicamente del Frontend Web
    ports:
    - protocol: TCP
      port: 5678
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: postgres # Permite tráfico de salida exclusivamente hacia PostgreSQL
    ports:
    - protocol: TCP
      port: 5432
  - to: # Permite resolución DNS con el plugin CoreDNS del clúster
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
```

---

## 💾 MÓDULO 6: Persistent Storage & Automated Backups

### 📄 Archivo 1: `mod6-storage/01-db-pvc.yaml`
```yaml
apiVersion: v1
kind: PersistentVolumeClaim # Solicitud de volumen de almacenamiento administrado dinámicamente
metadata:
  name: postgres-pvc
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  accessModes:
    - ReadWriteOnce # El volumen se monta como lectura/escritura por un solo nodo
  resources:
    requests:
      storage: 2Gi # Espacio reservado
```

### 📄 Archivo 2: `mod6-storage/02-backup-pvc.yaml`
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-pvc
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  accessModes:
    - ReadWriteMany # Permite lectura/escritura simultánea por múltiples pods
  resources:
    requests:
      storage: 5Gi # Espacio dedicado exclusivamente para volúmenes de respaldo
```

---

## 🛡️ MÓDULO 7: Hardening, Limits & PodDisruptionBudgets

### 📄 Archivo 1: `mod7-production-hardening/01-backend-pdb.yaml`
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget # Protege la disponibilidad asegurando réplicas mínimas durante mantenimientos
metadata:
  name: backend-pdb
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  minAvailable: 1 # Durante evicciones o drenado de nodos, garantiza que al menos 1 pod siga disponible
  selector:
    matchLabels:
      app: backend-api
```

### 📄 Archivo 2: `mod7-production-hardening/02-namespace-quota.yaml`
```yaml
apiVersion: v1
kind: ResourceQuota # Establece restricciones máximas agregadas de recursos para todo el Namespace
metadata:
  name: compute-quota
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  hard:
    requests.cpu: "2" # Suma máxima de CPU asignable a la suma de todos los pods
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    pods: "20" # Límite máximo global de pods dentro del namespace
```

---

## 🛠️ MÓDULO 8: Matriz de Troubleshooting Completa por Componente

### 📄 Archivo 1: `mod8-troubleshooting/01-error-imagepullbackoff.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: error-image-pull
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  replicas: 1
  selector:
    matchLabels:
      app: image-fail
  template:
    metadata:
      labels:
        app: image-fail
    spec:
      containers:
      - name: web
        image: registro-inexistente.com/app-ficticia:v999 # Error introducido intencionalmente
```

#### Comandos de Diagnóstico y Solución:
```powershell
# 1. Verificar el estado del Pod dentro de tu Namespace
kubectl get pods -l app=image-fail -n <apellido-alumno>

# 2. Obtener los eventos del Pod para diagnosticar el fallo de descarga
kubectl describe pod -l app=image-fail -n <apellido-alumno>

# Solución: Corregir el nombre de la imagen
kubectl set image deployment/error-image-pull web=nginx:alpine -n <apellido-alumno>
```

### 📄 Archivo 2: `mod8-troubleshooting/02-error-crashloopbackoff.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: error-crash-loop
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  replicas: 1
  selector:
    matchLabels:
      app: crash-fail
  template:
    metadata:
      labels:
        app: crash-fail
    spec:
      containers:
      - name: api
        image: node:18-alpine
        command: ["node", "-e", "throw new Error('FATAL: Variable de entorno DB_HOST no configurada');"]
```

#### Comandos de Diagnóstico y Solución:
```powershell
# 1. Inspeccionar los reinicios del Pod
kubectl get pods -l app=crash-fail -n <apellido-alumno>

# 2. Leer los logs del proceso fallido
kubectl logs -l app=crash-fail -n <apellido-alumno> --previous
```

### 📄 Archivo 3: `mod8-troubleshooting/03-error-oomkilled.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: error-oom-killed
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  replicas: 1
  selector:
    matchLabels:
      app: oom-fail
  template:
    metadata:
      labels:
        app: oom-fail
    spec:
      containers:
      - name: memory-eater
        image: polinux/stress
        resources:
          limits:
            memory: "20Mi" # Límite severamente restrictivo
        command: ["stress", "--vm", "1", "--vm-bytes", "50M"] # Intenta consumir 50MB
```

#### Comandos de Diagnóstico y Solución:
```powershell
# 1. Confirmar la causa del término a través de describe
kubectl describe pod -l app=oom-fail -n <apellido-alumno> | Select-String "OOMKilled"
```

### 📄 Archivo 4: `mod8-troubleshooting/04-error-pvc-pending.yaml`
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: error-pvc-pending
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  storageClassName: storage-class-inexistente # Error introducido intencionalmente
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Gi
```

#### Comandos de Diagnóstico y Solución:
```powershell
# 1. Comprobar que el PVC se queda en estado Pending
kubectl get pvc error-pvc-pending -n <apellido-alumno>

# 2. Inspeccionar el evento del aprovisionador de almacenamiento
kubectl describe pvc error-pvc-pending -n <apellido-alumno>
```

### 📄 Archivo 5: `mod8-troubleshooting/05-error-ingress-502-bad-gateway.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: error-ingress-bad-gateway
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /broken-route
        pathType: Prefix
        backend:
          service:
            name: backend-service
            port:
              number: 9999 # Puerto incorrecto: El servicio escucha en el 5678
```

#### Comandos de Diagnóstico y Solución:
```powershell
# 1. Probar el endpoint vía curl
curl http://localhost/broken-route

# 2. Inspeccionar los endpoints asociados al servicio
kubectl get endpoints backend-service -n <apellido-alumno>
```

### 📄 Archivo 6: `mod8-troubleshooting/06-error-networkpolicy-blocked.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: error-block-dns
  namespace: <apellido-alumno> # Namespace del estudiante
spec:
  podSelector:
    matchLabels:
      app: backend-api
  policyTypes:
  - Egress
  egress: [] # Bloquea TODO el tráfico saliente sin excepciones (incluyendo DNS)
```

#### Comandos de Diagnóstico y Solución:
```powershell
# 1. Probar resolución DNS desde el Pod afectado
kubectl exec -it deployment/backend-api -c api -n <apellido-alumno> -- nslookup postgres-service
```

---

## 🚀 GUÍA DE EJECUCIÓN Y VERIFICACIÓN PASO A PASO

### Paso 1: Configurar Namespace del Alumno
```powershell
kubectl apply -f 00-namespace.yaml
kubectl config set-context --current --namespace=<apellido-alumno>
```

### Paso 2: Aplicar Almacenamiento y Secretos Iniciales
```powershell
kubectl apply -f mod6-storage/01-db-pvc.yaml
kubectl apply -f mod6-storage/02-backup-pvc.yaml
kubectl apply -f mod3-workloads/01-db-secret.yaml
kubectl apply -f mod3-workloads/02-db-init-configmap.yaml
```

### Paso 3: Desplegar Base de Datos y Verificar Estado
```powershell
kubectl apply -f mod3-workloads/03-db-statefulset.yaml
kubectl apply -f mod5-networking/01-db-service.yaml

# Esperar a que PostgreSQL esté en estado Running
kubectl get pods -l app=postgres -w
```

### Paso 4: Aplicar Workloads Multicontenedor y Servicios
```powershell
kubectl apply -f mod3-workloads/05-backend-deployment-multicontainer.yaml
kubectl apply -f mod3-workloads/06-frontend-deployment-sidecar.yaml
kubectl apply -f mod5-networking/02-backend-service.yaml
kubectl apply -f mod5-networking/03-frontend-service.yaml
```

### Paso 5: Desplegar Autoscaling HPA
```powershell
kubectl apply -f mod3-workloads/10-hpa-autoscaler.yaml
kubectl get hpa
```

### Paso 6: Instalar Ingress Controller y Reglas Capa 7
```powershell
# Instalación del Ingress Controller oficial para Docker Desktop (Global)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

# Aplicar las reglas Ingress en el Namespace del alumno
kubectl apply -f mod5-networking/04-ingress-nginx.yaml
```

### Paso 7: Probar la Aplicación en el Navegador
1. Abre tu navegador e ingresa a: **`http://localhost`**
2. Interactúa con la interfaz CRUD: agrega, visualiza y elimina registros.

### Paso 8: Ejecutar Tareas Programadas y Verificar Respaldos Persistentes
```powershell
kubectl apply -f mod3-workloads/08-db-migration-job.yaml
kubectl apply -f mod3-workloads/09-db-backup-cronjob-pvc.yaml

# Confirmar la generación de respaldos en el PVC del alumno
kubectl get cronjob
kubectl run inspect-backup --image=busybox:1.36 --rm -it --restart=Never -n <apellido-alumno> -v backup-pvc:/backups -- ls -l /backups
```

### Paso 9: Aplicar Seguridad Zero-Trust
```powershell
kubectl apply -f mod5-networking/05-default-deny-networkpolicy.yaml
kubectl apply -f mod5-networking/06-frontend-networkpolicy.yaml
kubectl apply -f mod5-networking/07-backend-networkpolicy.yaml

# Probar aislamiento: Intentar conexión desde un Pod no autorizado (debe retornar Timeout)
kubectl run test-unauthorized --image=curlimages/curl --rm -it --restart=Never -n <apellido-alumno> -- curl -s --connect-timeout 3 http://backend-service:5678/api/productos
```

### Paso 10: Ejecutar Escenarios de Diagnóstico de Errores
```powershell
kubectl apply -f mod8-troubleshooting/01-error-imagepullbackoff.yaml
kubectl apply -f mod8-troubleshooting/02-error-crashloopbackoff.yaml
kubectl apply -f mod8-troubleshooting/03-error-oomkilled.yaml
kubectl apply -f mod8-troubleshooting/04-error-pvc-pending.yaml

kubectl get pods -w
```

---

## 📋 Lista de Entregables del Estudiante

Cada estudiante deberá entregar un repositorio en GitHub o carpeta comprimida (`.zip`) con el nombre `taller-k8s-<apellido-alumno>` conteniendo:

1. **Datos de Identificación Completos:** Llenar los datos del encabezado de la guía.
2. **Manifiestos YAML:** Todos los archivos de las carpetas con la propiedad `namespace: <apellido-alumno>` configurada correctamente.
3. **Reporte Técnico de Evidencias (PDF):**
   * Captura del comando `kubectl get all -n <apellido-alumno>` donde se observen los pods, servicios, HPA y statefulset ejecutándose correctamente.
   * Captura de pantalla de la interfaz funcional web interactuando con el backend en `http://localhost`.
   * Evidencia de la ejecución del CronJob y el listado de archivos dentro del volumen de backup (`backup-pvc`).
   * Resolución anotada de al menos 3 diagnósticos de error ejecutados del Módulo 8 (`kubectl describe` / `kubectl logs`).