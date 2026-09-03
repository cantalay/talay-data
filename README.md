# talay-data

Tek-node K3s için PostgreSQL ve Redis kurar. Parolalar Terraform değişkeni veya state'i yerine `ClusterSecretStore/vault` üzerinden External Secrets Operator ile alınır.

Vault'ta beklenen alanlar:

```text
kv/platform/postgresql: postgres-password, password
kv/platform/redis:      redis-password
```

PostgreSQL günlük logical dump PVC'si yanlışlıkla silinmeye karşı `keep` politikasına sahiptir; aynı sunucudaki bu PVC bir disaster-recovery kopyası değildir. Üretimde ayrıca şifreli, cluster dışı object storage'a düzenli backup ve restore testi gerekir.
