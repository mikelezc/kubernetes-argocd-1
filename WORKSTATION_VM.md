# Instalar iot-workstation en el campus — guía rápida (para mí)

Todo está en `/Users/miguel/Desktop/iot-workstation-vm/` (llevar al USB, **sin** `iot-workstation.qcow2.bak`, no hace falta):
`iot-workstation.qcow2`, `register-workstation-vm.sh`, `teardown-workstation-vm.sh`

---

## 1. Copiar del USB al disco local

```bash
mkdir /sgoinfre/students/mlezcano
chmod 700 /sgoinfre/students/mlezcano
cp -r /ruta/al/usb/iot-workstation-vm /sgoinfre/students/mlezcano/
cd /sgoinfre/students/mlezcano/iot-workstation-vm
```
- `mkdir` + `chmod 700`: crea mi carpeta y la deja privada (solo yo puedo entrar).
- `cp -r`: copia la carpeta entera del USB al disco del ordenador (arrancar desde el USB directamente va más lento).
- Límite de la carpeta: 15GB. El disco pesa 2.8GB, sobra margen.

---

## 2. Arrancar la VM

```bash
qemu-system-x86_64 \
  -enable-kvm -cpu host \
  -m 12288 -smp 4 \
  -drive file=iot-workstation.qcow2,if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:12222-:22 -device virtio-net-pci,netdev=net0 \
  -device virtio-vga,xres=1920,yres=1080 -display gtk
```

Qué hace cada trozo:
- `-enable-kvm -cpu host` → usa la CPU real del ordenador (rápido). Si da error, quitar esto y poner `-accel tcg -cpu max` (funciona pero muy lento — último recurso).
- `-m 12288 -smp 4` → le da 12GB de RAM y 4 CPUs a la VM. Bajar el número si el ordenador tiene menos.
- `-drive file=...` → el disco de la VM (el `.qcow2`).
- `-netdev ... hostfwd=tcp:127.0.0.1:12222-:22` → abre el puerto 12222 en el ordenador para poder hacer SSH a la VM. Si falla al reservar el puerto, probar con otro número (`13022`, etc.).
- `-device virtio-vga,xres=1920,yres=1080` → tamaño de la ventana. Cambiar los números si la pantalla es otra.
- `-display gtk` → abre la ventana con el escritorio.

**Login**: usuario `iot`, contraseña `iot` (vale tanto en la ventana como por SSH).

---

## 3. Meter el proyecto dentro

En el ordenador (fuera de la VM), dentro de la carpeta del repo:
```bash
git archive --format=tar.gz -o /tmp/proyecto.tar.gz HEAD
scp -P 12222 /tmp/proyecto.tar.gz iot@127.0.0.1:~/
```
- `git archive` → empaqueta el proyecto en un único fichero (sin arrastrar `.git`, que pesa de más).
- `scp` → copia ese fichero dentro de la VM por el puerto que abrimos en el paso 2.

Dentro de la VM:
```bash
mkdir -p ~/inception-of-things-42 && tar xzf ~/proyecto.tar.gz -C ~/inception-of-things-42
```
Descomprime el proyecto ahí dentro.

---

## 4. Ejecutar el proyecto

```bash
cd inception-of-things-42/p1
vagrant up
```
A partir de aquí, seguir el `README.md` normal de cada parte (`p1`, `p2`, `p3`, `bonus`) — sin nada especial por usar esta VM.

---

## 5. Si algo falla: plan B con VirtualBox en vez de QEMU

```bash
./register-workstation-vm.sh /sgoinfre/students/mlezcano/iot-workstation-vm/iot-workstation.qcow2
VBoxManage startvm iot-workstation --type gui
```
El script hace todo solo (crea la VM, activa la virtualización anidada, reserva RAM/CPU). SSH sería `ssh -p 2222 iot@127.0.0.1` (puerto distinto al de QEMU).

---

## 6. Al terminar

```bash
./teardown-workstation-vm.sh
```
Apaga y borra la VM y la copia local — no dejar nada en el ordenador del campus.
