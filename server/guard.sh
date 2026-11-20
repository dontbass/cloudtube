#!/usr/bin/env bash
# CloudTube guard: присмотр за invidious-companion (он получает видео с YouTube).
#   guard.sh check   — раз в 5 минут (таймер): companion отдаёт кусок тестового ролика?
#                      3 провала подряд → перезапуск контейнера (не чаще раза в 15 минут)
#   guard.sh update  — раз в сутки ночью (таймер): свежий образ companion (YouTube часто меняется),
#                      контейнер пересоздаётся, только если образ правда обновился
# Настройки — /etc/cloudtube-guard.env (пишет install-guard.sh / deploy.sh).
set -uo pipefail
[ -f /etc/cloudtube-guard.env ] && . /etc/cloudtube-guard.env
COMP_URL=${COMP_URL:-http://127.0.0.1:8282/companion}
COMP_CONTAINER=${COMP_CONTAINER:-}
STATE=${STATE:-/var/lib/cloudtube-guard}
FAILS_TO_RESTART=${FAILS_TO_RESTART:-3}
TEST_IDS=${TEST_IDS:-"jNQXAC9IVRw aqz-KE-bpKQ LXb3EKWsInQ"}
mkdir -p "$STATE"

log() { echo "[guard] $*"; }

container() {
  [ -n "$COMP_CONTAINER" ] && docker inspect "$COMP_CONTAINER" >/dev/null 2>&1 && { echo "$COMP_CONTAINER"; return; }
  docker ps -a --format '{{.Names}} {{.Image}}' | awk '$2 ~ /invidious-companion/ {print $1; exit}'
}

probe() {   # 0 — companion отдаёт видео
  local id code size
  for id in $TEST_IDS; do
    read -r code size < <(curl -s -L -m 40 -r 0-65535 -o /dev/null -w '%{http_code} %{size_download}' \
      "$COMP_URL/latest_version?id=$id&itag=18&local=true" 2>/dev/null || echo "000 0")
    if { [ "$code" = 200 ] || [ "$code" = 206 ]; } && [ "${size%.*}" -gt 1000 ]; then return 0; fi
    log "проверка $id: HTTP $code, $size байт"
  done
  return 1
}

restart() {
  local c now last
  c=$(container); [ -n "$c" ] || { log "контейнер companion не найден"; return 1; }
  now=$(date +%s); last=$(cat "$STATE/last_restart" 2>/dev/null || echo 0)
  if [ $((now - last)) -lt 900 ]; then log "перезапуск был $((now - last)) с назад — жду"; return 0; fi
  log "companion не отдаёт видео — перезапускаю $c"
  docker restart "$c" >/dev/null && echo "$now" > "$STATE/last_restart"
  echo "$(date '+%F %T') restart" >> "$STATE/history"; tail -n 200 "$STATE/history" > "$STATE/history.tmp" && mv "$STATE/history.tmp" "$STATE/history"
}

case "${1:-check}" in
  check)
    curl -fs -m 10 "$COMP_URL/healthz" >/dev/null 2>&1 || curl -fs -m 10 "${COMP_URL%/companion}/healthz" >/dev/null 2>&1 || {
      log "companion не отвечает"; }
    if probe; then
      [ -s "$STATE/fails" ] && [ "$(cat "$STATE/fails")" != 0 ] && log "companion снова в порядке"
      echo 0 > "$STATE/fails"
    else
      f=$(( $(cat "$STATE/fails" 2>/dev/null || echo 0) + 1 )); echo "$f" > "$STATE/fails"
      log "провал $f из $FAILS_TO_RESTART"
      if [ "$f" -ge "$FAILS_TO_RESTART" ]; then restart && echo 0 > "$STATE/fails"; fi
    fi
    ;;
  update)
    c=$(container); [ -n "$c" ] || { log "контейнер companion не найден"; exit 1; }
    img=$(docker inspect -f '{{.Config.Image}}' "$c")
    old=$(docker inspect -f '{{.Image}}' "$c")
    docker pull -q "$img" >/dev/null || { log "не удалось скачать $img"; exit 1; }
    new=$(docker image inspect -f '{{.Id}}' "$img")
    if [ "$old" = "$new" ]; then log "companion свежий"; exit 0; fi
    dir=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$c")
    svc=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$c")
    if [ -n "$dir" ] && [ -n "$svc" ] && [ -d "$dir" ]; then
      (cd "$dir" && docker compose up -d --no-deps "$svc") && log "companion обновлён ($img)"
      echo "$(date '+%F %T') update $new" >> "$STATE/history"
    else
      log "образ скачан, но контейнер создан не через docker compose — пересоздайте вручную"
    fi
    docker image prune -f >/dev/null 2>&1 || true
    ;;
  status)
    echo "провалов подряд: $(cat "$STATE/fails" 2>/dev/null || echo 0)"
    echo "последние события:"; tail -n 10 "$STATE/history" 2>/dev/null || echo "  нет"
    probe && echo "сейчас: companion отдаёт видео" || echo "сейчас: companion НЕ отдаёт видео"
    ;;
esac
