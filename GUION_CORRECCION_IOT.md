# Guion de corrección para Inception of Things

Este documento está pensado como guía práctica para la defensa del proyecto. Resume qué comprobar, qué preguntar, qué comandos usar y cómo demostrar cada parte con tu repositorio.

## 1. Preparación antes de empezar

Antes de evaluar, confirma que el grupo evaluado está presente y que el repositorio correcto es el que se va a revisar.

Comandos útiles:

```bash
git clone <URL_DEL_REPO> iot-eval
cd iot-eval
ls -la
```

Verifica que el repositorio contiene exactamente `p1/`, `p2/`, `p3/` y, si existe, `bonus/`.

Si sospechas de alias o trampas, comprueba el origen del repositorio y el historial:

```bash
git remote -v
git log --oneline --decorate --graph --max-count=10
```

## 2. Explicación rápida previa

Pide al grupo que explique de forma simple:

- Qué es Vagrant: herramienta para crear y administrar máquinas virtuales con un archivo de configuración. Sirve para levantar entornos reproducibles sin hacer la instalación a mano.
- Qué es K3s: distribución ligera de Kubernetes, pensada para consumir menos recursos y facilitar entornos pequeños o de laboratorio.
- Qué es K3d: herramienta para ejecutar K3s dentro de Docker. Permite crear clústeres rápidamente sin levantar VMs pesadas.
- Qué es CI/CD: integración continua y entrega/despliegue continuo. Es automatizar pruebas y despliegues para que los cambios lleguen al entorno de forma controlada.
- Qué es Argo CD y qué significa GitOps: Argo CD es una herramienta que sincroniza Kubernetes con un repositorio Git. GitOps significa que Git es la fuente de verdad: cualquier cambio en Git se refleja en el clúster.

Si no pueden explicarlo con claridad, detén la evaluación y vuelve al subject.

## 3. Parte 1 - Vagrant + K3s en dos máquinas

### Qué comprobar

- Debe existir un `Vagrantfile` en `p1/`.
- Debe haber dos máquinas virtuales.
- Ambas deben usar la versión estable de CentOS pedida por el subject.
- Debe existir una interfaz `eth1` con las IPs requeridas.
- Los nombres de las máquinas deben incluir el login del grupo.

### Comandos prácticos

```bash
cd p1
vagrant up
vagrant status
vagrant ssh <server>
vagrant ssh <worker>
```

Dentro de cada VM:

```bash
ifconfig eth1
hostname
```

En la máquina server:

```bash
kubectl get nodes -o wide
```

### Qué debe verse

- El nodo server y el nodo worker en el mismo clúster.
- Las IPs correctas en `eth1`.
- Los hostnames solicitados por el subject.

## 4. Parte 2 - Una VM con K3s + Ingress

### Qué comprobar

- Debe haber un único `Vagrantfile` en `p2/`.
- Debe existir una sola VM.
- Debe usar CentOS estable.
- Debe tener `eth1` con la IP pedida.
- Deben existir tres aplicaciones detrás de Ingress.

### Comandos prácticos

```bash
cd p2
vagrant up
vagrant ssh
ifconfig eth1
hostname
kubectl get nodes -o wide
kubectl get all -n kube-system
```

Para probar Ingress, usa `curl` con el header `Host` correcto según el subject:

```bash
curl -H "Host: app1.<dominio>" http://<IP_DE_LA_VM>/
curl -H "Host: app2.<dominio>" http://<IP_DE_LA_VM>/
curl -H "Host: app3.<dominio>" http://<IP_DE_LA_VM>/
```

Si el grupo no recuerda el comando exacto del Ingress, pídeles que lo expliquen; no hace falta memorizarlo si entienden el flujo.

### Qué debe verse

- Tres aplicaciones en `kube-system`.
- La segunda con tres réplicas, si así lo pide el subject.
- Cada app responde según el `Host` usado.

## 5. Parte 3 - K3d + Argo CD + GitOps

### Qué comprobar

- Debe haber al menos dos namespaces: `argocd` y `dev`.
- Debe haber pods en `dev`.
- Argo CD debe estar instalado y accesible desde navegador.
- El nombre del repositorio GitHub debe incluir el login del grupo.
- La imagen Docker usada en el repo debe ser la que pida el subject, con las etiquetas correctas.

### Comandos prácticos

```bash
cd p3
vagrant up
vagrant ssh
kubectl get ns
kubectl get pods -n dev
kubectl get nodes -o wide
kubectl get all -n kube-system
```

Si el subject o tu setup lo permite, prueba la app desde el host:

```bash
curl http://localhost:8888/
```

### Qué debe explicar el grupo

- Cómo Argo CD lee el repo.
- Cómo detecta cambios.
- Cómo sincroniza el clúster con el repositorio.
- Qué ocurre cuando se cambia una versión de la app en Git.

### Demo práctica de actualización

1. Abre el repositorio Git y localiza el manifiesto de despliegue.
2. Cambia la imagen de la app de `v1` a `v2`.
3. Haz commit y push.
4. Espera a que Argo CD sincronice automáticamente o fuerza un sync manual.
5. Verifica el cambio en el navegador o con `curl`.

Ejemplo genérico:

```bash
git clone <REPO_DE_GIT>
cd <REPO>
sed -i '' 's/wil42\/playground:v1/wil42\/playground:v2/' deployment.yaml
git add deployment.yaml
git commit -m "Update app to v2"
git push
```

Si usas el bonus con GitLab local, la idea es la misma pero el repo vive en GitLab y Argo CD apunta a ese repo interno.

## 6. Bonus - GitLab local + Argo CD local

### Qué comprobar

- Existen archivos de configuración en `bonus/`.
- GitLab funciona correctamente.
- Se puede crear un repositorio nuevo.
- Se puede añadir código y hacer push.
- Argo CD usa un repo local de GitLab.
- La app sigue funcionando y se actualiza entre dos versiones.

### Comandos prácticos para tu proyecto

```bash
cd bonus
vagrant up
```

Acceso a GitLab:

```bash
echo "192.168.56.111 gitlab.local" | sudo tee -a /etc/hosts
```

Obtener la contraseña inicial de `root`:

```bash
cd bonus
vagrant ssh -c "kubectl -n gitlab get secret gitlab-gitlab-initial-root-password -ojsonpath='{.data.password}' | base64 -d"
```

Crear y usar un PAT si lo necesitas para Git HTTPS:

```bash
# usuario: root
# contraseña: PAT o contraseña inicial
```

Comprobar que Argo CD está usando GitLab local:

```bash
cd p3
vagrant ssh -c "export KUBECONFIG=/home/vagrant/.kube/config; kubectl -n argocd get application playground-demo -o yaml | grep -E 'repoURL|targetRevision|path'"
```

Verificar sincronización y aplicación:

```bash
curl http://localhost:8888/
```

## 7. Guion recomendado para la defensa

Orden sugerido:

1. Comprobar que el grupo está presente.
2. Verificar que el repo clonado es el correcto.
3. Explicar las herramientas a alto nivel.
4. Revisar la Parte 1.
5. Revisar la Parte 2.
6. Revisar la Parte 3.
7. Si existe bonus, demostrar GitLab local + actualización automática con Argo CD.

## 8. Señales de que todo va bien

- `kubectl get nodes -o wide` muestra el nodo esperado.
- `kubectl get pods -n dev` muestra pods `Running`.
- `curl http://localhost:8888/` responde con la versión esperada.
- Argo CD muestra la aplicación sincronizada con el repo correcto.
- Los cambios hechos en Git se reflejan en el navegador después del sync.

## 9. Recursos oficiales y útiles

Documentación:

- Vagrant: https://developer.hashicorp.com/vagrant/docs
- K3s: https://docs.k3s.io/
- K3d: https://k3d.io/
- Kubernetes: https://kubernetes.io/docs/
- Argo CD: https://argo-cd.readthedocs.io/
- GitLab Helm chart: https://docs.gitlab.com/charts/
- Traefik: https://doc.traefik.io/traefik/

Recursos en vídeo:

- Busca en YouTube: `Vagrant K3s K3d Argo CD GitOps`
- Busca en YouTube: `Argo CD sync demo GitOps`
- Busca en YouTube: `K3d ingress tutorial`

## 10. Plantilla de preguntas para el grupo

- ¿Qué problema resuelve Vagrant aquí?
- ¿Por qué K3s en lugar de Kubernetes completo?
- ¿Qué aporta K3d respecto a una VM tradicional?
- ¿Qué diferencia hay entre CI/CD y GitOps?
- ¿Qué hace Argo CD cuando cambias un YAML en Git?
- ¿Por qué es importante que el repo del bonus sea local y no de GitHub?

## 11. Notas de tu proyecto actual

En tu repo, el bonus ya está adaptado a GitLab local y Argo CD apunta al repo interno. Si quieres usar este guion durante la defensa, céntrate en demostrar:

- acceso a GitLab local,
- creación o uso del repo `playground-demo`,
- push de un cambio,
- sincronización de Argo CD,
- verificación en `http://localhost:8888/`.
