#!/bin/sh
# Crea (si no existen) los buckets que necesita GitLab en MinIO, con política
# privada. ACCESS_KEY y SECRET_KEY llegan como variables de entorno del
# contenedor (los fija scripts/install.sh al lanzar el pod)
mc alias set myminio http://gitlab-minio-svc.gitlab.svc:9000 "$ACCESS_KEY" "$SECRET_KEY" >/dev/null 2>&1

for b in registry git-lfs runner-cache gitlab-uploads gitlab-artifacts \
          gitlab-backups gitlab-packages tmp gitlab-mr-diffs \
          gitlab-terraform-state gitlab-ci-secure-files \
          gitlab-dependency-proxy gitlab-pages; do
    mc mb "myminio/$b" >/dev/null 2>&1 || true

    mc policy set none "myminio/$b" >/dev/null 2>&1 || mc policy none "myminio/$b" >/dev/null 2>&1 || true
done
