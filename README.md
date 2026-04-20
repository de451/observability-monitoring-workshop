# Kubernetes Observability & Monitoring with IaC

> **เครื่องมือหลัก:** Terraform, Prometheus, Grafana, Loki, Alertmanager  
> **Cluster:** k3d local

---

## โครงสร้างหลักสูตร

```
Foundation & Metrics Monitoring
├── Module 1: Modern Observability Architecture
├── Module 2: Deployment with Terraform & Helm
└── Module 3: Grafana & PromQL

Alerting, Logging & Maintenance
├── Module 4: Intelligent Alerting System
├── Module 5: Centralized Logging with Loki
└── Module 6: Long-term Storage & Final Demo
```

---

## การเตรียม Cluster

```bash
k3d cluster create workshop \
  --servers 1 \
  --agents 2 \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer" \
  --k3s-arg "--kube-controller-manager-arg=node-monitor-grace-period=30s@server:*" \
  --k3s-arg "--kube-apiserver-arg=default-not-ready-toleration-seconds=30@server:*" \
  --k3s-arg "--kube-apiserver-arg=default-unreachable-toleration-seconds=30@server:*" \
  --k3s-arg "--node-taint=node-role.kubernetes.io/control-plane=true:NoSchedule@server:*"

kubectl create namespace workshop

kubectl config set-context --current --namespace=workshop
```

## Prerequisites

```bash
# ตรวจสอบเครื่องมือที่จำเป็น
terraform version   # >= 1.6
kubectl version     # >= 1.28
helm version        # >= 3.12
k3d version         # >= 5.6
```

### การติดตั้งบน Windows

ติดตั้งผ่าน [winget](https://learn.microsoft.com/en-us/windows/package-manager/) (Windows Package Manager):
```powershell
winget install Hashicorp.Terraform
winget install Kubernetes.kubectl
winget install Helm.Helm
winget install k3d
winget install jqlang.jq        # ใช้ใน Module 5-6
```

หรือผ่าน [Chocolatey](https://chocolatey.org/):
```powershell
choco install terraform kubectl kubernetes-helm k3d jq
```

> **หมายเหตุ Windows:**
> - คำสั่งที่ใช้ `\` ต่อบรรทัด ให้เปลี่ยนเป็น `` ` `` (backtick) ใน PowerShell
> - คำสั่งที่ใช้ `$VAR="value"` ให้เปลี่ยนเป็น `$env:VAR = "value"` หรือ `$VAR = "value"`
> - คำสั่งที่ใช้ `cmd &` (background) ให้เปิด Terminal แยกแทน
> - `open http://...` → `start http://...`
> - `grep "pattern"` → `Select-String -Pattern "pattern"`
> - `tail -N` → `Select-Object -Last N`
> - Workshop guide แต่ละ module มีคำสั่ง Windows (PowerShell) แยกไว้แล้ว

---

**[Module 1: Modern Observability Architecture](./01-observability-concepts/workshop-guide.md)**