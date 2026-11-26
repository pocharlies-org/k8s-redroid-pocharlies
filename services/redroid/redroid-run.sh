#!/usr/bin/env bash
# Arranca redroid (Android 13 + GMS + libhoudini) en alphalink FUERA del CRI, con
# `k3s ctr run` en red aislada (--cni) para que netd de Android no toque el
# netfilter del host (con --net-host tumbó el nodo: SC-1212). Se lanza detached y
# se bloquea sobre el PID de la tarea para que systemd lo supervise (ver abajo).
set -euo pipefail

IMG=harbor.lan.e-dani.com/homelab/redroid@sha256:a8e044c29e378c1a41c9f7a63f31e3be62a672d26f44c61fe41661a7504a9582
NAME=redroid
DATA=/var/lib/redroid/data

# binder: Android necesita /dev/binder,hwbinder,vndbinder. binder_linux es módulo
# (CONFIG_ANDROID_BINDERFS=m) y vive en linux-modules-extra-<kernel>; un bump de
# kernel deja el módulo fuera y el contenedor muere en init (vdc: /dev/binder no
# existe). Auto-curamos: si modprobe falla, instalamos el extra del kernel en marcha.
if ! modprobe binder_linux devices=binder,hwbinder,vndbinder 2>/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y "linux-modules-extra-$(uname -r)"
  modprobe binder_linux devices=binder,hwbinder,vndbinder
fi
for d in binder hwbinder vndbinder; do ln -sf "/dev/binderfs/$d" "/dev/$d"; done
mkdir -p "$DATA"

# ctr no hace CNI DEL al borrar el contenedor: queda la reserva de IP en host-local
# y el siguiente arranque falla con "duplicate allocation". Limpiamos contenedor y
# su asignación antes de correr.
k3s ctr tasks rm -f "$NAME" 2>/dev/null || true
k3s ctr containers rm "$NAME" 2>/dev/null || true
grep -rl "k8s.io-$NAME" /var/lib/cni/networks/*/ 2>/dev/null | xargs -r rm -f

# `ctr run` con args finales REEMPLAZA el command (no los añade al ENTRYPOINT como
# docker/k8s), así que repetimos el ENTRYPOINT de la imagen y le añadimos el puente
# houdini: sin él la imagen traduce con libndk_translation y Instagram SIGSEGA (SC-1248).
INIT=(/init androidboot.hardware=redroid ro.setupwizard.mode=DISABLED ro.dalvik.vm.native.bridge=libhoudini.so)

# El contenedor vive en el cgroup de containerd, no en el de la unidad: al parar,
# systemd no lo alcanza a matar, así que lo quitamos nosotros al salir (stop/restart).
cleanup(){ k3s ctr tasks rm -f "$NAME" 2>/dev/null || true; k3s ctr containers rm "$NAME" 2>/dev/null || true; }
trap cleanup EXIT TERM INT

# `ctr run` en primer plano sale al instante bajo systemd (sin TTY): se lanza detached
# y se bloquea sobre el PID de la tarea (--pid-file). Cuando la tarea muere (Android
# cae) o containerd se va (reinicio de k3s-agent), el PID desaparece, tail sale, el trap
# limpia y systemd relanza con /data intacto (hostPath).
k3s ctr run -d --privileged --cni --pid-file /run/redroid-task.pid \
  --mount type=bind,src=/dev/binderfs,dst=/dev/binderfs,options=rbind:rw \
  --mount type=bind,src="$DATA",dst=/data,options=rbind:rw \
  "$IMG" "$NAME" "${INIT[@]}"

PID="$(cat /run/redroid-task.pid 2>/dev/null || true)"
[ -n "$PID" ] || { echo "redroid: sin PID de tarea"; exit 1; }
tail --pid="$PID" -f /dev/null
