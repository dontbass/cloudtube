#!/usr/bin/env bash
# CloudTube: развёртывание своего сервера Invidious «под ключ» на чистом VPS (Debian 11+/Ubuntu 20.04+, root).
#
# Ставит: Docker, Invidious + invidious-companion + PostgreSQL, Materialious (сайт в виде YouTube)
# с оформлением CloudTube (логотип, тема, PWA), nginx, сертификат Let's Encrypt, пароль сайта (Basic Auth),
# аккаунт Invidious с тем же логином и паролем, серверные дополнения CloudTube (лента, Shorts, эфиры, аватарки),
# приглашения для друзей: «Доступ для друзей» на сайте (для администратора) или `ctinvite new` в консоли.
# присмотр за companion: перезапуск, если перестал отдавать видео, и свежий образ каждую ночь.
# «Подписки YouTube» (/ctsubs/): перенос подписок с YouTube (вход кодом или файл Takeout), автозагрузка, «удалить все».
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

if [ "${CT_SKIP_TLS:-}" != 1 ]; then  # CT_SKIP_TLS=1 — проверка без домена и сертификата (CI)
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
fi

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
            public_url: "https://$CT_DOMAIN/companion"
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
        use_pubsub_feeds: false
        channel_threads: 1
        feed_threads: 1
        default_user_preferences:
          locale: $CT_LANG
          default_home: Trending
          region: $CT_REGION
          dark_mode: dark
          local: true
          autoplay: false
          quality: dash
          quality_dash: auto
          related_videos: true
          comments: ["youtube", ""]
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
  materialious:
    image: docker.io/wardpearce/materialious:latest
    container_name: invidious-materialious
    restart: unless-stopped
    ports: ["127.0.0.1:3100:80"]
    environment:
      VITE_DEFAULT_INVIDIOUS_INSTANCE: "https://$CT_DOMAIN"
      VITE_DEFAULT_COMPANION_INSTANCE: "https://$CT_DOMAIN/companion"
      VITE_DEFAULT_FRONTEND_URL: "https://$CT_DOMAIN"
      VITE_DEFAULT_SPONSERBLOCK_INSTANCE: "https://sponsor.ajay.app"
      VITE_DEFAULT_DEARROW_INSTANCE: "https://sponsor.ajay.app"
      VITE_DEFAULT_DEARROW_THUMBNAIL_INSTANCE: "https://dearrow-thumb.ajay.app"
      VITE_DEFAULT_RETURNYTDISLIKES_INSTANCE: "https://returnyoutubedislikeapi.com"
      VITE_DEFAULT_SETTINGS: '{"region":"$CT_REGION","proxyVideos":true,"dashEnabled":true,"themeColor":"#ff0033"}'
    logging:
      options: { max-size: "10m", max-file: "3" }
volumes:
  postgresdata:
  companioncache:
EOF
chmod 600 docker-compose.yml .secrets

P 45 "Скачиваю образы Invidious и Materialious (3–6 минут)"
run docker compose pull || ERR "Не удалось скачать образы Docker"
P 60 "Запускаю Invidious"
run docker compose up -d || ERR "Invidious не запустился (docker compose up)"
for i in $(seq 1 60); do
  curl -fsS -m 5 http://127.0.0.1:3000/api/v1/stats >/dev/null 2>&1 && break
  P 62 "Жду, пока Invidious поднимется ($((i*5)) с)"
  sleep 5
done
curl -fsS -m 5 http://127.0.0.1:3000/api/v1/stats >/dev/null || ERR "Invidious не отвечает — docker compose logs invidious"

P 66 "Ставлю оформление CloudTube (логотип, тема сайта, PWA)"
WEB=/opt/cloudtube-web
mkdir -p $WEB/custom $WEB/pwa
for f in yt.css inv.css inv.js brand.js logo-icon.svg logo-dark.svg logo-light.svg; do
  curl -fsSL "$CT_REPO/server/web/custom/$f" -o "$WEB/custom/$f" 2>>/var/log/ct-deploy.debug || echo "нет $f" >> /var/log/ct-deploy.debug
done
for f in manifest.webmanifest icon-192.png icon-512.png icon-512-maskable.png; do
  curl -fsSL "$CT_REPO/server/web/pwa/$f" -o "$WEB/pwa/$f" 2>>/var/log/ct-deploy.debug || echo "нет $f" >> /var/log/ct-deploy.debug
done
[ -s $WEB/custom/brand.js ] || : > $WEB/custom/brand.js
chmod -R a+rX $WEB
V=$(date +%s)

P 68 "Настраиваю nginx"
htpasswd -bc /etc/nginx/.ct-htpasswd "$CT_USER" "$CT_PASS" >/dev/null 2>&1 || ERR "htpasswd"
chmod 640 /etc/nginx/.ct-htpasswd; chgrp www-data /etc/nginx/.ct-htpasswd 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/conf.d/00-cloudtube-map.conf <<'EOF'
# поиск: q=ct:<раздел> → дополнения CloudTube, остальное → Invidious
map $arg_q $ct_search_upstream {
    default          http://127.0.0.1:3000;
    "~*^ct(%3A|:)"   http://127.0.0.1:3200;
}
# пароль сайта (Basic) дальше nginx не передаём — Invidious путает его со своим входом; Bearer проходит
map $http_authorization $ct_upstream_auth {
    default     $http_authorization;
    "~*^Basic " "";
}
EOF
cat > /etc/nginx/conf.d/00-cloudtube-cache.conf <<'EOF'
proxy_cache_path /var/cache/nginx/cloudtube levels=1:2 keys_zone=ctimg:20m max_size=1g inactive=14d use_temp_path=off;
EOF
mkdir -p /var/cache/nginx/cloudtube
cat > /etc/nginx/conf.d/00-cloudtube-gzip.conf <<'EOF'
gzip_vary on;
gzip_proxied any;
gzip_comp_level 5;
gzip_min_length 1024;
gzip_types text/css application/javascript text/javascript application/json image/svg+xml application/manifest+json font/ttf;
EOF
mkdir -p /etc/nginx/snippets
cat > /etc/nginx/snippets/cloudtube-proxy.conf <<'EOF'
proxy_http_version 1.1;
proxy_set_header Host $host;
proxy_set_header Connection "";
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto https;
proxy_set_header Authorization $ct_upstream_auth;
proxy_buffering off;
proxy_request_buffering off;
proxy_read_timeout 600s;
proxy_send_timeout 600s;
EOF
# оформление сайта (Materialious): тема YouTube, логотип и название CloudTube
cat > /etc/nginx/snippets/cloudtube-skin.conf <<EOF
proxy_set_header Accept-Encoding "";
sub_filter_types text/html;
sub_filter_once on;
sub_filter '</head>' '<link rel="stylesheet" href="/custom/yt.css?v=$V"><link rel="icon" href="/custom/logo-icon.svg?v=$V"><link rel="manifest" href="/manifest.webmanifest"><script src="/custom/brand.js?v=$V" defer></script></head>';
sub_filter '<title>Materialious</title>' '<title>CloudTube</title>';
EOF
# оформление страниц самого Invidious (вход, настройки, импорт)
cat > /etc/nginx/snippets/cloudtube-pages.conf <<EOF
proxy_set_header Accept-Encoding "";
sub_filter_types text/html;
sub_filter_once on;
sub_filter '</head>' '<link rel="stylesheet" href="/custom/inv.css?v=$V"><script src="/custom/inv.js?v=$V"></script></head>';
EOF
cat > /etc/nginx/sites-available/cloudtube.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $CT_DOMAIN;
    client_max_body_size 20m;
    server_tokens off;
    add_header X-Robots-Tag "noindex, nofollow" always;
    add_header Referrer-Policy "no-referrer" always;
    auth_basic "CloudTube";
    auth_basic_user_file /etc/nginx/.ct-htpasswd;

    location /.well-known/acme-challenge/ { auth_basic off; root /var/www/html; }
    location = /robots.txt { auth_basic off; default_type text/plain; return 200 "User-agent: *\nDisallow: /\n"; }

    # видеопоток
    location ^~ /companion { include snippets/cloudtube-proxy.conf; proxy_pass http://127.0.0.1:8282; }

    # вход в аккаунт Invidious из клиентов (свой логин внутри)
    location ^~ /api/v1/auth/ { auth_basic off; include snippets/cloudtube-proxy.conf; proxy_pass http://127.0.0.1:3000; }

    # дополнения CloudTube: главная, разделы, Shorts, комментарии
    location = /api/v1/popular { include snippets/cloudtube-proxy.conf; proxy_pass http://127.0.0.1:3200; }
    location = /api/v1/search  { include snippets/cloudtube-proxy.conf; proxy_pass \$ct_search_upstream; }
    location ^~ /ct-api/       { include snippets/cloudtube-proxy.conf; proxy_pass http://127.0.0.1:3200; }

    # эфиры (HLS) и картинки каналов
    location ~ ^/api/v1/videos/ { include snippets/cloudtube-proxy.conf; proxy_pass http://127.0.0.1:3300; }
    location ^~ /live/          { include snippets/cloudtube-proxy.conf; proxy_pass http://127.0.0.1:3300; }
    location ^~ /ggpht/ {
        proxy_pass http://127.0.0.1:3300;
        proxy_http_version 1.1; proxy_set_header Connection "";
        proxy_buffering on; proxy_cache ctimg; proxy_cache_key \$uri;
        proxy_cache_valid 200 14d; proxy_cache_valid 404 10m; proxy_cache_lock on;
        proxy_cache_use_stale error timeout updating;
        proxy_ignore_headers Cache-Control Expires Set-Cookie;
        expires 7d;
    }
    location ^~ /vi/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1; proxy_set_header Host \$host; proxy_set_header Connection "";
        proxy_buffering on; proxy_cache ctimg; proxy_cache_key \$uri;
        proxy_cache_valid 200 3d; proxy_cache_valid 404 10m; proxy_cache_lock on;
        proxy_cache_use_stale error timeout updating;
        proxy_ignore_headers Cache-Control Expires Set-Cookie;
        expires 3d;
    }

    # Invidious: API, медиа, вход, настройки, импорт и их статика
    location ~ ^/(api/|sb/|s_p/|yts/|latest_version|videoplayback|authorize_token|token_manager|login|logout|signout|preferences|data_control|subscription_manager|subscription_ajax|playlist_ajax|watch_ajax|feed/|css/|js/|videojs/|fonts/|toggle_theme) {
        include snippets/cloudtube-proxy.conf;
        include snippets/cloudtube-pages.conf;
        proxy_pass http://127.0.0.1:3000;
    }

    # приглашения (регистрация по ссылке — без пароля сайта) и «Доступ для друзей» (только администратор)
    location ^~ /invite/ {
        auth_basic off;
        limit_except GET POST { deny all; }
        include snippets/cloudtube-proxy.conf;
        proxy_pass http://127.0.0.1:3400;
    }
    location ^~ /ctadmin {
        limit_except GET POST { deny all; }
        include snippets/cloudtube-proxy.conf;
        proxy_set_header X-Remote-User \$remote_user;
        proxy_pass http://127.0.0.1:3400;
    }
    # «Подписки YouTube»: перенос подписок с YouTube и удаление всех (для каждого пользователя сайта)
    location ^~ /ctsubs {
        limit_except GET POST { deny all; }
        include snippets/cloudtube-proxy.conf;
        proxy_set_header X-Remote-User \$remote_user;
        proxy_pass http://127.0.0.1:3500;
    }

    # оформление и логотип
    location ^~ /custom/ { alias $WEB/custom/; expires 1h; }
    location = /logo.svg { alias $WEB/custom/logo-icon.svg; }

    # PWA: Chrome запрашивает манифест и значки без пароля — открываем только их
    location = /manifest.webmanifest { auth_basic off; default_type application/manifest+json; alias $WEB/pwa/manifest.webmanifest; add_header Cache-Control "no-cache"; }
    location ^~ /ct-pwa/ { auth_basic off; alias $WEB/pwa/; expires 7d; }
    location = /sw.js    { auth_basic off; include snippets/cloudtube-proxy.conf; proxy_pass http://127.0.0.1:3100; add_header Cache-Control "no-cache"; }
    location ^~ /workbox- { auth_basic off; include snippets/cloudtube-proxy.conf; proxy_pass http://127.0.0.1:3100; }

    # JS/CSS сайта: долгий кэш
    location ^~ /_app/immutable/ {
        proxy_pass http://127.0.0.1:3100;
        proxy_http_version 1.1; proxy_set_header Host \$host; proxy_set_header Connection "";
        proxy_buffering on;
        proxy_hide_header Cache-Control; proxy_hide_header Expires;
        add_header Cache-Control "public, max-age=31536000, immutable" always;
    }

    # всё остальное — сайт (Materialious) с оформлением CloudTube
    location / {
        include snippets/cloudtube-proxy.conf;
        include snippets/cloudtube-skin.conf;
        add_header Cache-Control "no-cache, must-revalidate" always;
        add_header X-Robots-Tag "noindex, nofollow" always;
        add_header Referrer-Policy "no-referrer" always;
        proxy_pass http://127.0.0.1:3100;
    }
}
EOF
ln -sf /etc/nginx/sites-available/cloudtube.conf /etc/nginx/sites-enabled/cloudtube.conf
nginx -t >>/var/log/ct-deploy.debug 2>&1 || ERR "Ошибка в настройках nginx (nginx -t)"
systemctl enable nginx >/dev/null 2>&1; systemctl restart nginx || ERR "nginx не запустился"
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  run ufw allow 22/tcp; run ufw allow 80/tcp; run ufw allow 443/tcp
fi

if [ "${CT_SKIP_TLS:-}" != 1 ]; then
P 75 "Выпускаю сертификат Let's Encrypt для $CT_DOMAIN"
if [ -n "$CT_EMAIL" ]; then EM=(-m "$CT_EMAIL"); else EM=(--register-unsafely-without-email); fi
run certbot --nginx -d "$CT_DOMAIN" --non-interactive --agree-tos --redirect "${EM[@]}" \
  || ERR "Сертификат не выпущен: проверьте A-запись и что порт 80 открыт (см. /var/log/ct-deploy.debug)"
systemctl reload nginx
fi

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

P 92 "Ставлю эфиры и картинки каналов (cloudtube-live)"
if curl -fsSL "$CT_REPO/server/live.py" -o /opt/cloudtube-addons/live.py; then
  chmod 755 /opt/cloudtube-addons/live.py
  cat > /etc/systemd/system/cloudtube-live.service <<EOF
[Unit]
Description=CloudTube live (HLS-эфиры, картинки каналов)
After=network-online.target docker.service
[Service]
Environment=INV_URL=http://127.0.0.1:3000
Environment=LIVE_PORT=3300
Environment=PUBLIC_URL=https://$CT_DOMAIN
Environment=YTDLP=/usr/local/bin/yt-dlp
ExecStart=/usr/bin/python3 /opt/cloudtube-addons/live.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload; systemctl enable --now cloudtube-live >/dev/null 2>&1; systemctl restart cloudtube-live
else
  echo "live.py не скачался" >> /var/log/ct-deploy.debug
fi

P 94 "Ставлю приглашения для друзей (cloudtube-invite)"
if curl -fsSL "$CT_REPO/server/invite.py" -o /opt/cloudtube-addons/invite.py; then
  chmod 755 /opt/cloudtube-addons/invite.py
  ENVS="INVITE_DB=/opt/cloudtube-addons/invites.json HTPASSWD=/etc/nginx/.ct-htpasswd DOMAIN=$CT_DOMAIN INVITE_PORT=3400 ADMIN_USERS=$CT_USER DB_CONTAINER=invidious-db"
  cat > /usr/local/bin/ctinvite <<EOF
#!/bin/sh
exec env $ENVS /usr/bin/python3 /opt/cloudtube-addons/invite.py "\$@"
EOF
  chmod 755 /usr/local/bin/ctinvite
  cat > /etc/systemd/system/cloudtube-invite.service <<EOF
[Unit]
Description=CloudTube invites (регистрация друзей по ссылке)
After=network-online.target docker.service
[Service]
Environment=INVITE_DB=/opt/cloudtube-addons/invites.json
Environment=HTPASSWD=/etc/nginx/.ct-htpasswd
Environment=DOMAIN=$CT_DOMAIN
Environment=INVITE_PORT=3400
Environment=ADMIN_USERS=$CT_USER
Environment=DB_CONTAINER=invidious-db
ExecStart=/usr/bin/python3 /opt/cloudtube-addons/invite.py serve
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload; systemctl enable --now cloudtube-invite >/dev/null 2>&1; systemctl restart cloudtube-invite
else
  echo "invite.py не скачался" >> /var/log/ct-deploy.debug
fi

P 94 "Ставлю перенос подписок с YouTube (cloudtube-ytsync)"
if curl -fsSL "$CT_REPO/server/ytsync.py" -o /opt/cloudtube-addons/ytsync.py; then
  chmod 755 /opt/cloudtube-addons/ytsync.py
  cat > /etc/systemd/system/cloudtube-ytsync.service <<EOF
[Unit]
Description=CloudTube: подписки YouTube (перенос, автозагрузка, удаление всех)
After=network-online.target docker.service
[Service]
Environment=INV_URL=http://127.0.0.1:3000
Environment=SYNC_PORT=3500
Environment=SYNC_DB=/opt/cloudtube-addons/ytsync.json
Environment=SYNC_HOURS=6
Environment=DOMAIN=$CT_DOMAIN
Environment=REGION=$CT_REGION
Environment=HL=$CT_LANG
Environment=DB_CONTAINER=invidious-db
ExecStart=/usr/bin/python3 /opt/cloudtube-addons/ytsync.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload; systemctl enable --now cloudtube-ytsync >/dev/null 2>&1; systemctl restart cloudtube-ytsync
else
  echo "ytsync.py не скачался" >> /var/log/ct-deploy.debug
fi

P 94 "Ставлю присмотр за companion (автоперезапуск и ночное обновление)"
if curl -fsSL "$CT_REPO/server/install-guard.sh" -o /tmp/ct-install-guard.sh; then
  CT_REPO="$CT_REPO" COMP_URL=http://127.0.0.1:8282/companion bash /tmp/ct-install-guard.sh >>/var/log/ct-deploy.debug 2>&1 ||
    echo "guard не установился" >> /var/log/ct-deploy.debug
  rm -f /tmp/ct-install-guard.sh
fi

P 95 "Проверяю сервер снаружи"
sleep 3
BASE="https://$CT_DOMAIN"; HOSTH=()
[ "${CT_SKIP_TLS:-}" = 1 ] && { BASE="http://127.0.0.1"; HOSTH=(-H "Host: $CT_DOMAIN"); }
code=$(curl -s -o /dev/null -w '%{http_code}' -m 20 "${HOSTH[@]}" -u "$CT_USER:$CT_PASS" "$BASE/api/v1/stats")
[ "$code" = 200 ] || ERR "https://$CT_DOMAIN отвечает $code — проверьте /var/log/ct-deploy.debug"
addons=$(curl -s -m 10 "${HOSTH[@]}" -u "$CT_USER:$CT_PASS" "$BASE/ct-api/caps" | grep -c cloudtube || true)
rm -f /root/.ct-deploy.env
P 100 "Готово"
echo "##DONE {\"url\":\"https://$CT_DOMAIN\",\"user\":\"$CT_USER\",\"addons\":$([ "$addons" -gt 0 ] && echo true || echo false)}"
