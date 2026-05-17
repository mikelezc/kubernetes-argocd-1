# Parte 2: K3s y 3 Aplicaciones Web Básicas

## ¿Qué hacemos aquí?
En lugar de dos máquinas, ahora sólo tenemos **1 Servidor K3s**. El objetivo es levantar dentro del clúster de Kubernetes 3 aplicaciones diferentes, y aprender qué es un **Ingress** o puerta de entrada.

### ¿Cómo funciona el Ingress?
Dependiendo de qué dirección escribamos en el navegador o en la consola para acceder a la IP del servidor (`192.168.56.110`), Kubernetes nos enviará a una u otra aplicación:
- Si pides **app1.com** 👉 vas a la aplicación 1.
- Si pides **app2.com** 👉 vas a la aplicación 2 (esta tendrá 3 réplicas corriendo a la vez 🚀).
- Si pides **cualquier otra cosa** 👉 vas a la aplicación 3.

## Cómo ejecutarlo
1. Levanta la máquina desde esta carpeta:
   ```bash
   vagrant up
   ```
2. El script de aprovisionamiento instalará K3s y aplicará automáticamente todos los `.yaml` de la carpeta `confs/`.

## Cómo probarlo desde tu Mac
No necesitas entrar con `vagrant ssh`. Como la máquina se enciende y da servicio en una IP virtual compartida con tu Mac, simplemente escribe en otra terminal en tu Mac:

```bash
# Probar App1
curl -H "Host: app1.com" http://192.168.56.110

# Probar App2
curl -H "Host: app2.com" http://192.168.56.110

# Probar App3 (por defecto)
curl -H "Host: cuenca.com" http://192.168.56.110
```
La bandera `-H "Host: ..."` simula que desde el navegador hemos escrito esa dirección en lugar de la IP. El Ingress de Kubernetes atrapa esa petición y redirige el tráfico sabiamente.
