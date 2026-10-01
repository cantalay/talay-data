output "connection" {
  value = {
    host     = "postgresql.data.svc.cluster.local"
    port     = 5432
    database = var.database
    username = var.username
    secret   = "postgresql-auth"
  }
}
