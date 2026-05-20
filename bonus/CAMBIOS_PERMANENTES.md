# Resumen de Cambios Permanentes - Bonus Setup

**Fecha:** 20 de Mayo de 2026  
**Estado:** ✅ GitLab + ArgoCD Funcional en K3d (ARM64)

## Archivos Modificados

| Archivo | Cambio | Razón |
|---------|--------|-------|
| `bonus/Vagrantfile` | ↑ 6GB → 8GB RAM | Evitar "Insufficient memory" en pods GitLab |
| `bonus/confs/gitlab-values.yaml` | Añadió `gitlab.minio.image` con `minio/minio:latest` | Compatibilidad ARM64 |
| `bonus/scripts/post-install.sh` | Nuevo script | Automatizar parches post-vagrant up |
| `bonus/FIXES.md` | NUEVO archivo | Documentación de problemas y soluciones |
| `bonus/README.md` | Actualizado | Pasos claros para futuro `vagrant up` |

## Cambios Técnicos (Resumen Rápido)

### 1. Vagrantfile (Líneas 17-22)
```ruby
v.memory = 8192      # Era 6144
v.vmx["memsize"] = "8192"  # Era "6144"
```

### 2. gitlab-values.yaml (Líneas 25-34)
```yaml
gitlab:
  minio:
    image:
      repository: minio/minio
      tag: latest
```

### 3. Post-Install Script (Nuevo)
- Parchea ingress a clase `traefik`
- Crea buckets MinIO automáticamente
- Se ejecuta automáticamente desde `bonus/Vagrantfile` después de `scripts/install.sh`
- Fallback manual: `vagrant ssh -c 'bash /vagrant/scripts/post-install.sh'`

## Validación Final

✅ 12 pods en estado `Running` o `Completed`  
✅ 0 pods en `CrashLoopBackOff`, `Pending` o `Error`  
✅ `gitlab.local` responde con `302 Found` (login correcto)  
✅ MinIO operativo con `minio/minio:latest`  
✅ Buckets creados y accesibles  

## Para Próximos `vagrant up`

```bash
cd bonus
vagrant up --provider=vmware_desktop

# Esperar a que termine; el post-install ya se ejecuta solo

# Desde el host:
echo "192.168.56.110 gitlab.local" | sudo tee -a /etc/hosts

# Acceder:
open http://gitlab.local
```

## Documentación Adicional

- **[FIXES.md](./FIXES.md)** — Detalles técnicos de cada problema y solución
- **[README.md](./README.md)** — Guía de usuario actualizada

---

**Notas para el futuro:**
- La VM ahora requiere 8GB de RAM de forma exclusiva
- Si necesitas reducir recursos, edita `gitlab-values.yaml` y ejecuta `helm upgrade`
- El release Helm quedó en `pending-rollback` pero es estado residual sin efecto
