# taller-k8s-gponceb

Entrega del **Taller Práctico de Kubernetes — Edición Enterprise Extended** (Módulos 3 a 8).

| | |
|---|---|
| **Alumno** | Gilson Ponce Briones |
| **Namespace de K8s** | `gponceb` |
| **Fecha de entrega** | 23 de octubre de 2026 |
| **Asignatura** | Administración Avanzada de Contenedores y Orquestación con Kubernetes |

📄 **Reporte técnico de evidencias:** [`REPORTE-TECNICO-gponceb.pdf`](REPORTE-TECNICO-gponceb.pdf)
📘 **Guía del taller (con encabezado completo):** [`GUIA-TALLER.md`](GUIA-TALLER.md)

## Arquitectura

```
                 http://localhost
                        │
              ┌─────────▼──────────┐
              │ Ingress NGINX       │  /api ─────────────┐
              │ (ns ingress-nginx)  │  /    ──┐          │
              └─────────────────────┘         │          │
                                   ┌──────────▼───┐  ┌───▼──────────────────────────────┐
                                   │ frontend-web │  │ backend-api  (HPA 2–10, PDB)      │
                                   │ NGINX x2     │  │ init: check-db-ready              │
                                   └──────────────┘  │ api (Node.js) + log-adapter-sidecar│
                                                     └───┬──────────────────────────────┘
                     db-migration-job ─┐                 │ 5432
                     db-backup-cronjob ┼─────────► ┌─────▼────────────┐
                     (role=db-client)  │           │ postgres-db-0     │──► PVC postgres-storage (2Gi)
                            │                      │ StatefulSet       │
                            └──► backup-pvc (5Gi)  └───────────────────┘
          Zero-Trust: default-deny + allow-frontend / allow-backend / allow-database / allow-db-clients
          fluentd-logging (DaemonSet) · ResourceQuota + LimitRange
```

## Estructura

```
taller-k8s-gponceb/
├── 00-namespace.yaml
├── app-src/                    # Código y Dockerfiles (backend Node.js, frontend NGINX, init.sql)
├── mod3-workloads/             # Secret, ConfigMaps, StatefulSet, Deployments, DaemonSet, Job, CronJob, HPA
├── mod4-config/                # backend-api con liveness/readiness probes
├── mod5-networking/            # Services, Ingress y NetworkPolicies Zero-Trust
├── mod6-storage/               # PVCs
├── mod7-production-hardening/  # PDB, ResourceQuota, LimitRange
├── mod8-troubleshooting/       # 6 escenarios de error intencionales
├── cluster-setup/              # Instalación de Calico, local-path, metrics-server, ingress-nginx
├── scripts/                    # build de imágenes, despliegue, prueba de carga, inspección de backups
├── evidencias/                 # Salida real de cada paso (.txt), capturas de terminal y de la web (.png)
└── REPORTE-TECNICO-gponceb.pdf
```

## Cómo reproducirlo

El taller se ejecutó en un clúster **kubeadm de un nodo** (Kubernetes v1.37.1, containerd), no en Docker Desktop.

```bash
# 1. Complementos del clúster (Calico, StorageClass, metrics-server, Ingress Controller)
bash cluster-setup/install-addons.sh

# 2. Imágenes: docker build + importación en containerd
sudo bash scripts/build-images.sh

# 3. Despliegue completo (pasos 1–9 de la guía)
bash scripts/deploy.sh

# 4. Verificación
open http://localhost                       # interfaz CRUD
node scripts/load-test.js 240 64            # carga para el HPA  (kubectl get hpa -w)
bash scripts/inspect-backups.sh             # respaldos dentro de backup-pvc

# 5. Escenarios de troubleshooting (paso 10)
kubectl apply -f mod8-troubleshooting/
```

En **Docker Desktop** se omite el paso 1 (basta con instalar ingress-nginx y metrics-server) y en el paso 2 alcanza con `docker build`.

## Correcciones respecto a la guía

Cada cambio está comentado en el YAML correspondiente. El detalle está en la sección 2 del reporte.

| Archivo | Cambio | Motivo |
|---|---|---|
| `mod5-networking/04-ingress-nginx.yaml` | Sin `rewrite-target`, paths `Prefix` | El rewrite quitaba `/api` y el backend respondía 404 |
| `app-src/backend/package-lock.json` | Agregado | `npm ci` falla sin lockfile |
| `mod5-networking/07-backend-networkpolicy.yaml` | Permite el namespace `ingress-nginx` y DNS TCP | Con default-deny el Ingress no llegaba al backend |
| `mod5-networking/08-database-networkpolicy.yaml` | **Nuevo** | PostgreSQL rechazaba todo el tráfico; los Jobs no tenían salida |
| `mod5-networking/06-frontend-networkpolicy.yaml` | Permite DNS | default-deny bloquea CoreDNS |
| `mod6-storage/02-backup-pvc.yaml` | `ReadWriteOnce` | local-path/hostpath no soportan RWX |
| `mod7-production-hardening/03-limitrange.yaml` | **Nuevo** | La ResourceQuota rechaza pods sin requests/limits |
| `mod4-config/01-production-probes-resources.yaml` | Conserva sidecar y ConfigMap | Aplicarlo eliminaba el patrón multicontenedor |
| `mod3-workloads/04-backend-configmap.yaml`, `mod6-storage/03-statefulset-volume-claim-template.yaml` | **Creados** | Estaban en la estructura sin contenido |
| `scripts/inspect-backups.sh` | Reemplaza `kubectl run ... -v backup-pvc:/backups` | `-v` en kubectl es verbosidad, no un volumen |

## Resultados destacados

- **HPA:** bajo carga escaló a 10 réplicas deseadas (CPU 452 %/70 %); la ResourceQuota (`limits.cpu: 4`) limitó a 5 pods reales (`exceeded quota`). Al terminar volvió a 2.
- **Zero-Trust:** un pod no autorizado ya no llega al backend ni a PostgreSQL; la app, el Ingress y los backups siguen funcionando.
- **Escenario 6 (NetworkPolicy):** las políticas son **aditivas**. `error-block-dns` no bloquea mientras exista `allow-backend`; el fallo aparece cuando la política restrictiva queda sola.
