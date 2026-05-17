# Parte 1: K3s y Vagrant

## ¿Qué hacemos aquí?
El objetivo es crear un pequeño "cluster" (conjunto de máquinas) compuesto por:
- **Server (Controller)**: El jefe. Controla y administra el ecosistema.
- **Worker (Agent)**: El peón. Ejecuta las aplicaciones que el jefe le ordena.

## Requisitos de la Práctica
- Máquina 1 (Server): Hostname `miguelS`, IP: `192.168.56.110`.
- Máquina 2 (Worker): Hostname `miguelSW`, IP: `192.168.56.111`.
- K3s en modo *controller* en el Server, K3s en modo *agent* en el Worker.

## ¿Cómo ejecutarlo?
1. Abre tu terminal.
2. Entra en esta carpeta (`cd p1`).
3. Ejecuta vagrant para levantar ambas máquinas:
   ```bash
   vagrant up
   ```
4. Vagrant descargará el sistema operativo, creará las máquinas virtuales y ejecutará los scripts (`scripts/server.sh` y `scripts/worker.sh`).
5. Tras unos minutos, puedes entrar al servidor para verificar:
   ```bash
   vagrant ssh miguelS
   # Una vez dentro, comprueba que los dos nodos están conectados:
   kubectl get nodes
   ```
   Deberías ver `miguelS` (rol: control-plane) y `miguelSW` (rol: <none>).
