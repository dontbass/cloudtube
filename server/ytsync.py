#!/usr/bin/env python3
"""CloudTube server add-on (https://github.com/dontbass/cloudtube, AGPL-3.0).
«Подписки YouTube» — страница /ctsubs/ на сайте:
  • подключить свой аккаунт YouTube (вход кодом на youtube.com/activate, как на телевизоре)
    и загрузить его подписки в аккаунт CloudTube (Invidious) — разово или автоматически раз в N часов;
  • или загрузить файл subscriptions.csv из Google Takeout — без входа в YouTube;
  • удалить все подписки CloudTube одним нажатием (с возможностью вернуть).
Пользователь — логин сайта (basic auth nginx передаёт его в X-Remote-User), он же аккаунт Invidious.
Токены YouTube хранятся только на этом сервере (файл SYNC_DB, права 600)."""
import csv, io, json, os, random, re, secrets, subprocess, threading, time, urllib.error, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

INV = os.environ.get("INV_URL", "http://127.0.0.1:3000")
LISTEN = int(os.environ.get("SYNC_PORT", "3500"))
DATA = os.environ.get("SYNC_DB", "/opt/cloudtube-addons/ytsync.json")
DB_CONTAINER = os.environ.get("DB_CONTAINER", "invidious-db")
DOMAIN = os.environ.get("DOMAIN", "")
EVERY_H = max(1, int(os.environ.get("SYNC_HOURS", "6")))
HL = os.environ.get("HL", "ru")
GL = os.environ.get("REGION", "RU")

TV_UA = ("Mozilla/5.0 (Linux armeabi-v7a; Android 7.1.2; Fire OS 6.0) Cobalt/22.lts.3.306369-gold (unlike Gecko) "
         "v8/8.8.278.8-jit gles Starboard/13, Amazon_ATV_mediatek8695_2019/NS6294 (Amazon, AFTMM, Wireless) "
         "com.amazon.firetv.youtube/22.3.r2.v66.0")
TV_VER = "7.20260901.15.00"
SCOPE = "http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content"
UC_RE = re.compile(r"^UC[\w-]{22}$")

_lock = threading.Lock()          # файл настроек
_jobs = {}                        # user -> состояние текущей загрузки
_logins = {}                      # user -> {"code", "url", "until", "error"}
_creds = None


def log(*a):
    print("[ytsync]", *a, flush=True)


# ------------------------------------------------------------------ хранилище
def load():
    try:
        with open(DATA) as f:
            return json.load(f)
    except FileNotFoundError:
        return {"users": {}}
    except Exception as e:
        log("файл настроек испорчен:", e)
        return {"users": {}}


def save(d):
    tmp = DATA + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
    os.replace(tmp, DATA)


def user_cfg(name):
    with _lock:
        return dict(load()["users"].get(name, {}))


def update_user(name, **kw):
    with _lock:
        d = load()
        u = d["users"].setdefault(name, {})
        for k, v in kw.items():
            if v is None:
                u.pop(k, None)
            else:
                u[k] = v
        save(d)
        return dict(u)


# ------------------------------------------------------------------ база Invidious
def psql(script, **vars_):
    cmd = ["docker", "exec", "-i", DB_CONTAINER, "psql", "-U", "kemal", "-d", "invidious", "-At", "-v", "ON_ERROR_STOP=1"]
    for k, v in vars_.items():
        cmd += ["-v", f"{k}={v}"]
    r = subprocess.run(cmd + ["-f", "-"], input=script, capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip()[:300])
    return r.stdout.strip()


def account_exists(name):
    return psql("select count(*) from users where email = :'u';", u=name) != "0"


def inv_subs(name):
    raw = psql("select coalesce(array_to_json(subscriptions), '[]') from users where email = :'u';", u=name)
    try:
        return [x for x in json.loads(raw or "[]") if isinstance(x, str)]
    except ValueError:
        return []


def set_subs(name, ids):
    arr = "{" + ",".join(i for i in ids if UC_RE.match(i)) + "}"
    psql("update users set subscriptions = :'a'::text[], feed_needs_update = true where email = :'u';", u=name, a=arr)


def sql_subscribe(name, chans):
    """Запасной путь: канал в таблицу channels (иначе его нет в списке подписок) и в подписки —
    видео подтянет фоновое обновление Invidious."""
    if not chans:
        return
    rows = json.dumps([{"id": c["id"], "author": c.get("author") or c["id"]} for c in chans if UC_RE.match(c["id"])],
                      ensure_ascii=False)
    psql("""insert into channels (id, author, updated, deleted, subscribed)
            select x->>'id', x->>'author', 'epoch'::timestamptz, false, now() from json_array_elements(:'j'::json) x
            on conflict (id) do nothing;
            update users set feed_needs_update = true,
              subscriptions = (select array_agg(distinct s) from unnest(subscriptions ||
                (select array_agg(x->>'id') from json_array_elements(:'j'::json) x)) s)
            where email = :'u';""", u=name, j=rows)


def remove_subs(name, ids):
    cur = inv_subs(name)
    drop = set(ids)
    set_subs(name, [s for s in cur if s not in drop])


class Session:
    """Временная сессия Invidious для пользователя: подписка через его API (Invidious сразу загружает
    канал и видео, как при нажатии «Подписаться»). После работы сессия удаляется."""

    def __init__(self, name):
        self.name, self.sid = name, None

    def __enter__(self):
        self.sid = secrets.token_urlsafe(32)
        psql("insert into session_ids (id, email, issued) values (:'s', :'u', now());", s=self.sid, u=self.name)
        return self

    def __exit__(self, *a):
        try:
            psql("delete from session_ids where id = :'s';", s=self.sid)
        except Exception as e:
            log("сессия не удалена:", e)

    def subscribe(self, ucid):
        req = urllib.request.Request(f"{INV}/api/v1/auth/subscriptions/{ucid}", data=b"", method="POST",
                                     headers={"Cookie": f"SID={self.sid}"})
        with urllib.request.urlopen(req, timeout=45) as r:
            return r.status in (200, 204)


# ------------------------------------------------------------------ YouTube (клиент для ТВ)
def http_json(url, body=None, headers=None, timeout=25):
    data = json.dumps(body).encode() if body is not None else None
    h = {"User-Agent": TV_UA, **({"Content-Type": "application/json"} if data else {}), **(headers or {})}
    req = urllib.request.Request(url, data=data, headers=h, method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw, st = r.read(), r.status
    except urllib.error.HTTPError as e:
        raw, st = e.read(), e.code
    try:
        j = json.loads(raw or b"{}")
    except ValueError:
        j = {}
    if not isinstance(j, dict):
        j = {}
    j["_status"] = st
    return j


def http_text(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": TV_UA}), timeout=25) as r:
        return r.read().decode("utf-8", "replace")


def client_creds():
    """client_id/secret приложения YouTube для ТВ — из его скрипта (как в SmartTube и приложении CloudTube)."""
    global _creds
    if _creds and _creds[2] > time.time():
        return _creds[0], _creds[1]
    page = http_text("https://www.youtube.com/tv")
    m = (re.search(r'id="base-js" src="(.*?)"', page) or re.search(r"\.src = '(.*?m=base)'", page)
         or re.search(r"\.src = '(.*?)'; .\.id = 'base-js'", page))
    if not m:
        raise RuntimeError("не найден скрипт YouTube TV")
    src = m.group(1).replace("\\/", "/")
    if src.startswith("/"):
        src = "https://www.youtube.com" + src
    c = re.search(r'clientId:"([-\w]+\.apps\.googleusercontent\.com)",\n?[$\w]+:"(\w+)"', http_text(src))
    if not c:
        raise RuntimeError("не найден client_id YouTube TV")
    _creds = (c.group(1), c.group(2), time.time() + 12 * 3600)
    return c.group(1), c.group(2)


def device_id():
    h = lambda n: "".join(random.choice("0123456789abcdef") for _ in range(n))
    return f"{h(8)}-{h(4)}-4{h(3)}-a{h(3)}-{h(12)}"


class AuthError(Exception):
    pass


def access_token(refresh):
    cid, sec = client_creds()
    j = http_json("https://www.youtube.com/o/oauth2/token",
                  {"refresh_token": refresh, "client_id": cid, "client_secret": sec, "grant_type": "refresh_token"})
    if not j.get("access_token"):
        raise AuthError(f"вход в YouTube устарел — подключите заново ({j.get('error') or j['_status']})")
    return j["access_token"]


def innertube(token, endpoint, body):
    ctx = {"context": {"client": {"clientName": "TVHTML5", "clientVersion": TV_VER, "userAgent": TV_UA,
                                  "hl": HL, "gl": GL, "acceptLanguage": HL, "acceptRegion": GL},
                       "user": {"enableSafetyMode": False}}}
    j = http_json(f"https://www.youtube.com/youtubei/v1/{endpoint}?prettyPrint=false", {**ctx, **body},
                  {"Authorization": f"Bearer {token}", "X-Youtube-Client-Name": "7",
                   "X-Youtube-Client-Version": TV_VER, "Referer": "https://www.youtube.com/tv",
                   "Origin": "https://www.youtube.com"})
    if j["_status"] in (401, 403):
        raise AuthError(f"YouTube отклонил вход ({j['_status']})")
    if j["_status"] >= 400:
        raise RuntimeError(f"YouTube {endpoint}: {(j.get('error') or {}).get('message') or j['_status']}")
    return j


def _text(n):
    if isinstance(n, dict):
        if isinstance(n.get("simpleText"), str):
            return n["simpleText"]
        if isinstance(n.get("runs"), list):
            return "".join(r.get("text", "") for r in n["runs"] if isinstance(r, dict))
    return ""


def _find(n, pred):
    if isinstance(n, dict):
        for k, v in n.items():
            if pred(k, v):
                return v
            r = _find(v, pred)
            if r is not None:
                return r
    elif isinstance(n, list):
        for v in n:
            r = _find(v, pred)
            if r is not None:
                return r
    return None


def parse_channels(j, out):
    """Каналы со страницы «Все подписки» (плитки) и из колонки ленты подписок (вкладки с аватарами).
    Возвращает токен продолжения."""
    cont = [None]

    def walk(n):
        if isinstance(n, dict):
            tile = n.get("tileRenderer")
            if isinstance(tile, dict) and "CHANNEL" in str(tile.get("contentType", "")):
                cid = _find(tile.get("onSelectCommand"), lambda k, v: k == "browseId" and isinstance(v, str) and UC_RE.match(v))
                title = _text(((tile.get("metadata") or {}).get("tileMetadataRenderer") or {}).get("title"))
                if cid and title:
                    out.setdefault(cid, title)
            tab = n.get("tabRenderer")
            if isinstance(tab, dict):
                cid = _find(tab.get("endpoint"), lambda k, v: k == "browseId" and isinstance(v, str) and UC_RE.match(v))
                title = _text(tab.get("title"))
                if cid and title:
                    out.setdefault(cid, title)
            nxt = n.get("nextContinuationData") or n.get("reloadContinuationData")
            if cont[0] is None and isinstance(nxt, dict) and isinstance(nxt.get("continuation"), str):
                cont[0] = nxt["continuation"]
            cmd = n.get("continuationCommand")
            if cont[0] is None and isinstance(cmd, dict) and isinstance(cmd.get("token"), str):
                cont[0] = cmd["token"]
            for v in n.values():
                walk(v)
        elif isinstance(n, list):
            for v in n:
                walk(v)

    walk(j)
    return cont[0]


def youtube_subscriptions(refresh):
    token = access_token(refresh)
    out = {}
    err = None
    try:
        j = innertube(token, "browse", {"browseId": "FEchannels"})
        cont = parse_channels(j, out)
        for _ in range(60):
            if not cont:
                break
            before = len(out)
            cont = parse_channels(innertube(token, "browse", {"continuation": cont}), out)
            if len(out) == before:
                break
    except AuthError:
        raise
    except Exception as e:
        err = e
        log("FEchannels:", e)
    try:
        parse_channels(innertube(token, "browse", {"browseId": "FEsubscriptions"}), out)
    except AuthError:
        raise
    except Exception as e:
        log("FEsubscriptions:", e)
        if not out and err:
            raise err
    return [{"id": k, "author": v} for k, v in out.items()]


# ------------------------------------------------------------------ вход в YouTube кодом
def start_login(name):
    cid, _ = client_creds()
    j = http_json("https://www.youtube.com/o/oauth2/device/code",
                  {"client_id": cid, "device_id": device_id(), "model_name": "ytlr::", "scope": SCOPE})
    if not j.get("device_code"):
        raise RuntimeError(f"YouTube не выдал код: {j.get('error') or j['_status']}")
    st = {"code": j["user_code"], "url": j.get("verification_url") or "https://www.youtube.com/activate",
          "until": time.time() + int(j.get("expires_in") or 1800), "error": None}
    _logins[name] = st
    threading.Thread(target=wait_login, args=(name, st, j["device_code"], int(j.get("interval") or 5)), daemon=True).start()
    return st


def wait_login(name, st, device_code, interval):
    cid, sec = client_creds()
    while time.time() < st["until"] and _logins.get(name) is st:
        time.sleep(interval)
        j = http_json("https://www.youtube.com/o/oauth2/token",
                      {"code": device_code, "client_id": cid, "client_secret": sec,
                       "grant_type": "http://oauth.net/grant_type/device/1.0"})
        if j.get("refresh_token"):
            update_user(name, refresh=j["refresh_token"], linked=int(time.time()), auth_error=None)
            _logins.pop(name, None)
            log(name, "YouTube подключён")
            start_job(name, "youtube")          # сразу первая загрузка
            return
        e = j.get("error")
        if e == "slow_down":
            interval += 2
        if e in ("authorization_pending", "slow_down"):
            continue
        st["error"] = f"вход отклонён: {e or j['_status']}"
        return
    if _logins.get(name) is st:
        st["error"] = "время на ввод кода истекло"


# ------------------------------------------------------------------ загрузка подписок
def start_job(name, kind, csv_rows=None):
    if _jobs.get(name, {}).get("running"):
        return _jobs[name]
    job = {"running": True, "kind": kind, "stage": "Получаю список каналов…", "done": 0, "total": 0,
           "added": 0, "removed": 0, "found": 0, "error": None, "started": int(time.time())}
    _jobs[name] = job
    threading.Thread(target=run_job, args=(name, job, csv_rows), daemon=True).start()
    return job


def run_job(name, job, csv_rows):
    cfg = user_cfg(name)
    try:
        if job["kind"] == "youtube":
            if not cfg.get("refresh"):
                raise AuthError("YouTube не подключён")
            chans = youtube_subscriptions(cfg["refresh"])
        else:
            chans = csv_rows or []
        job["found"] = len(chans)
        if job["kind"] == "youtube" and not chans:
            raise RuntimeError("YouTube вернул пустой список подписок")
        have = set(inv_subs(name))
        new = [c for c in chans if c["id"] not in have]
        job["total"] = len(new)
        job["stage"] = f"Подписываюсь на новые каналы: {len(new)}" if new else "Новых каналов нет"
        failed = []
        if new:
            with Session(name) as s:
                def one(c):
                    try:
                        ok = s.subscribe(c["id"])
                    except Exception as e:
                        log(name, c["id"], e)
                        ok = False
                    job["done"] += 1
                    if ok:
                        job["added"] += 1
                    else:
                        failed.append(c)
                with ThreadPoolExecutor(3) as ex:
                    list(ex.map(one, new))
            if failed:                       # Invidious не смог загрузить канал — подписываем напрямую
                sql_subscribe(name, failed)
                job["added"] += len(failed)
        # «как на YouTube»: убрать каналы, от которых отписались на YouTube (только загруженные отсюда раньше)
        if job["kind"] == "youtube":
            now_ids = {c["id"] for c in chans}
            prev = set(cfg.get("yt_ids") or [])
            if cfg.get("mirror") and prev:
                gone = [i for i in prev - now_ids if i in have]
                if gone:
                    remove_subs(name, gone)
                    job["removed"] = len(gone)
            update_user(name, yt_ids=sorted(now_ids), auth_error=None)
        res = {"at": int(time.time()), "kind": job["kind"], "found": job["found"], "added": job["added"],
               "removed": job["removed"]}
        update_user(name, last=res)
        job["stage"] = "Готово"
        log(name, res)
    except AuthError as e:
        job["error"] = str(e)
        update_user(name, auth_error=str(e))
    except Exception as e:
        job["error"] = f"ошибка: {e}"
        log(name, "загрузка:", e)
    finally:
        job["running"] = False
        job["finished"] = int(time.time())


def parse_csv(text):
    """subscriptions.csv из Google Takeout: «Channel Id,Channel Url,Channel Title» (заголовки бывают по-русски)."""
    out, seen = [], set()
    for row in csv.reader(io.StringIO(text.lstrip("﻿"))):
        cid = next((x.strip() for x in row if UC_RE.match(x.strip())), None)
        if not cid:
            m = next((re.search(r"(UC[\w-]{22})", x) for x in row if "UC" in x), None)
            cid = m.group(1) if m else None
        if cid and cid not in seen:
            seen.add(cid)
            title = row[2].strip() if len(row) > 2 else cid
            out.append({"id": cid, "author": title or cid})
    return out


def scheduler():
    time.sleep(60)
    while True:
        try:
            users = load()["users"]
            for name, u in users.items():
                if not (u.get("auto") and u.get("refresh")) or u.get("auth_error"):
                    continue
                if time.time() - (u.get("last") or {}).get("at", 0) < EVERY_H * 3600:
                    continue
                job = start_job(name, "youtube")
                while job["running"]:
                    time.sleep(5)
        except Exception as e:
            log("расписание:", e)
        time.sleep(600)


# ------------------------------------------------------------------ веб
def state(name):
    cfg = user_cfg(name)
    try:
        exists = account_exists(name)
        n = len(inv_subs(name)) if exists else 0
    except Exception as e:
        log("база:", e)
        exists, n = True, -1
    lg = _logins.get(name)
    job = _jobs.get(name)
    return {
        "user": name, "account": exists, "subs": n, "hours": EVERY_H,
        "linked": bool(cfg.get("refresh")), "linkedAt": cfg.get("linked"), "authError": cfg.get("auth_error"),
        "auto": bool(cfg.get("auto")), "mirror": bool(cfg.get("mirror")), "last": cfg.get("last"),
        "undo": len(cfg.get("backup") or []), "backupAt": cfg.get("backup_at"),
        "login": {k: lg[k] for k in ("code", "url", "error")} | {"left": max(0, int(lg["until"] - time.time()))} if lg else None,
        "job": {k: v for k, v in job.items()} if job else None,
    }


PAGE = r"""<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title>Подписки YouTube — CloudTube</title><link rel="icon" href="/custom/logo-icon.svg">
<script>(function(){var d=null;try{d=JSON.parse(localStorage.getItem("darkMode"))}catch(e){}if(d===null)d=matchMedia("(prefers-color-scheme: dark)").matches;document.documentElement.classList.add(d?"ct-dark":"ct-light")})()</script>
<style>
:root{--bg:#0f0f0f;--card:#1f1f1f;--tx:#f1f1f1;--tx2:#aaa;--tx3:#888;--bd:#3f3f3f;--hv:#272727;--okb:#16301d;--okt:#8bd49b;--erb:#3b1a1a;--ert:#ff8a80;--link:#3ea6ff;--red:#e85d4a;--sh:rgba(0,0,0,.4)}
html.ct-light{--bg:#f2f2f2;--card:#fff;--tx:#0f0f0f;--tx2:#606060;--tx3:#777;--bd:#d3d3d3;--hv:#f2f2f2;--okb:#e6f4ea;--okt:#137333;--erb:#fce8e6;--ert:#c5221f;--link:#065fd4;--sh:rgba(0,0,0,.08)}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--tx);font:15px/1.5 Roboto,Arial,sans-serif;padding:16px}
.wrap{max-width:620px;margin:0 auto}.top{display:flex;align-items:center;gap:12px;margin:4px 0 16px}
.top a{color:var(--tx2);text-decoration:none;font-size:14px}.top a:hover{color:var(--tx)}
h1{font-size:22px;margin:0 0 4px;font-weight:700}.sub{color:var(--tx2);margin:0 0 18px;font-size:14px}
.card{background:var(--card);border-radius:16px;padding:20px 22px;margin-bottom:14px;box-shadow:0 6px 30px var(--sh)}
h2{font-size:16px;margin:0 0 8px;font-weight:600;display:flex;align-items:center;gap:8px}
p{margin:0 0 12px;color:var(--tx2);font-size:14px}.muted{color:var(--tx3);font-size:13px}
.big{font-size:34px;font-weight:800;letter-spacing:-.5px}
button,.btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;height:40px;padding:0 18px;border:0;border-radius:20px;
background:var(--tx);color:var(--bg);font-size:14px;font-weight:600;cursor:pointer;text-decoration:none;margin:4px 8px 4px 0}
button.sec{background:var(--hv);color:var(--tx);border:1px solid var(--bd)}button.danger{background:var(--red);color:#fff}
button:disabled{opacity:.5;cursor:default}
.code{font:800 30px/1.2 ui-monospace,Consolas,monospace;letter-spacing:4px;background:var(--hv);border-radius:12px;padding:12px 16px;display:inline-block;margin:6px 0 10px}
a{color:var(--link)}.row{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:10px 0;border-top:1px solid var(--bd)}
.row:first-of-type{border-top:0}.row div{min-width:0}.row b{font-weight:500;display:block}.row small{color:var(--tx3);font-size:12.5px}
.sw{position:relative;flex:none;width:44px;height:24px;border-radius:12px;background:var(--bd);cursor:pointer;transition:.15s}
.sw::after{content:"";position:absolute;left:3px;top:3px;width:18px;height:18px;border-radius:50%;background:#fff;transition:.15s}
.sw.on{background:var(--red)}.sw.on::after{left:23px}
.bar{height:6px;border-radius:3px;background:var(--hv);overflow:hidden;margin:10px 0 6px}.bar i{display:block;height:100%;background:var(--red);width:0;transition:width .3s}
.ok{background:var(--okb);color:var(--okt);border-radius:10px;padding:10px 12px;margin:10px 0;font-size:14px}
.err{background:var(--erb);color:var(--ert);border-radius:10px;padding:10px 12px;margin:10px 0;font-size:14px}
input[type=file]{display:none}.hide{display:none!important}
</style></head><body><div class="wrap">
<div class="top"><a href="/">← CloudTube</a><span style="flex:1"></span><a href="/subscriptions">Мои подписки</a></div>
<h1>Подписки YouTube</h1><p class="sub">Перенос подписок с YouTube в CloudTube и быстрая очистка.</p>
<div id="msg"></div>
<div class="card"><div class="muted">Подписок в CloudTube</div><div class="big" id="cnt">…</div><div class="muted" id="last"></div></div>

<div class="card" id="yt">
  <h2>▶ Аккаунт YouTube</h2>
  <div id="ytOff">
    <p>Войдите в YouTube кодом — так же, как на телевизоре. CloudTube прочитает список ваших подписок
       и подпишется на те же каналы. Пароль от Google сюда не вводится.</p>
    <button id="link">Подключить YouTube</button>
  </div>
  <div id="ytCode" class="hide">
    <p>Откройте на телефоне или компьютере <a id="codeUrl" target="_blank" rel="noopener">youtube.com/activate</a>,
       войдите в Google и введите код:</p>
    <div class="code" id="code"></div>
    <p class="muted" id="codeLeft">Жду подтверждения…</p>
    <button class="sec" id="linkCancel">Отмена</button>
  </div>
  <div id="ytOn" class="hide">
    <p id="ytInfo"></p>
    <button id="sync">Загрузить подписки сейчас</button>
    <div id="job" class="hide"><div class="bar"><i id="barI"></i></div><div class="muted" id="jobT"></div></div>
    <div class="row"><div><b>Автоматически</b><small id="autoT">Раз в 6 ч добавлять новые подписки с YouTube</small></div><span class="sw" id="auto"></span></div>
    <div class="row"><div><b>Как на YouTube</b><small>Отписались на YouTube — канал уйдёт и из CloudTube (только загруженные отсюда)</small></div><span class="sw" id="mirror"></span></div>
    <button class="sec" id="unlink" style="margin-top:10px">Отключить YouTube</button>
    <p class="muted" style="margin-top:6px">Доступ можно отозвать и в Google: <a href="https://myaccount.google.com/connections" target="_blank" rel="noopener">myaccount.google.com/connections</a></p>
  </div>
</div>

<div class="card">
  <h2>📄 Файл из Google Takeout</h2>
  <p>Без входа в YouTube: на <a href="https://takeout.google.com/" target="_blank" rel="noopener">takeout.google.com</a> выберите
     «YouTube и YouTube Music» → «подписки», скачайте архив и загрузите отсюда <code>subscriptions.csv</code>.</p>
  <label><input type="file" id="file" accept=".csv,text/csv"><button class="sec" id="fileBtn" type="button">Загрузить subscriptions.csv</button></label>
</div>

<div class="card">
  <h2>🗑 Удалить все подписки</h2>
  <p>Отписаться от всех каналов в CloudTube одним нажатием. На YouTube ничего не меняется.</p>
  <button class="danger" id="clear">Удалить все подписки</button>
  <button class="sec hide" id="undo">Вернуть удалённые</button>
</div>
</div>
<script>
var S={},poll=null;function $(i){return document.getElementById(i)}
function esc(s){return String(s).replace(/[&<>"]/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
function msg(t,ok){$('msg').innerHTML=t?'<div class="'+(ok?'ok':'err')+'">'+esc(t)+'</div>':''}
function when(t){if(!t)return'';var d=new Date(t*1000);return d.toLocaleDateString('ru-RU')+' '+d.toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'})}
function plural(n,a,b,c){var m=n%10,h=n%100;return n+' '+(m==1&&h!=11?a:m>=2&&m<=4&&(h<10||h>=20)?b:c)}
function api(p,body,raw){return fetch('/ctsubs/api/'+p,{method:body===undefined?'GET':'POST',credentials:'same-origin',cache:'no-store',
  headers:raw?{'Content-Type':'text/csv'}:{'Content-Type':'application/json'},body:body===undefined?undefined:(raw?body:JSON.stringify(body))})
  .then(function(r){return r.json().then(function(j){if(!r.ok)throw new Error(j.error||('HTTP '+r.status));return j})})}
function render(s){S=s;
  if(!s.account){msg('Нет аккаунта CloudTube «'+s.user+'». Войдите на сайте под этим логином хотя бы раз.');}
  $('cnt').textContent=s.subs<0?'—':s.subs;
  var L=s.last;$('last').textContent=L?'Последняя загрузка '+when(L.at)+(L.kind=='csv'?' (файл)':'')+': найдено '+L.found+', добавлено '+L.added+(L.removed?', убрано '+L.removed:''):'';
  $('ytOff').classList.toggle('hide',s.linked||!!s.login);$('ytCode').classList.toggle('hide',!s.login);$('ytOn').classList.toggle('hide',!s.linked||!!s.login);
  if(s.login){$('code').textContent=s.login.code;$('codeUrl').href=s.login.url;$('codeUrl').textContent=s.login.url.replace(/^https?:\/\/(www\.)?/,'');
    $('codeLeft').textContent=s.login.error?('Не получилось: '+s.login.error):('Жду подтверждения… код действует ещё '+Math.ceil(s.login.left/60)+' мин');}
  $('ytInfo').innerHTML=s.authError?'<span style="color:var(--ert)">'+esc(s.authError)+'</span>':('YouTube подключён'+(s.linkedAt?' '+when(s.linkedAt):'')+'.');
  $('auto').classList.toggle('on',s.auto);$('mirror').classList.toggle('on',s.mirror);$('autoT').textContent='Раз в '+s.hours+' ч добавлять новые подписки с YouTube';
  var j=s.job,run=j&&j.running;$('job').classList.toggle('hide',!j);
  if(j){$('barI').style.width=(j.total?Math.round(100*j.done/j.total):(run?8:100))+'%';
    $('jobT').textContent=j.error?('Ошибка: '+j.error):run?(j.stage+(j.total?' — '+j.done+' из '+j.total:'')):('Готово: найдено '+j.found+', добавлено '+j.added+(j.removed?', убрано '+j.removed:''));}
  ['sync','fileBtn','clear'].forEach(function(i){$(i).disabled=!!run||!s.account});
  $('undo').classList.toggle('hide',!s.undo);$('undo').textContent='Вернуть удалённые ('+s.undo+')';
  var busy=run||!!(s.login&&!s.login.error);if(busy&&!poll)poll=setInterval(refresh,2000);if(!busy&&poll){clearInterval(poll);poll=null}}
function refresh(){api('state').then(render).catch(function(e){msg(e.message)})}
function act(p,b,okText){msg('');return api(p,b).then(function(s){render(s);if(okText)msg(typeof okText=='function'?okText(s):okText,true)}).catch(function(e){msg(e.message)})}
$('link').onclick=function(){act('link',{})};$('linkCancel').onclick=function(){act('link-cancel',{})};
$('sync').onclick=function(){act('sync',{})};
$('unlink').onclick=function(){if(confirm('Отключить YouTube? Подписки в CloudTube останутся.'))act('unlink',{},'YouTube отключён')};
$('auto').onclick=function(){act('options',{auto:!S.auto})};$('mirror').onclick=function(){
  if(!S.mirror&&!confirm('Каналы, от которых вы отпишетесь на YouTube, будут убираться и из CloudTube. Включить?'))return;act('options',{mirror:!S.mirror})};
$('fileBtn').onclick=function(){$('file').click()};
$('file').onchange=function(){var f=this.files[0];this.value='';if(!f)return;f.text().then(function(t){msg('');
  return api('csv',t,true).then(render)}).catch(function(e){msg(e.message)})};
$('clear').onclick=function(){if(!S.subs){msg('Подписок и так нет',true);return}
  if(confirm('Удалить все '+plural(S.subs,'подписку','подписки','подписок')+' в CloudTube?'))act('clear',{},function(s){return'Подписки удалены. Передумали — «Вернуть удалённые».'})};
$('undo').onclick=function(){act('undo',{},function(s){return'Вернул подписки: теперь '+s.subs})};
refresh();
</script></body></html>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def user(self):
        u = self.headers.get("X-Remote-User", "").strip()
        return u if re.match(r"^[A-Za-z0-9._@-]{1,64}$", u) else None

    def same_origin(self):
        if self.headers.get("Sec-Fetch-Site") == "same-origin":
            return True
        o = self.headers.get("Origin") or self.headers.get("Referer") or ""
        host = self.headers.get("Host", "")
        return any(o == f"{p}://{h}" or o.startswith(f"{p}://{h}/") for p in ("https", "http") for h in {DOMAIN, host} if h)

    def send(self, code, body, ctype="application/json; charset=utf-8"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        name = self.user()
        p = urllib.parse.urlparse(self.path).path.rstrip("/")
        if not name:
            return self.send(401, {"error": "нужен вход на сайт"})
        if p == "/ctsubs":
            return self.send(200, PAGE.encode(), "text/html; charset=utf-8")
        if p == "/ctsubs/api/state":
            return self.send(200, state(name))
        self.send(404, {"error": "нет такой страницы"})

    def do_POST(self):
        name = self.user()
        if not name:
            return self.send(401, {"error": "нужен вход на сайт"})
        if not self.same_origin():
            return self.send(403, {"error": "запрос не с этого сайта"})
        n = int(self.headers.get("Content-Length") or 0)
        if n > 5 * 1024 * 1024:
            return self.send(413, {"error": "файл слишком большой"})
        raw = self.rfile.read(n) if n else b""
        p = urllib.parse.urlparse(self.path).path.rstrip("/")
        try:
            body = json.loads(raw or b"{}") if not p.endswith("/csv") else {}
        except ValueError:
            body = {}
        try:
            if p != "/ctsubs/api/link-cancel" and not account_exists(name):
                return self.send(400, {"error": f"нет аккаунта CloudTube «{name}»"})
            if p == "/ctsubs/api/link":
                start_login(name)
            elif p == "/ctsubs/api/link-cancel":
                _logins.pop(name, None)
            elif p == "/ctsubs/api/unlink":
                cfg = user_cfg(name)
                if cfg.get("refresh"):
                    try:      # отозвать токен и у Google
                        urllib.request.urlopen(urllib.request.Request(
                            "https://oauth2.googleapis.com/revoke?token=" + urllib.parse.quote(cfg["refresh"]),
                            data=b"", method="POST"), timeout=10).close()
                    except Exception as e:
                        log(name, "revoke:", e)
                update_user(name, refresh=None, linked=None, auth_error=None, auto=None, yt_ids=None)
            elif p == "/ctsubs/api/sync":
                if not user_cfg(name).get("refresh"):
                    return self.send(400, {"error": "сначала подключите YouTube"})
                update_user(name, auth_error=None)
                start_job(name, "youtube")
            elif p == "/ctsubs/api/options":
                kw = {k: bool(body[k]) for k in ("auto", "mirror") if k in body}
                update_user(name, **kw)
            elif p == "/ctsubs/api/csv":
                rows = parse_csv(raw.decode("utf-8", "replace"))
                if not rows:
                    return self.send(400, {"error": "в файле нет каналов — нужен subscriptions.csv из Takeout"})
                start_job(name, "csv", rows)
            elif p == "/ctsubs/api/clear":
                if _jobs.get(name, {}).get("running"):
                    return self.send(409, {"error": "идёт загрузка подписок — дождитесь конца"})
                cur = inv_subs(name)
                if cur:
                    update_user(name, backup=cur, backup_at=int(time.time()))
                    set_subs(name, [])
                    log(name, "удалены все подписки:", len(cur))
            elif p == "/ctsubs/api/undo":
                b = user_cfg(name).get("backup") or []
                if b:
                    cur = inv_subs(name)
                    set_subs(name, cur + [x for x in b if x not in set(cur)])
                    update_user(name, backup=None, backup_at=None)
            else:
                return self.send(404, {"error": "нет такого действия"})
            self.send(200, state(name))
        except Exception as e:
            log(name, p, e)
            self.send(500, {"error": str(e)})


if __name__ == "__main__":
    log(f":{LISTEN} <- {INV}, файл {DATA}, авто раз в {EVERY_H} ч")
    threading.Thread(target=scheduler, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", LISTEN), H).serve_forever()
