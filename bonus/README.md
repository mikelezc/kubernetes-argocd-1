# Bonus: GitLab On-Premise y GitOps local

## Conceptos Clave

En el bonus montamos una versión local y autocontenida del flujo GitOps. En vez de depender de GitHub, Argo CD trabaja contra un GitLab instalado dentro del propio entorno y todo queda cerrado en la misma infraestructura.

1. GitLab se despliega en la VM como repositorio Git interno.
2. Argo CD sigue usando Git como fuente de la verdad, pero ahora el repo vive dentro de nuestro entorno local (nuestra propia máquina).
3. Kubernetes sigue siendo el plano de ejecución donde se aplican los manifiestos.
4. Helm se usa para instalar GitLab porque el despliegue de todos sus componentes sería demasiado complejo hacerlo de forma manual (además el subject lo recomienda).

## Atención: requerimientos de sistema para poder desplegar todo.

GitLab es pesado y tiene bastantes dependencias: base de datos, Redis, webservice, shell, storage, ingress y más. Por eso el bonus necesita más memoria y más automatización que las partes anteriores.

- Hemos hecho que la VM reserva 8 GB de RAM y 3 CPU para evitar errores por falta de memoria.
- El arranque crea un clúster `k3d` local, instala GitLab con Helm y añade Argo CD.
- Después del arranque se aplican parches para dejar GitLab accesible y estable en esta topología local.

## Carpetas del módulo de Bonus

1. [Vagrantfile](Vagrantfile): define la VM, la arquitectura detectada y la provisión automática.

2. [confs/gitlab-values.yaml](confs/gitlab-values.yaml): valores de Helm para el despliegue reducido de GitLab.

3. [scripts/install.sh](scripts/install.sh): instala Docker, kubectl, k3d, Helm, crea el clúster y despliega GitLab + Argo CD.

4. [scripts/post-install.sh](scripts/post-install.sh): aplica los ajustes posteriores al despliegue, como ingress, MinIO y credenciales.


## Requisitos Previos

1. Tener Docker Desktop o un daemon Docker equivalente funcionando.
2. Tener Vagrant instalado.
3. Disponer de navegador y permisos para editar `/etc/hosts` en tu máquina anfitriona.
4. Tener tiempo y memoria libres: este bonus consume bastante más que las partes anteriores.

## Arranque de la Infraestructura

```bash
vagrant up
```

Durante el arranque se hace lo siguiente:

- Se instala Docker, kubectl, k3d y Helm dentro de la VM.
- Se crea el clúster `iot-bonus`.
- Se instala GitLab mediante Helm usando [confs/gitlab-values.yaml](confs/gitlab-values.yaml).
- Se instala Argo CD en el namespace `argocd`.
- Se ejecuta [scripts/post-install.sh](scripts/post-install.sh) para dejar GitLab listo.

## Acceso a GitLab

La VM expone GitLab en `gitlab.local`. Debemos asociar ese nombre a la IP privada de la VM en /etc/hosts

```bash
echo "192.168.56.111 gitlab.local" | sudo tee -a /etc/hosts
```

Después podemos comprobar la UI de GitLab:

```text
http://gitlab.local
```

## Flujo de Trabajo

1. Levanta la VM con `vagrant up`.
2. Entra en GitLab con el usuario `root` y la contraseña inicial que imprime el script.
3. Crea o usa un proyecto dentro de GitLab local.
4. Sube el manifiesto del proyecto de la Parte 3 al repo interno.
5. Apunta Argo CD a ese repositorio local.
6. Cambia la versión de la app y comprueba que Argo CD sincroniza correctamente.

## Qué Hace Cada Script

- [scripts/install.sh](scripts/install.sh): prepara la VM, levanta `iot-bonus`, instala GitLab con Helm y añade Argo CD.
- [scripts/post-install.sh](scripts/post-install.sh): corrige ingress, espera a MinIO, crea buckets y muestra credenciales iniciales.
- [scripts/create-gitlab-project-and-push.sh](scripts/create-gitlab-project-and-push.sh): automatiza la creación del proyecto `mlezcano-gitlab-demo`, sube un primer `deployment.yaml` y devuelve la URL web del proyecto y la URL Git del repositorio.
- [scripts/create_pat.rb](scripts/create_pat.rb): obtiene un token de API para el usuario `root`.
- [scripts/create_proj.rb](scripts/create_proj.rb): crea el proyecto desde Ruby y publica el archivo inicial.
- [scripts/push_initial_commit.sh](scripts/push_initial_commit.sh): empuja el commit inicial al repositorio ya creado.

## Comprobaciones Rápidas

```bash
kubectl get pods -A
kubectl -n gitlab get pods
kubectl -n argocd get pods
kubectl -n gitlab get svc
```

Qué deberías ver:

- Pods de GitLab en `Running` cuando el despliegue termine.
- Pods de Argo CD en `Running` en el namespace `argocd`.
- Servicios de GitLab expuestos dentro del clúster y accesibles por `gitlab.local`.

## Limpieza y Destrucción

Cuando termines, destruye el entorno para liberar memoria y CPU.

```bash
vagrant destroy -f
```

## Puntos a tener en cuenta cara a la corrección

### 1. Ficheros de configuración en `bonus/`

Los ficheros relevantes son [Vagrantfile](Vagrantfile) y [confs/gitlab-values.yaml](confs/gitlab-values.yaml), además de los scripts de [scripts/](scripts/).

- [Vagrantfile](Vagrantfile): define la VM, la red privada, la memoria, las CPU y los provisioners automáticos.
- [confs/gitlab-values.yaml](confs/gitlab-values.yaml): reduce el despliegue de GitLab a una configuración más ligera para el laboratorio.
- [scripts/install.sh](scripts/install.sh): realiza la instalación base del entorno.
- [scripts/post-install.sh](scripts/post-install.sh): aplica los parches y ajustes finales.
- [scripts/create-gitlab-project-and-push.sh](scripts/create-gitlab-project-and-push.sh): crea un repositorio en GitLab y sube el primer commit.
- [scripts/create_pat.rb](scripts/create_pat.rb): genera el token de acceso necesario para automatizar acciones sobre GitLab.
- [scripts/create_proj.rb](scripts/create_proj.rb): alternativa Ruby para crear el proyecto y el contenido inicial.
- [scripts/push_initial_commit.sh](scripts/push_initial_commit.sh): sube el commit inicial si el proyecto ya existe.

### 2. GitLab funciona correctamente y se pueden crear repositorios

La comprobación se hace creando un proyecto nuevo y subiendo un commit real al GitLab local.

Comando de referencia:

```bash
vagrant ssh -c 'bash /vagrant/scripts/create-gitlab-project-and-push.sh'
```

Qué demuestra:

- Que GitLab está operativo.
- Que es posible crear un repositorio nuevo.
- Que se puede hacer push de un commit inicial sin errores.
- Que el helper devuelve la URL web del proyecto y la URL del repo para copiarla en Argo CD.

### 3. La Parte 3 sigue funcionando y usa un repositorio local en GitLab

Una vez creado el proyecto local, Argo CD debe apuntar a ese repo interno en lugar de a un servicio externo.

#### Cómo cambiar el repo de Argo CD a GitLab local (paso a paso)

1. Crea el proyecto y el primer commit en GitLab local:

```bash
cd /vagrant/scripts
./create-gitlab-project-and-push.sh
```

2. Edita [p3/confs/argocd.yaml](../p3/confs/argocd.yaml) y cambia `spec.source.repoURL` a la URL interna que sí resuelve dentro del clúster:

De:

```yaml
repoURL: 'https://github.com/mikelezc/mlezcano-iot-argocd.git'
```

A:

```yaml
repoURL: 'http://gitlab-webservice-default.gitlab.svc:8181/root/mlezcano-gitlab-demo.git'
```

3. Registra el repositorio privado en Argo CD (esto es obligatorio porque el proyecto se crea en privado):

```bash
ROOT_PASSWORD=$(kubectl -n gitlab get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' | base64 -d)
kubectl -n argocd delete secret repo-gitlab-local --ignore-not-found
kubectl -n argocd create secret generic repo-gitlab-local \
	--from-literal=type=git \
	--from-literal=url=http://gitlab-webservice-default.gitlab.svc:8181/root/mlezcano-gitlab-demo.git \
	--from-literal=username=root \
	--from-literal=password="$ROOT_PASSWORD" \
	--from-literal=forceHttpBasicAuth=true \
	--from-literal=insecure=true
kubectl -n argocd label secret repo-gitlab-local argocd.argoproj.io/secret-type=repository --overwrite
kubectl -n argocd rollout restart deployment argocd-repo-server
kubectl -n argocd rollout status deployment argocd-repo-server --timeout=180s
```

4. Aplica el cambio en Argo CD (elige según dónde ejecutes):

```bash
# Si estás en el host, dentro de la carpeta bonus/
kubectl apply -f ../p3/confs/argocd.yaml

# Si estás dentro de la VM (vagrant ssh mlezcanoS), usa patch directo
# porque /vagrant solo monta la carpeta bonus y no contiene p3/
kubectl -n argocd patch application iot-app --type merge -p '{"spec":{"source":{"repoURL":"http://gitlab-webservice-default.gitlab.svc:8181/root/mlezcano-gitlab-demo.git","targetRevision":"main","path":"."}}}'
```

5. Fuerza reconciliación y comprueba que ya usa GitLab:

```bash
kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd get application iot-app -o jsonpath='{.spec.source.repoURL}{"\n"}'
kubectl -n argocd get application iot-app
```

Resultado esperado:

- `repoURL` debe ser `http://gitlab-webservice-default.gitlab.svc:8181/root/mlezcano-gitlab-demo.git`.
- `SYNC STATUS` debe pasar a `Synced`.
- `HEALTH STATUS` debe pasar a `Healthy`.

Si ves `ComparisonError` con `authentication required`, significa que Argo CD sí ve la URL del repo pero todavía no puede clonar el proyecto privado. En ese caso:

1. Comprueba que existe la secret `repo-gitlab-local` en el namespace `argocd`.
2. Verifica que la secret tenga `forceHttpBasicAuth=true`, `username=root` y la contraseña inicial de GitLab.
3. Reinicia `argocd-repo-server` para limpiar caché:

```bash
kubectl -n argocd rollout restart deployment argocd-repo-server
kubectl -n argocd rollout status deployment argocd-repo-server --timeout=180s
```

4. Vuelve a refrescar la Application:

```bash
kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh=hard --overwrite
```

Nota: si al principio aparece `OutOfSync`, pulsa `Refresh` o `Sync` en la UI de Argo CD y espera unos segundos.

Qué se revisa:

- Que el repo de Argo CD apunte a `gitlab-webservice-default.gitlab.svc:8181`.
- Que el manifiesto del despliegue siga usando la app de la Parte 3 con sus dos versiones.
- Que el cambio `v1 -> v2` se refleje tras el commit/push.

Comandos útiles para validar:

```bash
kubectl -n argocd get application
kubectl -n dev get pods
curl http://localhost:8888/
```

### 4. Validación final del bonus

Si la sincronización de Argo CD no muestra errores y la app cambia de versión correctamente, el bonus queda validado.

Puntos que deben quedar correctos:

- GitLab responde en `http://gitlab.local`.
- El proyecto de prueba se crea y acepta commits.
- Argo CD observa el repo local.
- La app despliega `v1` y después `v2` sin romper el flujo.

