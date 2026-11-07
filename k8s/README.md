# k8s/

Vacío a propósito desde el retiro de SC-1212 (07-11-2026): el pod privileged colgó el nodo x86 `ubuntu`
(comentario 48214 de SC-1212) y ningún sync manual debe traerlo de vuelta. Los manifiestos (pod, namespace,
PVC, service y NetworkPolicy) están en el historial de `deploy/prod`. El namespace `redroid` y el PVC
`redroid-data` siguen vivos en el cluster a propósito; el reintento va en NODO DEDICADO (requisito en SC-1212).

Este fichero queda aquí para que el path `k8s/` que lee la Application de ArgoCD siga existiendo
(ArgoCD ignora los `.md` en un directorio plano).
