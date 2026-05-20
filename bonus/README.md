# Bonus: GitLab On-Premise y GitOps 100% Local

## Conceptos Clave
El Bonus lleva el ecosistema GitOps a su expresión máxima de seguridad y privacidad a nivel empresarial. En lugar de depender de servidores en la nube (GitHub), desplegamos nuestro propio sistema de repositorios y CI/CD internamente (**GitLab On-Premise**). 

1. **Independencia en la Nube**: Argo CD ya no dialoga con servidores externos. Se comunica de forma 100% interna dentro del mismo ecosistema local con nuestro propio GitLab.
2. **Despliegues Complejos mediante Helm**: Kubernetes puro con YAMLs está limitado. Para desplegar "monstruos" enormes como GitLab (que incluye base de datos PostgreSQL, Redis, servidor web, repositorios git...), usamos **Helm**: el gestor de paquetes de K8s. Es el equivalente a hacer un "apt-get install" pero para clusters completos.

> **⚠️ ADVERTENCIA DE RENDIMIENTO ⚠️**
> GitLab es extremadamente pesado. Para correrlo de forma aceptable hemos automatizado la VM para que le asigne **6 GB de RAM y 3 CPUs** de tu Mac.

## ¿Cómo levantar todo el ecosistema?
Al igual que en las fases anteriores, hemos introducido un **Vagrantfile automatizado Multi-Arquitectura** aquí también.

### Paso 1: Levantar la VM
```bash
cd bonus
vagrant up --provider=vmware_desktop  # O virtualbox si usas Linux
```

El script, sin que tú intercedas, instalará:
- Docker y K3d.
- El clúster `iot-bonus` vinculando puertos locales (8888 para la App, 80 para Gitlab).
- GitLab minimalista usando Helm.
- Argo CD y los despliegues pertinentes.

> *Nota: Esta es la VM más grande. Tarda unos 5-10 minutos en levantar completamente porque descargar y descomprimir todos los contenedores de GitLab toma su tiempo.*

### Paso 2: Aplicar Parches Post-Install (Automático)
`vagrant up` ya ejecuta automáticamente el post-install después de desplegar GitLab, así que no hace falta lanzar ningún comando extra. Si quieres entender qué hace cada parche, lee [**FIXES.md**](./FIXES.md).

### Paso 3: Configurar Host y Acceder
En **tu Mac** (host), añade la VM a `/etc/hosts`:
```bash
echo "192.168.56.110 gitlab.local" | sudo tee -a /etc/hosts
```

Abre el navegador a **http://gitlab.local**. Deberías ver el login de GitLab.

## Probarlo y jugar 
1. **Acceder a GitLab Local:** Navegarás a `http://gitlab.local` (tendremos que mapearlo en el `/etc/hosts` de tu Mac hacia la IP virtual `192.168.56.110` en vez de 127.0.0.1).
2. **Simular Día a Día:** Al igual que en la Parte 3, crearás un repositorio, pero esta vez dentro de este GitLab que tienes alojado tú mismo.
3. Subirás el código de tu web, apuntarás el `argocd.yaml` a la URL de este repo interno, y observarás cómo las actualizaciones viajan desde tu base de datos interna directamente al publicador en vivo. ¡El círculo cerrado empresarial perfecto!

## 🧹 Limpieza Obligatoria
Al ser una VM tan pesada (6GB RAM dedicados de forma exclusiva), **es crítico que destruyas el entorno al terminar** si no lo estás usando, porque secuestrará esa memoria aunque no hagas nada.
```bash
vagrant destroy -f
```
