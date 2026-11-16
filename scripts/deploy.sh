#!/usr/bin/env bash
set -Eeuo pipefail
# Uso: bash scripts/deploy.sh staging|production imagem fail_health feature
ENVIRONMENT="${1:?Informe o ambiente}"
IMAGE="${2:?Informe a imagem}"
FAIL_HEALTH="${3:-false}"
FEATURE="${4:-false}"
case "$ENVIRONMENT" in
  staging) PORT=8081; ASPNET_ENV=Staging ;;
  production) PORT=8082; ASPNET_ENV=Production ;;
  *) echo "Ambiente invalido"; exit 2 ;;
esac
[[ "$FAIL_HEALTH" =~ ^(true|false)$ && "$FEATURE" =~ ^(true|false)$ ]] || exit 2
NAME="ceub-api-$ENVIRONMENT"
PREVIOUS="$NAME-previous"
URL="http://127.0.0.1:$PORT"

wait_for_health() {
  for attempt in $(seq 1 20); do
    if curl --fail --silent --show-error --max-time 3 "$URL/health"; then
      return 0
    fi
    sleep 2
  done
  return 1
}

smoke_test() {
  wait_for_health &&
    curl --fail --silent --show-error --max-time 5 "$URL/api/entregas"
}

# Confirme a imagem antes de parar a versao que esta atendendo.
docker image inspect "$IMAGE" >/dev/null
HAD_PREVIOUS=false
if docker container inspect "$NAME" >/dev/null 2>&1; then
  if docker container inspect "$PREVIOUS" >/dev/null 2>&1; then
    docker rm "$PREVIOUS" >/dev/null
  fi
  docker stop "$NAME" >/dev/null
  if ! docker rename "$NAME" "$PREVIOUS"; then
    docker start "$NAME" >/dev/null || true
    exit 1
  fi
  HAD_PREVIOUS=true
elif docker container inspect "$PREVIOUS" >/dev/null 2>&1; then
  echo "Deploy anterior interrompido. Restaure $PREVIOUS antes de repetir."
  exit 1
fi

if docker run -d --name "$NAME" --restart unless-stopped \
    -p "127.0.0.1:$PORT:8080" \
    -e ASPNETCORE_ENVIRONMENT="$ASPNET_ENV" \
    -e FAIL_HEALTH="$FAIL_HEALTH" \
    -e FEATURE_NOVIDADE="$FEATURE" "$IMAGE" && smoke_test; then
  printf '\n'
  docker inspect --format 'Imagem ativa: {{.Image}}' "$NAME"
  echo "Deploy validado: $ENVIRONMENT"
  exit 0
fi

docker logs --tail 60 "$NAME" 2>&1 || true
if docker container inspect "$NAME" >/dev/null 2>&1; then
  docker rm -f "$NAME" >/dev/null
fi
if [[ "$HAD_PREVIOUS" == true ]]; then
  if docker rename "$PREVIOUS" "$NAME" &&
     docker start "$NAME" >/dev/null &&
     smoke_test; then
    printf '\nROLLBACK OK: container anterior restaurado.\n'
  else
    printf '\nROLLBACK FALHOU: investigue os containers do ambiente.\n'
  fi
else
  echo "Sem versao anterior para restaurar."
fi
exit 1
