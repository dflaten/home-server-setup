#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HOME_SERVER_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
ENV_FILE=${HOME_SERVER_ROOT}/.env

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

REPO_PATH=${CONTAINERSCAN_REPO_PATH:-../ContainerScan}
if [[ "$REPO_PATH" != /* ]]; then
  REPO_PATH=${HOME_SERVER_ROOT}/${REPO_PATH}
fi

COMPOSE_FILE=${REPO_PATH}/docker-compose.yml
PROJECT_ENV_FILE=${REPO_PATH}/.env
ACTION=${1:-up}
shift || true

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "ContainerScan compose file not found at $COMPOSE_FILE" >&2
  exit 1
fi

compose_args=(--project-directory "$REPO_PATH" -f "$COMPOSE_FILE")
if [[ -f "$PROJECT_ENV_FILE" ]]; then
  compose_args+=(--env-file "$PROJECT_ENV_FILE")
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
