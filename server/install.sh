#!/usr/bin/env bash
# Установка серверных дополнений CloudTube рядом с Invidious (Debian/Ubuntu, root).
#   INV_URL=http://127.0.0.1:3000 FEED_PORT=3200 REGION=RU HL=ru bash install.sh
# Что ставится: yt-dlp, сервис cloudtube-feed (feed.py), nginx-сниппет (подключить вручную, см. вывод).
set -euo pipefail
INV_URL=${INV_URL:-http://127.0.0.1:3000}
FEED_PORT=${FEED_PORT:-3200}
REGION=${REGION:-RU}
HL=${HL:-ru}
DB_CONTAINER=${DB_CONTAINER:-invidious-db}
DIR=/opt/cloudtube-addons
SRC=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" = 0 ] || { echo "запустите от root"; exit 1; }
curl -fsS -m 10 "$INV_URL/api/v1/stats" >/dev/null || { echo "[x] Invidious не отвечает на $INV_URL"; exit 1; }

echo "[*] yt-dlp"
if ! command -v yt-dlp >/dev/null; then
  curl -fsSL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
  chmod 755 /usr/local/bin/yt-dlp
else
  yt-dlp -U >/dev/null 2>&1 || true
fi

echo "[*] feed.py → $DIR"
mkdir -p "$DIR"; install -m 755 "$SRC/feed.py" "$DIR/feed.py"
cat > /etc/systemd/system/cloudtube-feed.service <<UNIT
[Unit]
Description=CloudTube server add-ons (feed, sections, shorts, comments, avatars)
After=network-online.target docker.service
[Service]
Environment=INV_URL=$INV_URL
Environment=FEED_PORT=$FEED_PORT
Environment=REGION=$REGION
Environment=HL=$HL
Environment=DB_CONTAINER=$DB_CONTAINER
ExecStart=/usr/bin/python3 $DIR/feed.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now cloudtube-feed >/dev/null
systemctl restart cloudtube-feed; sleep 2
curl -fsS -m 10 "http://127.0.0.1:$FEED_PORT/ct-api/caps" && echo

INVP=${INV_URL##*:}
mkdir -p /etc/nginx/snippets
sed -e "s/127.0.0.1:3200/127.0.0.1:$FEED_PORT/g" "$SRC/nginx/cloudtube-addons.conf" > /etc/nginx/snippets/cloudtube-addons.conf
cat > /etc/nginx/conf.d/00-cloudtube-map.conf <<MAP
map \$arg_q \$ct_search_upstream {
    default          http://127.0.0.1:$INVP;
    "~*^ct(%3A|:)"   http://127.0.0.1:$FEED_PORT;
}
MAP
cat <<MSG

Готово. Осталось одно: в server { } вашего Invidious в nginx добавьте строку
    include /etc/nginx/snippets/cloudtube-addons.conf;
затем:  nginx -t && systemctl reload nginx
Проверка снаружи:  curl https://<ваш-домен>/ct-api/caps   → {"cloudtube": 1, ...}
Лог:  journalctl -u cloudtube-feed -f
MSG
