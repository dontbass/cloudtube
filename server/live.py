#!/usr/bin/env python3
"""CloudTube live helper.
 /api/v1/videos/<id>  -> прокси к Invidious; для эфиров (liveNow) подставляет hlsUrl
 /live/<id>.m3u8      -> master HLS (через yt-dlp), все ссылки переписаны на /live/p|s
 /live/p?u=...        -> media-плейлист (переписывается)
 /live/s?u=...        -> сегмент (стрим байтов через сервер)
 /ggpht/<path>        -> аватары/баннеры каналов с yt3.googleusercontent.com (вместо сломанного /ggpht Invidious)"""
import json, os, re, subprocess, threading, time, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

INV = os.environ.get("INV_URL", "http://127.0.0.1:3000")
LISTEN = int(os.environ.get("LIVE_PORT", "3300"))
PUBLIC = os.environ.get("PUBLIC_URL", "").rstrip("/")
YTDLP = os.environ.get("YTDLP", "yt-dlp")
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36"
ALLOWED = (".googlevideo.com", ".youtube.com", ".ytimg.com")
ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")

_master = {}            # id -> (ts, url)
_lock = threading.Lock()


def log(*a):
    print("[live]", *a, flush=True)


def master_url(vid):
    with _lock:
        hit = _master.get(vid)
        if hit and time.time() - hit[0] < 1800:
            return hit[1]
    out = subprocess.run([YTDLP, "-j", "--no-warnings", "--skip-download",
                          f"https://www.youtube.com/watch?v={vid}"],
                         capture_output=True, text=True, timeout=90)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip()[-400:])
    info = json.loads(out.stdout)
    url = info.get("manifest_url")
    if not url:
        for f in info.get("formats", []):
            if f.get("manifest_url") and "m3u8" in (f.get("protocol") or ""):
                url = f["manifest_url"]; break
    if not url:
        raise RuntimeError("no HLS manifest (not live?)")
    with _lock:
        _master[vid] = (time.time(), url)
    return url


def allowed(u):
    h = urllib.parse.urlparse(u).hostname or ""
    return urllib.parse.urlparse(u).scheme == "https" and h.endswith(ALLOWED)


def kind_of(u):
    pu = urllib.parse.urlparse(u)
    if "/videoplayback" in pu.path:
        return "s"
    if (pu.hostname or "").startswith("manifest.") or pu.path.endswith(".m3u8"):
        return "p"
    return "s"


def wrap(u, kind):
    # расширение в пути — чтобы плеер сразу понимал тип и не делал HEAD
    if kind == "p":
        name = "index.m3u8"
    else:
        tail = urllib.parse.urlparse(u).path.rsplit("/", 1)[-1]
        ext = tail.rsplit(".", 1)[-1].lower() if "." in tail else "ts"
        name = "seg." + (ext if ext in ("ts", "mp4", "m4s", "aac", "m4a") else "ts")
    return f"/live/{kind}/{name}?u=" + urllib.parse.quote(u, safe="")


def rewrite_m3u8(text, base):
    out = []
    for line in text.splitlines():
        s = line.strip()
        if s and not s.startswith("#"):
            absu = urllib.parse.urljoin(base, s)
            out.append(wrap(absu, kind_of(absu)))
        elif 'URI="' in line:
            def rep(m):
                absu = urllib.parse.urljoin(base, m.group(1))
                return f'URI="{wrap(absu, kind_of(absu))}"'
            out.append(re.sub(r'URI="([^"]+)"', rep, line))
        else:
            out.append(line)
    return "\n".join(out) + "\n"


def upstream(u, headers=None):
    req = urllib.request.Request(u, headers={"User-Agent": UA, **(headers or {})})
    return urllib.request.urlopen(req, timeout=30)


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def reply(self, code, body, ctype="application/json; charset=utf-8", extra=None):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    # ---------- /api/v1/videos/<id> ----------
    def videos(self, path, query):
        url = INV + path + (("?" + query) if query else "")
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"Accept": "application/json"}), timeout=60) as r:
                code, body, ctype = r.status, r.read(), r.headers.get("Content-Type", "application/json")
        except urllib.error.HTTPError as e:
            code, body, ctype = e.code, e.read(), e.headers.get("Content-Type", "application/json")
        if code == 200:
            try:
                d = json.loads(body)
                if isinstance(d, dict) and d.get("liveNow") and not d.get("hlsUrl"):
                    vid = d.get("videoId") or path.rsplit("/", 1)[-1]
                    d["hlsUrl"] = f"{PUBLIC}/live/{vid}.m3u8"
                    body = json.dumps(d, ensure_ascii=False).encode()
                    log("hlsUrl injected", vid)
            except Exception as e:
                log("json", e)
        self.reply(code, body, ctype)

    # ---------- HLS ----------
    def playlist(self, u):
        if not allowed(u):
            return self.reply(403, "forbidden", "text/plain")
        with upstream(u) as r:
            text = r.read().decode("utf-8", "replace")
            base = r.geturl()
        self.reply(200, rewrite_m3u8(text, base), "application/vnd.apple.mpegurl", {"Cache-Control": "no-cache"})

    def segment(self, u):
        if not allowed(u):
            return self.reply(403, "forbidden", "text/plain")
        hdr = {}
        if self.headers.get("Range"):
            hdr["Range"] = self.headers["Range"]
        try:
            r = upstream(u, hdr)
        except urllib.error.HTTPError as e:
            return self.reply(e.code, e.read() or b"", "text/plain")
        with r:
            self.send_response(r.status)
            for k in ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges"):
                if r.headers.get(k):
                    self.send_header(k, r.headers[k])
            if not r.headers.get("Content-Length"):
                self.send_header("Transfer-Encoding", "chunked")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            chunked = not r.headers.get("Content-Length")
            while True:
                buf = r.read(65536)
                if not buf:
                    break
                if chunked:
                    self.wfile.write(f"{len(buf):x}\r\n".encode() + buf + b"\r\n")
                else:
                    self.wfile.write(buf)
            if chunked:
                self.wfile.write(b"0\r\n\r\n")

    def do_HEAD(self):
        """Shaka делает HEAD к сегментам, чтобы узнать MIME-тип."""
        p = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(p.query)
        try:
            kind = re.match(r"^/live/([ps])(?:/[^/]*)?$", p.path)
            if kind and not (q.get("u") and allowed(q["u"][0])):
                self.send_response(403); self.send_header("Content-Length", "0"); self.end_headers(); return
            if kind and kind.group(1) == "s":
                ctype, clen = "video/mp2t", None
                try:
                    req = urllib.request.Request(q["u"][0], method="HEAD", headers={"User-Agent": UA})
                    with urllib.request.urlopen(req, timeout=15) as r:
                        ctype = r.headers.get("Content-Type") or ctype
                        clen = r.headers.get("Content-Length")
                except Exception:
                    pass
                self.send_response(200)
                self.send_header("Content-Type", ctype)
                if clen:
                    self.send_header("Content-Length", clen)
                self.send_header("Accept-Ranges", "bytes")
                self.end_headers()
                return
            if p.path.startswith("/live/"):
                self.send_response(200)
                self.send_header("Content-Type", "application/vnd.apple.mpegurl")
                self.end_headers()
                return
            self.send_response(405)
            self.send_header("Content-Length", "0")
            self.end_headers()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def image(self, path):
        # уменьшаем запрошенный размер: аватары на странице ≤ 176px, баннеры ≤ 1280px
        path = re.sub(r"=s(\d+)", lambda m: "=s" + str(min(int(m.group(1)), 176)), path)
        path = re.sub(r"=w(\d+)", lambda m: "=w" + str(min(int(m.group(1)), 1280)), path)
        last = None
        for host in ("https://yt3.googleusercontent.com", "https://yt3.ggpht.com"):
            try:
                with upstream(host + path) as r:
                    body = r.read()
                    return self.reply(200, body, r.headers.get("Content-Type", "image/jpeg"),
                                      {"Cache-Control": "public, max-age=86400"})
            except urllib.error.HTTPError as e:
                last = e.code
            except Exception as e:
                last = str(e)
        self.reply(404, f"image not found ({last})", "text/plain")

    def do_GET(self):
        p = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(p.query)
        try:
            if p.path.startswith("/ggpht/") and re.match(r"^/ggpht/[A-Za-z0-9_\-=/.,~]+$", p.path):
                return self.image(p.path[len("/ggpht"):])
            if p.path.startswith("/api/v1/videos/"):
                return self.videos(p.path, p.query)
            m = re.match(r"^/live/([A-Za-z0-9_-]{11})\.m3u8$", p.path)
            if m:
                return self.playlist(master_url(m.group(1)))
            kind = re.match(r"^/live/([ps])(?:/[^/]*)?$", p.path)
            if kind and q.get("u"):
                return (self.playlist if kind.group(1) == "p" else self.segment)(q["u"][0])
            self.reply(404, "not found", "text/plain")
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            log("error", self.path[:120], e)
            try:
                self.reply(502, str(e), "text/plain")
            except Exception:
                pass


if __name__ == "__main__":
    log(f":{LISTEN} inv={INV} public={PUBLIC}")
    ThreadingHTTPServer(("127.0.0.1", LISTEN), H).serve_forever()
