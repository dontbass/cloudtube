#!/usr/bin/env bash
# CloudTube: развёртывание своего сервера Invidious «под ключ» на чистом VPS (Debian 11+/Ubuntu 20.04+, root).
#
# Ставит: Docker, Invidious + invidious-companion + PostgreSQL, nginx, сертификат Let's Encrypt,
# пароль сайта (Basic Auth), аккаунт Invidious с тем же логином и паролем, серверные дополнения CloudTube.
#
# Параметры — переменные окружения или файл /root/.ct-deploy.env:
#   CT_DOMAIN=video.example.com   домен (A-запись уже указывает на этот сервер)
#   CT_USER=admin                 логин сайта и аккаунта Invidious
#   CT_PASS=secret                пароль
#   CT_EMAIL=me@example.com       почта для Let's Encrypt (необязательно)
#   CT_REGION=RU CT_LANG=ru       регион трендов и язык (необязательно)
#
# Прогресс выводится строками «##P <проценты> <текст>», итог — «##DONE <json>» или «##ERR <текст>».
# Приложение CloudTube запускает этот скрипт по SSH и рисует по ним прогресс-бар.
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
[ -f /root/.ct-deploy.env ] && . /root/.ct-deploy.env

P() { echo "##P $1 $2"; }
ERR() { echo "##ERR $*"; exit 1; }
run() { "$@" >>/var/log/ct-deploy.debug 2>&1; }

CT_DOMAIN=${CT_DOMAIN:-}; CT_USER=${CT_USER:-}; CT_PASS=${CT_PASS:-}
CT_EMAIL=${CT_EMAIL:-}; CT_REGION=${CT_REGION:-RU}; CT_LANG=${CT_LANG:-ru}
CT_REPO=${CT_REPO:-https://raw.githubusercontent.com/dontbass/cloudtube/main}
INV=/opt/invidious

P 1 "Проверяю параметры и систему"
[ "$(id -u)" = 0 ] || ERR "Нужны права root"
[ -n "$CT_DOMAIN" ] && [ -n "$CT_USER" ] && [ -n "$CT_PASS" ] || ERR "Не заданы домен, логин или пароль"
[[ "$CT_DOMAIN" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || ERR "Некорректный домен: $CT_DOMAIN"
[[ "$CT_USER" =~ ^[A-Za-z0-9._@-]{3,64}$ ]] || ERR "Логин: 3–64 символа, латиница, цифры, . _ @ -"
[ ${#CT_PASS} -ge 8 ] || ERR "Пароль должен быть не короче 8 символов"
. /etc/os-release 2>/dev/null || true
case "${ID:-}" in debian|ubuntu) ;; *) ERR "Поддерживаются Debian и Ubuntu (найдено: ${PRETTY_NAME:-неизвестно})";; esac
MEM=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
[ "$MEM" -ge 900 ] || ERR "Мало памяти: ${MEM} МБ, нужно от 1 ГБ"
: > /var/log/ct-deploy.debug

P 4 "Проверяю, что домен $CT_DOMAIN указывает на этот сервер"
MYIP=$(curl -4 -fsS -m 10 https://api.ipify.org || curl -4 -fsS -m 10 https://ifconfig.me || true)
[ -n "$MYIP" ] || ERR "Не удалось узнать внешний IP сервера — нет доступа в интернет?"
ok=0
for i in $(seq 1 30); do
  DIP=$(getent ahostsv4 "$CT_DOMAIN" | awk '{print $1; exit}')
  [ -z "$DIP" ] && DIP=$(curl -fsS -m 8 -H 'accept: application/dns-json' "https://cloudflare-dns.com/dns-query?name=$CT_DOMAIN&type=A" | grep -o '"data":"[0-9.]*"' | head -1 | cut -d'"' -f4)
  if [ "$DIP" = "$MYIP" ]; then ok=1; break; fi
  P 4 "Жду A-запись: $CT_DOMAIN → ${DIP:-нет записи}, нужно $MYIP (попытка $i из 30)"
  sleep 10
done
[ $ok = 1 ] || ERR "Домен $CT_DOMAIN не указывает на $MYIP. Создайте A-запись у регистратора и повторите"

if [ "$MEM" -lt 1900 ] && ! swapon --show | grep -q .; then
  P 7 "Мало памяти — добавляю файл подкачки 2 ГБ"
  run fallocate -l 2G /swapfile || run dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile; run mkswap /swapfile; run swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

P 10 "Обновляю список пакетов"
run apt-get update -y || ERR "apt-get update не прошёл"
P 15 "Ставлю nginx, certbot и утилиты"
run apt-get install -y ca-certificates curl gnupg git nginx certbot python3-certbot-nginx apache2-utils python3 openssl \
  || ERR "Не удалось установить пакеты (см. /var/log/ct-deploy.debug)"

if ! command -v docker >/dev/null; then
  P 25 "Ставлю Docker (2–4 минуты)"
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh || ERR "Не удалось скачать установщик Docker"
  run sh /tmp/get-docker.sh || ERR "Docker не установился (см. /var/log/ct-deploy.debug)"
fi
systemctl enable --now docker >/dev/null 2>&1
docker compose version >/dev/null 2>&1 || ERR "Нет docker compose"

P 38 "Готовлю Invidious"
mkdir -p $INV
if [ ! -d $INV/src/.git ]; then
  run git clone --depth 1 https://github.com/iv-org/invidious $INV/src || ERR "Не удалось скачать Invidious"
fi
cd $INV
[ -f .secrets ] || cat > .secrets <<EOF
HMAC=$(openssl rand -hex 20)
COMPANION=$(openssl rand -hex 8)
DBPASS=$(openssl rand -hex 12)
EOF
. ./.secrets
cat > docker-compose.yml <<EOF
services:
  invidious:
    image: quay.io/invidious/invidious:latest
    restart: unless-stopped
    ports: ["127.0.0.1:3000:3000"]
    environment:
      INVIDIOUS_CONFIG: |
        db:
          dbname: invidious
          user: kemal
          password: $DBPASS
          host: invidious-db
          port: 5432
        check_tables: true
        invidious_companion:
          - private_url: "http://companion:8282/companion"
        invidious_companion_key: "$COMPANION"
        external_port: 443
        domain: $CT_DOMAIN
        https_only: true
        hmac_key: "$HMAC"
        registration_enabled: true
        captcha_enabled: false
        login_enabled: true
        popular_enabled: true
        statistics_enabled: true
        default_user_preferences:
          locale: $CT_LANG
          region: $CT_REGION
          quality: dash
          local: true
    depends_on: [invidious-db]
    healthcheck:
      test: wget -nv --tries=1 --spider http://127.0.0.1:3000/api/v1/trending || exit 1
      interval: 30s
      timeout: 5s
      retries: 2
  companion:
    image: quay.io/invidious/invidious-companion:latest
    restart: unless-stopped
    environment:
      - SERVER_SECRET_KEY=$COMPANION
    ports: ["127.0.0.1:8282:8282"]
    cap_drop: [ALL]
    read_only: true
    volumes: [companioncache:/var/tmp/youtubei.js:rw]
    security_opt: ["no-new-privileges:true"]
  invidious-db:
    image: docker.io/library/postgres:14
    container_name: invidious-db
    restart: unless-stopped
    volumes:
      - postgresdata:/var/lib/postgresql/data
      - ./src/config/sql:/config/sql
      - ./src/docker/init-invidious-db.sh:/docker-entrypoint-initdb.d/init-invidious-db.sh
    environment:
      POSTGRES_DB: invidious
      POSTGRES_USER: kemal
      POSTGRES_PASSWORD: $DBPASS
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U kemal -d invidious"]
volumes:
  postgresdata:
  companioncache:
EOF
chmod 600 docker-compose.yml .secrets

P 45 "Скачиваю образы Invidious (3–6 минут)"
run docker compose pull || ERR "Не удалось скачать образы Docker"
P 60 "Запускаю Invidious"
run docker compose up -d || ERR "Invidious не запустился (docker compose up)"
for i in $(seq 1 60); do
  curl -fsS -m 5 http://127.0.0.1:3000/api/v1/stats >/dev/null 2>&1 && break
  P 62 "Жду, пока Invidious поднимется ($((i*5)) с)"
  sleep 5
done
curl -fsS -m 5 http://127.0.0.1:3000/api/v1/stats >/dev/null || ERR "Invidious не отвечает — docker compose logs invidious"

P 68 "Настраиваю nginx"
htpasswd -bc /etc/nginx/.ct-htpasswd "$CT_USER" "$CT_PASS" >/dev/null 2>&1 || ERR "htpasswd"
chmod 640 /etc/nginx/.ct-htpasswd; chgrp www-data /etc/nginx/.ct-htpasswd 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/conf.d/00-cloudtube-map.conf <<'EOF'
map $arg_q $ct_search_upstream {
    default          http://127.0.0.1:3000;
    "~*^ct(%3A|:)"   http://127.0.0.1:3200;
}
# пароль сайта не передаём в Invidious — он путает его со своим входом
map $http_authorization $ct_upstream_auth {
    default     $http_authorization;
    "~*^Basic " "";
}
EOF
mkdir -p /etc/nginx/snippets
cat > /etc/nginx/snippets/cloudtube-proxy.conf <<'EOF'
proxy_http_version 1.1;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header Authorization $ct_upstream_auth;
proxy_set_header Connection "";
proxy_buffering off;
proxy_read_timeout 300s;
EOF
cat > /etc/nginx/sites-available/cloudtube.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $CT_DOMAIN;
    client_max_body_size 20m;
    auth_basic "CloudTube";
    auth_basic_user_file /etc/nginx/.ct-htpasswd;

    location /.well-known/acme-challenge/ { auth_basic off; root /var/www/html; }
    location /companion { include snippets/cloudtube-proxy.conf; proxy_pass http://127.0.0.1:8282; }
    location = /api/v1/popular { include snippets/cloudtube-proxy.conf; proxy_pass http://127.0.0.1:3200; }
    location = /api/v1/search  { include snippets/cloudtube-proxy.conf; proxy_pass \$ct_search_upstream; }
    location ^~ /ct-api/       { include snippets/cloudtube-proxy.conf; proxy_pass http://127.0.0.1:3200; }
    location / { include snippets/cloudtube-proxy.conf; proxy_pass http://127.0.0.1:3000; }
}
EOF
ln -sf /etc/nginx/sites-available/cloudtube.conf /etc/nginx/sites-enabled/cloudtube.conf
nginx -t >>/var/log/ct-deploy.debug 2>&1 || ERR "Ошибка в настройках nginx (nginx -t)"
systemctl enable nginx >/dev/null 2>&1; systemctl restart nginx || ERR "nginx не запустился"
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  run ufw allow 22/tcp; run ufw allow 80/tcp; run ufw allow 443/tcp
fi

P 75 "Выпускаю сертификат Let's Encrypt для $CT_DOMAIN"
if [ -n "$CT_EMAIL" ]; then EM=(-m "$CT_EMAIL"); else EM=(--register-unsafely-without-email); fi
run certbot --nginx -d "$CT_DOMAIN" --non-interactive --agree-tos --redirect "${EM[@]}" \
  || ERR "Сертификат не выпущен: проверьте A-запись и что порт 80 открыт (см. /var/log/ct-deploy.debug)"
systemctl reload nginx

P 83 "Создаю аккаунт $CT_USER в Invidious"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:3000/login?type=invidious" \
  -H "Host: $CT_DOMAIN" -H "X-Forwarded-Proto: https" \
  --data-urlencode "email=$CT_USER" --data-urlencode "password=$CT_PASS" --data-urlencode "action=register")
case "$code" in 302|303|200) ;; *) echo "регистрация: HTTP $code" >> /var/log/ct-deploy.debug;; esac
# дальше регистрация закрыта — сервер личный
sed -i 's/registration_enabled: true/registration_enabled: false/' docker-compose.yml
run docker compose up -d

P 88 "Ставлю дополнения CloudTube (лента, Shorts, комментарии)"
mkdir -p /opt/cloudtube-addons
if curl -fsSL "$CT_REPO/server/feed.py" -o /opt/cloudtube-addons/feed.py; then
  chmod 755 /opt/cloudtube-addons/feed.py
  [ -x /usr/local/bin/yt-dlp ] || { curl -fsSL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp && chmod 755 /usr/local/bin/yt-dlp; }
  cat > /etc/systemd/system/cloudtube-feed.service <<EOF
[Unit]
Description=CloudTube server add-ons
After=network-online.target docker.service
[Service]
Environment=INV_URL=http://127.0.0.1:3000
Environment=FEED_PORT=3200
Environment=REGION=$CT_REGION
Environment=HL=$CT_LANG
Environment=DB_CONTAINER=invidious-db
ExecStart=/usr/bin/python3 /opt/cloudtube-addons/feed.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload; systemctl enable --now cloudtube-feed >/dev/null 2>&1; systemctl restart cloudtube-feed
else
  echo "дополнения не скачались" >> /var/log/ct-deploy.debug
fi

P 95 "Проверяю сервер снаружи"
sleep 3
code=$(curl -s -o /dev/null -w '%{http_code}' -m 20 -u "$CT_USER:$CT_PASS" "https://$CT_DOMAIN/api/v1/stats")
[ "$code" = 200 ] || ERR "https://$CT_DOMAIN отвечает $code — проверьте /var/log/ct-deploy.debug"
addons=$(curl -s -m 10 -u "$CT_USER:$CT_PASS" "https://$CT_DOMAIN/ct-api/caps" | grep -c cloudtube || true)
rm -f /root/.ct-deploy.env
P 100 "Готово"
echo "##DONE {\"url\":\"https://$CT_DOMAIN\",\"user\":\"$CT_USER\",\"addons\":$([ "$addons" -gt 0 ] && echo true || echo false)}"
