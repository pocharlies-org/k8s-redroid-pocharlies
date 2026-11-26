# k8s-redroid-pocharlies

Instancia [redroid](https://github.com/remote-android/redroid-doc) (Android 13 + MindTheGapps/GMS + libhoudini)
para la épica [SC-1210](https://e-dani.atlassian.net/browse/SC-1210) (Instagram por emulación). Historia: SC-1212.

## Modelo: fuera del CRI, bajo systemd (opción A — Dani, SC-1212 com 60839)

redroid **no corre como pod**. En cgroup v2 el CRI da a cada pod un cgroupns privado y Android no arranca
(`libprocessgroup: createProcessGroup`); y un pod privileged en un nodo compartido tumbó el `ubuntu` (com 48214).
Se lanza con `k3s ctr run --privileged --cni` (containerd de k3s, red aislada) **en primer plano bajo una unidad
systemd** en el nodo dedicado `alphalink`. `/data` es un hostPath persistente y el backup lo cubre el restic del nodo.

```
services/redroid/
  redroid-run.sh      # ctr run en primer plano; auto-cura binder; limpia la IP CNI huérfana
  redroid-adb-nat.sh  # DNAT del host a adb(5555) del contenedor, SOLO tailnet
  redroid.service     # Restart=always; Wants/After k3s-agent (sobrevive a su reinicio)
  install.sh          # instala scripts+unidad, deja binder persistente, enlaza el CNI, arranca
```

Instalar en alphalink: `bash services/redroid/install.sh`.

### Requisitos del host (los pone install.sh, y redroid-run.sh los re-afirma en runtime)

- **binder**: `CONFIG_ANDROID_BINDERFS=m`; el módulo `binder_linux` vive en `linux-modules-extra-<kernel>`. Un bump
  de kernel (unattended-upgrade) lo deja fuera y Android muere en init (`vdc: /dev/binder no existe`). install.sh deja
  `/etc/modules-load.d` + `/etc/modprobe.d` + el montaje de `/dev/binderfs` en `/etc/fstab`; redroid-run.sh, si
  `modprobe` falla, instala el extra del kernel en marcha y sigue.
- **CNI para `--cni`**: symlinks `/etc/cni/net.d` y `/opt/cni/bin` a los que ya trae k3s (flannel). Con `--net-host`
  el `netd` de Android reescribe el netfilter del host y tumba el nodo (incidente SC-1212): por eso la red es aislada.

### adb — solo tailnet

`redroid-adb-nat.sh` (ExecStartPost) hace DNAT de `100.94.8.40:30555` (src `100.64.0.0/10`) a la IP flannel del
contenedor:5555. Nada expuesto fuera de la tailnet.

```sh
adb connect 100.94.8.40:30555
scrcpy -s 100.94.8.40:30555
```

### Persistencia y backup

`/data` → hostPath `/var/lib/redroid/data`. Sobrevive a `systemctl restart redroid` y al reinicio de k3s-agent
(`Restart=always` relanza el `ctr run` con el mismo `/data`). El backup lo toma el restic del nodo
(`/usr/local/sbin/alphalink-backup.sh`, timer diario): hay que añadir `/var/lib/redroid/data` a sus rutas.

## Imagen

`harbor.lan.e-dani.com/homelab/redroid:13.0.0-mtg-houdini-20261107`
digest `sha256:a8e044c29e378c1a41c9f7a63f31e3be62a672d26f44c61fe41661a7504a9582` (redroid-run.sh fija el digest).

Construcción (así se regenera; se ejecutó en el `ubuntu`, requiere docker y ~10 GB libres):

```sh
git clone https://github.com/ayasa520/redroid-script.git && cd redroid-script
git checkout a4951b782fc8e06c845d9553bf07bb643fd8c158
python3 -m venv venv && venv/bin/pip install -r requirements.txt
venv/bin/python redroid.py -a 13.0.0 -mtg -i   # MindTheGapps (GMS) + libhoudini
docker tag redroid/redroid:13.0.0_mindthegapps_houdini harbor.lan.e-dani.com/homelab/redroid:13.0.0-mtg-houdini-20261107
docker push harbor.lan.e-dani.com/homelab/redroid:13.0.0-mtg-houdini-20261107
```

El contenedor arranca con `ro.dalvik.vm.native.bridge=libhoudini.so`: la imagen base trae el puente ndk y con él
Instagram SIGSEGA (medido en el spike, SC-1248); con houdini abre la pantalla de login sin crash.

## Instagram

APK oficial vía [apkeep](https://github.com/EFForg/apkeep) 1.0.0, proveedor `apk-pure` (espejo de binarios
firmados de Play; nunca se loguea una cuenta para descargarla):

```sh
apkeep -a com.instagram.android -d apk-pure .   # xapk (base + splits)
adb connect 100.94.8.40:30555 && adb -s 100.94.8.40:30555 install-matrix com.instagram.android*.xapk
```

Política de la épica: solo cuenta desechable (riesgo de baneo real); el login con 2FA es SC-1245.
