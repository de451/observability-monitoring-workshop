output "grafana_url" {
  description = "Grafana URL"
  value       = "http://grafana.localhost"
}

output "prometheus_url" {
  description = "Prometheus URL"
  value       = "http://prometheus.localhost"
}

output "alertmanager_url" {
  description = "Alertmanager URL"
  value       = "http://alertmanager.localhost"
}

output "grafana_credentials" {
  description = "Grafana login"
  value = {
    username = "admin"
    password = "workshop2026"
  }
  sensitive = true
}

output "port_forward_commands" {
  description = "Port-forward commands ถ้า Ingress ไม่ทำงาน"
  value = {
    grafana      = "kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    prometheus   = "kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
    alertmanager = "kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093"
  }
}
