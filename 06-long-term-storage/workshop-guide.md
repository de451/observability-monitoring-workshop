# Module 6: Long-term Storage & Final Demo

## 6.1 Prometheus Retention — ปัญหาของ Local Storage

Prometheus เก็บข้อมูลใน local disk โดยค่า default `retention: 15d`

**ปัญหา:**
```
Cardinality สูง (metrics * labels * time) → disk เต็มเร็ว
ไม่ redundant → ถ้า Prometheus pod ตาย ข้อมูลหาย
ไม่ scale ได้ → ถ้า query หนัก Prometheus ช้า
```

**ตรวจสอบ TSDB stats:**

Linux / Mac:
```bash
curl -s http://prometheus.localhost/api/v1/status/tsdb | jq '.data | {
  headChunks: .headStats.numChunks,
  series: .headStats.numSeries,
  sampleCount: .headStats.numSamples,
  minTime: (.headStats.minTime / 1000 | todate),
  maxTime: (.headStats.maxTime / 1000 | todate)
}'

# ดู top metrics ที่ใช้ cardinality สูง
curl -s http://prometheus.localhost/api/v1/status/tsdb | \
  jq '.data.seriesCountByMetricName[:10]'
```

Windows (PowerShell — ต้องติดตั้ง [jq](https://jqlang.org/download/) ก่อน):
```powershell
$tsdb = Invoke-RestMethod "http://prometheus.localhost/api/v1/status/tsdb"
$tsdb.data | ConvertTo-Json -Depth 3

# ดู top cardinality metrics
$tsdb.data.seriesCountByMetricName | Select-Object -First 10
```

---

## 6.2 Long-term Storage Options

### Option A: Thanos (Enterprise)

```
┌──────────────┐    sidecar   ┌─────────────┐    upload    ┌───────────┐
│  Prometheus  │ ──────────── │Thanos Sidecar│ ──────────► │  S3 / GCS │
└──────────────┘              └─────────────┘              └───────────┘
                                                                  │
                              ┌─────────────┐    query            │
                              │Thanos Query │ ◄───────────────────┘
                              └─────────────┘
```

- **ข้อดี:** Global view ข้ามหลาย Prometheus, downsampling, deduplication
- **ข้อเสีย:** ซับซ้อน, ต้องการ Object Storage (S3)

### Option B: VictoriaMetrics (แนะนำ)

```
┌──────────────┐  remote_write  ┌───────────────────┐
│  Prometheus  │ ─────────────► │  VictoriaMetrics  │ ← Single binary
└──────────────┘                │  (Long-term store)│ ← ประหยัด disk 7x
                                └───────────────────┘
                                         │
                              ┌──────────▼──────────┐
                              │      Grafana        │
                              │  (datasource: VM)   │
                              └─────────────────────┘
```

- **ข้อดี:** ง่าย, compress ดีกว่า Prometheus 7x, compatible กับ PromQL
- **ข้อเสีย:** ecosystem เล็กกว่า Thanos

### Option C: Grafana Mimir (Cloud-native)

- Horizontally scalable
- Multi-tenancy
- ใช้ Object Storage (S3, GCS, Azure Blob)
- เหมาะกับ Production scale

---

## 6.3 Retention Strategy

```
ระยะสั้น (0-7 วัน)   → Prometheus local TSDB    ← raw resolution
ระยะกลาง (7-90 วัน)  → VictoriaMetrics / Thanos ← 5min downsampled
ระยะยาว (90d-2 ปี)   → Object Storage (S3/GCS)  ← 1hr downsampled
```

**ตั้งค่า Remote Write ใน Prometheus:**
```yaml
# เพิ่มใน values/kube-prometheus-stack.yaml
prometheus:
  prometheusSpec:
    remoteWrite:
      - url: http://victoriametrics:8428/api/v1/write
        queueConfig:
          maxSamplesPerSend: 10000
          capacity: 20000
```

---

## 6.4 Final Demo: จำลองสถานการณ์ระบบผิดปกติ

> **Scenario:** Application ทำงานช้าลงกะทันหัน → Pod restart → Service ไม่ตอบสนอง

### Setup Demo Environment

```bash
cd demo-app
kubectl apply -f .
kubectl wait --for=condition=ready pod -l app=demo-app -n workshop --timeout=120s
```

### ขั้นตอนที่ 1: Inject Fault — สร้าง Memory Leak

```bash
# Patch demo app ให้ใช้ memory เกิน limit
kubectl set resources deployment demo-app -n workshop \
  --limits=memory=64Mi \
  --requests=memory=32Mi
```

Generate load — Linux / Mac:
```bash
kubectl run load \
  --image=busybox \
  --restart=Never \
  -- sh -c "while true; do wget -q -O- http://demo-app.workshop; done" &
```

Generate load — Windows (PowerShell) เปิด Terminal แยก:
```powershell
kubectl run load `
  --image=busybox `
  --restart=Never `
  -- sh -c "while true; do wget -q -O- http://demo-app.workshop; done"
```

### ขั้นตอนที่ 2: รับ Telegram Alert

รอประมาณ 2-5 นาที → Telegram จะแจ้งเตือน:
```
🔥 ALERT FIRING
📌 PodOOMKilled
🏷 Severity: warning
📦 Namespace: workshop
🐳 Pod: demo-app-xxx-yyy
📝 Container demo-app ถูก kill เพราะ memory เกิน limit
```

### ขั้นตอนที่ 3: ตรวจสอบ Dashboard

```
เปิด Grafana → Workshop Dashboard

1. ดู Memory Usage panel → เห็น spike
2. ดู Pod Restart Rate → เห็น restart เพิ่ม
3. ดู Running Pods → count ลดลงชั่วคราว
```

### ขั้นตอนที่ 4: ดู Log ใน Loki

```
Grafana → Explore → Loki

Query: {namespace="workshop", app="demo-app"}

สิ่งที่จะเห็น:
- Log ก่อน OOM: request เยอะ, memory allocate
- Log สุดท้ายก่อน killed
- Log หลัง restart: "Container starting..."
```

### ขั้นตอนที่ 5: ตรวจสอบด้วย kubectl

Linux / Mac:
```bash
# ดู events ล่าสุด 20 รายการ
kubectl get events -n workshop --sort-by='.lastTimestamp' | tail -20

# ดูว่า OOMKilled จริงไหม
kubectl get pod -n workshop -o json | \
  jq '.items[].status.containerStatuses[].lastState.terminated | select(.reason == "OOMKilled")'
```

Windows (PowerShell):
```powershell
# ดู events ล่าสุด 20 รายการ
kubectl get events -n workshop --sort-by='.lastTimestamp' | Select-Object -Last 20

# ดูว่า OOMKilled จริงไหม (ต้องติดตั้ง jq)
kubectl get pod -n workshop -o json | `
  jq '.items[].status.containerStatuses[].lastState.terminated | select(.reason == "OOMKilled")'
```

```bash
# ดู resource usage จริง (ใช้ได้ทุก OS)
kubectl top pod -n workshop

# Timeline จาก Prometheus
# rate(container_memory_working_set_bytes{namespace="workshop"}[5m])
```

### ขั้นตอนที่ 6: แก้ปัญหา

```bash
# เพิ่ม memory limit
kubectl set resources deployment demo-app -n workshop \
  --limits=memory=256Mi \
  --requests=memory=128Mi

# ตรวจสอบว่า Pod stable แล้ว
kubectl get pod -n workshop -w

# รอ → ได้รับ Telegram: ✅ RESOLVED
```

---

## 6.5 สรุป Full Observability Loop

```
┌─────────────────────────────────────────────────────────────┐
│                    Observability Workflow                   │
│                                                             │
│  1. Metrics (Prometheus)                                    │
│     └─► เห็น Memory spike → Alert fires                      │
│                                                             │
│  2. Alert (Alertmanager + Telegram)                         │
│     └─► ได้รับแจ้งเตือนทันที                                      │
│                                                             │
│  3. Dashboard (Grafana)                                     │
│     └─► เห็น timeline → ระบุช่วงเวลาที่เกิดปัญหา                   │
│                                                             │
│  4. Logs (Loki + LogQL)                                     │
│     └─► ดู log ก่อน-หลัง → หาสาเหตุที่แท้จริง                       │
│                                                             │
│  5. Fix → Verify → Alert Resolved                           │
│     └─► ยืนยันการแก้ไขด้วย metrics + logs                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 6.6 Cleanup

```bash
# ลบ demo resources (ใช้ได้ทุก OS)
kubectl delete deployment load-generator log-generator -n workshop
kubectl delete pod load -n workshop --ignore-not-found
```

Linux / Mac:
```bash
cd 05-loki && terraform destroy -auto-approve
cd ../04-alerting && terraform destroy -auto-approve
cd ../02-terraform-prometheus && terraform destroy -auto-approve
k3d cluster delete workshop
```

Windows (PowerShell) — รันแยกทีละ directory:
```powershell
cd 05-loki
terraform destroy -auto-approve
cd ../04-alerting
terraform destroy -auto-approve
cd ../02-terraform-prometheus
terraform destroy -auto-approve
k3d cluster delete workshop
```

---

## 6.7 Next Steps

| หัวข้อ | เครื่องมือ |
|--------|-----------|
| Distributed Tracing | Grafana Tempo + OpenTelemetry |
| Service Mesh Metrics | Istio + Kiali |
| Cost Monitoring | Kubecost |
| Security Monitoring | Falco |
| SLO/Error Budget | Pyrra / Sloth |
| Long-term Storage | VictoriaMetrics / Thanos |

**Recommended reading:**
- Prometheus documentation: https://prometheus.io/docs/
- Grafana Loki documentation: https://grafana.com/docs/loki/
- kube-prometheus-stack: https://github.com/prometheus-community/helm-charts
