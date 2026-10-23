#!/usr/bin/env bash
# Lista los respaldos dentro de backup-pvc. Reemplaza al comando de la guía
# ("kubectl run ... -v backup-pvc:/backups"), que no funciona: en kubectl "-v" es el
# nivel de verbosidad de logs, no un volumen. El PVC se monta mediante --overrides.
set -euo pipefail
NS=${1:-gponceb}
kubectl run inspect-backup --image=busybox:1.36 --restart=Never -n "$NS" --overrides='{
  "spec": {
    "containers": [{
      "name": "inspect-backup",
      "image": "busybox:1.36",
      "command": ["sh", "-c", "ls -l /backups && echo && echo Datos del respaldo mas reciente: && grep -A20 \"^COPY public.productos\" $(ls -1 /backups/*.sql | tail -1) | sed /^$/q"],
      "volumeMounts": [{ "name": "backups", "mountPath": "/backups" }]
    }],
    "volumes": [{ "name": "backups", "persistentVolumeClaim": { "claimName": "backup-pvc" } }]
  }
}'
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/inspect-backup -n "$NS" --timeout=60s >/dev/null
kubectl logs inspect-backup -n "$NS"
kubectl delete pod inspect-backup -n "$NS" --now >/dev/null
