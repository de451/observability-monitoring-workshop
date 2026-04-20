terraform {
  required_version = ">= 1.6"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "k3d-workshop"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "k3d-workshop"
  }
}

# ─────────────────────────────────────────────
# Grafana Loki Stack
# ─────────────────────────────────────────────
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  version    = "2.10.2"
  namespace  = "monitoring"

  values = [
    file("${path.module}/values/loki-stack.yaml")
  ]

  wait    = true
  timeout = 300
}

# ─────────────────────────────────────────────
# เพิ่ม Loki เป็น Datasource ใน Grafana
# ─────────────────────────────────────────────
resource "kubernetes_config_map" "loki_datasource" {
  metadata {
    name      = "loki-datasource"
    namespace = "monitoring"
    labels = {
      grafana_datasource = "1"   # Grafana sidecar จะโหลดอัตโนมัติ
    }
  }

  data = {
    "loki-datasource.yaml" = yamlencode({
      apiVersion = 1
      datasources = [{
        name      = "Loki"
        type      = "loki"
        access    = "proxy"
        url       = "http://loki:3100"
        isDefault = false
        jsonData = {
          maxLines = 1000
        }
      }]
    })
  }

  depends_on = [helm_release.loki]
}

# ─────────────────────────────────────────────
# Loki Dashboard (Explore Logs)
# ─────────────────────────────────────────────
resource "kubernetes_config_map" "loki_dashboard" {
  metadata {
    name      = "loki-logs-dashboard"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "loki-logs.json" = file("${path.module}/dashboards/loki-logs-dashboard.json")
  }

  depends_on = [helm_release.loki]
}
