# Module 2: Deployment with Terraform & Helm

## Step 1: เข้าใจโครงสร้าง Terraform

```
02-terraform-prometheus/
├── main.tf              ← Provider config + helm_release
├── outputs.tf           ← URL และ credentials
└── values/
    └── kube-prometheus-stack.yaml  ← Helm values แยกไฟล์
```

**ทบทวน:** ทำไม values ถึงแยกออกมาเป็นไฟล์ต่างหาก?
> เพราะ YAML อ่านง่ายกว่า HCL สำหรับ config ที่ซับซ้อน + สามารถ review diff ได้ง่ายกว่า

---

## Step 2: Initialize และ Deploy

```bash
cd 02-terraform-prometheus

# ดูว่า provider อะไรจะถูกติดตั้ง
terraform init

# ดูก่อนว่าจะสร้างอะไรบ้าง (ยังไม่ apply)
terraform plan

# Deploy! (รอประมาณ 3-5 นาที)
terraform apply
```

**สังเกต output ของ `terraform plan`:**
- `+ create` = จะสร้างใหม่
- `~ update` = จะอัปเดต (เห็น diff)
- `- destroy` = จะลบ

---

## Step 3: ตรวจสอบ Pods

```bash
# ดู Pods ทั้งหมดใน monitoring namespace
kubectl get pods -n monitoring

# รอให้ทุก Pod พร้อม
kubectl get pods -n monitoring -w

# ดู Events ถ้า Pod ไม่ขึ้น
kubectl describe pod -n monitoring <pod-name>
```

ผล output ที่คาดหวัง:
```
NAME                                                   READY   STATUS    RESTARTS
alertmanager-prometheus-kube-prometheus-alertmanager-0 2/2     Running   0
prometheus-grafana-xxx                                 3/3     Running   0
prometheus-kube-prometheus-operator-xxx                1/1     Running   0
prometheus-kube-prometheus-prometheus-0                2/2     Running   0
prometheus-kube-state-metrics-xxx                      1/1     Running   0
prometheus-prometheus-node-exporter-xxx (x3)           1/1     Running   0
```

---

## Step 4: ทดสอบ Ingress

**Linux / Mac:**
```bash
# เพิ่ม hosts ใน /etc/hosts (ทำครั้งเดียว)
echo "127.0.0.1 grafana.localhost prometheus.localhost alertmanager.localhost" | sudo tee -a /etc/hosts

# ทดสอบ curl
curl -s -o /dev/null -w "%{http_code}" http://grafana.localhost
# คาดหวัง: 200 หรือ 302
```

**Windows (PowerShell — Run as Administrator):**
```powershell
# เพิ่ม hosts ใน C:\Windows\System32\drivers\etc\hosts
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" `
  -Value "127.0.0.1 grafana.localhost prometheus.localhost alertmanager.localhost"

# ทดสอบ curl
curl -s -o NUL -w "%{http_code}" http://grafana.localhost
```

เปิด Browser:
- Grafana: http://grafana.localhost (admin / workshop2026)
- Prometheus: http://prometheus.localhost
- Alertmanager: http://alertmanager.localhost

---

## Step 5: สำรวจ Resource Limits และ Storage

```bash
# ดู Resource requests/limits ของ Prometheus
kubectl get pod -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0 \
  -o jsonpath='{.spec.containers[*].resources}' | jq

# ดู PersistentVolumeClaim
kubectl get pvc -n monitoring

# ดูขนาด storage ที่ใช้จริง
kubectl exec -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0 \
  -- df -h /prometheus
```

---

## Step 6: ทดลองแก้ Config ผ่าน Terraform

แก้ไขค่า retention ใน `values/kube-prometheus-stack.yaml`:

```yaml
# เปลี่ยนจาก 7d เป็น 14d
prometheusSpec:
  retention: 14d
```

แล้วรัน:
```bash
terraform plan    # เห็น diff ที่จะเปลี่ยน
terraform apply   # apply การเปลี่ยนแปลง
```

**Key Insight:** Terraform รู้ว่า Helm Release มีอยู่แล้ว จะทำ `helm upgrade` ไม่ใช่ `helm install` ใหม่

---

## Terraform State คืออะไร?

```bash
# ดู state ที่ Terraform เก็บไว้
terraform state list

# ดูรายละเอียดของ resource
terraform state show helm_release.kube_prometheus_stack

# ข้อมูล output
terraform output
terraform output -json grafana_credentials
```

**สำคัญ:** ไฟล์ `terraform.tfstate` เก็บ state ของระบบ ห้ามลบ!
ใน production ควรเก็บไว้ใน S3 / GCS (remote state)

---

## Troubleshooting

### Error: namespaces "monitoring" already exists

```
│ Error: namespaces "monitoring" already exists
│   with kubernetes_namespace.monitoring
```

**สาเหตุ:** Namespace ถูกสร้างไว้ก่อนแล้ว (เช่น สร้างด้วย kubectl) แต่ Terraform ไม่มีใน state

**แก้ไข:** Import namespace เข้า Terraform state แล้ว apply ใหม่

```bash
terraform import kubernetes_namespace.monitoring monitoring
terraform apply
```

**ทำความเข้าใจ:** `terraform import` ดึง resource ที่มีอยู่แล้วใน cluster เข้ามาอยู่ใน state  
หลังจาก import แล้ว Terraform จะ manage namespace นั้นได้ปกติ

---

### Error: Helm release อื่นๆ

```bash
# Helm release status
helm status prometheus -n monitoring

# ดู logs ของ Prometheus
kubectl logs -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0 \
  -c prometheus --tail=50

# ดู logs ของ Grafana
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=50
```

**ถ้า Ingress ไม่ทำงาน ใช้ port-forward แทน:**

Linux / Mac — รันใน background terminal:
```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093 &
```

Windows (PowerShell) — เปิด Terminal แยกสำหรับแต่ละคำสั่ง:
```powershell
# Terminal 1
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Terminal 2
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Terminal 3
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093
```

---

**[Module 3: Grafana & PromQL](../03-grafana-promql/workshop-guide.md)**