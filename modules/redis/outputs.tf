output "connection" {
  value = {
    host   = "redis-master.data.svc.cluster.local"
    port   = 6379
    secret = "redis-auth"
  }
}
