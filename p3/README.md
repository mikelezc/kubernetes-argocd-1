# Parte 3: K3d y Argo CD (GitOps)

## ¿Qué es esto?
Aquí no usamos Vagrant. El manual asume que lanzarás el script en una máquina Linux limpia (como un Ubuntu en UTM si estás en el Mac), o incluso directamente en tu Mac (si modificas el script para usar `brew`).
El objetivo es automatizar todo con:
- **K3d**: K3s pero que corre dentro de Docker (súper ligero).
- **Argo CD**: Un robot que mira TODO EL RATO un repositorio tuyo de Github, y si cambias algo allí, actualiza tu Kubernetes en vivo (GitOps).

## ¿Qué tienes que hacer antes de ejecutar nada?

1. **Crear un Repositorio en GitHub (Público)**:
   - Debe tener el nombre de tu usuario de 42, por ejemplo: `miguel-iot-argocd`.
   - Entra en la carpeta `app-para-tu-github/` de este proyecto, copia el archivo `deployment.yaml` de ahí y súbelo a ese repositorio de GitHub. 

2. **Editar la configuración local**:
   - Entra en `confs/argocd.yaml`.
   - Busca donde dice `repoURL: ...` y pon la URL de tu repositorio que acabas de crear (por ejemplo: `https://github.com/tu-usuario/miguel-iot-argocd.git`).

## ¿Cómo ejecutarlo? (En Linux / Máquina Virtual)
Abre la máquina virtual y entra en la carpeta `p3/scripts/`. Luego:

```bash
sudo bash ./install.sh
```

El script hará magia:
1. Instalará Docker y K3d.
2. Creará un clúster de kubernetes llamado `iot-cluster` dentro de Docker.
3. Instalará Argo CD.
4. Aplicará tu `confs/argocd.yaml` conectándolo a tu Github.

## ¿La prueba de fuego?
Si en tu Github entras a `deployment.yaml` y cambias `wil42/playground:v1` por `wil42/playground:v2`, al de unos instantes verás cómo al recargar en `http://localhost:8888` la app ahora dice `v2`. ¡Aprobado!
