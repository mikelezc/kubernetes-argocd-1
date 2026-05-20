#!/bin/bash
set -euo pipefail

export KUBECONFIG=${KUBECONFIG:-/home/vagrant/.kube/config}

EXTRA_LINE="192.168.56.111 gitlab.local"

COREFILE=$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')
NODEHOSTS=$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.NodeHosts}')

TMPF=$(mktemp)
# Indent Corefile and NodeHosts content for YAML block scalar
IND_CORE=$(printf "%s\n" "$COREFILE" | sed 's/^/    /')
IND_NODE=$(printf "%s\n" "$NODEHOSTS" | sed 's/^/    /')
cat > "$TMPF" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
$IND_CORE
  NodeHosts: |
$IND_NODE
    $EXTRA_LINE
EOF

kubectl apply -f "$TMPF"
rm -f "$TMPF"

kubectl -n kube-system rollout restart deployment/coredns
kubectl -n kube-system rollout status deployment/coredns --timeout=60s || true

echo "CoreDNS NodeHosts updated"
