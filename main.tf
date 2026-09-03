resource "helm_release" "data_secrets" {
  name      = "data-secrets"
  namespace = "data"
  chart     = "${path.module}/charts/data-secrets"

  atomic  = true
  wait    = true
  timeout = 300

  values = [yamlencode({
    refreshInterval = "1h"
    postgresql = {
      remoteKey = var.vault_postgresql_key
    }
    redis = {
      remoteKey = var.vault_redis_key
    }
  })]
}

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
      username       = var.postgres_username
      database       = var.postgres_database
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
        size         = var.postgres_storage_size
        annotations = {
          "helm.sh/resource-policy" = "keep"
        }
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          memory = "1Gi"
        }
      }
      pdb = {
        create = false
      }
    }
    backup = {
      enabled = var.postgres_backup_enabled
      cronjob = {
        schedule          = "0 2 * * *"
        concurrencyPolicy = "Forbid"
        storage = {
          enabled        = true
          storageClass   = var.storage_class
          size           = var.postgres_backup_size
          resourcePolicy = "keep"
        }
      }
    }
    metrics = {
      enabled = true
      service = {
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9187"
        }
      }
      serviceMonitor = {
        enabled = false
      }
    }
  })]

  depends_on = [helm_release.data_secrets]
}

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
        size         = var.redis_storage_size
        annotations = {
          "helm.sh/resource-policy" = "keep"
        }
      }
      resources = {
        requests = {
          cpu    = "50m"
          memory = "128Mi"
        }
        limits = {
          memory = "512Mi"
        }
      }
      pdb = {
        create = false
      }
    }
    metrics = {
      enabled = true
      service = {
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9121"
        }
      }
      serviceMonitor = {
        enabled = false
      }
    }
  })]

  depends_on = [helm_release.data_secrets]
}
