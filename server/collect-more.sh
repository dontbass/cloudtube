#!/usr/bin/env bash
# CloudTube: добрать файлы оформления, которые collect-design.sh пропустил (brand.js и др.).
# ТОЛЬКО ЧИТАЕТ: пишет лишь /tmp/ct-more.tgz и печатает его в base64. Пароли/ключи/токены в скриптах → ***.
#   curl -fsSL https://raw.githubusercontent.com/dontbass/cloudtube/main/server/collect-more.sh | sudo bash
set -eu
D=/tmp/ct-more
rm -rf "$D"; mkdir -p "$D"
for f in /opt/invidious/custom/brand.js /opt/invidious/custom/inv.css /opt/invidious/invite/invite.py; do
  [ -f "$f" ] && cp "$f" "$D/"
done
for n in dark explore guide invite mobile search shorts ui-admin; do
  [ -f "/root/cloudtube-$n.sh" ] && cp "/root/cloudtube-$n.sh" "$D/"
done
for f in "$D"/*.py "$D"/*.sh; do
  [ -f "$f" ] || continue
  sed -i -E \
    -e 's/((password|passwd|secret|hmac_key|companion_key|SERVER_SECRET_KEY|POSTGRES_PASSWORD|api_key|CT_PASS|PASS)[A-Za-z_]*["'\'']?[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1***/I' \
    -e 's/(htpasswd[[:space:]]+-[a-zA-Z]*b[a-zA-Z]*[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+)[^[:space:]]+/\1***/' \
    -e 's/(Bearer[[:space:]]+)[A-Za-z0-9._~+\/=-]{16,}/\1***/' "$f"
done
ls -la "$D" >&2
tar -czf /tmp/ct-more.tgz -C /tmp ct-more
rm -rf "$D"
echo "---- base64 (скопируйте строку ниже целиком) ----" >&2
base64 -w0 /tmp/ct-more.tgz; echo
