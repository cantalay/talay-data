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
        requests = { cpu = "40m", memory = "128Mi" }
        limits   = { memory = "512Mi" }
      }
      pdb = { create = false }
      # Varsayılan probe'lar 5 sn'de bir bash + redis-cli exec ediyor; TCP kontrolü container'da süreç başlatmaz.
      customLivenessProbe = {
        tcpSocket           = { port = "redis" }
        initialDelaySeconds = 20
        periodSeconds       = 30
        timeoutSeconds      = 10
        failureThreshold    = 6
      }
      customReadinessProbe = {
        tcpSocket        = { port = "redis" }
        periodSeconds    = 15
        timeoutSeconds   = 10
        failureThreshold = 6
      }
    }
    metrics = {
      enabled = true
      resources = {
        requests = { cpu = "10m", memory = "16Mi" }
        limits   = { memory = "64Mi" }
      }
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
