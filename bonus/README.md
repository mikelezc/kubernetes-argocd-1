# Bonus: GitLab en Local

## ¿Qué hacemos aquí?
El bonus pide instalar **GitLab en local** dentro del mismo clúster o en tu máquina, de manera que Argo CD no vigile GitHub en internet, ¡sino tu propio GitLab funcionando localmente!

> **⚠️ ADVERTENCIA DE RENDIMIENTO ⚠️**
> GitLab es extremadamente pesado. Para correrlo de forma aceptable vas a necesitar que tu clúster tenga asignados **al menos 6 u 8 GB de RAM** y buenos CPUs. Dado que estás en un **Macbook M4 Pro**, no tendrás problemas de potencia, pero asegúrate de asignar suficiente RAM (si usas Docker Desktop o UTM, sube la memoria a 12GB o más).

## ¿Cómo ejecutarlo?
1. Ejecuta el script de instalación:
   ```bash
   sudo bash ./scripts/install.sh
   ```
2. Este comando usará `Helm` para instalar un GitLab minimalista en el namespace `gitlab`.
3. Tarda unos 5-10 minutos en arrancar todos los servicios.

## ¿Cómo usarlo con ArgoCD?
1. Entrarás a `http://gitlab.local` (tendremos que mapearlo en tu `/etc/hosts` hacia 127.0.0.1).
2. Te loguearás, crearás un repositorio.
3. Subirás el código de tu web y apuntarás el `argocd.yaml` a la URL local de tu GitLab.
