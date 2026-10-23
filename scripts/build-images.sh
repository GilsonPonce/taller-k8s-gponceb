#!/usr/bin/env bash
# Construye las imágenes del taller y las importa al containerd del nodo.
# En Docker Desktop basta con "docker build": Kubernetes comparte el daemon de Docker.
# En un clúster kubeadm el kubelet usa containerd, que NO ve las imágenes de Docker,
# por eso se exportan con "docker save" y se importan en el namespace k8s.io de containerd.
#
# Uso:  sudo bash scripts/build-images.sh
set -euo pipefail

cd "$(dirname "$0")/../app-src"

if ! systemctl is-active --quiet docker; then
  echo ">> Iniciando el daemon de Docker"
  systemctl start docker
fi

echo ">> Build de la imagen Backend"
docker build -t k8s-backend:v1.0 ./backend

echo ">> Build de la imagen Frontend"
docker build -t k8s-frontend:v1.0 ./frontend

echo ">> Importando imágenes en containerd (namespace k8s.io)"
docker save k8s-backend:v1.0 k8s-frontend:v1.0 | ctr -n k8s.io images import -

echo ">> Imágenes disponibles para el kubelet:"
ctr -n k8s.io images ls -q | grep k8s-
