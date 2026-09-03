variable "kubeconfig_path" {
  type    = string
  default = "../talay-cluster/stacks/bootstrap/kubeconfig.yaml"
}

variable "storage_class" {
  type    = string
  default = "local-path"
}

variable "postgres_database" {
  type    = string
  default = "talay"
}

variable "postgres_username" {
  type    = string
  default = "talay"
}

variable "postgres_storage_size" {
  type    = string
  default = "20Gi"
}

variable "postgres_backup_enabled" {
  type    = bool
  default = true
}

variable "postgres_backup_size" {
  type    = string
  default = "10Gi"
}

variable "redis_storage_size" {
  type    = string
  default = "5Gi"
}

variable "vault_postgresql_key" {
  type    = string
  default = "platform/postgresql"
}

variable "vault_redis_key" {
  type    = string
  default = "platform/redis"
}
