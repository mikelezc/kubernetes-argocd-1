## Instrucciones rápidas de la demo

Resumen: el entorno tiene dos VMs gestionadas por Vagrant: `bonus` (GitLab) en 192.168.56.111 y `p3` (ArgoCD + app) que expone la app en `http://localhost:8888`.

- Levantar VMs:

```bash
vagrant up bonus p3
```

- Acceder a GitLab UI:

```bash
# si no resuelve gitlab.local:
sudo sh -c 'echo "192.168.56.111 gitlab.local" >> /etc/hosts'

# obtener contraseña root desde host:
cd bonus
vagrant ssh -c "kubectl -n gitlab get secret gitlab-gitlab-initial-root-password -ojsonpath='{.data.password}' | base64 -d"
```

- Clonar o ver repo en GitLab:

```bash
# ejemplo (desde host):
git clone http://gitlab.local/root/playground-demo.git

# si Git pide credenciales al hacer push: usuario 'root' y como contraseña el PAT (o la contraseña root)
```

- Acceder a ArgoCD UI:

```bash
# abrir http://localhost:8080
cd p3
vagrant ssh -c "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
```

- Forzar sync desde UI o consola:

```bash
cd p3
vagrant ssh -c "export KUBECONFIG=/home/vagrant/.kube/config; kubectl -n argocd get application playground-demo -o wide"
vagrant ssh -c "export KUBECONFIG=/home/vagrant/.kube/config; kubectl -n argocd describe application playground-demo"
```

- Ver la app desde el host:

```bash
curl http://localhost:8888/
# Debe mostrar VERSION 2 después del push y sync
```

- Scripts útiles en el repo:
  - `bonus/scripts/create-gitlab-project-and-push.sh`
  - `bonus/scripts/push_initial_commit.sh`
  - `p3/scripts/create_argocd_secret_and_app.sh`
  - `p3/scripts/update-demo-to-v2.sh`

- Para convertir ArgoCD a usar SSH (deploy-key) automática: usa el script `p3/scripts/convert_repo_to_ssh_deploy_key.sh` (ver abajo).

-- Fin
