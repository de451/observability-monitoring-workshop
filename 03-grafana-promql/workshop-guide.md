# Module 3: Grafana & PromQL

## 3.1 ทำความเข้าใจ PromQL

PromQL (Prometheus Query Language) ใช้ดึงข้อมูล Time-Series

### Data Types

```
instant vector   — ค่า ณ เวลาปัจจุบัน
range vector     — ช่วงข้อมูลย้อนหลัง [5m]
scalar           — ตัวเลขเดียว
string           — ข้อความ
```

### Syntax พื้นฐาน

```promql
# 1. Metric ธรรมดา
up

# 2. ใส่ Label Selector
up{job="prometheus-kube-prometheus-prometheus"}

# 3. ใส่เงื่อนไข Label
kube_pod_status_phase{phase="Running", namespace="monitoring"}

# 4. Range Vector (ข้อมูลย้อนหลัง 5 นาที)
prometheus_http_requests_total[5m]

# 5. ฟังก์ชัน rate (อัตราต่อวินาทีเฉลี่ย)
rate(prometheus_http_requests_total[5m])
```

---

## 3.2 PromQL Workshop — Query ที่ใช้งานจริง

เปิด Prometheus UI: http://prometheus.localhost

### CPU Usage

```promql
# CPU ใช้ของ Node ทั้งหมด (%)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# CPU ของแต่ละ Pod
rate(container_cpu_usage_seconds_total{namespace="monitoring", container!=""}[5m])

# Top 5 Pods ที่ใช้ CPU สูงสุด
topk(5, rate(container_cpu_usage_seconds_total{container!="", container!="POD"}[5m]))
```

### Memory Usage

```promql
# Memory Node (bytes)
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes

# Memory usage % ของ Node
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Memory ของ Pod (MB)
container_memory_working_set_bytes{namespace="monitoring", container!=""} / 1024 / 1024

```

### Pod & Deployment Status

```promql
# จำนวน Pod ที่ Running
count(kube_pod_status_phase{phase="Running"}) by (namespace)

# Pod ที่ Restart บ่อย
rate(kube_pod_container_status_restarts_total[1h]) * 3600

# Deployment ที่ desired != ready
kube_deployment_spec_replicas - kube_deployment_status_ready_replicas

# Pod ที่ Pending
kube_pod_status_phase{phase="Pending"}
```

### Disk Usage

```promql
# Disk usage ของ Node (%) — กรอง tmpfs/overlay/squashfs ออก
(
  node_filesystem_size_bytes{fstype!~"tmpfs|overlay|squashfs"}
  - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs"}
) / node_filesystem_size_bytes{fstype!~"tmpfs|overlay|squashfs"} * 100

# Disk ที่เหลือ (GB) — ดูทุก mountpoint ที่เป็น disk จริง
node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs"} / 1024 / 1024 / 1024
```

> **หมายเหตุ:**
> - ใช้ `avail` ไม่ใช่ `free` — `avail` คือพื้นที่ที่ user ใช้ได้จริง, `free` รวม reserved blocks (~5%) ที่ Linux กันไว้สำหรับ root
> - บน k3d (Docker) จะเห็น mountpoint หลายอัน เช่น `/`, `/etc/hosts`, `/dev/shm` — filter `fstype` ช่วยตัด overlay ของ Docker ออก

---

## 3.3 สร้าง Custom Dashboard ใน Grafana

### ขั้นตอน

1. เปิด Grafana: http://grafana.localhost
2. ไป **Dashboards → New → New Dashboard**
3. **Add visualization**

### Panel 1: CPU Usage Overview

```
Visualization: Time series
Query:
  100 - (avg by (node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
Legend: {{node}}
Unit: Percent (0-100)
Thresholds:
  - 70% = Yellow (Warning)
  - 90% = Red (Critical)
```

### Panel 2: Memory Usage per Pod

```
Visualization: Bar gauge
Query:
  sort_desc(
    topk(10, container_memory_working_set_bytes{namespace!="", container!="", container!="POD"})
  )
Legend: {{namespace}}/{{pod}}
Unit: bytes (IEC)
```

### Panel 3: Pod Status Overview

```
Visualization: Stat
Query A (Running):  count(kube_pod_status_phase{phase="Running"})
Query B (Pending):  count(kube_pod_status_phase{phase="Pending"}) or vector(0)
Query C (Failed):   count(kube_pod_status_phase{phase="Failed"}) or vector(0)
```

### Panel 4: Pod Restart Rate

```
Visualization: Time series
Query:
  topk(5, rate(kube_pod_container_status_restarts_total[30m]) * 3600)
Legend: {{namespace}}/{{pod}}/{{container}}
Unit: restarts/hour
```

---

## 3.4 Import Dashboard สำเร็จรูป

ไป **Dashboards → Import → Grafana.com Dashboard**

Dashboard IDs ที่แนะนำ:
| ID | ชื่อ |
|----|------|
| `1860` | Node Exporter Full |
| `315` | Kubernetes Cluster Monitoring |
| `13770` | 1 Kubernetes All-in-one |
| `14518` | Kubernetes / Views / Global |

---

## 3.5 ConfigMap Dashboard (Dashboards as Code)

สร้าง Dashboard ที่ Grafana โหลดอัตโนมัติผ่าน ConfigMap:

```bash
kubectl apply -f 03-grafana-promql/workshop-dashboard-cm.yaml
```

ดูไฟล์: [workshop-dashboard-cm.yaml](./workshop-dashboard-cm.yaml)

Grafana sidecar จะตรวจจับ ConfigMap ที่มี label `grafana_dashboard: "1"` 
และโหลด dashboard อัตโนมัติโดยไม่ต้อง restart

---

## 3.6 ทดลองกับ Demo App

```bash
# ติดตั้ง demo app (ใช้ prom/prometheus image ซึ่งมี /metrics endpoint ในตัว)
kubectl apply -f demo-app/

# Generate traffic ไปที่ /-/healthy endpoint
kubectl run load-gen --image=busybox --restart=Never \
  -- sh -c "while true; do wget -q -O- http://demo-app/-/healthy; sleep 0.1; done"
```

ดู metrics ของ demo app ใน Prometheus UI:
```promql
# นับ request ที่เข้ามาที่ demo-app แยกตาม handler และ HTTP code
rate(prometheus_http_requests_total{job="demo-app"}[5m])

# ดู latency เฉลี่ย
rate(prometheus_http_request_duration_seconds_sum{job="demo-app"}[5m])
  /
rate(prometheus_http_request_duration_seconds_count{job="demo-app"}[5m])
```

> **metric ที่มีใน demo app (`prom/prometheus`):**
> - `prometheus_http_requests_total` — จำนวน HTTP request แยกตาม handler, code
> - `prometheus_http_request_duration_seconds` — latency histogram
> - `go_goroutines` — จำนวน goroutines ของ process

---

**[Module 4: Intelligent Alerting System](../04-alerting/workshop-guide.md)**
