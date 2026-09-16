# VM "puesto de trabajo" para la evaluación (Plan B)

Cómo preparar y usar la máquina virtual **`iot-workstation`**.

**No sustituye al flujo normal del proyecto** dentro de esta VM se sigue exactamente el `README.md` de cada parte (`p1`, `p2`, `p3`, `bonus`).

---

## Vias para iniciar el proyecto

Dentro de `iot-workstation` vas a volver a usar VirtualBox (para levantar las VMs reales de `p1`/`p2`/`p3`). Eso es virtualización anidada, y **no viene activada por defecto**. El comando exacto depende de qué vía de arranque uses (sección 3):

- **Vía A (QEMU directo)**: pasar `-enable-kvm -cpu host` al arrancar, y que el host tenga el anidado de KVM activado (comprobar con `cat /sys/module/kvm_intel/parameters/nested` en Intel, o `kvm_amd` en AMD — debe mostrar `Y`).

- **Vía B (import en VirtualBox)**: `VBoxManage modifyvm "iot-workstation" --nested-hw-virt on` (ya incluido en `register-workstation-vm.sh`).


**Conflicto real (solo Vía A, QEMU): KVM vs VirtualBox por la extensión de hardware.** Con `-cpu host`, el host real pasa AMD-V/VT-x a `iot-workstation`, y su kernel carga `kvm_amd`/`kvm_intel` automáticamente sin pedirlo. Cuando VirtualBox intenta arrancar `mlezcanoS`, su módulo `vboxdrv` no puede coger esa misma extensión (ya la tiene `kvm_amd`) y falla con `VERR_SVM_IN_USE` (o el equivalente Intel). Arreglo, **dentro de `iot-workstation`**, una sola vez (queda fijo en el disco, no hace falta repetirlo el día D):
```bash
sudo rmmod kvm_amd kvm_intel kvm 2>/dev/null   # descarga lo que esté cargado ahora
echo -e "blacklist kvm_amd\nblacklist kvm_intel\nblacklist kvm" | sudo tee /etc/modprobe.d/blacklist-kvm.conf
sudo update-initramfs -u
```
Dentro de esta VM nunca hace falta KVM (solo VirtualBox), así que bloquearlo aquí no tiene contrapartida.

## Pasos para preparar la VM en el campus

Crear la carpeta sgoinfre para poder usar la VM y protegerla:

```bash
mkdir /sgoinfre/students/mlezcano
chmod 700 /sgoinfre/students/mlezcano
```
Después copiamos la carpeta con la VM aprovisionada en el pendrive, al disco local.

**NOTA: No se puede guardar más de 15G en la carpeta**

**Tamaño del fichero y USB en exFAT/FAT32**: `discard=unmap,detect-zeroes=unmap` en el comando de abajo hace que, si dentro de la VM borras algo y ejecutas `sudo fstrim -av`, el hueco se libere también en el propio `.qcow2` — sin esto, el fichero solo crece y nunca encoge, aunque por dentro esté prácticamente vacío. Aun así, un `.qcow2` disperso (con huecos) puede copiarse "a su tamaño aparente completo" si el USB está en exFAT/FAT32 (no soportan ficheros dispersos). Para evitarlo, antes de copiar al USB, compacta a un fichero nuevo de tamaño real:
```bash
qemu-img convert -O qcow2 -c iot-workstation.qcow2 iot-workstation-compact.qcow2
# comprobar que arranca bien (sección de abajo) antes de sustituir el original
mv iot-workstation-compact.qcow2 iot-workstation.qcow2
```


### Vía A — QEMU directo

```bash
qemu-system-x86_64 \
  -enable-kvm -cpu host \
  -m 12288 -smp 4 \
  -drive file=iot-workstation.qcow2,if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:12222-:22 -device virtio-net-pci,netdev=net0 \
  -device virtio-vga,xres=1920,yres=1080 -display gtk
```

Ajustar `-m`/`-smp` si el ordenador del campus tiene menos recursos disponibles (necesarios para el escritorio + Vagrant/VirtualBox anidado + `p3`, que por sí solo pide 8GB). Si `-enable-kvm` falla (KVM no disponible/sin permisos), quitar `-enable-kvm -cpu host` y usar `-accel tcg -cpu max` en su lugar — funciona igual pero mucho más lento (emulación por software).

> Red: usa `-device virtio-net-pci` (no `-net nic` a secas, que emula un e1000 real) — bajo TCG, emular un e1000 de verdad paquete a paquete es lentísimo y puede convertir una descarga de unos cientos de MB en horas. `virtio-net` es mucho más ligero de emular y da velocidades razonables incluso sin KVM.

> El puerto `2222` a secas falla al reservarlo en algunos entornos aunque esté libre (nos pasó en el Mac de construcción) — usar `12222` con bind explícito a `127.0.0.1` como arriba lo evita. Si `12222` también fallara, prueba con cualquier otro puerto alto (`13022`, `50022`...).

**Credenciales de acceso** — usuario `iot`, contraseña `iot`. 
Sirven tanto para la pantalla de login gráfico que aparece en la propia ventana de QEMU, como por SSH:

```bash
ssh -p 12222 iot@127.0.0.1
```

En la pantalla de login gráfico: escribe `iot` en el campo de usuario, pulsa Intro (o Tab), y luego `iot` en el de contraseña. Si da "Your password is incorrect": revisa que no se haya activado Bloq Mayús y que el teclado emulado por QEMU no esté metiendo algún carácter raro (pasa a veces con distribuciones de teclado no-US) — como comprobación fiable, prueba primero el `ssh` de arriba con las mismas credenciales; si el SSH sí entra pero el login gráfico no, el problema es del teclado emulado en la ventana de QEMU, no de la contraseña en sí. Si hiciera falta, puedes resetearla desde el SSH ya dentro: `sudo passwd iot`.

**Para probar esto mismo en Mac**

```bash
qemu-system-x86_64 \
  -accel tcg -cpu max \
  -m 4096 -smp 4 \
  -drive file=iot-workstation.qcow2,if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:12222-:22 -device virtio-net-pci,netdev=net0 \
  -device virtio-vga,xres=1920,yres=1080 -display cocoa
```

> Resolución de la ventana: `-device virtio-vga,xres=1920,yres=1080` fija esa resolución al arrancar (cambia los números si tu pantalla es distinta, p. ej. `2560,1440`). Si aun así aparece pequeña o quieres cambiarla ya con la VM arrancada, dentro del escritorio XFCE: `Aplicaciones → Configuración → Pantalla`, o por terminal con `xrandr` (`xrandr` sin argumentos lista los modos disponibles, luego `xrandr --output <salida> --mode <modo>`).

### Vía B — Importar en VirtualBox

El disco es un `.qcow2` (formato que VirtualBox acepta de forma nativa, sin convertir). El script `register-workstation-vm.sh` (en la misma carpeta que el disco) crea la VM, adjunta el disco, activa `--nested-hw-virt on` y reserva RAM/CPU, todo de una vez:

```bash
cp -r /ruta/al/usb/iot-workstation-vm ~/iot-workstation-vm
cd ~/iot-workstation-vm

./register-workstation-vm.sh ~/iot-workstation-vm/iot-workstation.qcow2

VBoxManage startvm iot-workstation --type gui
```

Ajustar `--memory`/`--cpus` dentro de `register-workstation-vm.sh` si hace falta. A mano en vez de con el script: `VBoxManage createvm --register` + `VBoxManage storagectl`/`storageattach` (adjuntando el `.qcow2` como `--type hdd`) + `VBoxManage modifyvm --nested-hw-virt on` — o el equivalente gráfico en VirtualBox Manager (`New...` → "usar un disco duro virtual existente" → seleccionar el `.qcow2` → `Settings → System → Processor` → *Enable Nested VT-x/AMD-V*).

## 4. Acceder por SSH

Además de la ventana gráfica, puedes entrar por SSH desde una terminal del host — útil para copiar el repo o para trabajar por terminal en vez de por el escritorio. El puerto depende de qué vía de arranque usaste (sección 3):

```bash
# Vía A (QEMU directo) -- puerto 12222
ssh -p 12222 iot@127.0.0.1

# Vía B (VirtualBox, register-workstation-vm.sh) -- puerto 2222
ssh -p 2222 iot@127.0.0.1
```

Usuario `iot`, contraseña `iot`.

**Si aparece "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!" o "Host key verification failed":** es normal tras reiniciar la VM, recrearla, o cambiar de vía de arranque (cada arranque desde cero genera una identidad SSH nueva). Elimina la entrada antigua de ese puerto en tu `known_hosts` y reintenta:
```bash
ssh-keygen -R "[127.0.0.1]:12222"   # o el puerto que corresponda (2222 en la Vía B)
ssh -p 12222 iot@127.0.0.1
```

## 5. Meter el proyecto dentro

Una vez arrancada y con sesión en el escritorio XFCE (usuario `iot`):

```bash
# En el host (tu Mac ahora para probar; el ordenador del campus el día D), dentro del repo:
git archive --format=tar.gz -o /tmp/proyecto.tar.gz HEAD

# Copiar ese único fichero a la VM (puerto 12222 en la Vía A/QEMU; 2222 en la Vía B/VirtualBox):
scp -P 12222 /tmp/proyecto.tar.gz iot@127.0.0.1:~/

# Dentro de la VM: descomprimirlo
mkdir -p ~/inception-of-things-42 && tar xzf ~/proyecto.tar.gz -C ~/inception-of-things-42
```

## 6. Ejecutar el proyecto

Desde un terminal **dentro** de `iot-workstation` (XFCE → Terminal), exactamente igual que en el `README.md` de cada parte:

```bash
cd inception-of-things-42/p1
vagrant up
# ... seguir el README normal desde aquí
```

Los `Vagrantfile` del proyecto ya detectan Linux automáticamente y usan `virtualbox` como provider — no hace falta tocar nada.

**Importante — precachear el box de Vagrant ahora, no el día D**: la primera vez que hagas `vagrant up` en cualquier parte, Vagrant descarga el box `bento/debian-13` (unos cientos de MB) desde Vagrant Cloud si no lo tiene ya en `~/.vagrant.d/boxes/` dentro de esta misma VM. Como ese caché vive en el propio disco `iot-workstation.qcow2`, **si lo descargas ahora (probando) se queda guardado para siempre en la VM** — el día de la evaluación ya no hará falta volver a descargarlo, sea cual sea la velocidad de red del campus. Hazlo con margen antes del día D, no lo dejes para ese momento.

## 7. Al terminar: eliminar la VM del ordenador del campus

No es tu máquina — conviene no dejar rastro. `teardown-workstation-vm.sh` (misma carpeta) para la VM (por cualquiera de las dos vías) y borra la copia local hecha en el disco del campus:

```bash
./teardown-workstation-vm.sh
```
