#!/usr/bin/env bash
# Prepara un clúster kubeadm "pelado" (un nodo, flannel) con lo que Docker Desktop trae de serie
# y lo que el taller necesita:
#   1. Calico como CNI   -> flannel NO aplica NetworkPolicies; Calico sí (Módulo 5 Zero-Trust)
#   2. local-path        -> StorageClass por defecto para los PVC (Módulos 3 y 6)
#   3. metrics-server    -> métricas de CPU para el HPA y "kubectl top" (Módulo 3)
#   4. ingress-nginx     -> Ingress Controller publicado en el puerto 80 del host (Módulo 5)
#
# Uso:  bash cluster-setup/install-addons.sh
set -euo pipefail

CALICO_VERSION=v3.32.2
LOCAL_PATH_VERSION=v0.0.37
METRICS_SERVER_VERSION=v0.9.0
INGRESS_NGINX_VERSION=controller-v1.15.1
POD_CIDR=10.244.0.0/16 # podSubnet configurado en kubeadm

echo ">> [1/4] Reemplazando flannel por Calico"
kubectl delete -n kube-flannel daemonset kube-flannel-ds --ignore-not-found
kubectl delete namespace kube-flannel --ignore-not-found
curl -fsSL https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml \
  | sed -e "s|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|" \
        -e "s|#   value: \"192.168.0.0/16\"|  value: \"${POD_CIDR}\"|" \
  | kubectl apply -f -
kubectl rollout status -n kube-system daemonset/calico-node --timeout=300s
# Los pods existentes conservan la red de flannel: se recrean para tomar IPs de Calico
kubectl rollout restart -n kube-system deployment/coredns
kubectl rollout status -n kube-system deployment/coredns --timeout=180s

echo ">> [2/4] Instalando local-path-provisioner como StorageClass por defecto"
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/${LOCAL_PATH_VERSION}/deploy/local-path-storage.yaml
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl rollout status -n local-path-storage deployment/local-path-provisioner --timeout=180s

echo ">> [3/4] Instalando metrics-server"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml
# kubeadm firma los certificados del kubelet con su propia CA: se omite la verificación TLS (solo laboratorio)
kubectl patch -n kube-system deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl rollout status -n kube-system deployment/metrics-server --timeout=180s

echo ">> [4/4] Instalando ingress-nginx (bare-metal) en el puerto 80/443 del host"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_NGINX_VERSION}/deploy/static/provider/baremetal/deploy.yaml
# Sin LoadBalancer en bare-metal: se publican los puertos del controlador con hostPort,
# así http://localhost funciona igual que en Docker Desktop
kubectl patch -n ingress-nginx deployment ingress-nginx-controller --type=json -p '[
  {"op":"add","path":"/spec/template/spec/containers/0/ports/0/hostPort","value":80},
  {"op":"add","path":"/spec/template/spec/containers/0/ports/1/hostPort","value":443}
]'
kubectl rollout status -n ingress-nginx deployment/ingress-nginx-controller --timeout=300s

echo ">> Complementos listos"
kubectl get pods -A
