#!/usr/bin/env bash
# Instala la unidad redroid en alphalink (fuera del CRI). Patrón casa: copia los
# scripts y la unidad, deja el binder persistente (binder_linux + binderfs), enlaza
# el CNI de k3s para `--cni`, y arranca. Idempotente.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# scripts + unidad
sudo install -m 755 "$HERE/redroid-run.sh"     /usr/local/bin/redroid-run.sh
sudo install -m 755 "$HERE/redroid-adb-nat.sh" /usr/local/bin/redroid-adb-nat.sh
sudo install -m 644 "$HERE/redroid.service"    /etc/systemd/system/redroid.service

# binder: módulo (vive en linux-modules-extra) + binderfs montado en arranque.
# El run script lo auto-cura en runtime; esto lo deja persistente entre reboots.
echo binder_linux | sudo tee /etc/modules-load.d/redroid-binder.conf >/dev/null
echo 'options binder_linux devices=binder,hwbinder,vndbinder' \
  | sudo tee /etc/modprobe.d/redroid-binder.conf >/dev/null
grep -q '/dev/binderfs' /etc/fstab \
  || echo 'binder /dev/binderfs binder nofail 0 0' | sudo tee -a /etc/fstab >/dev/null
sudo mkdir -p /dev/binderfs && sudo mount /dev/binderfs 2>/dev/null || true

# --cni: reutiliza la config y los binarios del CNI que ya trae k3s (flannel).
[ -e /etc/cni/net.d ] || sudo ln -s /var/lib/rancher/k3s/agent/etc/cni/net.d /etc/cni/net.d
[ -e /opt/cni/bin ]   || sudo ln -s /var/lib/rancher/k3s/data/cni /opt/cni/bin

sudo systemctl daemon-reload
sudo systemctl enable --now redroid.service
sleep 3
sudo systemctl status --no-pager redroid.service | head -15
