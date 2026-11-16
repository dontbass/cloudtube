#!/usr/bin/env python3
"""CloudTube invites.
Сервер:  invite.py serve                      — страница /invite/<token> (без basic auth)
CLI:     ctinvite new [-u USES] [-d DAYS] [-n NOTE]  — создать ссылку-приглашение
         ctinvite list | revoke TOKEN | users | deluser NAME
Регистрация создаёт ОДНУ пару логин/пароль: и для входа на сайт (basic auth nginx),
и для аккаунта Invidious (подписки, история)."""
import html, json, os, re, secrets, subprocess, sys, threading, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DATA = os.environ.get("INVITE_DB", "/opt/invidious/invites.json")
HTPASSWD = os.environ.get("HTPASSWD", "/etc/nginx/.htpasswd-invidious")
DOMAIN = os.environ.get("DOMAIN", "localhost")
LISTEN = int(os.environ.get("INVITE_PORT", "3400"))
DB_CONTAINER = os.environ.get("DB_CONTAINER", "invidious-db")
ADMINS = {a.strip() for a in os.environ.get("ADMIN_USERS", "admin").split(",") if a.strip()}
USER_RE = re.compile(r"^[a-z0-9][a-z0-9_.-]{2,31}$")
PASS_RE = re.compile(r"^[A-Za-z0-9_\-.!@#%^&+=?]{8,64}$")
_lock = threading.Lock()

LOGO = ('<svg viewBox="0 0 230 52" width="190" height="43" xmlns="http://www.w3.org/2000/svg"><g transform="translate(0 1)">'
        '<path d="M22 14 14 4M30 14l8-10" stroke="#9aa4b2" stroke-width="2.6" stroke-linecap="round"/>'
        '<circle cx="14" cy="4" r="2.4" fill="#9aa4b2"/><circle cx="38" cy="4" r="2.4" fill="#9aa4b2"/>'
        '<rect x="3" y="13" width="46" height="33" rx="7" fill="#e85d4a"/><rect x="7.5" y="17.5" width="29" height="24" rx="4.5" fill="#1f2a3a"/>'
        '<path d="M11 22.5c5-2 13-2 18 1" stroke="#7fb3ff" stroke-width="2" stroke-linecap="round" fill="none" opacity=".7"/>'
        '<circle cx="42.5" cy="23" r="2.6" fill="#ffd166"/><circle cx="42.5" cy="31" r="2.6" fill="#ffd166"/>'
        '<rect x="40" y="37" width="5" height="2.4" rx="1.2" fill="#7a2a20"/><path d="M12 46l-2 4M40 46l2 4" stroke="#7a2a20" stroke-width="2.6" stroke-linecap="round"/></g>'
        '<text x="58" y="36" font-family="Roboto,Arial,sans-serif" font-size="25" font-weight="800" letter-spacing="-.5" fill="currentColor">CLOUD<tspan fill="#e85d4a">TUBE</tspan></text></svg>')

CSS = """:root{--bg:#0f0f0f;--card:#1f1f1f;--tx:#f1f1f1;--tx2:#aaa;--tx3:#888;--bd:#3f3f3f;--bd2:#2c2c2c;--in:#121212;--hv:#272727;--hv2:#242424;--hv3:#3a3a3a;--btnh:#d9d9d9;--sh:var(--sh);--okb:#16301d;--okt:#8bd49b;--erb:#3b1a1a;--ert:#ff8a80;--link:#3ea6ff}
html.ct-light{--bg:#f2f2f2;--card:#fff;--tx:#0f0f0f;--tx2:#606060;--tx3:#777;--bd:#d3d3d3;--bd2:#e5e5e5;--in:#fff;--hv:#f2f2f2;--hv2:#f7f7f7;--hv3:#e5e5e5;--btnh:#333;--sh:rgba(0,0,0,.08);--okb:#e6f4ea;--okt:#137333;--erb:#fce8e6;--ert:#c5221f;--link:#065fd4}
*{box-sizing:border-box}body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
background:var(--bg);color:var(--tx);font:15px/1.5 Roboto,Arial,sans-serif;padding:16px}
.card svg{color:var(--tx)}.card{width:100%;max-width:400px;background:var(--card);border-radius:16px;padding:28px 28px 24px;box-shadow:0 8px 40px var(--sh)}
h1{font-size:20px;margin:18px 0 6px;font-weight:600}p{margin:0 0 16px;color:var(--tx2);font-size:14px}
label{display:block;font-size:13px;color:var(--tx2);margin:14px 0 6px}
input{width:100%;height:42px;border-radius:10px;border:1px solid var(--bd);background:var(--in);color:var(--tx);padding:0 12px;font-size:15px;outline:none}
input:focus{border-color:var(--link)}
button,.btn{display:block;width:100%;height:42px;margin-top:22px;border:0;border-radius:21px;background:var(--tx);color:var(--bg);
font-size:15px;font-weight:600;cursor:pointer;text-align:center;line-height:42px;text-decoration:none}
button:hover,.btn:hover{background:var(--btnh)}.err{background:var(--erb);color:var(--ert);border-radius:10px;padding:10px 12px;margin:14px 0 0;font-size:14px}
.ok{background:var(--okb);color:var(--okt);border-radius:10px;padding:12px;margin:14px 0;font-size:14px}
.hint{font-size:12px;color:var(--tx3);margin-top:6px}code{background:var(--hv);padding:1px 6px;border-radius:6px;color:var(--tx)}
ol{padding-left:20px;color:var(--tx2);font-size:14px;margin:10px 0 0}li{margin:6px 0}"""


# ------------------------------------------------------------------ storage
def load():
    try:
        with open(DATA) as f:
            return json.load(f)
    except FileNotFoundError:
        return {"invites": {}}


def save(d):
    tmp = DATA + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
    os.chmod(tmp, 0o600)
    os.replace(tmp, DATA)


def valid_invite(d, token):
    inv = d["invites"].get(token)
    if not inv or inv.get("revoked"):
        return None, "Приглашение недействительно."
    if inv["expires"] < time.time():
        return None, "Срок действия приглашения истёк."
    if inv["uses_left"] <= 0:
        return None, "Приглашение уже использовано."
    return inv, None


# ------------------------------------------------------------------ accounts
def htpasswd_users():
    try:
        with open(HTPASSWD) as f:
            return {l.split(":", 1)[0] for l in f if ":" in l}
    except FileNotFoundError:
        return set()


def psql(script, **vars_):
    cmd = ["docker", "exec", "-i", DB_CONTAINER, "psql", "-U", "kemal", "-d", "invidious", "-At", "-v", "ON_ERROR_STOP=1"]
    for k, v in vars_.items():
        cmd += ["-v", f"{k}={v}"]
    r = subprocess.run(cmd + ["-f", "-"], input=script, capture_output=True, text=True, timeout=20)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip()[:300])
    return r.stdout.strip()


def invidious_user_exists(name):
    return psql("select count(*) from users where email = :'u';", u=name) != "0"


def bcrypt_hash(password):
    # htpasswd генерирует bcrypt ($2y$, cost 10) — его принимает и nginx, и Invidious (Crystal)
    r = subprocess.run(["htpasswd", "-niBC", "10", "x"], input=password + "\n", capture_output=True, text=True, timeout=20)
    if r.returncode != 0:
        raise RuntimeError("htpasswd: " + r.stderr.strip())
    return r.stdout.strip().split(":", 1)[1]


def create_account(name, password):
    h = bcrypt_hash(password)
    # 1) вход на сайт (basic auth)
    with open(HTPASSWD, "a") as f:
        f.write(f"{name}:{h}\n")
    # 2) аккаунт Invidious (настройки копируются у первого существующего пользователя)
    token = secrets.token_urlsafe(32)
    psql("""insert into users (updated, notifications, subscriptions, email, preferences, password, token, watched, feed_needs_update)
            select now(), '{}', '{}', :'u',
                   coalesce((select preferences from users order by updated limit 1), '{}'),
                   :'h', :'t', '{}', true;""", u=name, h=h, t=token)


def set_password(name, password):
    h = bcrypt_hash(password)
    with open(HTPASSWD) as f:
        lines = [l for l in f if not l.startswith(name + ":")]
    lines.append(f"{name}:{h}\n")
    with open(HTPASSWD, "w") as f:
        f.writelines(lines)
    psql("update users set password = :'h' where email = :'u'; delete from session_ids where email = :'u';", u=name, h=h)


def users_info():
    raw = psql("select coalesce(json_agg(t),'[]') from (select email, extract(epoch from updated)::bigint upd, "
               "coalesce(array_length(subscriptions,1),0) subs, coalesce(array_length(watched,1),0) w from users) t;")
    info = {r["email"]: r for r in json.loads(raw or "[]")}
    return info


def delete_account(name):
    lines = []
    with open(HTPASSWD) as f:
        lines = [l for l in f if not l.startswith(name + ":")]
    with open(HTPASSWD, "w") as f:
        f.writelines(lines)
    psql("delete from session_ids where email = :'u'; delete from users where email = :'u';", u=name)


# ------------------------------------------------------------------ web
def page(body, title="Приглашение в CloudTube"):
    return f"""<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title>{title}</title><script>(function(){{var d=null;try{{d=JSON.parse(localStorage.getItem("darkMode"))}}catch(e){{}}if(d===null)d=matchMedia("(prefers-color-scheme: dark)").matches;document.documentElement.classList.add(d?"ct-dark":"ct-light")}})()</script><style>{CSS}</style></head>
<body><div class="card">{LOGO}{body}</div></body></html>""".encode()


def form(token, err="", user=""):
    e = f'<div class="err">{html.escape(err)}</div>' if err else ""
    return page(f"""<h1>Вас пригласили в CloudTube</h1><p>Придумайте логин и пароль — они будут для входа на сайт и для подписок.</p>{e}
<form method="post" action="/invite/{html.escape(token)}" autocomplete="off">
<label>Логин</label><input name="u" value="{html.escape(user)}" required pattern="[a-z0-9][a-z0-9_.\\-]{{2,31}}" autocapitalize="none" spellcheck="false">
<div class="hint">3–32 символа: латиница в нижнем регистре, цифры, <code>_ . -</code></div>
<label>Пароль</label><input name="p" type="password" required minlength="8" maxlength="64">
<div class="hint">8–64 символа: латиница, цифры, <code>_ - . ! @ # % ^ & + = ?</code> (без <code>*</code> и пробелов)</div>
<label>Пароль ещё раз</label><input name="p2" type="password" required minlength="8" maxlength="64">
<button type="submit">Создать аккаунт</button></form>""")


def done(user):
    u = html.escape(user)
    return page(f"""<h1>Готово! 🎉</h1><div class="ok">Аккаунт <b>{u}</b> создан.</div>
<ol><li>Откройте сайт по кнопке ниже — браузер спросит логин и пароль: введите <code>{u}</code> и ваш пароль.</li>
<li>Чтобы работали подписки и история: значок входа справа вверху → <b>Login</b> → тот же логин и пароль → <b>Authorize</b>.</li>
<li>На телефоне, телевизоре и Windows — приложение <b>CloudTube</b> (github.com/dontbass/cloudtube): «У меня есть сервер», адрес <code>https://{html.escape(DOMAIN)}</code>, логин и пароль сайта.</li></ol>
<a class="btn" href="https://{html.escape(DOMAIN)}/">Открыть CloudTube</a>""", "Аккаунт создан")


# ------------------------------------------------------------------ admin page
ADMIN_CSS = CSS.replace(".card{width:100%;max-width:400px", ".card{width:100%;max-width:980px") + """
body{align-items:flex-start}.card{margin-top:24px}
h2{font-size:16px;margin:28px 0 10px;font-weight:600}
table{width:100%;border-collapse:collapse;font-size:14px}th{text-align:left;color:var(--tx3);font-weight:500;font-size:12px;padding:6px 8px;border-bottom:1px solid var(--bd2)}
td{padding:9px 8px;border-bottom:1px solid var(--bd2);vertical-align:middle}tr:hover td{background:var(--hv2)}
.row{display:flex;gap:10px;flex-wrap:wrap;align-items:flex-end}.row>div{flex:1;min-width:120px}.row>div.btns{flex:0 0 auto}
.row button{margin-top:0;width:auto;padding:0 22px}
.pill{display:inline-block;padding:2px 10px;border-radius:12px;font-size:12px;background:var(--hv);color:var(--tx2)}
.pill.on{background:var(--okb);color:var(--okt)}.pill.off{background:var(--erb);color:var(--ert)}
.sm{height:32px;line-height:32px;margin:0;width:auto;display:inline-block;padding:0 14px;font-size:13px;border-radius:16px;background:var(--hv);color:var(--tx);font-weight:500}
.sm:hover{background:var(--hv3)}.sm.red{background:var(--erb);color:var(--ert)}.sm.red:hover{background:var(--erb)}
td form{display:inline}.mono{font-family:ui-monospace,Consolas,monospace;font-size:13px}
.link{display:flex;gap:8px;align-items:center;margin-top:10px}.link input{flex:1;font-family:ui-monospace,Consolas,monospace;font-size:13px}
.top{display:flex;justify-content:space-between;align-items:center}.top a{color:var(--link);text-decoration:none;font-size:14px}
@media(max-width:700px){.hide-m{display:none}td,th{padding:8px 4px}}"""


def admin_page(me, flash="", link="", newpw=None):
    d = load()
    try:
        info = users_info()
    except Exception as e:
        info = {}; flash = (flash + " " if flash else "") + f"(БД недоступна: {e})"
    who_invited = {}
    for t, i in d["invites"].items():
        for u in i.get("used_by", []):
            who_invited[u["user"]] = i.get("note") or t[:6]
    now = time.time()
    rows_inv = []
    for t, i in sorted(d["invites"].items(), key=lambda x: -x[1]["created"]):
        if i.get("revoked"):
            st, cls = "отозвано", "off"
        elif i["expires"] < now:
            st, cls = "истекло", ""
        elif i["uses_left"] <= 0:
            st, cls = "использовано", ""
        else:
            st, cls = f"активно · {i['uses_left']}", "on"
        url = f"https://{DOMAIN}/invite/{t}"
        used = ", ".join(html.escape(u["user"]) for u in i.get("used_by", [])) or "—"
        act = ""
        if cls == "on":
            act = (f'<button class="sm" type="button" onclick="cp(\'{url}\')">Копировать</button> '
                   f'<form method="post" action="/ctadmin/revoke"><input type="hidden" name="t" value="{t}">'
                   f'<button class="sm red" onclick="return confirm(\'Отозвать приглашение?\')">Отозвать</button></form>')
        rows_inv.append(f'<tr><td class="mono">{t[:8]}…</td><td><span class="pill {cls}">{st}</span></td>'
                        f'<td class="hide-m">{time.strftime("%d.%m %H:%M", time.localtime(i["expires"]))}</td>'
                        f'<td>{html.escape(i.get("note") or "")}</td><td>{used}</td><td style="white-space:nowrap">{act}</td></tr>')
    rows_u = []
    for u in sorted(htpasswd_users() | set(info)):
        r = info.get(u, {})
        last = time.strftime("%d.%m.%Y", time.localtime(r["upd"])) if r.get("upd") else "—"
        acc = '<span class="pill on">есть</span>' if u in info else '<span class="pill off">нет</span>'
        site = '<span class="pill on">есть</span>' if u in htpasswd_users() else '<span class="pill off">нет</span>'
        me_mark = ' <span class="pill">это вы</span>' if u == me else ""
        act = ""
        if u != me:
            act = (f'<form method="post" action="/ctadmin/resetpw"><input type="hidden" name="u" value="{html.escape(u)}">'
                   f'<button class="sm" onclick="return confirm(\'Сбросить пароль {html.escape(u)}? Будет выдан новый.\')">Новый пароль</button></form> '
                   f'<form method="post" action="/ctadmin/deluser"><input type="hidden" name="u" value="{html.escape(u)}">'
                   f'<button class="sm red" onclick="return confirm(\'Удалить {html.escape(u)} полностью (вход на сайт и аккаунт с подписками)?\')">Удалить</button></form>')
        rows_u.append(f'<tr><td><b>{html.escape(u)}</b>{me_mark}</td><td>{site}</td><td class="hide-m">{acc}</td>'
                      f'<td class="hide-m">{r.get("subs", "—")}</td><td class="hide-m">{r.get("w", "—")}</td>'
                      f'<td class="hide-m">{html.escape(who_invited.get(u, "—"))}</td><td>{last}</td><td style="white-space:nowrap">{act}</td></tr>')
    fl = ""
    if flash:
        fl += f'<div class="{"err" if flash.startswith("!") else "ok"}">{html.escape(flash.lstrip("!"))}</div>'
    if link:
        msg = f"Привет! Вот приглашение в CloudTube: {link}"
        fl += (f'<div class="ok">Ссылка готова — отправьте её другу:<div class="link"><input id="nl" readonly value="{link}">'
               f'<button class="sm" type="button" onclick="cp(document.getElementById(\'nl\').value)">Копировать</button>'
               f'<button class="sm" type="button" onclick="cp({json.dumps(msg)})">С текстом</button></div></div>')
    if newpw:
        fl += (f'<div class="ok">Новый пароль для <b>{html.escape(newpw[0])}</b> (покажется один раз):'
               f'<div class="link"><input id="np" readonly value="{html.escape(newpw[1])}">'
               f'<button class="sm" type="button" onclick="cp(document.getElementById(\'np\').value)">Копировать</button></div></div>')
    body = f"""<div class="top">{LOGO}<a href="/">← на сайт</a></div>
<h1>Управление доступом</h1><p>Вы вошли как <b>{html.escape(me)}</b>.</p>{fl}
<h2>Новое приглашение</h2>
<form method="post" action="/ctadmin/new" class="row">
<div><label>Для кого (заметка)</label><input name="n" maxlength="60" placeholder="Петя"></div>
<div><label>Регистраций</label><input name="u" type="number" min="1" max="50" value="1"></div>
<div><label>Действует, дней</label><input name="d" type="number" min="1" max="90" value="7"></div>
<div class="btns"><button type="submit">Создать ссылку</button></div></form>
<h2>Приглашения</h2>
<table><tr><th>Код</th><th>Статус</th><th class="hide-m">До</th><th>Для кого</th><th>Кто зарегистрировался</th><th></th></tr>
{''.join(rows_inv) or '<tr><td colspan="6" style="color:#888">пока нет</td></tr>'}</table>
<h2>Пользователи</h2>
<table><tr><th>Логин</th><th>Вход на сайт</th><th class="hide-m">Аккаунт</th><th class="hide-m">Подписок</th><th class="hide-m">Просмотров</th>
<th class="hide-m">Приглашение</th><th>Активность</th><th></th></tr>{''.join(rows_u)}</table>
<script>function cp(t){{navigator.clipboard?navigator.clipboard.writeText(t).then(()=>toast('Скопировано')):prompt('Скопируйте:',t)}}
function toast(m){{var d=document.createElement('div');d.textContent=m;d.style.cssText='position:fixed;bottom:24px;left:50%;transform:translateX(-50%);background:#f1f1f1;color:#0f0f0f;padding:10px 18px;border-radius:8px;font-size:14px;z-index:9';document.body.appendChild(d);setTimeout(()=>d.remove(),1500)}}</script>"""
    return f"""<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title>CloudTube — доступ</title><script>(function(){{var d=null;try{{d=JSON.parse(localStorage.getItem("darkMode"))}}catch(e){{}}if(d===null)d=matchMedia("(prefers-color-scheme: dark)").matches;document.documentElement.classList.add(d?"ct-dark":"ct-light")}})()</script><style>{ADMIN_CSS}</style></head>
<body><div class="card">{body}</div></body></html>""".encode()


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Frame-Options", "DENY")
        self.end_headers()
        self.wfile.write(body)

    def token(self):
        m = re.match(r"^/invite/([A-Za-z0-9_-]{16,64})/?$", urllib.parse.urlparse(self.path).path)
        return m.group(1) if m else None

    def admin_user(self):
        u = self.headers.get("X-Remote-User", "")
        return u if u in ADMINS else None

    def same_origin(self):
        o = self.headers.get("Origin") or self.headers.get("Referer") or ""
        return o.startswith(f"https://{DOMAIN}/") or o == f"https://{DOMAIN}" or self.headers.get("Sec-Fetch-Site") == "same-origin"

    def admin(self, method):
        me = self.admin_user()
        if urllib.parse.urlparse(self.path).path.rstrip("/") == "/ctadmin/whoami":
            body = json.dumps({"admin": bool(me), "user": self.headers.get("X-Remote-User", "")}).encode()
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body); return
        if not me:
            return self.send(403, page("<h1>Нет доступа</h1><p>Эта страница только для администратора.</p>"))
        p = urllib.parse.urlparse(self.path).path.rstrip("/")
        if method == "GET":
            return self.send(200, admin_page(me))
        if not self.same_origin():
            return self.send(403, page("<h1>Запрос отклонён</h1>"))
        n = min(int(self.headers.get("Content-Length") or 0), 4096)
        f = {k: v[0] for k, v in urllib.parse.parse_qs(self.rfile.read(n).decode("utf-8", "replace")).items()}
        with _lock:
            d = load()
            try:
                if p == "/ctadmin/new":
                    uses = max(1, min(50, int(f.get("u") or 1))); days = max(1, min(90, float(f.get("d") or 7)))
                    t = secrets.token_urlsafe(16)
                    d["invites"][t] = {"created": int(time.time()), "expires": int(time.time() + days * 86400),
                                       "uses_left": uses, "note": (f.get("n") or "")[:60], "used_by": []}
                    save(d)
                    return self.send(200, admin_page(me, link=f"https://{DOMAIN}/invite/{t}"))
                if p == "/ctadmin/revoke" and f.get("t") in d["invites"]:
                    d["invites"][f["t"]]["revoked"] = True; save(d)
                    return self.send(200, admin_page(me, "Приглашение отозвано."))
                u = f.get("u", "")
                if u == me or u in ADMINS:
                    return self.send(200, admin_page(me, "!Свой аккаунт и аккаунты администраторов здесь менять нельзя."))
                if p == "/ctadmin/deluser" and u:
                    delete_account(u)
                    return self.send(200, admin_page(me, f"Пользователь {u} удалён."))
                if p == "/ctadmin/resetpw" and u:
                    pw = secrets.token_urlsafe(9).replace("-", "a").replace("_", "b")
                    set_password(u, pw)
                    return self.send(200, admin_page(me, newpw=(u, pw)))
            except Exception as e:
                print("[admin] error:", e, flush=True)
                return self.send(200, admin_page(me, f"!Ошибка: {e}"))
        self.send(400, admin_page(me, "!Неизвестное действие."))

    def do_GET(self):
        if self.path.startswith("/ctadmin"):
            return self.admin("GET")
        t = self.token()
        if not t:
            return self.send(404, page("<h1>Страница не найдена</h1>"))
        with _lock:
            _, err = valid_invite(load(), t)
        if err:
            return self.send(410, page(f"<h1>Упс</h1><p>{err}</p><p>Попросите у пригласившего новую ссылку.</p>"))
        self.send(200, form(t))

    def do_POST(self):
        if self.path.startswith("/ctadmin"):
            return self.admin("POST")
        t = self.token()
        if not t:
            return self.send(404, page("<h1>Страница не найдена</h1>"))
        n = min(int(self.headers.get("Content-Length") or 0), 4096)
        f = urllib.parse.parse_qs(self.rfile.read(n).decode("utf-8", "replace"))
        user = (f.get("u", [""])[0]).strip().lower()
        p1, p2 = f.get("p", [""])[0], f.get("p2", [""])[0]
        with _lock:
            d = load()
            inv, err = valid_invite(d, t)
            if err:
                return self.send(410, page(f"<h1>Упс</h1><p>{err}</p>"))
            if not USER_RE.match(user):
                return self.send(400, form(t, "Логин: 3–32 символа, латиница в нижнем регистре, цифры, _ . -", user))
            if not PASS_RE.match(p1):
                return self.send(400, form(t, "Пароль: 8–64 символа из разрешённых (без * и пробелов).", user))
            if p1 != p2:
                return self.send(400, form(t, "Пароли не совпадают.", user))
            try:
                if user in htpasswd_users() or invidious_user_exists(user):
                    return self.send(400, form(t, "Такой логин уже занят, выберите другой.", user))
                create_account(user, p1)
            except Exception as e:
                print("[invite] error:", e, flush=True)
                return self.send(500, form(t, "Не получилось создать аккаунт. Напишите пригласившему.", user))
            inv["uses_left"] -= 1
            inv.setdefault("used_by", []).append({"user": user, "at": int(time.time())})
            save(d)
            print(f"[invite] {t[:6]}… -> {user}", flush=True)
        self.send(200, done(user))


# ------------------------------------------------------------------ CLI
def cli(argv):
    import argparse
    ap = argparse.ArgumentParser(prog="ctinvite", description="Приглашения CloudTube")
    sp = ap.add_subparsers(dest="cmd", required=True)
    n = sp.add_parser("new", help="создать приглашение")
    n.add_argument("-u", "--uses", type=int, default=1, help="сколько регистраций по ссылке (по умолч. 1)")
    n.add_argument("-d", "--days", type=float, default=7, help="срок действия, дней (по умолч. 7)")
    n.add_argument("-n", "--note", default="", help="заметка: для кого")
    sp.add_parser("list", help="список приглашений")
    r = sp.add_parser("revoke", help="отозвать приглашение"); r.add_argument("token")
    sp.add_parser("users", help="пользователи сайта")
    du = sp.add_parser("deluser", help="удалить пользователя"); du.add_argument("name")
    a = ap.parse_args(argv)
    d = load()
    if a.cmd == "new":
        t = secrets.token_urlsafe(16)
        d["invites"][t] = {"created": int(time.time()), "expires": int(time.time() + a.days * 86400),
                           "uses_left": a.uses, "note": a.note, "used_by": []}
        save(d)
        print(f"https://{DOMAIN}/invite/{t}")
        print(f"  регистраций: {a.uses}, действует до {time.strftime('%d.%m.%Y %H:%M', time.localtime(time.time() + a.days * 86400))}")
    elif a.cmd == "list":
        if not d["invites"]:
            print("приглашений нет")
        for t, i in sorted(d["invites"].items(), key=lambda x: x[1]["created"]):
            st = "отозвано" if i.get("revoked") else "истекло" if i["expires"] < time.time() else \
                 "использовано" if i["uses_left"] <= 0 else f"активно, осталось {i['uses_left']}"
            who = ", ".join(u["user"] for u in i.get("used_by", [])) or "—"
            print(f"{t}  [{st}]  до {time.strftime('%d.%m %H:%M', time.localtime(i['expires']))}  кто: {who}  {i.get('note', '')}")
    elif a.cmd == "revoke":
        if a.token in d["invites"]:
            d["invites"][a.token]["revoked"] = True; save(d); print("отозвано")
        else:
            print("нет такого приглашения"); sys.exit(1)
    elif a.cmd == "users":
        for u in sorted(htpasswd_users()):
            print(u)
    elif a.cmd == "deluser":
        if a.name not in htpasswd_users():
            print("нет такого пользователя"); sys.exit(1)
        delete_account(a.name); print(f"{a.name} удалён (сайт + аккаунт Invidious)")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "serve":
        print(f"[invite] :{LISTEN} domain={DOMAIN}", flush=True)
        ThreadingHTTPServer(("127.0.0.1", LISTEN), H).serve_forever()
    else:
        cli(sys.argv[1:])
