terraform {
  required_version = ">= 1.6"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
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
# Variables: Telegram Bot
# ─────────────────────────────────────────────
variable "telegram_bot_token" {
  description = "Telegram Bot Token จาก @BotFather"
  type        = string
  sensitive   = true
}

variable "telegram_chat_id" {
  description = "Telegram Chat ID (ใช้ @userinfobot หรือ getUpdates API)"
  type        = string
}

# ─────────────────────────────────────────────
# Secret: Alertmanager Telegram config
# ─────────────────────────────────────────────
resource "kubernetes_secret" "alertmanager_telegram" {
  metadata {
    name      = "alertmanager-telegram-secret"
    namespace = "monitoring"
  }

  data = {
    bot_token = var.telegram_bot_token
  }
}

# ─────────────────────────────────────────────
# Alerting Rules (PrometheusRule CRD)
#
# ถ้า resource มีอยู่แล้ว ให้รัน:
#   terraform import kubernetes_manifest.alert_rules \
#     "apiVersion=monitoring.coreos.com/v1,kind=PrometheusRule,namespace=monitoring,name=workshop-alert-rules"
# ─────────────────────────────────────────────
resource "kubernetes_manifest" "alert_rules" {
  manifest = yamldecode(file("${path.module}/alert-rules.yaml"))
}

# ─────────────────────────────────────────────
# Upgrade prometheus stack: เพิ่ม Alertmanager config
#
# Helm release "prometheus" ถูกติดตั้งไว้แล้วใน Module 02
# ถ้า error "cannot re-use a name that is still in use" ให้รัน:
#   terraform import helm_release.prometheus_alerting monitoring/prometheus
# ─────────────────────────────────────────────
resource "helm_release" "prometheus_alerting" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "65.1.1"
  namespace  = "monitoring"

  # รวม values จาก Module 02 + alerting config ใหม่
  values = [
    file("${path.module}/../02-terraform-prometheus/values/kube-prometheus-stack.yaml"),
    file("${path.module}/values/alertmanager-config.yaml"),
  ]

  set_sensitive {
    name  = "alertmanager.config.global.telegram_api_url"
    value = "https://api.telegram.org"
  }

  wait    = true
  timeout = 300

  depends_on = [kubernetes_secret.alertmanager_telegram]
}
