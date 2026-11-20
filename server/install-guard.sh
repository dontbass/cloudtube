#!/usr/bin/env bash
# CloudTube guard: автоперезапуск и автообновление invidious-companion — на уже работающий сервер.
#   curl -fsSL https://raw.githubusercontent.com/dontbass/cloudtube/main/server/install-guard.sh | bash
# Ставит /opt/cloudtube-addons/guard.sh и таймеры:
#   cloudtube-guard.timer   — раз в 5 мин проверка: companion отдаёт тестовый ролик? 3 провала подряд → перезапуск
#   cloudtube-update.timer  — каждую ночь в 04:20 свежий образ companion (если вышел)
# Параметры (необязательно): COMP_URL COMP_CONTAINER UPDATE_TIME CT_REPO
set -euo pipefail
CT_REPO=${CT_REPO:-https://raw.githubusercontent.com/dontbass/cloudtube/main}
UPDATE_TIME=${UPDATE_TIME:-04:20}
DIR=/opt/cloudtube-addons
[ "$(id -u)" = 0 ] || { echo "[x] запустите от root"; exit 1; }

COMP_CONTAINER=${COMP_CONTAINER:-$(docker ps --format '{{.Names}} {{.Image}}' | awk '$2 ~ /invidious-companion/ {print $1; exit}' || true)}
[ -n "$COMP_CONTAINER" ] || { echo "[x] не нашёл контейнер invidious-companion (укажите COMP_CONTAINER=имя)"; exit 1; }
if [ -z "${COMP_URL:-}" ]; then
  port=$(docker port "$COMP_CONTAINER" 8282/tcp 2>/dev/null | head -1 | sed 's/^0\.0\.0\.0:/127.0.0.1:/; s/^\[::\]:/127.0.0.1:/' || true)
  [ -n "$port" ] || port=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$COMP_CONTAINER"):8282
  COMP_URL="http://$port/companion"
fi
echo "[*] companion: $COMP_CONTAINER, $COMP_URL"

mkdir -p "$DIR"
curl -fsSL "$CT_REPO/server/guard.sh" -o "$DIR/guard.sh.new"; bash -n "$DIR/guard.sh.new"
mv "$DIR/guard.sh.new" "$DIR/guard.sh"; chmod 755 "$DIR/guard.sh"
cat > /etc/cloudtube-guard.env <<ENV
COMP_URL=$COMP_URL
COMP_CONTAINER=$COMP_CONTAINER
ENV

cat > /etc/systemd/system/cloudtube-guard.service <<'UNIT'
[Unit]
Description=CloudTube guard: проверка invidious-companion
After=docker.service
[Service]
Type=oneshot
ExecStart=/opt/cloudtube-addons/guard.sh check
UNIT
cat > /etc/systemd/system/cloudtube-guard.timer <<'UNIT'
[Unit]
Description=CloudTube guard: проверка companion раз в 5 минут
[Timer]
OnBootSec=3min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
UNIT
cat > /etc/systemd/system/cloudtube-update.service <<'UNIT'
[Unit]
Description=CloudTube: свежий образ invidious-companion
After=docker.service network-online.target
[Service]
Type=oneshot
ExecStart=/opt/cloudtube-addons/guard.sh update
UNIT
cat > /etc/systemd/system/cloudtube-update.timer <<UNIT
[Unit]
Description=CloudTube: обновление companion каждую ночь
[Timer]
OnCalendar=*-*-* $UPDATE_TIME:00
RandomizedDelaySec=20min
Persistent=true
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now cloudtube-guard.timer cloudtube-update.timer >/dev/null
echo "[*] первая проверка:"
"$DIR/guard.sh" status || true
echo "[*] обновляю companion сейчас:"
"$DIR/guard.sh" update || true
echo "[✓] готово. Журнал: journalctl -u cloudtube-guard -u cloudtube-update -n 30   Состояние: $DIR/guard.sh status"
