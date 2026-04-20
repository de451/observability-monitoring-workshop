# Module 4: Intelligent Alerting System

## 4.1 Alerting Architecture

```
PrometheusRule (CRD)
    │  defines rules
    ▼
Prometheus
    │  evaluates every 30s
    │  fires alert if condition true for [for: duration]
    ▼
Alertmanager
    │  routes → groups → inhibits → silences
    ▼
Telegram Bot
```

---

## 4.2 เตรียม Telegram Bot

### ขั้นตอน

**1. สร้าง Bot**
```
1. เปิด Telegram → ค้นหา @BotFather
2. พิมพ์ /newbot
3. ตั้งชื่อ Bot เช่น "Workshop Alert Bot"
4. ตั้ง username เช่น "workshop_k8s_alert_bot_student_id"
5. รับ Token เช่น: 1234567890:ABCdefGHIjklMNOpqrsTUVwxyz
```

**2. หา Chat ID**
```
วิธีที่ 1 (ง่ายที่สุด ใช้ได้ทุก OS):
  เปิด Telegram → ค้นหา @userinfobot → ส่งข้อความใดก็ได้ → รับ Chat ID
```

วิธีที่ 2 ผ่าน API — Linux / Mac:
```bash
BOT_TOKEN="<your-bot-token>"
# ส่งข้อความหา Bot ก่อน 1 ครั้ง แล้วรัน:
curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates" | jq '.result[0].message.chat.id'
```

วิธีที่ 2 ผ่าน API — Windows (PowerShell):
```powershell
$BOT_TOKEN = "<your-bot-token>"
# ส่งข้อความหา Bot ก่อน 1 ครั้ง แล้วรัน:
(Invoke-RestMethod "https://api.telegram.org/bot$BOT_TOKEN/getUpdates").result[0].message.chat.id
```

**3. ทดสอบส่งข้อความ**

Linux / Mac:
```bash
BOT_TOKEN="<your-bot-token>"
CHAT_ID="<your-chat-id>"

curl -s -X POST \
  "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  -d "parse_mode=HTML" \
  -d "text=Workshop Alert Bot พร้อมใช้งาน"
```

Windows (PowerShell):
```powershell
$BOT_TOKEN = "<your-bot-token>"
$CHAT_ID   = "<your-chat-id>"

Invoke-RestMethod -Method Post `
  -Uri "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" `
  -Body @{
    chat_id    = $CHAT_ID
    parse_mode = "HTML"
    text       = "Workshop Alert Bot พร้อมใช้งาน"
  }
```

---

## 4.3 สร้าง terraform.tfvars

Linux / Mac:
```bash
cd 04-alerting

cat > terraform.tfvars << 'EOF'
telegram_bot_token = "1234567890:ABCdefGHIjklMNOpqrsTUVwxyz"
telegram_chat_id   = "-1001234567890"
EOF

# ห้าม commit ไฟล์นี้!
echo "terraform.tfvars" >> .gitignore
```

Windows (PowerShell):
```powershell
cd 04-alerting

@"
telegram_bot_token = "1234567890:ABCdefGHIjklMNOpqrsTUVwxyz"
telegram_chat_id   = "-1001234567890"
"@ | Out-File -Encoding utf8 terraform.tfvars

# ห้าม commit ไฟล์นี้!
Add-Content .gitignore "terraform.tfvars"
```

> **ทั้ง 2 OS:** แก้ไขไฟล์ `terraform.tfvars` ด้วย text editor ก็ได้ เช่น VS Code: `code terraform.tfvars`

---

## 4.4 แก้ไข Chat ID ใน alertmanager-config.yaml

Linux / Mac:
```bash
CHAT_ID="<your-chat-id>"
sed -i "s/__REPLACE_CHAT_ID__/${CHAT_ID}/g" values/alertmanager-config.yaml
```

Windows (PowerShell):
```powershell
$CHAT_ID = "<your-chat-id>"
(Get-Content values/alertmanager-config.yaml) `
  -replace '__REPLACE_CHAT_ID__', $CHAT_ID |
  Set-Content values/alertmanager-config.yaml
```

หรือแก้มือในไฟล์ `values/alertmanager-config.yaml` (แนะนำ ง่ายกว่า):
```yaml
telegram_configs:
  - bot_token_file: /etc/alertmanager/secrets/.../bot_token
    chat_id: -1001234567890   # ← ใส่ Chat ID ตรงนี้
```

---

## 4.5 Deploy Alerting Rules

```bash
cd 04-alerting

# Apply alert rules (PrometheusRule CRD)
kubectl apply -f alert-rules.yaml
```

เปิด port-forward แล้วตรวจสอบ Rules ใน Prometheus UI:

Linux / Mac:
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
open http://localhost:9090/rules
```

Windows (PowerShell) — เปิด Terminal แยก:
```powershell
# Terminal แยก:
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Terminal หลัก:
start http://localhost:9090/rules
```

ใน Prometheus UI → Rules:
- เห็น group `pod-health`, `deployment-health`, `node-resources`
- สถานะ `OK` = กำลัง evaluate อยู่

---

## 4.6 Deploy Alertmanager Config ผ่าน Terraform

```bash
terraform init
terraform plan
terraform apply
```

**ถ้าเจอ error "already exists" / "cannot re-use a name":**

```bash
# Import PrometheusRule ที่มีอยู่แล้ว (apply -f alert-rules.yaml ไปก่อนหน้า)
terraform import kubernetes_manifest.alert_rules \
  "apiVersion=monitoring.coreos.com/v1,kind=PrometheusRule,namespace=monitoring,name=workshop-alert-rules"

# Import Helm release prometheus (ติดตั้งไว้แล้วใน Module 02)
terraform import helm_release.prometheus_alerting monitoring/prometheus

terraform apply
```

Windows (PowerShell):
```powershell
terraform import kubernetes_manifest.alert_rules `
  "apiVersion=monitoring.coreos.com/v1,kind=PrometheusRule,namespace=monitoring,name=workshop-alert-rules"

terraform import helm_release.prometheus_alerting monitoring/prometheus

terraform apply
```

ตรวจสอบ Alertmanager config:
```bash
# ดู merged config (Alertmanager v0.24+ เก็บ config จริงที่ config_out/)
kubectl exec -n monitoring alertmanager-prometheus-kube-prometheus-alertmanager-0 \
  -- cat /etc/alertmanager/config_out/alertmanager.env.yaml

# หรือดูผ่าน API (วิธีนี้ใช้ได้เสมอ ไม่ขึ้นกับ path)
curl -s http://alertmanager.localhost/api/v2/status | jq '.config.original'

# ดู logs
kubectl logs -n monitoring alertmanager-prometheus-kube-prometheus-alertmanager-0 \
  -c alertmanager --tail=30
```

---

## 4.7 ทดสอบ Alert — จำลองปัญหา

### ทดสอบ 1: Pod Crash Loop

```bash
# สร้าง Pod ที่ crash อย่างต่อเนื่อง
kubectl run crasher \
  --image=busybox \
  --restart=Always \
  -- sh -c "echo 'starting...'; sleep 2; exit 1"

# ดู restart count เพิ่มขึ้น
kubectl get pod crasher -w

# ดู alert ใน Prometheus
# http://localhost:9090/alerts → PodCrashLooping

# รอ 5 นาที → รับ Telegram notification!

# ลบ Pod
kubectl delete pod crasher
# รอ → รับ "RESOLVED" notification
```

### ทดสอบ 2: Deployment Replicas Mismatch

```bash
# สร้าง deployment ที่ขอ resource มากเกินไป → บาง Pod จะ Pending
kubectl create deployment big-deploy --image=nginx --replicas=10
kubectl set resources deployment big-deploy --requests=cpu=2,memory=4Gi
```

เปิด Alertmanager UI — Linux / Mac:
```bash
open http://alertmanager.localhost
```

Windows:
```powershell
start http://alertmanager.localhost
```

```bash
# ลบเมื่อเสร็จ
kubectl delete deployment big-deploy
```

### ทดสอบ 3: ส่ง Test Alert โดยตรง

```bash
# ส่ง test alert ผ่าน Alertmanager API (ไม่ต้องรอ condition จริง)
curl -X POST http://alertmanager.localhost/api/v2/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning",
      "namespace": "workshop",
      "pod": "test-pod-123"
    },
    "annotations": {
      "summary": "นี่คือ Test Alert",
      "description": "ทดสอบการส่ง alert จาก Workshop"
    },
    "generatorURL": "http://prometheus.localhost/graph"
  }]'
```

---

## 4.8 Alertmanager UI — Route Tree

เปิด http://alertmanager.localhost

- **Alerts** — alert ที่กำลัง fire อยู่
- **Silences** — ปิดเสียง alert ชั่วคราว (เช่น ช่วง maintenance)
- **Status** — ดู config และ cluster info

### สร้าง Silence (ปิดเสียงชั่วคราว)

> **แนะนำ:** ใช้ Alertmanager UI ที่ http://alertmanager.localhost → Silences → New Silence — ง่ายกว่าและใช้ได้ทุก OS

หรือผ่าน API — Linux / Mac:
```bash
curl -X POST http://alertmanager.localhost/api/v2/silences \
  -H "Content-Type: application/json" \
  -d "{
    \"matchers\": [{\"name\": \"namespace\", \"value\": \"workshop\", \"isRegex\": false}],
    \"startsAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"endsAt\": \"$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+1H +%Y-%m-%dT%H:%M:%SZ)\",
    \"createdBy\": \"workshop-user\",
    \"comment\": \"Maintenance window\"
  }"
```

Windows (PowerShell):
```powershell
$now    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$plus1h = (Get-Date).AddHours(1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Invoke-RestMethod -Method Post `
  -Uri "http://alertmanager.localhost/api/v2/silences" `
  -ContentType "application/json" `
  -Body (@{
    matchers  = @(@{ name = "namespace"; value = "workshop"; isRegex = $false })
    startsAt  = $now
    endsAt    = $plus1h
    createdBy = "workshop-user"
    comment   = "Maintenance window"
  } | ConvertTo-Json)
```

---

## 4.9 Alert as Code — สรุป

```
alert-rules.yaml          ← Rules ที่ Prometheus evaluate
values/alertmanager-config.yaml  ← วิธีส่ง notification
main.tf                   ← Deploy ทุกอย่างผ่าน Terraform
```

ทุกอย่างอยู่ใน Git → review ได้ → rollback ได้ → reproduce ได้

---

## 4.10 คู่มืออ้างอิง

### Alertmanager Configuration
| หัวข้อ | ลิ้งค์ |
|--------|--------|
| Alertmanager Config Reference (route, receiver, inhibit) | https://prometheus.io/docs/alerting/latest/configuration/ |
| Notification Template Reference (Go template syntax) | https://prometheus.io/docs/alerting/latest/notifications/ |
| Alertmanager HTTP API (silence, alert) | https://prometheus.io/docs/alerting/latest/clients/ |

### Prometheus Alerting Rules
| หัวข้อ | ลิ้งค์ |
|--------|--------|
| Alerting Rules Reference (expr, for, labels, annotations) | https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/ |
| Recording Rules (precompute PromQL) | https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/ |
| PrometheusRule CRD (Prometheus Operator) | https://prometheus-operator.dev/docs/user-guides/alerting/ |

### PromQL สำหรับเขียน Alert
| หัวข้อ | ลิ้งค์ |
|--------|--------|
| PromQL Reference | https://prometheus.io/docs/prometheus/latest/querying/basics/ |
| PromQL Functions (`rate`, `increase`, `topk`, `histogram_quantile`) | https://prometheus.io/docs/prometheus/latest/querying/functions/ |

### Telegram Bot API
| หัวข้อ | ลิ้งค์ |
|--------|--------|
| Bot API — sendMessage, parse_mode | https://core.telegram.org/bots/api#sendmessage |
| HTML formatting tags ที่รองรับ | https://core.telegram.org/bots/api#html-style |
| getUpdates (หา Chat ID) | https://core.telegram.org/bots/api#getupdates |

### Alerting Best Practices
| หัวข้อ | ลิ้งค์ |
|--------|--------|
| Google SRE Book — Alerting on SLOs | https://sre.google/workbook/alerting-on-slos/ |
| Awesome Prometheus Alerts (rules สำเร็จรูป) | https://samber.github.io/awesome-prometheus-alerts/ |

---

**[Module 5: Centralized Logging with Loki](../05-loki/workshop-guide.md)**
