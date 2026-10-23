# taller-k8s-gponceb

Esta es mi entrega del **Taller Práctico de Kubernetes — Edición Enterprise Extended** (Módulos 3 a 8).

| | |
|---|---|
| **Alumno** | Gilson Ponce Briones |
| **Namespace de K8s** | `gponceb` |
| **Fecha de entrega** | 23 de octubre de 2026 |
| **Asignatura** | Administración Avanzada de Contenedores y Orquestación con Kubernetes |

📄 **Mi reporte técnico de evidencias:** [`REPORTE-TECNICO-gponceb.pdf`](REPORTE-TECNICO-gponceb.pdf)
📘 **La guía del taller, con mis datos en el encabezado:** [`GUIA-TALLER.md`](GUIA-TALLER.md)

## Lo que construí

Desplegué en mi namespace `gponceb` una aplicación CRUD de productos con esta arquitectura:

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

## Cómo organicé el repositorio

```
taller-k8s-gponceb/
├── 00-namespace.yaml
├── app-src/                    # Código y Dockerfiles (backend Node.js, frontend NGINX, init.sql)
├── mod3-workloads/             # Secret, ConfigMaps, StatefulSet, Deployments, DaemonSet, Job, CronJob, HPA
├── mod4-config/                # backend-api con liveness/readiness probes
├── mod5-networking/            # Services, Ingress y NetworkPolicies Zero-Trust
├── mod6-storage/               # PVCs
├── mod7-production-hardening/  # PDB, ResourceQuota, LimitRange
├── mod8-troubleshooting/       # Los 6 escenarios de error intencionales
├── cluster-setup/              # Cómo preparé el clúster: Calico, local-path, metrics-server, ingress-nginx
├── scripts/                    # Build de imágenes, despliegue, prueba de carga, inspección de backups
├── evidencias/                 # La salida real de cada paso (.txt) y mis capturas de terminal y de la web (.png)
└── REPORTE-TECNICO-gponceb.pdf
```

## Cómo lo ejecuté

No usé Docker Desktop: trabajé sobre un clúster **kubeadm de un nodo** en Linux (Kubernetes v1.37.1 con containerd). Estos son los pasos que seguí y que sirven para reproducirlo:

```bash
# 1. Preparé el clúster (Calico, StorageClass, metrics-server, Ingress Controller)
bash cluster-setup/install-addons.sh

# 2. Construí las imágenes y las importé a containerd
sudo bash scripts/build-images.sh

# 3. Desplegué todo (pasos 1–9 de la guía)
bash scripts/deploy.sh

# 4. Verifiqué
open http://localhost                       # la interfaz CRUD
node scripts/load-test.js 240 64            # la carga para el HPA  (kubectl get hpa -w)
bash scripts/inspect-backups.sh             # los respaldos dentro de backup-pvc

# 5. Reproduje los escenarios de troubleshooting (paso 10)
kubectl apply -f mod8-troubleshooting/
```

Si alguien lo prueba en **Docker Desktop**, puede saltarse el paso 1 (solo hace falta instalar ingress-nginx y metrics-server), y en el paso 2 le basta con `docker build`.

## Problemas que encontré en la guía y cómo los corregí

Al seguir la guía tal cual, varias cosas me fallaron. Dejé comentado cada cambio en su YAML, y en la sección 2 del reporte explico el detalle.

| Archivo | Qué cambié | Por qué |
|---|---|---|
| `mod5-networking/04-ingress-nginx.yaml` | Quité el `rewrite-target` y usé paths `Prefix` | El rewrite quitaba `/api` y mi backend respondía 404 |
| `app-src/backend/package-lock.json` | Lo agregué | `npm ci` falla sin lockfile |
| `mod5-networking/07-backend-networkpolicy.yaml` | Permití el namespace `ingress-nginx` y el DNS por TCP | Con default-deny el Ingress no llegaba a mi backend |
| `mod5-networking/08-database-networkpolicy.yaml` | **Lo creé** | PostgreSQL rechazaba todo el tráfico y los Jobs no tenían salida |
| `mod5-networking/06-frontend-networkpolicy.yaml` | Permití el DNS | default-deny bloqueaba CoreDNS |
| `mod6-storage/02-backup-pvc.yaml` | Lo cambié a `ReadWriteOnce` | local-path/hostpath no soportan RWX |
| `mod7-production-hardening/03-limitrange.yaml` | **Lo creé** | La ResourceQuota rechazaba mis pods sin requests/limits |
| `mod4-config/01-production-probes-resources.yaml` | Conservé el sidecar y el ConfigMap | Al aplicarlo perdía el patrón multicontenedor |
| `mod3-workloads/04-backend-configmap.yaml`, `mod6-storage/03-statefulset-volume-claim-template.yaml` | **Los creé** | Estaban en la estructura pero sin contenido |
| `scripts/inspect-backups.sh` | Reemplaza a `kubectl run ... -v backup-pvc:/backups` | En kubectl `-v` es verbosidad, no un volumen |

## Lo que más me llamó la atención

- **HPA:** con carga, mi HPA pidió 10 réplicas (CPU 452 %/70 %), pero la ResourceQuota (`limits.cpu: 4`) lo frenó en 5 pods reales (`exceeded quota`). Al quitar la carga volvió a 2.
- **Zero-Trust:** después de aplicar las políticas, un pod no autorizado ya no llega a mi backend ni a PostgreSQL, y la app, el Ingress y los backups siguen funcionando.
- **Escenario 6 (NetworkPolicy):** descubrí que las políticas se **suman**. `error-block-dns` no bloquea nada mientras exista `allow-backend`; el fallo aparece cuando la política restrictiva queda sola.
