# Dockerfile multi-arquitectura (ARM64/AMD64)
FROM python:3.9-slim

ARG VERSION=v1
ENV VERSION=${VERSION}

WORKDIR /app
COPY app.py /app/
EXPOSE 8888
CMD ["python", "/app/app.py"]
