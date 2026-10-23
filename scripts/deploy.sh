#!/usr/bin/env bash
# Despliega el taller completo en el orden de la "Guía de ejecución" (pasos 1–9).
# Requisitos previos: cluster-setup/install-addons.sh y scripts/build-images.sh ya ejecutados.
# Uso:  bash scripts/deploy.sh
set -euo pipefail
cd "$(dirname "$0")/.."
NS=gponceb

echo ">> Paso 1: Namespace del alumno"
kubectl apply -f 00-namespace.yaml
kubectl config set-context --current --namespace=$NS

echo ">> Paso 2: Almacenamiento, secretos y configuración"
kubectl apply -f mod6-storage/01-db-pvc.yaml -f mod6-storage/02-backup-pvc.yaml
kubectl apply -f mod3-workloads/01-db-secret.yaml -f mod3-workloads/02-db-init-configmap.yaml -f mod3-workloads/04-backend-configmap.yaml

echo ">> Paso 3: PostgreSQL"
kubectl apply -f mod3-workloads/03-db-statefulset.yaml -f mod5-networking/01-db-service.yaml
kubectl rollout status statefulset/postgres-db --timeout=300s

echo ">> Paso 4: Workloads multicontenedor, servicios y logging"
kubectl apply -f mod5-networking/02-backend-service.yaml -f mod5-networking/03-frontend-service.yaml
kubectl apply -f mod3-workloads/07-fluentd-daemonset.yaml
kubectl apply -f mod3-workloads/06-frontend-deployment-sidecar.yaml
kubectl apply -f mod4-config/01-production-probes-resources.yaml # backend-api con probes (superset del mod3/05)
kubectl rollout status deployment/backend-api --timeout=300s
kubectl rollout status deployment/frontend-web --timeout=180s

echo ">> Módulo 7: Hardening (PDB, LimitRange, ResourceQuota)"
kubectl apply -f mod7-production-hardening/01-backend-pdb.yaml
kubectl apply -f mod7-production-hardening/03-limitrange.yaml
kubectl apply -f mod7-production-hardening/02-namespace-quota.yaml

echo ">> Paso 5: HPA"
kubectl apply -f mod3-workloads/10-hpa-autoscaler.yaml

echo ">> Paso 6: Ingress"
kubectl apply -f mod5-networking/04-ingress-nginx.yaml

echo ">> Paso 8: Job de migración y CronJob de backup"
kubectl apply -f mod3-workloads/08-db-migration-job.yaml -f mod3-workloads/09-db-backup-cronjob-pvc.yaml

echo ">> Paso 9: Zero-Trust"
kubectl apply -f mod5-networking/05-default-deny-networkpolicy.yaml \
              -f mod5-networking/06-frontend-networkpolicy.yaml \
              -f mod5-networking/07-backend-networkpolicy.yaml \
              -f mod5-networking/08-database-networkpolicy.yaml

kubectl get all -n $NS
echo ">> Listo: abre http://localhost"
