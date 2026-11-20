#!/usr/bin/env bash
# CloudTube: модуль «Подписки YouTube» (страница /ctsubs/) на уже работающий сервер — без переустановки.
#   curl -fsSL https://raw.githubusercontent.com/dontbass/cloudtube/main/server/install-ytsync.sh | sudo bash
# Что делает:
#   • ставит ytsync.py в /opt/cloudtube-addons и сервис cloudtube-ytsync (127.0.0.1:3500);
#   • добавляет в nginx location /ctsubs (если находит конфиг CloudTube, иначе печатает, что вставить);
#   • обновляет brand.js и yt.css сайта (пункт «Импорт подписок», плитки каналов на «Подписках»).
# Параметры (необязательно): INV_URL DB_CONTAINER SYNC_PORT SYNC_HOURS REGION HL CT_DOMAIN CT_REPO NGINX_CONF WEB
#   SYNC_USER_MAP="логин_сайта=аккаунт_invidious,…" — если логин сайта не совпадает с аккаунтом Invidious
set -euo pipefail
CT_REPO=${CT_REPO:-https://raw.githubusercontent.com/dontbass/cloudtube/main}
WEB=${WEB:-/opt/cloudtube-web}
DIR=/opt/cloudtube-addons

[ "$(id -u)" = 0 ] || { echo "[x] запустите от root"; exit 1; }

# параметры — как у уже установленных дополнений (cloudtube-feed), иначе ищем сами
envof() { systemctl show "$1" -p Environment 2>/dev/null | tr ' ' '\n' | sed -n "s/^\(Environment=\)\?$2=//p" | head -1; }
INV_URL=${INV_URL:-$(envof cloudtube-feed INV_URL)}
DB_CONTAINER=${DB_CONTAINER:-$(envof cloudtube-feed DB_CONTAINER)}
REGION=${REGION:-$(envof cloudtube-feed REGION)}
HL=${HL:-$(envof cloudtube-feed HL)}
REGION=${REGION:-RU}; HL=${HL:-ru}; SYNC_HOURS=${SYNC_HOURS:-6}

if ! { [ -n "${INV_URL:-}" ] && curl -fsS -m 5 "$INV_URL/api/v1/stats" >/dev/null 2>&1; }; then
  INV_URL=""
  # порты контейнера Invidious, затем прокси nginx, затем обычные порты
  cands=$(docker ps --format '{{.Image}} {{.Ports}}' 2>/dev/null | grep -i 'invidious/invidious\|iv-org/invidious\|invidious:' |
          grep -o '[0-9.]*:[0-9]*->3000' | sed 's/->3000//; s/^0\.0\.0\.0:/127.0.0.1:/; s/^:/127.0.0.1:/' || true)
  cands="$cands $(grep -rhoE 'proxy_pass +http://(127\.0\.0\.1|localhost):[0-9]+' /etc/nginx/ 2>/dev/null | grep -oE '[0-9]+$' | sort -u | sed 's/^/127.0.0.1:/' || true)"
  for c in $cands 127.0.0.1:3000 127.0.0.1:3001 127.0.0.1:8080; do
    if curl -fsS -m 4 "http://$c/api/v1/stats" 2>/dev/null | grep -q '"software"'; then INV_URL="http://$c"; break; fi
  done
fi
[ -n "$INV_URL" ] || { echo "[x] не нашёл Invidious. Укажите адрес: INV_URL=http://127.0.0.1:ПОРТ bash install-ytsync.sh"; exit 1; }
echo "[*] Invidious: $INV_URL"

if [ -z "${DB_CONTAINER:-}" ] || ! docker exec "$DB_CONTAINER" true 2>/dev/null; then
  DB_CONTAINER=$(docker ps --format '{{.Names}} {{.Image}}' | awk '$2 ~ /postgres/ {print $1}' |
                 while read -r n; do docker exec "$n" psql -U kemal -d invidious -Atc "select 1" >/dev/null 2>&1 && { echo "$n"; break; }; done || true)
fi
[ -n "${DB_CONTAINER:-}" ] && docker exec "$DB_CONTAINER" psql -U kemal -d invidious -Atc "select 1" >/dev/null 2>&1 ||
  { echo "[x] нет доступа к базе Invidious (контейнер PostgreSQL, пользователь kemal). Укажите DB_CONTAINER=имя"; exit 1; }
echo "[*] база: контейнер $DB_CONTAINER"

INVP=${INV_URL##*:}
# свободный порт для сервиса (3500, если не занят чем-то другим)
SYNC_PORT=${SYNC_PORT:-$(envof cloudtube-ytsync SYNC_PORT)}
if [ -z "$SYNC_PORT" ]; then
  for p in 3500 3501 3502 3510 3520; do ss -ltn 2>/dev/null | grep -q "[:.]$p " || { SYNC_PORT=$p; break; }; done
fi
SYNC_PORT=${SYNC_PORT:-3500}
# папка оформления сайта (brand.js): из nginx «alias …/custom/»
[ -d "$WEB/custom" ] || WEB=$(grep -rhoE 'alias +[^;]+/custom/' /etc/nginx/ 2>/dev/null | head -1 | sed -E 's/alias +//; s#/custom/$##' || true)
NGINX_CONF=${NGINX_CONF:-$(grep -lsE "proxy_pass http://127\.0\.0\.1:3400|location \^~ /ctadmin" /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf 2>/dev/null | head -1 || true)}
[ -n "$NGINX_CONF" ] || NGINX_CONF=$(grep -lsE "proxy_pass +http://(127\.0\.0\.1|localhost):$INVP" /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf 2>/dev/null | head -1 || true)
NGINX_CONF=$(readlink -f "$NGINX_CONF" 2>/dev/null || true)
if [ -z "${CT_DOMAIN:-}" ] && [ -n "$NGINX_CONF" ]; then
  CT_DOMAIN=$(awk '/server_name/{gsub(";","",$2); if ($2 != "_") {print $2; exit}}' "$NGINX_CONF")
fi
echo "[*] nginx: ${NGINX_CONF:-не найден}, домен: ${CT_DOMAIN:-?}"

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
Environment=SYNC_PORT=$SYNC_PORT
Environment=SYNC_DB=$DIR/ytsync.json
Environment=SYNC_HOURS=$SYNC_HOURS
Environment=DOMAIN=${CT_DOMAIN:-}
Environment=REGION=$REGION
Environment=HL=$HL
Environment=DB_CONTAINER=$DB_CONTAINER
Environment=SYNC_USER_MAP=${SYNC_USER_MAP:-$(envof cloudtube-ytsync SYNC_USER_MAP)}
ExecStart=/usr/bin/python3 $DIR/ytsync.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now cloudtube-ytsync >/dev/null
systemctl restart cloudtube-ytsync

if [ -n "${WEB:-}" ] && [ -d "$WEB/custom" ]; then
  echo "[*] оформление сайта (brand.js, yt.css) → $WEB/custom"
  for f in brand.js yt.css; do
    curl -fsSL "$CT_REPO/server/web/custom/$f" -o "$WEB/custom/$f.new" && mv "$WEB/custom/$f.new" "$WEB/custom/$f"
  done
fi

BLOCK='    # «Подписки YouTube»: перенос подписок с YouTube и удаление всех (для каждого пользователя сайта)
    location ^~ /ctsubs {
        limit_except GET POST { deny all; }
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Remote-User $remote_user;
        proxy_read_timeout 120s;
        proxy_pass http://127.0.0.1:'$SYNC_PORT';
    }'
if [ -n "$NGINX_CONF" ] && grep -q "location \^~ /ctsubs" "$NGINX_CONF"; then
  echo "[*] nginx: /ctsubs уже есть в $NGINX_CONF"
elif [ -n "$NGINX_CONF" ]; then
  echo "[*] nginx: добавляю /ctsubs в $NGINX_CONF"
  BAK=/root/nginx-$(basename "$NGINX_CONF").bak-ytsync; cp "$NGINX_CONF" "$BAK"
  if BLOCK="$BLOCK" python3 - "$NGINX_CONF" <<'PY'
import os, re, sys
p = sys.argv[1]; s = open(p).read(); b = os.environ["BLOCK"]
m = re.search(r"\n([ \t]*)location \^~ /ctadmin \{.*?\n\1\}", s, re.S)
if m:
    s = s[:m.end()] + "\n" + b + s[m.end():]
else:
    # первый «location / {» в server с паролем сайта (auth_basic "…"), иначе просто первый
    pos = None
    starts = [m.end() for m in re.finditer(r"(?m)^\s*server\s*\{", s)] + [len(s)]
    for a, z in zip(starts, starts[1:]):
        body = s[a:z]
        lm = re.search(r"\n[ \t]*location\s+/\s*\{", body)
        if lm and re.search(r'auth_basic\s+"', body):
            pos = a + lm.start(); break
    if pos is None:
        lm = re.search(r"\n[ \t]*location\s+/\s*\{", s)
        if not lm:
            sys.exit(3)
        pos = lm.start()
    s = s[:pos] + "\n" + b + "\n" + s[pos:]
open(p, "w").write(s)
PY
  then
    if nginx -t 2>/dev/null; then systemctl reload nginx; else
      echo "[x] nginx -t не прошёл — возвращаю прежний конфиг"; cp "$BAK" "$NGINX_CONF"; nginx -t; exit 1; fi
    grep -q "auth_basic" "$NGINX_CONF" || echo "[!] в $NGINX_CONF нет auth_basic — страница /ctsubs/ работает только за паролем сайта"
  else
    echo "[!] не нашёл, куда вставить. Добавьте вручную в server { } сайта:"; echo "$BLOCK"
  fi
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
