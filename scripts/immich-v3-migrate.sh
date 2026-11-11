#!/usr/bin/env bash
#
# Migrate an existing Immich deployment from pgvecto.rs to VectorChord.
#
# Immich v3 removed support for pgvecto.rs. Deployments still running the
# tensorchord/pgvecto-rs Postgres image crash-loop with:
#
#   Error: No vector extension found. Available extensions: vchord, vector
#
# This script backs up the Immich database, swaps the database container to
# the VectorChord image declared in docker-compose-server.yml, restarts the
# stack, and waits for the automatic extension/index migration to finish.
#
# Run it on the Docker host, from anywhere:
#
#   ./scripts/immich-v3-migrate.sh
#
# The script is interrupted-safe up to the point where the database image is
# swapped; after that, let the migration finish rather than restarting it.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

COMPOSE_FILE=${COMPOSE_FILE:-$ROOT/docker-compose-server.yml}
ENV_FILE=${ENV_FILE:-$ROOT/.env}
BACKUP_DIR=${BACKUP_DIR:-$ROOT/backups}
WAIT_MINUTES=${WAIT_MINUTES:-30}
IMMICH_PORT=${IMMICH_PORT:-2283}

DB_CONTAINER=immich_postgres
APP_SERVICES=(immich-server immich-machine-learning)

ASSUME_YES=0
LOG_PID=

usage() {
  cat <<'EOF'
Usage: immich-v3-migrate.sh [options]

Options:
  -y, --yes              Do not prompt for confirmation
      --backup-dir DIR   Where to write the dump and migration log
                         (default: <repo>/backups)
      --wait MINUTES     How long to wait for Immich to answer (default: 30)
  -h, --help             Show this help

Environment overrides: COMPOSE_FILE, ENV_FILE, BACKUP_DIR, WAIT_MINUTES,
IMMICH_PORT.
EOF
}

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "$LOG_PID" ]] && kill -0 "$LOG_PID" 2>/dev/null; then
    kill "$LOG_PID" 2>/dev/null || true
    wait "$LOG_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1; shift ;;
    --backup-dir) [[ $# -ge 2 ]] || die "--backup-dir needs a value"; BACKUP_DIR=$2; shift 2 ;;
    --backup-dir=*) BACKUP_DIR=${1#*=}; shift ;;
    --wait) [[ $# -ge 2 ]] || die "--wait needs a value"; WAIT_MINUTES=$2; shift 2 ;;
    --wait=*) WAIT_MINUTES=${1#*=}; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (try --help)" ;;
  esac
done

read_env_value() {
  local key=$1 file=$2
  python3 - "$key" "$file" <<'PYENV'
import sys
from pathlib import Path

key = sys.argv[1]
path = Path(sys.argv[2])
if not path.exists():
    raise SystemExit(1)

for raw_line in path.read_text().splitlines():
    line = raw_line.strip()
    if not line or line.startswith('#') or '=' not in line:
        continue
    current_key, value = line.split('=', 1)
    if current_key.strip() != key:
        continue
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        value = value[1:-1]
    print(value)
    raise SystemExit(0)
raise SystemExit(1)
PYENV
}

compose() {
  docker compose --project-directory "$ROOT" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}

http_ping() {
  local url="http://127.0.0.1:${IMMICH_PORT}/api/server/ping"
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 5 "$url" >/dev/null 2>&1
  else
    wget -q -T 5 -O /dev/null "$url" >/dev/null 2>&1
  fi
}

db_query() {
  docker exec "$DB_CONTAINER" psql \
    --dbname="$DB_NAME" --username="$DB_USER" --tuples-only --no-align \
    --command="$1" | tr -d '\r'
}

# ---------------------------------------------------------------- preflight

[[ -f "$COMPOSE_FILE" ]] || die "compose file not found: $COMPOSE_FILE"
[[ -f "$ENV_FILE" ]] || die "env file not found: $ENV_FILE (copy .env.example first)"
[[ "$WAIT_MINUTES" =~ ^[0-9]+$ ]] || die "--wait must be a whole number of minutes"
[[ "$IMMICH_PORT" =~ ^[0-9]+$ ]] || die "IMMICH_PORT must be a port number"

command -v docker >/dev/null 2>&1 || die "docker not found in PATH"
command -v python3 >/dev/null 2>&1 || die "python3 not found in PATH"
docker info >/dev/null 2>&1 || die "cannot talk to the Docker daemon (try sudo or check docker.service)"
docker compose version >/dev/null 2>&1 || die "docker compose plugin not available"

DB_USER=$(read_env_value DB_USERNAME "$ENV_FILE" || true)
DB_USER=${DB_USER:-postgres}
DB_NAME=$(read_env_value DB_DATABASE_NAME "$ENV_FILE" || true)
DB_NAME=${DB_NAME:-immich}

docker inspect "$DB_CONTAINER" >/dev/null 2>&1 \
  || die "container $DB_CONTAINER not found; is the Immich stack installed and started?"

if [[ "$(docker inspect -f '{{.State.Running}}' "$DB_CONTAINER")" != "true" ]]; then
  log "Starting the database container so it can be inspected and backed up..."
  compose up -d database
fi

log "Waiting for $DB_CONTAINER to accept connections..."
db_ready=0
for _ in $(seq 1 60); do
  if docker exec "$DB_CONTAINER" pg_isready --dbname="$DB_NAME" --username="$DB_USER" >/dev/null 2>&1; then
    db_ready=1
    break
  fi
  sleep 2
done
[[ "$db_ready" -eq 1 ]] || die "$DB_CONTAINER did not become ready; check 'docker logs $DB_CONTAINER'"

installed_exts=$(db_query "SELECT extname FROM pg_extension ORDER BY extname")
if grep -qx 'vchord' <<<"$installed_exts"; then
  log "VectorChord is already installed. Nothing to migrate."
  exit 0
fi
if ! grep -qx 'vectors' <<<"$installed_exts"; then
  if grep -qx 'vector' <<<"$installed_exts"; then
    die "this database uses pgvector, not pgvecto.rs. This script only handles the pgvecto.rs migration."
  fi
  die "no pgvecto.rs ('vectors') extension found in database $DB_NAME; unexpected starting state."
fi

pg_version_num=$(db_query "SHOW server_version_num" | tr -d '[:space:]')
[[ "$pg_version_num" =~ ^[0-9]+$ ]] || die "could not determine the Postgres version"
pg_major=$((pg_version_num / 10000))
[[ "$pg_major" -eq 14 ]] \
  || die "this database is Postgres $pg_major, but the compose file targets Postgres 14. Adjust the database image in $COMPOSE_FILE before migrating."

db_image=$(python3 - "$COMPOSE_FILE" <<'PY'
import re
import sys

in_database = False
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.rstrip("\n")
    if re.match(r"^  database:\s*$", line):
        in_database = True
        continue
    if in_database and re.match(r"^  \S", line):
        break
    if in_database:
        match = re.match(r"^\s+image:\s*(\S+)", line)
        if match:
            print(match.group(1))
            break
PY
)

if [[ "$db_image" != ghcr.io/immich-app/postgres:*vectorchord* ]]; then
  die "the database service in $COMPOSE_FILE still uses '${db_image:-<unknown>}'.
Update it to ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
(and remove the old 'command:'/'healthcheck:' overrides) before running this script."
fi
if grep -q 'shared_preload_libraries=vectors\.so' "$COMPOSE_FILE"; then
  die "$COMPOSE_FILE still passes 'shared_preload_libraries=vectors.so'. Remove the old database 'command:' override."
fi

image_major=${db_image#*postgres:}
image_major=${image_major%%-*}
[[ "$image_major" == "$pg_major" ]] \
  || die "compose image targets Postgres $image_major but the running database is Postgres $pg_major."

immich_version=$(read_env_value IMMICH_VERSION "$ENV_FILE" || true)
log ""
log "Migration plan:"
log "  database container : $DB_CONTAINER (Postgres $pg_major, pgvecto.rs)"
log "  new image          : $db_image"
log "  Immich version     : ${immich_version:-<default>}"
log "  backup directory   : $BACKUP_DIR"
log "  API port on host   : $IMMICH_PORT"
log ""
log "The database will be dumped first, then the Immich server and"
log "machine-learning containers will be stopped, the database image swapped,"
log "and the stack restarted so the migration can run. This can take several"
log "minutes. Do not interrupt it once the database has restarted."
log ""

if [[ "$ASSUME_YES" -ne 1 ]]; then
  if [[ -t 0 ]]; then
    printf "Type 'migrate' to continue: "
    read -r confirmation
    [[ "$confirmation" == "migrate" ]] || die "aborted by user"
  else
    die "refusing to run non-interactively without --yes"
  fi
fi

mkdir -p "$BACKUP_DIR"

timestamp=$(date +%Y%m%d-%H%M%S)
dump_file="$BACKUP_DIR/immich-db-pre-v3-$timestamp.sql.gz"
log_file="$BACKUP_DIR/immich-v3-migrate-$timestamp.log"

# ------------------------------------------------------------------- backup

log "Dumping database $DB_NAME to $dump_file ..."
if ! docker exec "$DB_CONTAINER" pg_dump --clean --if-exists \
      --dbname="$DB_NAME" --username="$DB_USER" | gzip -c > "$dump_file"; then
  rm -f "$dump_file"
  die "database backup failed; nothing was changed"
fi

gzip -t "$dump_file" || die "backup archive is corrupt; nothing was changed"
dump_size=$(stat -c%s "$dump_file" 2>/dev/null || stat -f%z "$dump_file")
[[ "$dump_size" -gt 1024 ]] || die "backup file is only ${dump_size} bytes; refusing to continue"

log "Backup written ($(numfmt --to=iec "$dump_size" 2>/dev/null || echo "${dump_size}B"))."

# -------------------------------------------------------------- swap + start

log "Stopping ${APP_SERVICES[*]} before swapping the database image..."
compose stop "${APP_SERVICES[@]}" >/dev/null 2>&1 || true

log "Pulling $db_image ..."
if ! compose pull database; then
  warn "failed to pull the new database image; restarting the stopped containers"
  compose up -d >/dev/null 2>&1 || true
  die "image pull failed; nothing was migrated"
fi

log "Recreating the database container..."
compose up -d --force-recreate database

log "Waiting for the new database container to become healthy..."
db_status=
for _ in $(seq 1 300); do
  db_status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$DB_CONTAINER" 2>/dev/null || echo missing)
  case "$db_status" in
    healthy|running) break ;;
  esac
  sleep 2
done
case "$db_status" in
  healthy|running) ;;
  *) die "database did not become healthy (status: ${db_status:-unknown}); check 'docker logs $DB_CONTAINER'" ;;
esac

db_ready=0
for _ in $(seq 1 60); do
  if docker exec "$DB_CONTAINER" pg_isready --dbname="$DB_NAME" --username="$DB_USER" >/dev/null 2>&1; then
    db_ready=1
    break
  fi
  sleep 2
done
[[ "$db_ready" -eq 1 ]] || die "new database container is not accepting connections"

log "Starting the stack; Immich will now create VectorChord and reindex..."
compose up -d

compose logs -f --no-color database immich-server >"$log_file" 2>&1 &
LOG_PID=$!

log "Waiting up to ${WAIT_MINUTES} minute(s) for Immich on port $IMMICH_PORT ..."
deadline=$((SECONDS + WAIT_MINUTES * 60))
migrated=0
while (( SECONDS < deadline )); do
  if http_ping; then
    migrated=1
    break
  fi
  sleep 5
done

if [[ "$migrated" -ne 1 ]]; then
  cleanup
  LOG_PID=
  warn "Immich did not become reachable within ${WAIT_MINUTES} minute(s)."
  warn "Last log lines ($log_file):"
  tail -n 80 "$log_file" >&2 || true
  cat >&2 <<EOF

The database may still be migrating. Before doing anything else, check:
  docker logs --tail 200 $DB_CONTAINER
  docker logs --tail 200 immich_server

If you must roll back, stop Immich and restore the dump (last resort):
  docker compose --project-directory $(printf '%q' "$ROOT") \\
    -f $(printf '%q' "$COMPOSE_FILE") --env-file $(printf '%q' "$ENV_FILE") \\
    stop immich-server immich-machine-learning
  gunzip -c $(printf '%q' "$dump_file") \\
    | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \\
    | docker exec -i $DB_CONTAINER psql --dbname=$(printf '%q' "$DB_NAME") --username=$(printf '%q' "$DB_USER") \\
        --single-transaction --set ON_ERROR_STOP=on
  docker compose --project-directory $(printf '%q' "$ROOT") \\
    -f $(printf '%q' "$COMPOSE_FILE") --env-file $(printf '%q' "$ENV_FILE") up -d
EOF
  exit 1
fi

# ------------------------------------------------------------------ verify

sleep 2
cleanup
LOG_PID=

final_exts=$(db_query "SELECT extname FROM pg_extension ORDER BY extname")
if ! grep -qx 'vchord' <<<"$final_exts"; then
  warn "Immich is reachable but the 'vchord' extension is not listed yet:"
  warn "$(tr '\n' ' ' <<<"$final_exts")"
  warn "Give the migration more time and re-check with:"
  warn "  docker exec -it $DB_CONTAINER psql --dbname=$DB_NAME --username=$DB_USER -c '\\dx'"
fi

log ""
log "Migration complete."
log "  VectorChord installed : $(grep -qx 'vchord' <<<"$final_exts" && echo yes || echo 'not yet - check logs')"
log "  Database backup       : $dump_file"
log "  Migration log         : $log_file"
log ""
log "Next steps:"
log "  1. Open Immich and verify login, timeline, and smart search."
log "  2. Check Admin > Jobs; let any queued jobs finish."
log "  3. Do not downgrade Immich below v1.133 after this migration."
if [[ "$immich_version" == "release" ]]; then
  log "  4. Consider pinning IMMICH_VERSION (for example v3.4.0) in $ENV_FILE."
fi
