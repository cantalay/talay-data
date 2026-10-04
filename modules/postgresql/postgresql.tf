resource "helm_release" "postgresql" {
  name       = "postgresql"
  namespace  = "data"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "postgresql"
  version    = "18.8.16"

  atomic  = true
  wait    = true
  timeout = 900

  values = [yamlencode({
    architecture = "standalone"
    auth = {
      username       = var.username
      database       = var.database
      existingSecret = "postgresql-auth"
      secretKeys = {
        adminPasswordKey = "postgres-password"
        userPasswordKey  = "password"
      }
      usePasswordFiles = true
    }
    primary = {
      priorityClassName = "talay-platform-critical"
      persistence = {
        enabled      = true
        storageClass = var.storage_class
        size         = var.storage_size
        annotations  = { "helm.sh/resource-policy" = "keep" }
      }
      resources = {
        requests = { cpu = "50m", memory = "256Mi" }
        limits   = { memory = "1Gi" }
      }
      pdb = { create = false }
      # exec pg_isready her çağrıda runc exec + Postgres backend fork'u demek; düşük CPU'da probe'un kendisi yük
      # oluyordu. TCP kontrolü kubelet içinden yapılır, container'da süreç başlatmaz.
      customLivenessProbe = {
        tcpSocket           = { port = "tcp-postgresql" }
        initialDelaySeconds = 30
        periodSeconds       = 30
        timeoutSeconds      = 10
        failureThreshold    = 6
      }
      customReadinessProbe = {
        tcpSocket        = { port = "tcp-postgresql" }
        periodSeconds    = 15
        timeoutSeconds   = 10
        failureThreshold = 6
      }
    }
    backup = {
      enabled = var.backup_enabled
      cronjob = {
        schedule          = "0 2 * * *"
        concurrencyPolicy = "Forbid"
        storage = {
          enabled        = true
          storageClass   = var.storage_class
          size           = var.backup_size
          resourcePolicy = "keep"
        }
      }
    }
    metrics = {
      enabled = true
      resources = {
        requests = { cpu = "10m", memory = "48Mi" }
        limits   = { memory = "128Mi" }
      }
      service = {
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9187"
        }
      }
      serviceMonitor = { enabled = false }
    }
  })]
}
