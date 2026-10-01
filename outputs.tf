output "postgresql" {
  value = module.postgresql.connection
}

output "redis" {
  value = module.redis.connection
}
