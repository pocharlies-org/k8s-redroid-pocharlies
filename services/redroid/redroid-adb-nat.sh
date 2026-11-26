#!/usr/bin/env bash
# Expone adb (5555) del contenedor redroid en un puerto del host SOLO para la
# tailnet: DNAT de 100.94.8.40:30555 (src 100.64.0.0/10) a la IP flannel del
# contenedor. Con --net-host Android pondría adb en el host pero su netd rompe el
# nodo; aquí adb vive dentro del netns y lo asomamos con esta regla.
set -euo pipefail
NAME=redroid
HOST_IP=100.94.8.40      # IP tailnet de alphalink
PORT=30555
NET=100.64.0.0/10        # tailnet; nada fuera de esto entra

IP=""
for _ in $(seq 1 30); do
  IP=$(grep -rl "k8s.io-$NAME" /var/lib/cni/networks/*/ 2>/dev/null | head -1 | xargs -r basename || true)
  [ -n "$IP" ] && break
  sleep 2
done
[ -n "$IP" ] || { echo "sin IP para $NAME"; exit 1; }

# idempotente
iptables -t nat -C PREROUTING -s "$NET" -d "$HOST_IP" -p tcp --dport "$PORT" \
  -j DNAT --to-destination "$IP:5555" 2>/dev/null || \
iptables -t nat -A PREROUTING -s "$NET" -d "$HOST_IP" -p tcp --dport "$PORT" \
  -j DNAT --to-destination "$IP:5555"
iptables -C FORWARD -d "$IP" -p tcp --dport 5555 -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -d "$IP" -p tcp --dport 5555 -j ACCEPT
echo "adb tailnet: $HOST_IP:$PORT -> $IP:5555"
