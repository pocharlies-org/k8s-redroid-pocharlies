# k8s-redroid-pocharlies

Instancia [redroid](https://github.com/remote-android/redroid-doc) (Android 13 en contenedor) en el cluster,
desplegada por GitOps para la épica [SC-1210](https://e-dani.atlassian.net/browse/SC-1210) (Instagram por
emulación). Historia: SC-1212.

Reintento sobre **nodo dedicado** (requisito fijado 07-11 tras colgar el x86 `ubuntu`, com 48214): nunca privileged
en un nodo compartido. Antes estaba en `ubuntu`; ahora va fijado a `alphalink` (Cloud, taint `dedicated=alpha`).

- **Nodo**: `alphalink`. Requiere `binder_linux` + `/dev/binderfs` en el host (ya instalados y persistidos por el
  spike SC-1211: paquete stock `linux-modules-extra` + `modules-load.d`/`modprobe.d`/`fstab`).
- **cgroup v2 (lo que destrabó SC-1212, SC-1211 com 58962)**: alphalink es cgroup v2 puro y el driver systemd-cgroup
  de k3s cuelga el cgroup del contenedor de `kubepods.slice/…`; `libprocessgroup` no crea ahí sus grupos
  `uid_X/pid_Y` → `createProcessGroup` falla → surfaceflinger fatal → Android se auto-apaga a ~2 s. El `pod.yaml`
  monta la jerarquía cgroup del host (`hostPath /sys/fs/cgroup`) para dar a Android una raíz escribible — lo mismo
  que el `cgroupns=host` que el spike validó con `k3s ctr run --privileged` (`sys.boot_completed=1`). No hace falta
  rebuild de AOSP ni volver el nodo a cgroup v1 (que rebotaría el WordPress/MySQL vivos).
- **Privilegiado**: solo en el ns `redroid` (PSS `enforce: privileged`) y solo en `alphalink` (nodeSelector + toleration).
- **Storage**: `/data` en PVC Longhorn `redroid-data` (grupo `daily-backup` → NFS x86, retención 14). alphalink NO es
  nodo Longhorn hoy: para que attachee hay que habilitarlo (etiqueta `storage-longhorn=true` en el nodo + toleration
  `dedicated=alpha` en el DS `longhorn-manager`, en k8s-infra). El engine corre en alphalink, los réplices y el backup
  en los nodos Longhorn.
- **adb**: `100.94.8.40:30555` (NodePort, solo CIDR tailnet `100.64.0.0/10`).
- **scrcpy** (vista remota para intervención manual, desde cualquier máquina del tailnet con adb):
  ```sh
  adb connect 100.94.8.40:30555
  scrcpy -s 100.94.8.40:30555
  ```

## Imagen

`harbor.lan.e-dani.com/homelab/redroid:13.0.0-mtg-houdini-20261107`
digest `sha256:a8e044c29e378c1a41c9f7a63f31e3be62a672d26f44c61fe41661a7504a9582` (el `pod.yaml` fija el digest).

Construcción (así se regenera; se ejecutó en el `ubuntu`, requiere docker y ~10 GB libres):

```sh
git clone https://github.com/ayasa520/redroid-script.git && cd redroid-script
git checkout a4951b782fc8e06c845d9553bf07bb643fd8c158
python3 -m venv venv && venv/bin/pip install -r requirements.txt
venv/bin/python redroid.py -a 13.0.0 -mtg -i   # MindTheGapps (GMS) + libhoudini
docker tag redroid/redroid:13.0.0_mindthegapps_houdini harbor.lan.e-dani.com/homelab/redroid:13.0.0-mtg-houdini-20261107
docker push harbor.lan.e-dani.com/homelab/redroid:13.0.0-mtg-houdini-20261107
```

El pod arranca con `ro.dalvik.vm.native.bridge=libhoudini.so`: la imagen base trae el puente ndk y con él
Instagram SIGSEGA (medido en el spike, SC-1248); con houdini abre la pantalla de login sin crash.

## Instagram

APK oficial vía [apkeep](https://github.com/EFForg/apkeep) 1.0.0, proveedor `apk-pure` (espejo de binarios
firmados de Play; nunca se loguea una cuenta para descargarla):

```sh
apkeep -a com.instagram.android -d apk-pure .   # xapk (base + splits)
adb connect 100.94.8.40:30555 && adb -s 100.94.8.40:30555 install-matrix com.instagram.android*.xapk
```

Política de la épica: solo cuenta desechable (riesgo de baneo real); el login con 2FA es SC-1245.
