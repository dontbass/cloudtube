#!/usr/bin/env bash
# CloudTube: модуль «Подписки YouTube» (страница /ctsubs/) на уже работающий сервер — без переустановки.
#   curl -fsSL https://raw.githubusercontent.com/dontbass/cloudtube/main/server/install-ytsync.sh | sudo bash
# Что делает:
#   • ставит ytsync.py в /opt/cloudtube-addons и сервис cloudtube-ytsync (127.0.0.1:3500);
#   • добавляет в nginx location /ctsubs (если находит конфиг CloudTube, иначе печатает, что вставить);
#   • обновляет brand.js сайта (пункт «Импорт подписок» в меню), если сайт ставился deploy.sh.
# Параметры (необязательно): INV_URL DB_CONTAINER SYNC_HOURS REGION HL CT_DOMAIN CT_REPO NGINX_CONF WEB
set -euo pipefail
CT_REPO=${CT_REPO:-https://raw.githubusercontent.com/dontbass/cloudtube/main}
INV_URL=${INV_URL:-http://127.0.0.1:3000}
DB_CONTAINER=${DB_CONTAINER:-invidious-db}
SYNC_HOURS=${SYNC_HOURS:-6}
REGION=${REGION:-RU}
HL=${HL:-ru}
WEB=${WEB:-/opt/cloudtube-web}
DIR=/opt/cloudtube-addons

[ "$(id -u)" = 0 ] || { echo "[x] запустите от root"; exit 1; }
curl -fsS -m 10 "$INV_URL/api/v1/stats" >/dev/null || { echo "[x] Invidious не отвечает на $INV_URL"; exit 1; }
docker exec "$DB_CONTAINER" psql -U kemal -d invidious -Atc "select 1" >/dev/null 2>&1 ||
  { echo "[x] нет доступа к базе: контейнер $DB_CONTAINER (задайте DB_CONTAINER=…)"; exit 1; }

NGINX_CONF=${NGINX_CONF:-$(grep -lsE "proxy_pass http://127\.0\.0\.1:3400|server_name .*${CT_DOMAIN:-__none__}" /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf 2>/dev/null | head -1 || true)}
if [ -z "${CT_DOMAIN:-}" ] && [ -n "$NGINX_CONF" ]; then
  CT_DOMAIN=$(awk '/server_name/{gsub(";","",$2); print $2; exit}' "$NGINX_CONF")
fi

echo "[*] ytsync.py → $DIR"
mkdir -p "$DIR"
curl -fsSL "$CT_REPO/server/ytsync.py" -o "$DIR/ytsync.py.new"
python3 -m py_compile "$DIR/ytsync.py.new"
mv "$DIR/ytsync.py.new" "$DIR/ytsync.py"; chmod 755 "$DIR/ytsync.py"
cat > /etc/systemd/system/cloudtube-ytsync.service <<UNIT
[Unit]
Description=CloudTube: подписки YouTube (перенос, автозагрузка, удаление всех)
After=network-online.target docker.service
[Service]
Environment=INV_URL=$INV_URL
Environment=SYNC_PORT=3500
Environment=SYNC_DB=$DIR/ytsync.json
Environment=SYNC_HOURS=$SYNC_HOURS
Environment=DOMAIN=${CT_DOMAIN:-}
Environment=REGION=$REGION
Environment=HL=$HL
Environment=DB_CONTAINER=$DB_CONTAINER
ExecStart=/usr/bin/python3 $DIR/ytsync.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now cloudtube-ytsync >/dev/null
systemctl restart cloudtube-ytsync

if [ -d "$WEB/custom" ]; then
  echo "[*] brand.js → $WEB/custom"
  curl -fsSL "$CT_REPO/server/web/custom/brand.js" -o "$WEB/custom/brand.js.new" && mv "$WEB/custom/brand.js.new" "$WEB/custom/brand.js"
fi

BLOCK='    # «Подписки YouTube»: перенос подписок с YouTube и удаление всех (для каждого пользователя сайта)
    location ^~ /ctsubs {
        limit_except GET POST { deny all; }
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Remote-User $remote_user;
        proxy_read_timeout 120s;
        proxy_pass http://127.0.0.1:3500;
    }'
if [ -n "$NGINX_CONF" ] && grep -q "location \^~ /ctsubs" "$NGINX_CONF"; then
  echo "[*] nginx: /ctsubs уже есть в $NGINX_CONF"
elif [ -n "$NGINX_CONF" ] && grep -q "location \^~ /ctadmin" "$NGINX_CONF"; then
  echo "[*] nginx: добавляю /ctsubs в $NGINX_CONF"
  BAK=/root/nginx-$(basename "$NGINX_CONF").bak-ytsync; cp "$NGINX_CONF" "$BAK"
  BLOCK="$BLOCK" python3 - "$NGINX_CONF" <<'PY'
import os, re, sys
p = sys.argv[1]; s = open(p).read()
m = re.search(r"\n([ \t]*)location \^~ /ctadmin \{.*?\n\1\}", s, re.S)
s = s[:m.end()] + "\n" + os.environ["BLOCK"] + s[m.end():]
open(p, "w").write(s)
PY
  if nginx -t 2>/dev/null; then systemctl reload nginx; else
    echo "[x] nginx -t не прошёл — возвращаю прежний конфиг"; cp "$BAK" "$NGINX_CONF"; nginx -t; exit 1; fi
else
  cat <<MSG

[!] Конфиг nginx CloudTube не найден. Добавьте в server { } вашего сайта (под паролем сайта, basic auth):

$BLOCK

затем:  nginx -t && systemctl reload nginx
MSG
fi
sleep 1
systemctl is-active --quiet cloudtube-ytsync && echo "[✓] cloudtube-ytsync работает. Страница: https://${CT_DOMAIN:-<ваш-домен>}/ctsubs/" ||
  { echo "[x] сервис не запустился: journalctl -u cloudtube-ytsync -n 30"; exit 1; }
