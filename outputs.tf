output "postgresql" {
  value = {
    host     = "postgresql.data.svc.cluster.local"
    port     = 5432
    database = var.postgres_database
    username = var.postgres_username
    secret   = "postgresql-auth"
  }
}

output "redis" {
  value = {
    host   = "redis-master.data.svc.cluster.local"
    port   = 6379
    secret = "redis-auth"
  }
}
