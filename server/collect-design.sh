#!/usr/bin/env bash
# CloudTube: собрать оформление своего сервера (Materialious, логотип, стили, nginx, docker compose)
# в один архив, чтобы перенести его в скрипт развёртывания.
#
# ТОЛЬКО ЧИТАЕТ: ничего на сервере не меняет и не перезапускает. Пишет лишь /tmp/ct-design.tgz.
# Пароли, ключи и токены в конфигах заменяются на «***».
#
#   curl -fsSL https://raw.githubusercontent.com/dontbass/cloudtube/main/server/collect-design.sh | sudo bash
#   (или с параметром домена: … | sudo CT_DOMAIN=cloud.example.com bash)

set -u
DOMAIN="${CT_DOMAIN:-}"
OUT=/tmp/ct-design
rm -rf "$OUT" && mkdir -p "$OUT"/{nginx,compose,assets,docker}

redact() {
  sed -E \
    -e 's/((password|passwd|secret|hmac_key|companion_key|SERVER_SECRET_KEY|POSTGRES_PASSWORD|token|api_key|apikey|private_key|key)[A-Za-z_]*["'\'']?[[:space:]]*[:=][[:space:]]*).*/\1***/I' \
    -e 's#(postgres(ql)?://[^:]+:)[^@]+@#\1***@#I'
}

echo "== nginx"
for f in /etc/nginx/nginx.conf /etc/nginx/sites-enabled/* /etc/nginx/conf.d/* /etc/nginx/snippets/*; do
  [ -f "$f" ] || continue
  if [ -z "$DOMAIN" ] || grep -q "$DOMAIN" "$f" 2>/dev/null || [[ "$f" == */snippets/* ]] || [[ "$f" == */conf.d/* ]]; then
    redact < "$f" > "$OUT/nginx/$(echo "$f" | tr / _)"
  fi
done

echo "== docker"
if command -v docker >/dev/null; then
  docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}' > "$OUT/docker/ps.txt" 2>/dev/null
  for c in $(docker ps --format '{{.Names}}'); do
    docker inspect "$c" --format '{{json .Config.Env}}' 2>/dev/null | tr ',' '\n' | redact > "$OUT/docker/env_$c.txt"
    docker inspect "$c" --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' > "$OUT/docker/mounts_$c.txt" 2>/dev/null
    docker inspect "$c" --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' >> "$OUT/docker/compose_dirs.txt" 2>/dev/null
  done
fi

echo "== docker compose"
{ sort -u "$OUT/docker/compose_dirs.txt" 2>/dev/null; echo /opt; echo /root; echo /srv; echo /home; } | while read -r d; do
  [ -d "$d" ] || continue
  find "$d" -maxdepth 4 \( -name 'docker-compose*.yml' -o -name 'compose*.yml' -o -name 'docker-compose*.yaml' -o -name '.env' \) 2>/dev/null
done | sort -u | while read -r f; do
  redact < "$f" > "$OUT/compose/$(echo "$f" | tr / _)"
done

echo "== оформление (логотипы, стили, Materialious)"
# файлы оформления: всё, что упоминает CLOUDTUBE/CloudTube, и картинки/стили рядом с ними
for d in /var/www /srv /opt /root /usr/share/nginx $(cut -d' ' -f1 "$OUT"/docker/mounts_* 2>/dev/null | sort -u); do
  [ -e "$d" ] || continue
  grep -rIl --exclude-dir=node_modules --exclude-dir='.*' --exclude='.*' --exclude='*.log' \
    --exclude-dir='postgres*' --exclude-dir=pgdata --exclude-dir=letsencrypt \
    -i 'cloudtube' "$d" 2>/dev/null | head -200
done | sort -u > "$OUT/assets/files.txt"
while read -r f; do
  [ -f "$f" ] || continue
  sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
  [ "$sz" -gt 3000000 ] && continue
  dst="$OUT/assets/$(echo "$f" | tr / _)"
  case "$f" in
    *.yml|*.yaml|*.env|*.conf|*.json) redact < "$f" > "$dst" ;;
    *) # файлы, где могут быть пароли (скрипты, заметки), не берём
       grep -qiE 'CT_PASS|passw|secret|token' "$f" 2>/dev/null && { echo "пропущен (похоже на секреты): $f" >> "$OUT/assets/skipped.txt"; continue; }
       cp "$f" "$dst" ;;
  esac
  # картинки и стили в той же папке (логотипы, favicon)
  for g in "$(dirname "$f")"/*.{svg,png,ico,webp,css}; do
    [ -f "$g" ] && [ "$(stat -c %s "$g")" -lt 3000000 ] && cp -n "$g" "$OUT/assets/$(echo "$g" | tr / _)" 2>/dev/null
  done
done < "$OUT/assets/files.txt"

tar -czf /tmp/ct-design.tgz -C /tmp ct-design
rm -rf "$OUT"
echo
echo "Готово: /tmp/ct-design.tgz ($(du -h /tmp/ct-design.tgz | cut -f1))"
echo "Пароли и ключи в конфигах заменены на ***. Перед отправкой можно проверить: tar -tzf /tmp/ct-design.tgz"
