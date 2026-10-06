# talay-data

Tek-node K3s için PostgreSQL ve Redis kurar. Parolalar Terraform değişkeni veya state'i yerine `ClusterSecretStore/vault` üzerinden External Secrets Operator ile alınır.

Root stack `modules/postgresql`, `modules/redis` ve bu iki release'in mevcut secret sözleşmesini koruyan `modules/data-secrets` modüllerini çağırır.

Vault'ta beklenen alanlar:

```text
kv/platform/postgresql: postgres-password, password
kv/platform/redis:      redis-password
```

PostgreSQL günlük logical dump PVC'si yanlışlıkla silinmeye karşı `keep` politikasına sahiptir; aynı sunucudaki bu PVC bir disaster-recovery kopyası değildir. Üretimde ayrıca şifreli, cluster dışı object storage'a düzenli backup ve restore testi gerekir.

## Uygulama veritabanı provisioning

Uygulamalar paylaşımlı PostgreSQL'de kendi database'ine ve aynı adlı owner role'üne sahiptir; `PUBLIC`'in CONNECT
yetkisi kaldırılır. Bağlantı bilgileri uygulamanın Vault path'ine (`kv/apps/<project>/<component>`) yazılır ve
`talay-service` chart'ı `externalSecret.remoteKey` ile bunları env olarak alır. Tablolar uygulamanın kendi
migration'larıyla oluşturulur; bu repo şema yönetmez.

```bash
export VAULT_ADDR=https://vault.cantalay.com && vault login -method=oidc
# Plan (varsayılan dry-run, hiçbir şey yazmaz ve secret göstermez)
./scripts/provision-app-database.sh --project vitafinder --database vitafinder --consumer api --consumer worker --redis-db 2
# Uygula
APPLY=true ./scripts/provision-app-database.sh --project vitafinder --database vitafinder --consumer api --consumer worker --redis-db 2
# Parola rotasyonu
APPLY=true ./scripts/provision-app-database.sh --project vitafinder --database vitafinder --consumer api --consumer worker --rotate
```

Script idempotenttir: role ve Vault parolası zaten varsa parolayı değiştirmez. `kubectl` varsayılan olarak
`ssh root@<TALAY_HOST>` üzerinden çalışır; `TALAY_KUBE_MODE=local` lokal kubeconfig kullanır. Admin parolası
pod içindeki dosyadan okunur, uygulama parolası `openssl rand` ile üretilip yalnız stdin ve mode 600 geçici dosya
üzerinden taşınır.

Yazılan key'ler: `DATABASE_URL`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`,
`SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`; `--redis-db` ile ayrıca
`REDIS_URL`, `REDIS_HOST`, `REDIS_PORT`, `REDIS_DB`, `REDIS_PASSWORD`, `REDIS_KEY_PREFIX`.

### Redis DB index tahsisi

Redis tek parolalı paylaşımlı bir instance'tır; izolasyon DB index ve key prefix ile sağlanır. Yeni index
almadan önce bu tabloyu güncelleyin.

| Index | Proje | Not |
| --- | --- | --- |
| 0 | — | Varsayılan index; eski kullanımlar olabilir, yeni uygulamalara verilmez |
| 1 | vitafinder | api, worker (`vitafinder:` prefix) |
| 2 | financefollower | api, analytics (`financefollower:` prefix) |
