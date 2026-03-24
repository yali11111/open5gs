#!/bin/bash
set -e

echo "===== Open5GS + Minikube + Xtesting Setup ====="

# -----------------------------
# 1. Install prerequisites
# -----------------------------
echo "[1/5] Installing dependencies..."
if ! command -v minikube &> /dev/null; then
    echo "Installing Minikube..."
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
fi

if ! command -v kubectl &> /dev/null; then
    echo "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
fi

if ! command -v xtesting &> /dev/null; then
    echo "Installing Xtesting..."
    pip3 install --user xtesting
    export PATH=$PATH:$HOME/.local/bin
fi

# -----------------------------
# 2. Start Minikube
# -----------------------------
echo "[2/5] Starting Minikube..."
minikube start --driver=docker

# -----------------------------
# 3. Deploy Open5GS
# -----------------------------
echo "[3/5] Deploying Open5GS..."

mkdir -p ~/open5gs-minikube
cd ~/open5gs-minikube

cat <<EOF > open5gs.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: open5gs-amf
spec:
  replicas: 1
  selector:
    matchLabels:
      app: amf
  template:
    metadata:
      labels:
        app: amf
    spec:
      containers:
      - name: amf
        image: open5gs/open5gs:latest
        command: ["open5gs-amfd"]
---
apiVersion: v1
kind: Service
metadata:
  name: amf-service
spec:
  type: NodePort
  selector:
    app: amf
  ports:
    - port: 38412
      targetPort: 38412
      nodePort: 30007
EOF

kubectl apply -f open5gs.yaml

# -----------------------------
# 4. Wait for pods
# -----------------------------
echo "[4/5] Waiting for Open5GS pods to be ready..."
kubectl wait --for=condition=ready pod -l app=amf --timeout=120s

# -----------------------------
# 5. Xtesting functional test
# -----------------------------
echo "[5/5] Preparing Xtesting..."
mkdir -p ~/open5gs-minikube/tests
cat <<EOF > ~/open5gs-minikube/tests/test_open5gs_amf.py
from xtesting.core.testcase import TestCase
import subprocess

def run_cmd(cmd):
    return subprocess.check_output(cmd, shell=True, text=True)

class Open5GS_AMF_Test(TestCase):
    def run(self):
        pods = run_cmd("kubectl get pods")
        if "open5gs-amf" in pods:
            desc = run_cmd("kubectl get svc amf-service")
            if "30007" in desc:
                self.result = 100
                return 0
        self.result = 0
        return 1
EOF

cat <<EOF > ~/open5gs-minikube/xtesting.yaml
project: open5gs-minikube
case_dir: ./tests
testcases_file: testcases.yaml
EOF

cat <<EOF > ~/open5gs-minikube/testcases.yaml
tiers:
  - name: k8s
    testcases:
      - case_name: open5gs.amf
        project_name: open5gs-minikube
        run:
          module: tests.test_open5gs_amf
EOF

cd ~/open5gs-minikube
xtesting

echo "===== DONE: Open5GS deployed & tested on Minikube ====="
