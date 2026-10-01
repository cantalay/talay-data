resource "helm_release" "data_secrets" {
  name      = "data-secrets"
  namespace = "data"
  chart     = var.chart_path

  atomic  = true
  wait    = true
  timeout = 300

  values = [yamlencode({
    refreshInterval = "1h"
    postgresql      = { remoteKey = var.vault_postgresql_key }
    redis           = { remoteKey = var.vault_redis_key }
  })]
}
