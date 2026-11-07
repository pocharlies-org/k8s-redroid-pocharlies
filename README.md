# k8s-redroid-pocharlies

Instancia [redroid](https://github.com/remote-android/redroid-doc) (Android 13 en contenedor) en el cluster,
desplegada por GitOps para la épica [SC-1210](https://e-dani.atlassian.net/browse/SC-1210) (Instagram por
emulación). Historia: SC-1212.

**Retirado del tronco (07-11-2026)**: el pod privileged colgó el nodo x86 `ubuntu` (comentario 48214 de SC-1212).
Los manifiestos de `k8s/` se van del tronco para que ningún sync manual lo traiga de vuelta; el namespace `redroid`
y el PVC `redroid-data` siguen vivos a propósito y la Application de ArgoCD `redroid` queda parada (su retiro lo
decide Dani). Requisito del reintento: **NODO DEDICADO**, nunca privileged en un nodo compartido (SC-1212).
Lo de abajo es cómo se montó, para ese reintento.

- **Nodo**: `ubuntu` (x86). Requiere `binder_linux` + `/dev/binderfs` en el host (SC-1223, persistente).
- **Privilegiado**: autorizado por SC-3936 (nodo x86, namespace aislado con PSS `enforce: privileged`,
  adb solo tailnet, `/data` en PVC).
- **adb**: `100.83.56.98:30555` (NodePort, solo CIDR tailnet `100.64.0.0/10`).
- **scrcpy** (vista remota para intervención manual, desde cualquier máquina del tailnet con adb):
  ```sh
  adb connect 100.83.56.98:30555
  scrcpy -s 100.83.56.98:30555
  ```
- **Persistencia**: `/data` en PVC Longhorn `redroid-data` (grupo `daily-backup` → NFS de x86, retención 14).
  La sesión de Instagram sobrevive a `kubectl delete pod` (ArgoCD selfHeal lo recrea con el mismo PVC).

## Imagen

`harbor.lan.e-dani.com/homelab/redroid:13.0.0-mtg-houdini-20261107`
digest `sha256:a8e044c29e378c1a41c9f7a63f31e3be62a672d26f44c61fe41661a7504a9582` (el manifiesto fija el digest).

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
adb connect 100.83.56.98:30555 && adb -s 100.83.56.98:30555 install-matrix com.instagram.android*.xapk
```

Política de la épica: solo cuenta desechable (riesgo de baneo real); el login con 2FA es SC-1245.
