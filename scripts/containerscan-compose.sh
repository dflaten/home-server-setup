#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HOME_SERVER_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
ENV_FILE=${HOME_SERVER_ROOT}/.env

read_env_value() {
  local key=$1
  local file=$2
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

REPO_PATH=../ContainerScan
if [[ -f "$ENV_FILE" ]]; then
  if env_repo_path=$(read_env_value CONTAINERSCAN_REPO_PATH "$ENV_FILE"); then
    REPO_PATH=$env_repo_path
  fi
fi
if [[ "$REPO_PATH" != /* ]]; then
  REPO_PATH=${HOME_SERVER_ROOT}/${REPO_PATH}
fi

COMPOSE_FILE=${REPO_PATH}/docker-compose.yml
ACTION=${1:-up}
shift || true

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "ContainerScan compose file not found at $COMPOSE_FILE" >&2
  exit 1
fi

compose_args=(--project-directory "$REPO_PATH" -f "$COMPOSE_FILE")
if [[ -f "$ENV_FILE" ]]; then
  compose_args+=(--env-file "$ENV_FILE")
fi

case "$ACTION" in
  up)
    exec docker compose "${compose_args[@]}" up -d --build "$@"
    ;;
  down)
    exec docker compose "${compose_args[@]}" down "$@"
    ;;
  logs)
    exec docker compose "${compose_args[@]}" logs -f "$@"
    ;;
  ps)
    exec docker compose "${compose_args[@]}" ps "$@"
    ;;
  restart)
    exec docker compose "${compose_args[@]}" restart "$@"
    ;;
  *)
    echo "Usage: $0 {up|down|logs|ps|restart} [compose args]" >&2
    exit 1
    ;;
esac
