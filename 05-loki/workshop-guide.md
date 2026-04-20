# Module 5: Centralized Logging with Loki

## 5.1 Loki vs ELK — ทำไมเลือก Loki?

```
┌─────────────────┬──────────────────┬──────────────────────┐
│                 │   Elasticsearch  │   Grafana Loki       │
├─────────────────┼──────────────────┼──────────────────────┤
│ Index           │ Full-text index  │ Label index เท่านั้น    │
│                 │ (memory heavy)   │ (lightweight)        │
├─────────────────┼──────────────────┼──────────────────────┤
│ Storage         │ ใช้ disk มาก      │ ประหยัด disk 5-10x    │
├─────────────────┼──────────────────┼──────────────────────┤
│ Query           │ Full-text search │ LogQL (คล้าย PromQL)  │
├─────────────────┼──────────────────┼──────────────────────┤
│ Integration     │ Kibana           │ Grafana (เหมือน       │
│                 │ (แยก UI)         │  Metrics dashboard)  │
├─────────────────┼──────────────────┼──────────────────────┤
│ Setup           │ ซับซ้อน            │ ง่าย                  │
└─────────────────┴──────────────────┴──────────────────────┘
```

**Loki concept:** "Like Prometheus, but for logs"
- Labels แทน Full-text Index → query เร็ว, storage น้อย
- ดู Logs คู่กับ Metrics ใน Grafana ได้ในหน้าเดียว

---

## 5.2 Architecture: Promtail → Loki → Grafana

```
┌──────────────────────────────────────────────────────┐
│ Kubernetes Node                                      │
│                                                      │
│  Pod A ──┐                                           │
│  Pod B ──┼─► /var/log/pods/  ◄── Promtail (DaemonSet)│
│  Pod C ──┘         │                                 │
└────────────────────┼─────────────────────────────────┘
                     │ push
                     ▼
              ┌─────────────┐
              │    Loki     │  (จัดเก็บ + index)
              └──────┬──────┘
                     │ query (LogQL)
                     ▼
              ┌─────────────┐
              │   Grafana   │  (Explore + Dashboard)
              └─────────────┘
```

---

## 5.3 Deploy Loki Stack

```bash
cd 05-loki

# เพิ่ม Helm repo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Deploy
terraform init
terraform apply
```

ตรวจสอบ:

Linux / Mac:
```bash
kubectl get pods -n monitoring | grep -E "loki|promtail"
```

Windows (PowerShell):
```powershell
kubectl get pods -n monitoring | Select-String -Pattern "loki|promtail"
```

```
# ต้องเห็น:
# loki-0                    1/1     Running
# loki-promtail-xxx (x3)    1/1     Running   ← DaemonSet บนทุก Node
```

---

## 5.4 LogQL Workshop — Query ภาษา Loki

เปิด Grafana → **Explore** → เลือก Datasource: **Loki**

### Syntax พื้นฐาน

```logql
# 1. ดู log ทุก pod ใน namespace monitoring
{namespace="monitoring"}

# 2. ดู log เฉพาะ pod ที่มีชื่อขึ้นต้นด้วย prometheus
{namespace="monitoring", pod=~"prometheus-.*"}

# 3. Filter เฉพาะ log ที่มีคำว่า "error" (case insensitive)
{namespace="monitoring"} |= "error"

# 4. ยกเว้น log ที่มีคำว่า "debug"
{namespace="monitoring"} != "debug"

# 5. Regex filter
{namespace="monitoring"} |~ "err(or)?"
```

### Pipeline Processing

```logql
# Parse JSON log แล้ว filter ด้วย field
{namespace="workshop"} | json | level="error"

# ดึงเฉพาะ field ที่สนใจ
{namespace="workshop"} | json | line_format "{{.time}} [{{.level}}] {{.msg}}"

# นับ error ต่อนาที
sum(rate({namespace="workshop"} |= "error" [1m])) by (pod)
```

### Query สำหรับ Root Cause Analysis

```logql
# ดู log ของ pod ที่ crash ใน 1 ชั่วโมงที่ผ่านมา
{namespace="workshop", pod="crasher"} | json

# หา error ที่เกิดบ่อยที่สุด
topk(5,
  sum by (msg) (
    count_over_time({namespace="workshop"} | json | level="error" [1h])
  )
)

# ดู log ก่อน-หลัง restart (เปรียบเทียบ timeline)
{namespace="workshop", pod=~"myapp-.*"} |= "FATAL"
```

---

## 5.5 Correlate Logs กับ Metrics

ใน Grafana Dashboard ที่สร้างไว้ในModule 3:

1. เพิ่ม Panel ใหม่ → เลือก **Logs** visualization
2. Query: `{namespace="monitoring", pod=~"prometheus-.*"}`
3. วาง Panel ไว้ถัดจาก CPU/Memory Graph

**ผลลัพธ์:** เห็น log เพิ่มขึ้นพร้อมกับ CPU spike → หาสาเหตุได้

### Exemplars (เชื่อม Metrics ↔ Traces)
```
Dashboard Panel → คลิกจุดบน Graph → "View Logs" → กระโดดไปดู Log ช่วงนั้น
```

---

## 5.6 ทดลอง: Generate Logs และ Query

ใช้ไฟล์ YAML ที่เตรียมไว้ (ใช้ได้ทุก OS):
```bash
kubectl apply -f log-generator.yaml
kubectl wait --for=condition=ready pod -l app=log-generator -n workshop --timeout=60s

# ดู logs ใน Loki
# Grafana → Explore → Loki → {namespace="workshop", app="log-generator"}
```

> **หมายเหตุ:** `kubectl apply -f - <<'EOF'` ใช้ได้เฉพาะ Linux/Mac  
> บน Windows ให้บันทึกไฟล์ YAML แล้ว `kubectl apply -f <filename>.yaml` แทน

ไฟล์ [log-generator.yaml](./log-generator.yaml) มีเนื้อหา:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: log-generator
  namespace: workshop
spec:
  replicas: 1
  selector:
    matchLabels:
      app: log-generator
  template:
    metadata:
      labels:
        app: log-generator
    spec:
      containers:
        - name: logger
          image: mingrammer/flog
          args:
            - --format=json
            - --loop
            - --delay=500ms
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
```

### Query ที่น่าทดลอง

```logql
# ดู log ดิบพร้อม format แสดง method + status + path
{app="log-generator"} | json
  | line_format "{{.method}} {{.status}} {{.request}}"

# นับ request แยกตาม HTTP method (GET/POST/PUT/DELETE)
# | json extract ทุก field เป็น label → ใช้ method ได้เลย
sum by (method) (
  count_over_time({app="log-generator"} | json [1m])
)

# Error rate (HTTP 5xx) ต่อวินาที
sum(rate({app="log-generator"} | json | status =~ "5.." [1m]))

# Request แยกตาม HTTP status code (low cardinality — มีแค่ 200/404/500 ฯลฯ)
sum by (status) (
  count_over_time({app="log-generator"} | json [5m])
)
```

> **หมายเหตุ:**
> - `label_format dest={{.src}}` ต้องใส่ `"..."` ครอบ template: `label_format dest="{{.src}}"` — แต่ถ้า `| json` extract มาเป็น label แล้ว ไม่จำเป็นต้องใช้ `label_format`
> - หลีกเลี่ยง `sum by (request)` เพราะ `request` คือ URL path ที่มีค่าไม่ซ้ำกันมาก (high cardinality) → เกิน limit 500 series ของ Loki ใช้ `status` หรือ `method` แทน

---

## 5.7 Loki Retention & Storage

```bash
# ดู disk usage ของ Loki
kubectl exec -n monitoring loki-0 -- du -sh /data/loki/

# ดู chunk ที่เก็บอยู่
kubectl exec -n monitoring loki-0 -- ls -lh /data/loki/chunks/

# Config retention ใน values/loki-stack.yaml:
# limits_config:
#   retention_period: 168h  ← 7 วัน
```

เปลี่ยน retention ผ่าน Terraform:
```bash
# แก้ retention_period ใน values/loki-stack.yaml
# แล้ว terraform apply
```

---

**[Module 6: Long-term Storage & Final Demo](../06-long-term-storage/workshop-guide.md)**
