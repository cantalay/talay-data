module "data_secrets" {
  source = "./modules/data-secrets"

  chart_path           = "${path.root}/charts/data-secrets"
  vault_postgresql_key = var.vault_postgresql_key
  vault_redis_key      = var.vault_redis_key
}

module "postgresql" {
  source = "./modules/postgresql"

  username       = var.postgres_username
  database       = var.postgres_database
  storage_class  = var.storage_class
  storage_size   = var.postgres_storage_size
  backup_enabled = var.postgres_backup_enabled
  backup_size    = var.postgres_backup_size

  depends_on = [module.data_secrets]
}

module "redis" {
  source = "./modules/redis"

  storage_class = var.storage_class
  storage_size  = var.redis_storage_size

  depends_on = [module.data_secrets]
}

moved {
  from = helm_release.data_secrets
  to   = module.data_secrets.helm_release.data_secrets
}

moved {
  from = helm_release.postgresql
  to   = module.postgresql.helm_release.postgresql
}

moved {
  from = helm_release.redis
  to   = module.redis.helm_release.redis
}
