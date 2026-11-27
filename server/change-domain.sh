#!/usr/bin/env bash
# Переезд сервера CloudTube (Invidious + Materialious + дополнения) на новый домен.
# База Invidious не трогается: пользователи, подписки и история остаются.
#
#   OLD=старый.домен NEW=новый.домен bash change-domain.sh
#
# Перед запуском: A-запись NEW должна указывать на этот сервер.
set -euo pipefail

OLD=${OLD:?укажите OLD=старый.домен}
NEW=${NEW:?укажите NEW=новый.домен}
INV=/opt/invidious
STAMP=$(date +%Y%m%d-%H%M%S)
BK=/root/ct-domain-backup-$STAMP

[ "$(id -u)" = 0 ] || { echo "[x] запустите от root"; exit 1; }
[[ "$NEW" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || { echo "[x] некорректный домен: $NEW"; exit 1; }

MYIP=$(curl -fsS -4 -m 8 https://api.ipify.org || true)
DIP=$(getent ahostsv4 "$NEW" | awk '{print $1; exit}' || true)
if [ -n "$MYIP" ] && [ "$DIP" != "$MYIP" ]; then
  echo "[!] $NEW указывает на ${DIP:-никуда}, а этот сервер — $MYIP."
  echo "    Если домен за Cloudflare (оранжевое облако), это нормально — продолжаю. Иначе прервите (Ctrl+C)."
  sleep 5
fi

# все файлы, где записан старый домен (сертификаты Let's Encrypt не трогаем — certbot выпустит новые)
FILES=$(grep -rlF "$OLD" \
  "$INV/docker-compose.yml" \
  /etc/nginx/sites-available /etc/nginx/snippets /etc/nginx/conf.d \
  /etc/systemd/system/cloudtube-*.service \
  /usr/local/bin/ctinvite \
  /opt/cloudtube-addons /opt/cloudtube-web 2>/dev/null | grep -v '\.json$' || true)
[ -n "$FILES" ] || { echo "[x] старый домен $OLD нигде не найден — проверьте OLD"; exit 1; }

echo "[*] резервная копия: $BK"
mkdir -p "$BK"
for f in $FILES; do mkdir -p "$BK$(dirname "$f")"; cp -a "$f" "$BK$f"; done

echo "[*] меняю $OLD → $NEW в:"
for f in $FILES; do
  echo "    $f"
  # строки с путями к сертификатам оставляем — их перепишет certbot
  sed -i "/letsencrypt/!s/$(printf '%s' "$OLD" | sed 's/[.]/\\./g')/$NEW/g" "$f"
done

echo "[*] nginx"
nginx -t
systemctl reload nginx

echo "[*] сертификат Let's Encrypt для $NEW"
certbot --nginx -d "$NEW" --non-interactive --agree-tos --redirect --register-unsafely-without-email --keep-until-expiring

echo "[*] перезапуск Invidious и веб-интерфейса"
(cd "$INV" && docker compose up -d)

echo "[*] перезапуск дополнений"
systemctl daemon-reload
for s in cloudtube-feed cloudtube-live cloudtube-invite cloudtube-ytsync; do
  systemctl is-enabled --quiet "$s" 2>/dev/null && systemctl restart "$s" && echo "    $s"
done

sleep 5
code=$(curl -s -o /dev/null -w '%{http_code}' -m 15 "https://$NEW/api/v1/stats" || true)
echo "[*] https://$NEW/api/v1/stats → $code"
echo "[✓] готово. Откат: скопировать файлы из $BK обратно и повторить reload/restart."
echo "    Старый сертификат можно удалить: certbot delete --cert-name $OLD"
