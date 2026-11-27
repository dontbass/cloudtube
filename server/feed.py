#!/usr/bin/env python3
"""CloudTube server add-on (https://github.com/dontbass/cloudtube, AGPL-3.0).
«Для вас»: персональная главная вместо /api/v1/popular.
Смешивает:
  • похожие на недавно просмотренные (история аккаунта Invidious → recommendedVideos)
  • свежие видео с подписок (таблица channel_videos)
  • тренды RU (для разнообразия и как запасной вариант)
Названия запрашиваются с hl=ru (без автоперевода на английский)."""
import json, os, random, subprocess, threading, time, urllib.error, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

INV = os.environ.get("INV_URL", "http://127.0.0.1:3000")
LISTEN = int(os.environ.get("FEED_PORT", "3200"))
REGION = os.environ.get("REGION", "RU")
HL = os.environ.get("HL", "ru")
TTL = int(os.environ.get("TTL", "600"))
# Без зрителей фоновые сборки не идут: после IDLE_MIN минут тишины сервер не ходит в YouTube
# (раньше лента, разделы и Shorts пересобирались круглосуточно — тысячи запросов в сутки с одного IP).
IDLE_MIN = int(os.environ.get("IDLE_MIN", "90"))
DB_CONTAINER = os.environ.get("DB_CONTAINER", "invidious-db")
HISTORY_N = int(os.environ.get("HISTORY_N", "10"))
PER_VIDEO = int(os.environ.get("PER_VIDEO", "8"))

_cache = {"t": 0.0, "body": b"[]"}
_details = {}                      # videoId -> (ts, dict)
_lock = threading.Lock()
_last_use = [0.0]                  # когда последний раз открывали ленту/разделы


def touch():
    _last_use[0] = time.time()


def active():
    """Кто-то пользовался лентой недавно — фоновое обновление имеет смысл."""
    return time.time() - _last_use[0] < IDLE_MIN * 60


def log(*a):
    print("[feed]", *a, flush=True)


def api(path):
    sep = "&" if "?" in path else "?"
    url = f"{INV}/api/v1/{path}{sep}hl={HL}&region={REGION}"
    try:
        with urllib.request.urlopen(url, timeout=25) as r:
            return json.load(r)
    except Exception as e:
        log("api", path, e)
        return None


def sql(q):
    try:
        out = subprocess.run(["docker", "exec", DB_CONTAINER, "psql", "-U", "kemal", "-d", "invidious", "-At", "-c", q],
                             capture_output=True, text=True, timeout=20)
        if out.returncode != 0:
            log("sql", out.stderr.strip()[:200]); return None
        return out.stdout.strip()
    except Exception as e:
        log("sql", e); return None


def history():
    raw = sql("select coalesce(json_agg(array_to_json(watched)),'[]') from users where watched is not null")
    ids, seen = [], set()
    try:
        for arr in json.loads(raw or "[]"):
            for v in reversed(arr or []):          # свежие в конце массива
                if v not in seen:
                    seen.add(v); ids.append(v)
    except Exception as e:
        log("history", e)
    return ids


def subs_videos():
    raw = sql("select coalesce(json_agg(t),'[]') from (select id,title,extract(epoch from published)::bigint p,ucid,author,"
              "length_seconds,live_now,views from channel_videos where ucid in (select unnest(subscriptions) from users) "
              "and published > now()-interval '21 days' order by published desc limit 80) t")
    try:
        return [to_item(r) for r in json.loads(raw or "[]")]
    except Exception as e:
        log("subs", e); return []


def ago(ts):
    d = max(0, int(time.time() - ts))
    for sec, one, few, many in ((86400, "день", "дня", "дней"), (3600, "час", "часа", "часов"), (60, "минуту", "минуты", "минут")):
        n = d // sec
        if n:
            w = one if n % 10 == 1 and n % 100 != 11 else few if 2 <= n % 10 <= 4 and not 12 <= n % 100 <= 14 else many
            return f"{n} {w} назад"
    return "только что"


def to_item(r):
    vid = r["id"]
    return {"type": "video", "title": r.get("title") or "", "videoId": vid,
            "author": r.get("author") or "", "authorId": r.get("ucid"), "authorUrl": f"/channel/{r.get('ucid')}",
            "videoThumbnails": [{"quality": q, "url": f"/vi/{vid}/{f}.jpg", "width": w, "height": h}
                                for q, f, w, h in (("maxres", "maxresdefault", 1280, 720), ("high", "hqdefault", 480, 360),
                                                   ("medium", "mqdefault", 320, 180))],
            "lengthSeconds": r.get("length_seconds") or 0, "viewCount": r.get("views") or 0,
            "published": r.get("p") or 0, "publishedText": ago(r.get("p") or time.time()),
            "liveNow": bool(r.get("live_now")), "isUpcoming": False, "premium": False}


def details(vid):
    hit = _details.get(vid)
    if hit and time.time() - hit[0] < 6 * 3600:
        return hit[1]
    d = api(f"videos/{vid}") or {}
    _details[vid] = (time.time(), d)
    if d.get("authorId") and d.get("authorThumbnails"):
        av_remember(d["authorId"], d["authorThumbnails"])
    if len(_details) > 3000:                       # не раздуваем память
        for k in sorted(_details, key=lambda k: _details[k][0])[:1000]:
            _details.pop(k, None)
    return d


# ---------------- аватарки каналов: /ct-api/avatars?ids=UC..,UC.. ----------------
import re
from concurrent.futures import ThreadPoolExecutor
AV_FILE = os.environ.get("AV_FILE", os.path.join(os.path.dirname(os.path.abspath(__file__)), "avatars.json"))
AV_TTL = 14 * 86400
_av = {}                                   # channelId -> [ts, url]
_av_pending = {}
_av_pool = ThreadPoolExecutor(4)
_av_dirty = [False]
try:
    _av = json.load(open(AV_FILE))
except Exception:
    _av = {}


def av_url(thumbs):
    best = None
    for t in thumbs or []:
        w = t.get("width") or 0
        if w >= 48 and (best is None or w < (best.get("width") or 0)):
            best = t
    if not best and thumbs:
        best = thumbs[-1]
    if not best:
        return ""
    u = best.get("url", "")
    if u.startswith("//"):
        u = "https:" + u
    m = re.match(r"^https?://(yt3\.ggpht\.com|yt3\.googleusercontent\.com)(/.*)$", u)
    if m:
        u = "/ggpht" + m.group(2)
    return re.sub(r"=s\d+-", "=s88-", u)


def av_remember(cid, thumbs):
    u = av_url(thumbs)
    if cid and u:
        with _lock:
            _av[cid] = [time.time(), u]; _av_dirty[0] = True


def av_fetch(cid):
    try:
        d = api(f"channels/{cid}?fields=authorThumbnails") or {}
        av_remember(cid, d.get("authorThumbnails"))
    finally:
        with _lock:
            _av_pending.pop(cid, None)


def av_saver():
    while True:
        time.sleep(30)
        if _av_dirty[0]:
            _av_dirty[0] = False
            try:
                with _lock:
                    data = json.dumps(_av)
                tmp = AV_FILE + ".tmp"
                open(tmp, "w").write(data); os.replace(tmp, AV_FILE)
            except Exception as e:
                log("av save", e)


def avatars(ids):
    now, out, wait = time.time(), {}, []
    for cid in ids[:60]:
        if not re.match(r"^UC[\w-]{22}$", cid):
            continue
        with _lock:
            hit = _av.get(cid)
            if hit and now - hit[0] < AV_TTL:
                out[cid] = hit[1]; continue
            f = _av_pending.get(cid)
            if not f:
                f = _av_pending[cid] = _av_pool.submit(av_fetch, cid)
        wait.append((cid, f))
    end = time.time() + 6
    for cid, f in wait:
        try:
            f.result(timeout=max(0.1, end - time.time()))
        except Exception:
            pass
        with _lock:
            hit = _av.get(cid)
        if hit:
            out[cid] = hit[1]
    return json.dumps(out).encode()


# ---------------- комментарии через yt-dlp: /ct-api/comments?v=ID&sort=top|new ----------------
import shutil
_cm = {}                                    # (vid, sort) -> (ts, bytes)
_cm_lock = threading.Lock()
YTDLP = shutil.which("yt-dlp") or "/usr/local/bin/yt-dlp"


def ytdlp_comments(vid, sort):
    key = (vid, sort)
    with _cm_lock:
        hit = _cm.get(key)
        if hit and time.time() - hit[0] < 1800:
            return hit[1]
    cmd = [YTDLP, "--skip-download", "--write-comments", "--no-warnings", "--quiet", "-J",
           "--extractor-args", f"youtube:max_comments=60,60,0,0;comment_sort={'new' if sort == 'new' else 'top'}",
           f"https://www.youtube.com/watch?v={vid}"]
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=90)
        info = json.loads(p.stdout or b"{}")
    except Exception as e:
        log("yt-dlp comments", vid, e)
        info = {}
    out = []
    for c in info.get("comments") or []:
        if c.get("parent", "root") != "root":
            continue
        th = c.get("author_thumbnail") or ""
        out.append({
            "author": c.get("author") or "",
            "authorId": c.get("author_id") or "",
            "authorThumbnails": [{"url": th, "width": 88, "height": 88}] if th else [],
            "content": c.get("text") or "",
            "publishedText": c.get("_time_text") or "",
            "likeCount": c.get("like_count") or 0,
            "authorIsChannelOwner": bool(c.get("author_is_uploader")),
            "creatorHeart": {} if c.get("is_favorited") else None,
            "isEdited": False,
            "commentId": c.get("id") or "",
        })
    body = json.dumps({"videoId": vid, "commentCount": info.get("comment_count") or len(out),
                       "comments": out}, ensure_ascii=False).encode()
    with _cm_lock:
        if out:
            _cm[key] = (time.time(), body)
        if len(_cm) > 500:
            for k in sorted(_cm, key=lambda k: _cm[k][0])[:100]:
                _cm.pop(k, None)
    return body


def related_for(vid):
    items = []
    for v in (details(vid).get("recommendedVideos") or [])[:PER_VIDEO]:
        v = dict(v); v.setdefault("type", "video"); items.append(v)
    return items


def short(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}".rstrip("0").rstrip(".").replace(".", ",") + " млн"
    if n >= 1000:
        return f"{n / 1000:.1f}".rstrip("0").rstrip(".").replace(".", ",") + " тыс."
    return str(n)


def views_text(n):
    if n >= 1000:
        return f"{short(n)} просмотров"
    a = n % 100; b = n % 10
    w = "просмотров" if 11 <= a <= 14 else "просмотр" if b == 1 else "просмотра" if 2 <= b <= 4 else "просмотров"
    return f"{short(n)} {w}"


def enrich(items, limit=80):
    """Invidious иногда отдаёт 0 просмотров и дату «сейчас» (не распарсил карточку YouTube) —
    дотягиваем реальные значения из /videos/<id> (кэш 6 ч)."""
    now, n = time.time(), 0
    for v in items:
        if n >= limit:
            break
        if v.get("liveNow"):
            d = details(v.get("videoId")); n += 1
            viewers = (d or {}).get("viewCount") or 0
            v["viewCountText"] = f"{short(viewers)} смотрят" if viewers else "Трансляция"
            v["published"] = 0
            v["publishedText"] = "в эфире"
            continue
        pub = v.get("published") or 0
        if v.get("viewCount") and pub and now - pub > 300:
            continue
        d = details(v.get("videoId")); n += 1
        if not d or d.get("error"):
            continue
        if d.get("viewCount"):
            v["viewCount"] = d["viewCount"]; v["viewCountText"] = views_text(d["viewCount"])
        if d.get("published"):
            v["published"] = d["published"]; v["publishedText"] = d.get("publishedText") or v.get("publishedText", "")
        if d.get("lengthSeconds") and not v.get("lengthSeconds"):
            v["lengthSeconds"] = d["lengthSeconds"]


def trending():
    out = []
    for t in ("", "music"):
        data = api("trending" + (f"?type={t}" if t else ""))
        out += data if isinstance(data, list) else []
    return out


def playable(v):
    if v.get("isUpcoming") or v.get("premium"):
        return False
    return bool(v.get("lengthSeconds")) or bool(v.get("liveNow"))


def build():
    watched = history()
    skip = set(watched)
    rel = []
    for vid in watched[:HISTORY_N]:
        rel += related_for(vid)
    sub = subs_videos()
    trd = trending()
    random.shuffle(rel); random.shuffle(trd)          # подписки — по свежести
    stats = f"history={len(watched)} related={len(rel)} subs={len(sub)} trending={len(trd)}"
    pools, pattern = {"r": rel, "s": sub, "t": trd}, "rrstrsrt"
    seen, out, i = set(), [], 0
    while any(pools.values()) and len(out) < 72:
        src = pools[pattern[i % len(pattern)]]; i += 1
        while src:
            v = src.pop(0)
            vid = v.get("videoId")
            if vid and vid not in seen and vid not in skip and playable(v):
                seen.add(vid); out.append(v); break
    enrich(out)
    for v in out:                                  # у видео из подписок (БД) нет готовой подписи
        if not v.get("liveNow") and not v.get("viewCountText") and v.get("viewCount"):
            v["viewCountText"] = views_text(v["viewCount"])
    log(f"built: {stats} -> {len(out)}")
    return json.dumps(out, ensure_ascii=False).encode()


_building = threading.Event()


def rebuild():
    """Полная сборка в фоне; пока идёт — отдаём прошлую ленту."""
    if _building.is_set():
        return
    _building.set()
    try:
        body = build()
        if body != b"[]":
            with _lock:
                _cache.update(t=time.time(), body=body)
    except Exception as e:
        log("rebuild", e)
    finally:
        _building.clear()


def quick():
    """Быстрая лента из одного запроса трендов — только пока нет первой полной сборки."""
    data = api("trending") or []
    out = [v for v in data if isinstance(v, dict) and playable(v)]
    return json.dumps(out, ensure_ascii=False).encode()


def get_body():
    with _lock:
        body, age = _cache["body"], time.time() - _cache["t"]
    if body != b"[]":
        if age > TTL:
            threading.Thread(target=rebuild, daemon=True).start()
        return body                                   # мгновенно, даже если устарело
    threading.Thread(target=rebuild, daemon=True).start()
    return quick()


def warmer():
    """Держит ленту свежей, пока ей пользуются. В простое — ничего не запрашивает;
    первый заход после простоя мгновенно получает прошлую ленту и запускает пересборку."""
    while True:
        if not active():
            time.sleep(60)
            continue
        rebuild()
        time.sleep(max(60, TTL - 30))


# ---------------- «Навигатор»: Музыка, Новости, Спорт… (q=ct:<раздел> в /api/v1/search) ----------------
SECTIONS = {
    "music":    [("новый клип", {"date": "week"}), ("премьера клипа", {"date": "week"}), ("новая песня", {"date": "week"}),
                 ("official music video", {"date": "week"})],
    "news":     [("новости", {"date": "today"}), ("новости сегодня", {"date": "today"}), ("главное за день", {"date": "today"})],
    "sport":    [("обзор матча", {"date": "week"}), ("футбол", {"date": "week"}), ("хоккей КХЛ", {"date": "week"}),
                 ("UFC бой", {"date": "week"})],
    "gaming":   [("прохождение", {"date": "week"}), ("обзор игры", {"date": "week"}), ("игровые новости", {"date": "week"}),
                 ("gameplay", {"date": "week"})],
    "live":     [("прямой эфир", {"features": "live"}), ("стрим", {"features": "live"}), ("live", {"features": "live"})],
    "podcasts": [("подкаст", {"date": "week", "duration": "long"}), ("интервью", {"date": "week", "duration": "long"})],
    "movies":   [("трейлер на русском", {"date": "week"}), ("фильм трейлер", {"date": "month"})],
    "shorts":   [],                     # собирается отдельно: build_shorts()
}
SHORTS_Q = ["#shorts", "shorts приколы", "#shorts россия", "#shorts музыка", "#shorts авто", "#shorts животные",
            "#shorts смешно", "#shorts спорт", "#shorts еда", "#shorts лайфхак", "#shorts игры", "#shorts фильм",
            "#shorts танцы", "#shorts юмор", "#shorts мультик"]
SHORTS_TAGS = ["shorts", "приколы", "юмор", "смешно", "животные", "кошки", "собаки", "еда", "рецепты", "лайфхак",
               "авто", "машины", "спорт", "футбол", "хоккей", "игры", "майнкрафт", "музыка", "танцы", "кино",
               "мультик", "путешествия", "природа", "технологии", "ремонт", "мемы", "россия", "fyp", "funny", "viral"]
SEC_TTL = int(os.environ.get("SEC_TTL", "1800"))
PAGE = 24
_sec = {}                                  # name -> (ts, [videos])
_sec_building = set()


def search(q, extra, page=1):
    p = {"q": q, "type": "video", "page": page, "sort": "views", "sort_by": "view_count"}
    if extra.get("features"):
        p.pop("sort"); p.pop("sort_by")      # эфиры — по релевантности, иначе вылезают старые
    p.update(extra)
    data = api("search?" + urllib.parse.urlencode(p))
    return [v for v in (data or []) if isinstance(v, dict) and v.get("type") == "video"]


def build_section(name):
    if name == "shorts":
        return build_shorts()
    lists = []
    for q, extra in SECTIONS[name]:
        got = []
        for page in ((1,) if name == "shorts" else (1, 2)):
            got += search(q, extra, page)
        lists.append(got)
    seen, out = set(), []
    cap = 400 if name == "shorts" else 120
    while any(lists) and len(out) < cap:                       # по одному из каждого запроса — разнообразнее
        for l in lists:
            while l:
                v = l.pop(0); vid = v.get("videoId")
                live_ok = name == "live" and v.get("liveNow")
                ln = v.get("lengthSeconds") or 0
                short_ok = name == "shorts" and not v.get("liveNow") and not v.get("isUpcoming") and ln <= 180
                ok = live_ok if name == "live" else short_ok if name == "shorts" else playable(v)
                if vid and vid not in seen and ok:
                    seen.add(vid); out.append(v); break
    if name == "shorts":
        out = shorts_filter(out)
    enrich(out, limit=0 if name == "shorts" else 40)
    for v in out:
        if not v.get("liveNow") and v.get("viewCount") and not v.get("viewCountText"):
            v["viewCountText"] = views_text(v["viewCount"])
    log(f"section {name}: {len(out)}")
    return out


_SCRIPT_BAD = re.compile("[\u0590-\u08ff\u0900-\u0dff\u0e00-\u0fff\u1000-\u109f\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]")
SHORTS_MIN_VIEWS = int(os.environ.get("SHORTS_MIN_VIEWS", "50000"))


VERT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vertical.json")
try:
    _vert = json.load(open(VERT_FILE))
except Exception:
    _vert = {}
_vert_lock = threading.Lock()


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


_noredir = urllib.request.build_opener(_NoRedirect)


def shorts_url(vid):
    """youtube.com/shorts/ID: 200 — это Shorts, редирект на /watch — обычное видео, иначе None."""
    req = urllib.request.Request(f"https://www.youtube.com/shorts/{vid}", method="HEAD", headers={
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36",
        "Cookie": "SOCS=CAI; CONSENT=YES+cb", "Accept-Language": "ru,en;q=0.8"})
    try:
        with _noredir.open(req, timeout=8) as r:
            return r.status == 200
    except urllib.error.HTTPError as e:
        if e.code in (301, 302, 303, 307, 308):
            loc = e.headers.get("Location", "")
            return False if "/watch" in loc else None
        return None
    except Exception:
        return None


def is_vertical(vid):
    """True — вертикальное видео (настоящий Shorts), False — широкое, None — не удалось узнать."""
    with _vert_lock:
        if vid in _vert:
            return _vert[vid]
    r = shorts_url(vid)
    if r is not None:
        with _vert_lock:
            _vert[vid] = r
        return r
    d = details(vid)
    w = h = 0
    for f in (d.get("adaptiveFormats") or []) + (d.get("formatStreams") or []):
        m = re.match(r"^(\d+)x(\d+)$", str(f.get("size") or ""))
        if m:
            w, h = int(m.group(1)), int(m.group(2))
            break
    if not w:
        return None
    r = h > w * 1.1
    with _vert_lock:
        _vert[vid] = r
    return r


def vert_save():
    try:
        with _vert_lock:
            data = json.dumps(_vert)
        open(VERT_FILE + ".tmp", "w").write(data); os.replace(VERT_FILE + ".tmp", VERT_FILE)
    except Exception as e:
        log("vert save", e)


def shorts_filter(items):
    """Только вертикальные, популярные и на латинице/кириллице; сортировка по просмотрам."""
    from concurrent.futures import ThreadPoolExecutor as _TPE
    items = [v for v in items if not _SCRIPT_BAD.search((v.get("title") or "") + (v.get("author") or ""))]
    items.sort(key=lambda v: -(v.get("viewCount") or 0))
    items = items[:450]
    with _TPE(6) as ex:
        verdict = list(ex.map(lambda v: is_vertical(v.get("videoId")), items))
    vert_save()
    yes = [v for v, ok in zip(items, verdict) if ok]
    unknown = [v for v, ok in zip(items, verdict) if ok is None]
    log(f"shorts: вертикальных {len(yes)}, не удалось проверить {len(unknown)}, широких {len(items) - len(yes) - len(unknown)}")
    items = yes if len(yes) >= 30 else yes + unknown       # проверка не сработала — лучше показать, чем пусто
    good = [v for v in items if (v.get("viewCount") or 0) >= SHORTS_MIN_VIEWS]
    if len(good) < 40:                       # если популярных мало — добираем лучшими из остальных
        good += [v for v in items if v not in good][:40 - len(good)]
    good.sort(key=lambda v: -(v.get("viewCount") or 0))
    return good[:300]


# ---------------- Shorts: как NewPipe/LibreTube — из вкладки «Shorts» каналов ----------------
# Вкладка /channel/X/shorts содержит только настоящие Shorts (вертикальные, без трансляций),
# поэтому ролики берутся оттуда. Каналы-источники: подписки, авторы роликов со страниц
# youtube.com/hashtag/<тег>/shorts (yt-dlp) и авторы проверенных Shorts из поиска.
# Список каналов копится между пересборками (shorts_channels.json) — подборка растёт.
SH_CH_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "shorts_channels.json")
SH_MAX_CH = int(os.environ.get("SHORTS_CHANNELS", "90"))
SH_PER_CH = int(os.environ.get("SHORTS_PER_CHANNEL", "18"))
try:
    _sh_ch = json.load(open(SH_CH_FILE))           # ucid -> {"n": author, "t": last_seen_ts, "ok": shorts_found}
except Exception:
    _sh_ch = {}


def hashtag_ids(tag, n=60):
    url = f"https://www.youtube.com/hashtag/{urllib.parse.quote(tag)}/shorts"
    try:
        p = subprocess.run([YTDLP, "--flat-playlist", "-J", "--no-warnings", "--quiet", "--playlist-end", str(n),
                            "--extractor-args", "youtube:lang=ru", url], capture_output=True, timeout=90)
        info = json.loads(p.stdout or b"{}")
    except Exception as e:
        log("hashtag", tag, e); return []
    out = []
    for e in info.get("entries") or []:
        vid = e.get("id")
        if vid and re.match(r"^[\w-]{11}$", vid):
            out.append((vid, e.get("view_count") or 0, e.get("channel_id")))
    return out


def channel_shorts(ucid):
    data = api(f"channels/{ucid}/shorts?sort_by=popular")
    vids = (data or {}).get("videos") if isinstance(data, dict) else data
    out = []
    for v in vids or []:
        if not isinstance(v, dict) or not v.get("videoId") or v.get("liveNow") or v.get("isUpcoming"):
            continue
        v = dict(v); v["type"] = "video"
        v.setdefault("author", (_sh_ch.get(ucid) or {}).get("n", "")); v.setdefault("authorId", ucid)
        v["authorUrl"] = f"/channel/{ucid}"
        if not v.get("videoThumbnails"):
            vid = v["videoId"]
            v["videoThumbnails"] = [{"quality": "high", "url": f"/vi/{vid}/hqdefault.jpg", "width": 480, "height": 360}]
        out.append(v)
    return out


def build_shorts():
    from concurrent.futures import ThreadPoolExecutor as _TPE
    now = time.time()
    found = {}                                  # ucid -> author
    # 1) хэштеги (yt-dlp): id роликов → авторы через Invidious /videos
    tags = random.sample(SHORTS_TAGS, min(10, len(SHORTS_TAGS)))
    with _TPE(3) as ex:
        tag_ids = [x for l in ex.map(hashtag_ids, tags) for x in l]
    log(f"shorts: с хэштегов {len(tag_ids)} роликов")
    tag_ids.sort(key=lambda x: -x[1])
    need = [vid for vid, _, ch in tag_ids if not ch][:80]
    for vid, _, ch in tag_ids:
        if ch:
            found.setdefault(ch, "")
    with _TPE(6) as ex:
        for d in ex.map(details, need):
            if d.get("authorId"):
                found[d["authorId"]] = d.get("author") or ""
    # 2) поиск #shorts: только ролики, которые youtube.com/shorts подтвердил
    cand = []
    for q in random.sample(SHORTS_Q, 6):
        cand += [v for v in search(q, {"date": "month", "duration": "short"}) if v.get("authorId")]
    with _TPE(6) as ex:
        ok = list(ex.map(lambda v: is_vertical(v["videoId"]), cand))
    vert_save()
    for v, r in zip(cand, ok):
        if r:
            found.setdefault(v["authorId"], v.get("author") or "")
    # 3) подписки — всегда
    subs = set()
    try:
        subs = set(json.loads(sql("select coalesce(json_agg(s),'[]') from (select distinct unnest(subscriptions) s from users) t") or "[]"))
    except Exception as e:
        log("shorts subs", e)
    for ucid, name in found.items():
        c = _sh_ch.setdefault(ucid, {"n": name, "t": now, "ok": 1})
        c["t"] = now
        if name:
            c["n"] = name
    # каналы, где Shorts не нашлись 3 раза подряд, и давно не встречавшиеся — забываем
    for ucid in [u for u, c in _sh_ch.items() if c.get("ok", 1) <= -3 or now - c.get("t", 0) > 21 * 86400]:
        _sh_ch.pop(ucid, None)
    fresh = [u for u in found if u in _sh_ch]
    old = [u for u in _sh_ch if u not in found]
    random.shuffle(fresh); random.shuffle(old)
    pick = list(dict.fromkeys(list(subs) + fresh[:SH_MAX_CH // 2] + old))[:SH_MAX_CH + len(subs)]
    with _TPE(6) as ex:
        res = list(ex.map(channel_shorts, pick))
    per = []
    for ucid, vids in zip(pick, res):
        c = _sh_ch.get(ucid)
        if c is not None:
            c["ok"] = 1 if vids else min(0, c.get("ok", 1)) - 1
        vids = [v for v in vids if not _SCRIPT_BAD.search((v.get("title") or "") + (v.get("author") or ""))]
        if ucid not in subs:
            vids = [v for v in vids if (v.get("viewCount") or 0) >= SHORTS_MIN_VIEWS] or vids[:3]
        random.shuffle(vids)
        if vids:
            per.append(vids[:SH_PER_CH])
    try:
        open(SH_CH_FILE + ".tmp", "w").write(json.dumps(_sh_ch, ensure_ascii=False)); os.replace(SH_CH_FILE + ".tmp", SH_CH_FILE)
    except Exception as e:
        log("shorts ch save", e)
    # по одному ролику с канала по кругу — чтобы подряд не шёл один автор
    random.shuffle(per)
    out, seen = [], set()
    while any(per):
        for l in per:
            if l:
                v = l.pop(0)
                if v["videoId"] not in seen:
                    seen.add(v["videoId"]); out.append(v)
    for v in out:
        if v.get("viewCount") and not v.get("viewCountText"):
            v["viewCountText"] = views_text(v["viewCount"])
    log(f"shorts: каналов {len(pick)} (новых {len(found)}, подписок {len(subs)}), с Shorts {len(per)}, роликов {len(out)}")
    return out


def section_bg(name):
    if name in _sec_building:
        return
    _sec_building.add(name)
    try:
        items = build_section(name)
        if items:
            with _lock:
                _sec[name] = (time.time(), items)
    except Exception as e:
        log("section", name, e)
    finally:
        _sec_building.discard(name)


def section_page(name, page):
    with _lock:
        hit = _sec.get(name)
    if not hit:
        section_bg(name)                                      # первый раз — ждём (10–20 с)
        for _ in range(90):                                   # или ждём, пока соберёт фоновая сборка
            with _lock:
                hit = _sec.get(name)
            if hit or name not in _sec_building:
                break
            time.sleep(1)
    elif time.time() - hit[0] > SEC_TTL:
        threading.Thread(target=section_bg, args=(name,), daemon=True).start()
    items = hit[1] if hit else []
    page = max(1, page)
    if name == "shorts" and items:                            # Shorts не кончаются: по кругу
        start = ((page - 1) * PAGE) % len(items)
        chunk = (items + items)[start: start + PAGE]
        return json.dumps(chunk, ensure_ascii=False).encode()
    return json.dumps(items[(page - 1) * PAGE: page * PAGE], ensure_ascii=False).encode()


def section_warmer():
    time.sleep(20)
    while True:
        if not active():                                      # простой — разделы обновятся при заходе
            time.sleep(60)
            continue
        for n in SECTIONS:
            section_bg(n); time.sleep(5)
        time.sleep(max(300, SEC_TTL - 300))


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        qs = urllib.parse.parse_qs(u.query)
        q = (qs.get("q") or [""])[0]
        if not u.path.startswith("/ct-api/caps"):            # проверка дополнений при запуске — не просмотр
            touch()
        if u.path.startswith("/ct-api/caps"):            # приложение CloudTube проверяет, есть ли дополнения
            body = json.dumps({"cloudtube": 1, "sections": sorted(SECTIONS), "comments": True, "avatars": True}).encode()
        elif u.path.startswith("/ct-api/comments"):
            vid = (qs.get("v") or [""])[0]
            sort = (qs.get("sort") or ["top"])[0]
            body = ytdlp_comments(vid, sort) if re.match(r"^[\w-]{11}$", vid) else b'{"comments":[]}'
        elif u.path.startswith("/ct-api/avatars"):
            ids = [x for x in (qs.get("ids") or [""])[0].split(",") if x]
            body = avatars(ids)
        elif u.path.endswith("/search") and q.startswith("ct:") and q[3:] in SECTIONS:
            try:
                page = int((qs.get("page") or ["1"])[0])
            except ValueError:
                page = 1
            body = section_page(q[3:], page)
        elif u.path.endswith("/search"):                  # не наш раздел — пусто (nginx сюда такое не шлёт)
            body = b"[]"
        elif self.path.startswith("/refresh"):               # ручная пересборка (ждёт результат)
            rebuild()
            with _lock:
                body = _cache["body"]
        else:
            body = get_body()
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    log(f":{LISTEN} <- {INV} region={REGION} hl={HL} ttl={TTL}s idle={IDLE_MIN}m")
    threading.Thread(target=warmer, daemon=True).start()   # лента всегда готова заранее
    threading.Thread(target=section_warmer, daemon=True).start()
    threading.Thread(target=av_saver, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", LISTEN), H).serve_forever()
