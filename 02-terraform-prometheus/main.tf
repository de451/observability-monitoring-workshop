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

# ใช้ kubeconfig จากเครื่อง (k3d cluster)
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
# Namespace: monitoring
#
# ถ้า namespace มีอยู่แล้ว ให้รัน:
#   terraform import kubernetes_namespace.monitoring monitoring
# แล้วค่อย terraform apply ใหม่
# ─────────────────────────────────────────────
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  lifecycle {
    # ไม่ลบ namespace เมื่อ terraform destroy
    # เพราะอาจมี resource อื่นอยู่ข้างใน
    prevent_destroy = false

    # ไม่ error ถ้า label ถูกแก้จากภายนอก
    ignore_changes = [metadata[0].annotations, metadata[0].labels]
  }
}

# ─────────────────────────────────────────────
# Helm Repo: prometheus-community
# ─────────────────────────────────────────────
resource "helm_release" "kube_prometheus_stack" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "65.1.1"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  # อ่าน values จากไฟล์แยก (จัดการง่ายกว่า)
  values = [
    file("${path.module}/values/kube-prometheus-stack.yaml")
  ]

  # รอให้ Pods พร้อมก่อน Terraform ถือว่าสำเร็จ
  wait    = true
  timeout = 600

  # อัปเดต CRDs อัตโนมัติเมื่อ upgrade
  set {
    name  = "crds.enabled"
    value = "true"
  }

  depends_on = [kubernetes_namespace.monitoring]
}
