#!/usr/bin/env bash
# Uygulama için PostgreSQL database + owner role ve/veya Redis DB index tahsis eder; bağlantı bilgilerini
# Vault kv/apps/<project>/<consumer> path'lerine yazar. Varsayılan dry-run'dır; APPLY=true ile uygular.
# Parolalar stdout'a, argv'ye veya Terraform state'ine yazılmaz.
#
# Kullanım:
#   scripts/provision-app-database.sh --project <project> [--database <db>] --consumer <component> [--consumer …]
#                                     [--redis-db <0-15>] [--rotate]
# Ortam:
#   APPLY=true            değişiklikleri uygula (yoksa yalnız plan)
#   VAULT_ADDR            varsayılan https://vault.cantalay.com (geçerli vault token gerekir: vault login -method=oidc)
#   TALAY_HOST            varsayılan 152.53.66.101 (kubectl SSH üzerinden çalışır)
#   TALAY_KUBE_MODE=local kubectl'i lokal KUBECONFIG ile çalıştır (SSH yerine)
set -euo pipefail

export VAULT_ADDR="${VAULT_ADDR:-https://vault.cantalay.com}"
TALAY_HOST="${TALAY_HOST:-152.53.66.101}"
VAULT_MOUNT="${VAULT_MOUNT:-kv}"
APPLY="${APPLY:-false}"

PG_HOST="postgresql.data.svc.cluster.local"
PG_PORT="5432"
REDIS_HOST="redis-master.data.svc.cluster.local"
REDIS_PORT="6379"

project="" database="" redis_db="" rotate=false
consumers=()

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
die() { echo "HATA: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="${2:-}"; shift 2 ;;
    --database) database="${2:-}"; shift 2 ;;
    --consumer) consumers+=("${2:-}"); shift 2 ;;
    --redis-db) redis_db="${2:-}"; shift 2 ;;
    --rotate) rotate=true; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Bilinmeyen argüman: $1" >&2; usage 1 ;;
  esac
done

dns_label='^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'
[[ "$project" =~ $dns_label ]] || die "--project DNS-1123 olmalı"
[[ ${#consumers[@]} -gt 0 ]] || die "en az bir --consumer gerekli"
for c in "${consumers[@]}"; do [[ "$c" =~ $dns_label ]] || die "--consumer '$c' DNS-1123 olmalı"; done
[[ -n "$database" || -n "$redis_db" ]] || die "--database veya --redis-db gerekli"
if [[ -n "$database" ]]; then
  [[ "$database" =~ ^[a-z][a-z0-9_]{0,62}$ ]] || die "--database ^[a-z][a-z0-9_]{0,62}$ olmalı"
  [[ "$database" != "postgres" && "$database" != "talay" && "$database" != template* ]] || die "'$database' rezerve"
fi
if [[ -n "$redis_db" ]]; then
  [[ "$redis_db" =~ ^([0-9]|1[0-5])$ ]] || die "--redis-db 0-15 olmalı"
  [[ "$redis_db" != "0" ]] || die "Redis DB 0 varsayılan index (eski kullanımlar olabilir); uygulamalara 1-15 verilir"
fi

command -v vault >/dev/null || die "vault CLI yok"
command -v python3 >/dev/null || die "python3 yok"
vault token lookup >/dev/null 2>&1 || die "Vault girişi yok: VAULT_ADDR=$VAULT_ADDR vault login -method=oidc"

# kubectl komutunu SSH üzerinden (varsayılan) ya da lokal çalıştırır. $1 tek bir shell komut dizesidir.
cluster() {
  if [[ "${TALAY_KUBE_MODE:-ssh}" == "local" ]]; then bash -c "$1"; else ssh -o BatchMode=yes "root@$TALAY_HOST" "$1"; fi
}
# stdin'deki SQL'i postgres süper kullanıcısıyla çalıştırır; admin parolası pod içindeki dosyadan okunur.
psql_admin() {
  cluster "kubectl exec -i -n data postgresql-0 -c postgresql -- sh -c 'PGPASSWORD=\"\$(cat /opt/bitnami/postgresql/secrets/postgres-password)\" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -qAt'"
}
vault_field() { vault kv get -mount="$VAULT_MOUNT" -field="$2" "$1" 2>/dev/null || true; }
vault_exists() { vault kv get -mount="$VAULT_MOUNT" "$1" >/dev/null 2>&1; }

paths=(); for c in "${consumers[@]}"; do paths+=("apps/$project/$c"); done

echo "Proje      : $project"
echo "Tüketiciler: ${paths[*]/#/$VAULT_MOUNT/}"
echo "Mod        : $([[ "$APPLY" == "true" ]] && echo UYGULA || echo DRY-RUN)"

password="" password_action="" role_exists=false db_exists=false
if [[ -n "$database" ]]; then
  state="$(printf "select (select count(*) from pg_roles where rolname = '%s') || ',' || (select count(*) from pg_database where datname = '%s');\n" "$database" "$database" | psql_admin)"
  [[ "${state%%,*}" == "1" ]] && role_exists=true
  [[ "${state##*,}" == "1" ]] && db_exists=true

  existing=""
  for p in "${paths[@]}"; do existing="$(vault_field "$p" DB_PASSWORD)"; [[ -n "$existing" ]] && break; done

  if $rotate; then
    password_action="rotate"
  elif [[ -n "$existing" ]]; then
    password="$existing"; password_action=$($role_exists && echo "keep" || echo "create-with-vault-password")
  else
    password_action=$($role_exists && echo "reset (role var, Vault'ta parola yok)" || echo "create")
  fi
  [[ -z "$password" ]] && password="$(openssl rand -hex 24)"

  echo
  echo "PostgreSQL ($PG_HOST:$PG_PORT)"
  echo "  role     $database : $($role_exists && echo mevcut || echo OLUŞTURULACAK) (LOGIN, NOSUPERUSER, NOCREATEDB, NOCREATEROLE)"
  echo "  database $database : $($db_exists && echo mevcut || echo "OLUŞTURULACAK (owner $database)")"
  echo "  CONNECT  : PUBLIC'ten kaldırılır, yalnız $database"
  echo "  parola   : $password_action"
fi

redis_password=""
if [[ -n "$redis_db" ]]; then
  redis_password="$(vault_field platform/redis redis-password)"
  [[ -n "$redis_password" ]] || die "Vault $VAULT_MOUNT/platform/redis redis-password okunamadı"
  echo
  echo "Redis ($REDIS_HOST:$REDIS_PORT) DB index $redis_db, key prefix '$project:'"
  echo "  (index'i talay-data/README.md tahsis tablosuna eklemeyi unutma)"
fi

keys=()
[[ -n "$database" ]] && keys+=(DATABASE_URL DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD SPRING_DATASOURCE_URL SPRING_DATASOURCE_USERNAME SPRING_DATASOURCE_PASSWORD)
[[ -n "$redis_db" ]] && keys+=(REDIS_URL REDIS_HOST REDIS_PORT REDIS_DB REDIS_PASSWORD REDIS_KEY_PREFIX)
echo
echo "Vault'a yazılacak key'ler (değerler gösterilmez): ${keys[*]}"
for p in "${paths[@]}"; do
  echo "  $VAULT_MOUNT/$p : $(vault_exists "$p" && echo "patch (mevcut key'ler korunur)" || echo "yeni secret")"
done

if [[ "$APPLY" != "true" ]]; then
  echo
  echo "DRY-RUN: hiçbir şey değiştirilmedi. Uygulamak için başına APPLY=true ekleyin."
  exit 0
fi

if [[ -n "$database" ]]; then
  {
    if [[ "$password_action" == "keep" ]]; then
      :
    elif $role_exists; then
      printf 'ALTER ROLE "%s" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '\''%s'\'';\n' "$database" "$password"
    else
      printf 'CREATE ROLE "%s" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '\''%s'\'';\n' "$database" "$password"
    fi
    $db_exists || printf 'CREATE DATABASE "%s" OWNER "%s";\n' "$database" "$database"
    printf 'REVOKE CONNECT, TEMPORARY ON DATABASE "%s" FROM PUBLIC;\n' "$database"
    printf 'GRANT CONNECT, TEMPORARY ON DATABASE "%s" TO "%s";\n' "$database" "$database"
  } | psql_admin
  echo "PostgreSQL: tamam"
fi

umask 077
payload="$(mktemp)"
trap 'rm -f "$payload"' EXIT
DB="$database" PW="$password" RDB="$redis_db" RPW="$redis_password" PROJECT="$project" \
PG_HOST="$PG_HOST" PG_PORT="$PG_PORT" REDIS_HOST="$REDIS_HOST" REDIS_PORT="$REDIS_PORT" \
python3 - "$payload" <<'PY'
import json, os, sys
from urllib.parse import quote
e = os.environ
data = {}
if e["DB"]:
    db, pw, host, port = e["DB"], e["PW"], e["PG_HOST"], e["PG_PORT"]
    data.update({
        "DATABASE_URL": f"postgresql://{db}:{quote(pw, safe='')}@{host}:{port}/{db}?sslmode=disable",
        "DB_HOST": host, "DB_PORT": port, "DB_NAME": db, "DB_USER": db, "DB_PASSWORD": pw,
        "SPRING_DATASOURCE_URL": f"jdbc:postgresql://{host}:{port}/{db}",
        "SPRING_DATASOURCE_USERNAME": db, "SPRING_DATASOURCE_PASSWORD": pw,
    })
if e["RDB"]:
    host, port, rdb, rpw = e["REDIS_HOST"], e["REDIS_PORT"], e["RDB"], e["RPW"]
    data.update({
        "REDIS_URL": f"redis://:{quote(rpw, safe='')}@{host}:{port}/{rdb}",
        "REDIS_HOST": host, "REDIS_PORT": port, "REDIS_DB": rdb, "REDIS_PASSWORD": rpw,
        "REDIS_KEY_PREFIX": f"{e['PROJECT']}:",
    })
with open(sys.argv[1], "w") as f:
    json.dump(data, f)
PY

for p in "${paths[@]}"; do
  if vault_exists "$p"; then
    vault kv patch -mount="$VAULT_MOUNT" "$p" @"$payload" >/dev/null
  else
    vault kv put -mount="$VAULT_MOUNT" "$p" @"$payload" >/dev/null
  fi
  echo "Vault: $VAULT_MOUNT/$p yazıldı"
done

if [[ "$password_action" == rotate || "$password_action" == reset* ]]; then
  echo
  echo "Parola değişti: ExternalSecret yenilendikten sonra (≤1 saat ya da force-sync) ilgili deployment'ları yeniden başlatın."
fi
