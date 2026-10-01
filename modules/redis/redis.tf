resource "helm_release" "redis" {
  name       = "redis"
  namespace  = "data"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "redis"
  version    = "28.0.14"

  atomic  = true
  wait    = true
  timeout = 900

  values = [yamlencode({
    architecture = "standalone"
    auth = {
      enabled                   = true
      existingSecret            = "redis-auth"
      existingSecretPasswordKey = "redis-password"
      usePasswordFiles          = true
    }
    master = {
      priorityClassName = "talay-platform-critical"
      persistence = {
        enabled      = true
        storageClass = var.storage_class
        size         = var.storage_size
        annotations  = { "helm.sh/resource-policy" = "keep" }
      }
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "512Mi" }
      }
      pdb = { create = false }
    }
    metrics = {
      enabled = true
      service = {
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9121"
        }
      }
      serviceMonitor = { enabled = false }
    }
  })]
}
