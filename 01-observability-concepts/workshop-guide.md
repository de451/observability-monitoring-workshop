# Module 1: Modern Observability Architecture

## 1.1 Observability Pillars ในยุค 2026

Observability คือความสามารถในการเข้าใจสถานะภายในของระบบจากข้อมูลที่ระบบส่งออกมา มี 3 ข้อหลัก:

```
┌─────────────────────────────────────────────────────────┐
│                  Observability Pillars                  │
├──────────────┬──────────────────┬───────────────────────┤
│   METRICS    │      LOGS        │       TRACES          │
│              │                  │                       │
│ ตัวเลขวัดผล    │ บันทึกเหตุการณ์      │ ติดตามการไหลของ Request│
│ ตลอดเวลา     │ ที่เกิดขึ้น           │ ข้ามหลาย Services      │
│              │                  │                       │
│ Prometheus   │ Grafana Loki     │ Jaeger / Tempo        │
│ PromQL       │ LogQL            │ OpenTelemetry         │
└──────────────┴──────────────────┴───────────────────────┘
```

### คำถามที่แต่ละ Pillar ให้คำตอบได้

| คำถาม | Pillar |
|-------|--------|
| CPU ของ Pod A ใช้เท่าไร? | Metrics |
| Error อะไรเกิดขึ้นเมื่อ 3 นาทีที่แล้ว? | Logs |
| Request ช้าเกิดที่ Service ไหน? | Traces |
| ระบบตอบสนองช้าตั้งแต่เมื่อไร? | Metrics + Logs |

---

## 1.2 สถาปัตยกรรม Prometheus Ecosystem

```
┌─────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                     │
│                                                         │
│  ┌──────────┐    scrape    ┌──────────────────────────┐ │
│  │  Pods /  │ ──────────►  │      Prometheus          │ │
│  │  Nodes   │              │  (Time-Series Database)  │ │
│  └──────────┘              └─────────┬────────────────┘ │
│                                      │ query            │
│  ┌──────────┐    push     ┌──────────▼───────────────┐  │
│  │ Pushgate │ ──────────► │       Grafana            │  │
│  │   way    │             │    (Visualization)       │  │
│  └──────────┘             └──────────────────────────┘  │
│                                       │ alert           │
│  ┌──────────────────────────────────► │                 │
│  │           AlertManager             │                 │
│  │    (Route → Telegram/Slack/Email)  │                 │
│  └────────────────────────────────────┘                 │
└─────────────────────────────────────────────────────────┘
```

### kube-prometheus-stack รวมอะไรบ้าง?

```bash
# เพิ่ม repo ก่อน (ทำครั้งเดียว)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# ดู top-level keys ของ chart values
helm show values prometheus-community/kube-prometheus-stack | grep -E "^[a-z]" | head -30
```

Windows (PowerShell):
```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm show values prometheus-community/kube-prometheus-stack | Select-String -Pattern "^[a-z]" | Select-Object -First 30
```

Component หลักที่ติดมาด้วย:
- **Prometheus** — เก็บ metrics
- **Alertmanager** — จัดการ alerts
- **Grafana** — visualize
- **kube-state-metrics** — ดู state ของ K8s objects
- **node-exporter** — ดู metrics ของ Node (CPU, RAM, Disk)
- **Prometheus Operator** — จัดการ Prometheus ผ่าน CRD

---

## 1.3 ทำไมต้องใช้ Terraform? (Observability as Code)

### ปัญหาของการ Deploy ด้วย Helm ตรงๆ

```bash
# วิธีเดิม — ไม่รู้ว่าใครเปลี่ยนอะไร เมื่อไร
helm install prometheus prometheus-community/kube-prometheus-stack \
  --set grafana.adminPassword=secret123 \
  --set prometheus.prometheusSpec.retention=7d
```

**ปัญหา:**
- ไม่มี state management (ไม่รู้ config ปัจจุบันคืออะไร)
- ไม่มี version history
- ยากต่อการ review การเปลี่ยนแปลง
- ทำซ้ำใน environment อื่นยาก

### วิธีใหม่ด้วย Terraform

```hcl
# เห็นชัดว่าระบบ monitoring มี config อะไรบ้าง
resource "helm_release" "prometheus" {
  name    = "prometheus"
  version = "65.1.1"           # pinned version
  
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "7d"               # retention policy ชัดเจน
  }
}
```

**ประโยชน์:**
- `terraform plan` — เห็นก่อนว่าจะเปลี่ยนอะไร
- `terraform state` — รู้ state ปัจจุบันเสมอ
- Git history — ดูได้ว่าใครเปลี่ยนอะไรเมื่อไร
- `terraform destroy` — ลบทุกอย่างได้ครบถ้วน

---

## 1.4 Workshop Checklist

ก่อนเข้า Module 2 ตรวจสอบ:

```bash
# 1. Cluster พร้อม
kubectl get nodes
# ต้องเห็น: 1 control-plane, 2 agents

# 2. Namespace
kubectl create namespace monitoring
kubectl create namespace workshop

# 3. Terraform initialized
cd 02-terraform-prometheus
terraform init

# 4. Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

---

**[Module 2: Deployment with Terraform & Helm](../02-terraform-prometheus/workshop-guide.md)**