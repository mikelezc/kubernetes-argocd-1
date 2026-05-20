# 📋 DEMO CHECKLIST - Bonus GitLab + ArgoCD

## Estado: ✅ LISTO PARA EVALUACIÓN

Toda la automatización fue completada. A continuación están los pasos que se ejecutaron automáticamente.

---

## ✅ Que Fue Hecho Automáticamente

### 1. **Proyecto GitLab Creado**
- Nombre: `playground-demo`
- URL: `http://gitlab.local/root/playground-demo.git`
- Contenido inicial: `deployment.yaml` con imagen `playground:v1`

### 2. **ArgoCD Configurado**
- Secret de autenticación: token PAT (`a214cd7dc135d9264368f9f1122d530f`)
- Application creada: `playground-demo`
- Sincronización automática: **ACTIVADA** (reconcilia cada cambio en el repo)

### 3. **DNS del Cluster P3**
- CoreDNS actualizado para resolver `gitlab.local` → `192.168.56.111` (VM bonus)
- Permite que ArgoCD (corriendo en p3) acceda a GitLab (bonus)

### 4. **Demo v1 → v2 Ejecutada**
- ✅ Cambio committed y pushed a GitLab: `playground:v1` → `playground:v2`
- ✅ ArgoCD detectó el cambio automáticamente
- ✅ Pod actualizado y aplicación sirviendo v2 en `http://localhost:8888`

---

## 🎯 Para el Día de Evaluación

### Pasos Simples para Demostrar GitOps:

1. **Abrir tab del navegador (macOS):**
   ```
   http://localhost:8888
   ```
   → Deberías ver: **"🔵 VERSION 2"**

2. **Explicar a los evaluadores:**
   > "El deployment se actualiza automáticamente desde el repositorio de GitLab. Cambié la versión de `v1` a `v2` en el archivo `deployment.yaml` en GitLab, y ArgoCD lo detectó automáticamente sin necesidad de `kubectl apply` manual."

3. **(Opcional) Mostrar el repositorio:**
   - Abre: `http://gitlab.local/root/playground-demo`
   - Login: `root` / `aUlgEQ36uZTB57wJQsDPTrGc1AmRQ7DYKppXmORkTSzNyNPUT2ei3Kp0Jw8rR4Uy%`
   - Ve el archivo `deployment.yaml` con la versión v2

4. **(Opcional) Mostrar ArgoCD:**
   - Abre: `http://localhost:8080`
   - Application: `playground-demo` (sync status debe mostrar "Synced" o "OutOfSync" dependiendo de si hay cambios)

---

## 🔑 Credenciales Importantes

| Servicio | URL | Usuario | Contraseña / Token |
|----------|-----|---------|-------------------|
| **GitLab** | http://gitlab.local | `root` | `aUlgEQ36uZTB57wJQsDPTrGc1AmRQ7DYKppXmORkTSzNyNPUT2ei3Kp0Jw8rR4Uy%` |
| **ArgoCD** | http://localhost:8080 | `admin` | (ver logs o secret) |
| **App v2** | http://localhost:8888 | — | — |

---

## 📁 Scripts Utilizados (Automatización Backend)

Todos los scripts ya fueron ejecutados. Para referencia:

1. `bonus/scripts/push_initial_commit.sh` — Creó repo y pusheó v1  
2. `p3/scripts/create_argocd_secret_and_app.sh` — Configuró ArgoCD  
3. `p3/scripts/append_coredns_nodehosts.sh` — Resolvió DNS  
4. `p3/scripts/update-demo-to-v2.sh` — Cambió a v2  

Todos completados. ✅

---

## ⚠️ Notas Técnicas

- **Ambas VMs están levantadas simultáneamente** sin conflictos (bonus en `192.168.56.111`, p3 en `192.168.56.110`).
- **Los clusters NO comparten kubeconfig** — p3 apunta a `iot-cluster`, bonus a `iot-bonus`.
- **GitLab se comunica via HTTP local** (no HTTPS; usamos `insecure` en ingress).
- **PAT Token** fue necesario porque GitLab v18+ requiere token en lugar de contraseña para HTTP Git.

---

## 🚀 Próximas Encarnaciones (si reinicias)

Si destruyes y recreas la VM, los scripts volverán a ejecutarse automáticamente porque el `Vagrantfile` las llama en los provisioners. El único paso manual será: **copiar la contraseña root del output y usarla si necesitas acceso manual a GitLab**.

