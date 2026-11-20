(function () {
  var B = 'CloudTube';
  function fixTitle() { var t = document.title; if (/Materialious/.test(t)) document.title = t.replace(/Materialious/g, B); }
  new MutationObserver(fixTitle).observe(document.querySelector('title') || document.head, { childList: true, subtree: true, characterData: true });
  fixTitle();

  /* ---- перевод дат dayjs (Materialious не подгружает русскую локаль dayjs) ---- */
  var U = { second: ['секунду', 'секунды', 'секунд'], minute: ['минуту', 'минуты', 'минут'], hour: ['час', 'часа', 'часов'],
            day: ['день', 'дня', 'дней'], week: ['неделю', 'недели', 'недель'], month: ['месяц', 'месяца', 'месяцев'], year: ['год', 'года', 'лет'] };
  var MON = { Jan: 'янв.', Feb: 'февр.', Mar: 'мар.', Apr: 'апр.', May: 'мая', Jun: 'июн.', Jul: 'июл.', Aug: 'авг.', Sep: 'сент.', Oct: 'окт.', Nov: 'нояб.', Dec: 'дек.' };
  function pl(n, f) { var a = Math.abs(n) % 100, b = a % 10; if (a > 10 && a < 20) return f[2]; if (b > 1 && b < 5) return f[1]; if (b === 1) return f[0]; return f[2]; }
  function unit(n, u) { var one = (n === 'a' || n === 'an'); var k = one ? 1 : +n; return (one ? '' : k + ' ') + pl(k, U[u]); }
  var UN = '(second|minute|hour|day|week|month|year)s?';
  var reAgo = new RegExp('\\b(a|an|\\d+) ' + UN + ' ago\\b', 'g');
  var reIn = new RegExp('\\bin (a|an|\\d+) ' + UN + '\\b', 'g');
  var reDate = /\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{1,2})(st|nd|rd|th)(?: (\d{4}))?\b/g;
  var reQuick = /ago\b|\bin (a|an|\d)|a few seconds|(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d/;
  function tr(s) {
    return s.replace(/\ba few seconds ago\b/g, 'только что').replace(/\bin a few seconds\b/g, 'через несколько секунд')
      .replace(reAgo, function (m, n, u) { return unit(n, u) + ' назад'; })
      .replace(reIn, function (m, n, u) { return 'через ' + unit(n, u); })
      .replace(reDate, function (m, mo, d, s, y) { return d + ' ' + MON[mo] + (y ? ' ' + y + ' г.' : ''); });
  }
  var SKIP = 'a.video-title, h5, h6, .comment-info > p, .description, input, textarea, script, style';
  function walk(root) {
    if (!root || root.nodeType !== 1 && root.nodeType !== 3) return;
    if (root.nodeType === 3) { fixNode(root); return; }
    var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT), n;
    while ((n = w.nextNode())) fixNode(n);
  }
  function fixNode(n) {
    var v = n.nodeValue; if (!v || !reQuick.test(v)) return;
    var p = n.parentElement; if (!p || p.closest(SKIP)) return;
    var t = tr(v); if (t !== v) n.nodeValue = t;
  }
  var queue = [], scheduled = false;
  function flush() { scheduled = false; var q = queue; queue = []; for (var i = 0; i < q.length; i++) walk(q[i]); }
  function start() {
    walk(document.body);
    new MutationObserver(function (ms) {
      for (var i = 0; i < ms.length; i++) {
        var m = ms[i];
        if (m.type === 'characterData') queue.push(m.target);
        else for (var j = 0; j < m.addedNodes.length; j++) queue.push(m.addedNodes[j]);
      }
      if (!scheduled && queue.length) { scheduled = true; requestAnimationFrame(flush); }
    }).observe(document.body, { childList: true, subtree: true, characterData: true });
  }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();

/* ---- пункт «Доступ» (админка приглашений) — только для администратора ---- */
(function () {
  var isAdmin = false;
  function addLinks() {
    if (!isAdmin) return;
    var nav = document.getElementById('left-nav');
    if (nav && !nav.querySelector('a.ct-admin')) {
      var links = nav.querySelectorAll(':scope > a');
      var a = document.createElement('a');
      a.className = 'ct-admin'; a.href = '/ctadmin/';
      a.innerHTML = '<i>group_add</i><div>Доступ</div>';
      if (links.length) links[links.length - 1].after(a); else nav.appendChild(a);
    }
    var top = document.getElementById('top-content');
    if (top && !top.querySelector('a.ct-admin-top')) {
      var b = document.createElement('a');
      b.className = 'button circle transparent ct-admin-top'; b.href = '/ctadmin/'; b.title = 'Доступ';
      b.innerHTML = '<i>group_add</i>';
      var last = top.querySelector(':scope > button:last-of-type, :scope > a:last-of-type');
      if (last) last.before(b); else top.appendChild(b);
    }
  }
  fetch('/ctadmin/whoami', { credentials: 'same-origin', cache: 'no-store' })
    .then(function (r) { return r.ok ? r.json() : null; })
    .then(function (j) {
      if (!j || !j.admin) return;
      isAdmin = true; addLinks();
      new MutationObserver(addLinks).observe(document.body, { childList: true, subtree: true });
    }).catch(function () {});
})();

/* ---- пункт «Подписки YouTube» (перенос с YouTube, удалить все) — для всех пользователей ---- */
(function () {
  function addLink() {
    var nav = document.getElementById('left-nav');
    if (!nav || nav.querySelector('a.ct-ytsubs')) return;
    var a = document.createElement('a');
    a.className = 'ct-ytsubs'; a.href = '/ctsubs/'; a.title = 'Перенести подписки с YouTube или удалить все';
    a.innerHTML = '<i>sync_alt</i><div>Импорт подписок</div>';
    var subs = nav.querySelector(':scope > a[href$="/subscriptions"]'), links = nav.querySelectorAll(':scope > a:not(.ct-admin)');
    if (subs) subs.after(a); else if (links.length) links[links.length - 1].after(a); else nav.appendChild(a);
  }
  function start() { addLink(); new MutationObserver(addLink).observe(document.body, { childList: true, subtree: true }); }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();

/* ---- SponsorBlock: понятные русские названия сегментов в уведомлении ---- */
(function () {
  var CAT = { sponsor: 'реклама', selfpromo: 'самопиар', interaction: 'просьба подписаться', intro: 'заставка', outro: 'концовка',
              preview: 'превью', music_offtopic: 'немузыкальная часть', filler: 'отступление', poi_highlight: 'главный момент', exclusive_access: 'эксклюзив' };
  var re = new RegExp('^(.*?)\\s*\\b(' + Object.keys(CAT).join('|') + ')\\s*$');
  function fix(root) {
    var ps = (root.querySelectorAll ? root : document).querySelectorAll('[data-melt-toaster-toast-content] p');
    ps.forEach(function (p) {
      var t = p.lastChild; if (!t || t.nodeType !== 3) return;
      var m = t.nodeValue.match(re); if (!m) return;
      var head = m[1].replace(/Upcoming segment/i, 'Сейчас будет').trim() || 'Сейчас будет';
      t.nodeValue = ' ' + head + ': ' + CAT[m[2]];
      if (!p.querySelector('i')) { var i = document.createElement('i'); i.textContent = 'fast_forward'; p.prepend(i); }
    });
    document.querySelectorAll('[data-melt-toaster-toast-content] button span').forEach(function (s) {
      if (/^\s*skip\s*$/i.test(s.textContent)) s.textContent = 'Пропустить';
    });
  }
  function start() { new MutationObserver(function () { fix(document); }).observe(document.body, { childList: true, subtree: true }); }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();

/* ---- «Premium»-режим одной кнопкой: набор настроек Materialious как в YouTube Premium ---- */
(function () {
  var FLAG = 'ctPremium', BACKUP = 'ctPremiumBackup';
  var SET = {
    sponsorBlock: true,
    sponsorBlockCategoriesv2: { sponsor: 'automatic', selfpromo: 'automatic', interaction: 'automatic', preview: 'automatic',
                                intro: 'manual', outro: 'manual', filler: 'manual', music_offtopic: 'automatic' },
    sponsorBlockDisplayToast: true,
    sponsorBlockTimeline: true,
    defaultQuality: '1080',
    autoplayNextByDefault: true,
    miniplayerEnabled: true,
    savePlaybackPosition: true,
    returnYtDislikes: true,
    proxyVideos: true,
    darkMode: true
  };
  function ser(v) { return (v && typeof v === 'object') ? JSON.stringify(Object.assign({}, v, { '#$@__reference__': 0 })) : JSON.stringify(v); }
  function isOn() { try { return localStorage.getItem(FLAG) === '1'; } catch (e) { return false; } }
  function toggle() {
    try {
      if (!isOn()) {
        var bak = {};
        Object.keys(SET).forEach(function (k) { bak[k] = localStorage.getItem(k); localStorage.setItem(k, ser(SET[k])); });
        localStorage.setItem('advancedTheming', '{"#$@__reference__":0}');
        localStorage.setItem(BACKUP, JSON.stringify(bak)); localStorage.setItem(FLAG, '1');
        sessionStorage.setItem('ctPremiumMsg', 'on');
      } else {
        var b = {}; try { b = JSON.parse(localStorage.getItem(BACKUP) || '{}'); } catch (e) {}
        Object.keys(SET).forEach(function (k) { if (b[k] === null || b[k] === undefined) localStorage.removeItem(k); else localStorage.setItem(k, b[k]); });
        localStorage.setItem('advancedTheming', '{"#$@__reference__":0}');
        localStorage.removeItem(BACKUP); localStorage.setItem(FLAG, '0');
        sessionStorage.setItem('ctPremiumMsg', 'off');
      }
    } catch (e) { alert('Не удалось сохранить настройки: ' + e); return; }
    location.reload();
  }
  function toast(text) {
    var d = document.createElement('div'); d.className = 'ct-toast'; d.innerHTML = text; document.body.appendChild(d);
    setTimeout(function () { d.classList.add('show'); }, 30);
    setTimeout(function () { d.classList.remove('show'); setTimeout(function () { d.remove(); }, 400); }, 5200);
  }
  function addButton() {
    var top = document.getElementById('top-content'); if (!top || top.querySelector('.ct-premium-btn')) return;
    var b = document.createElement('button');
    b.className = 'circle transparent ct-premium-btn' + (isOn() ? ' on' : '');
    b.title = isOn() ? 'Premium-режим включён — нажмите, чтобы выключить' : 'Включить Premium-режим';
    b.innerHTML = '<i>workspace_premium</i>';
    b.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); toggle(); });
    var gear = Array.prototype.find.call(top.querySelectorAll('i'), function (i) { return i.textContent.trim() === 'settings'; });
    var anchor = gear && gear.closest('button, a');
    if (anchor && anchor.parentElement) anchor.parentElement.insertBefore(b, anchor); else top.appendChild(b);
  }
  /* в Premium тема всегда тёмная. Materialious запоминает палитру (advancedTheming) и при ней
     игнорирует darkMode — поэтому сбрасываем палитру, он сам пересоберёт тёмную */
  var EMPTY = '{"#$@__reference__":0}';
  function forceDark() {
    if (!isOn()) return;
    try {
      var light = localStorage.getItem('darkMode') !== 'true' || (document.body && document.body.classList.contains('light'));
      if (!light) { sessionStorage.removeItem('ctDarkFix'); return; }
      var n = +(sessionStorage.getItem('ctDarkFix') || 0);
      if (n >= 2) return;                                   // защита от бесконечной перезагрузки
      sessionStorage.setItem('ctDarkFix', String(n + 1));
      localStorage.setItem('darkMode', 'true');
      localStorage.setItem('advancedTheming', EMPTY);
      if (n === 0 && localStorage.getItem('ctPremiumMsg') !== null) localStorage.removeItem('ctPremiumMsg');
      if (!sessionStorage.getItem('ctPremiumMsg')) sessionStorage.setItem('ctPremiumMsg', 'dark');
      location.reload();
    } catch (e) {}
  }
  forceDark();
  function start() {
    if (isOn()) document.documentElement.classList.add('ct-premium');
    setInterval(forceDark, 1500);
    addButton();
    new MutationObserver(addButton).observe(document.body, { childList: true, subtree: true });
    var msg = sessionStorage.getItem('ctPremiumMsg');
    if (msg) {
      sessionStorage.removeItem('ctPremiumMsg');
      toast(msg === 'on'
        ? '<b>Premium-режим включён</b><br>Тёмная тема. Реклама и самопиар в роликах пропускаются автоматически, качество 1080p, автовоспроизведение следующего, мини-плеер, продолжение с места остановки, дизлайки.'
        : msg === 'dark' ? '<b>В Premium-режиме тема всегда тёмная</b><br>Чтобы включить светлую, выключите Premium (значок рядом с настройками).'
        : '<b>Premium-режим выключен</b><br>Ваши прежние настройки восстановлены.');
    }
  }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();

/* ---- меню-гамбургер, мини-меню, скрытое меню на странице просмотра, подписки в меню ---- */
(function () {
  var D = document.documentElement;
  var BURGER = '<svg viewBox="0 0 24 24"><path d="M3 6h18v2H3zm0 5h18v2H3zm0 5h18v2H3z"/></svg>';
  function ls(k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) { return null; } }
  if (ls('ctNavMini') === '1') D.classList.add('ct-mini');

  function isWatch() { return /^\/watch\b/.test(location.pathname); }
  function closeDrawer() { D.classList.remove('ct-drawer'); }
  function toggle() {
    if (D.classList.contains('ct-watch') || window.innerWidth < 1000) {
      if (!D.classList.contains('ct-watch')) { D.classList.toggle('ct-mini'); return; }
      D.classList.toggle('ct-drawer');
    } else {
      var on = D.classList.toggle('ct-mini'); ls('ctNavMini', on ? '1' : '0');
    }
  }
  function mkHead() {
    var h = document.createElement('div'); h.className = 'ct-head';
    h.innerHTML = '<button class="ct-burger" type="button" title="Меню">' + BURGER + '</button><a class="ct-logo" href="/" title="Главная"></a>';
    h.querySelector('.ct-burger').addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); toggle(); });
    return h;
  }
  function ensureHead() {
    var top = document.getElementById('top-content'), nav = document.getElementById('left-nav');
    if (top && !top.querySelector(':scope > .ct-head')) { top.insertBefore(mkHead(), top.firstChild); D.classList.add('ct-has-head'); }
    if (nav && !nav.querySelector(':scope > .ct-head')) nav.insertBefore(mkHead(), nav.firstChild);
    if (!document.querySelector('.ct-scrim')) {
      var s = document.createElement('div'); s.className = 'ct-scrim'; s.addEventListener('click', closeDrawer);
      document.body.appendChild(s);
    }
  }
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeDrawer(); });
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('#left-nav a:not(.ct-more)'); if (a) setTimeout(closeDrawer, 0);
  }, true);

  /* ---- подписки ---- */
  function auth() {
    try { var a = JSON.parse(ls('authToken') || 'null'); return a && a.token ? a.token : null; } catch (e) { return null; }
  }
  function hdr(t) { return t.indexOf('SID=') === 0 ? { __sid_auth: t } : { Authorization: 'Bearer ' + t }; }
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  function imgUrl(u) {
    if (!u) return ''; if (u.indexOf('//') === 0) u = 'https:' + u;
    var m = u.match(/^https?:\/\/(yt3\.ggpht\.com|yt3\.googleusercontent\.com)(\/.*)$/); if (m) u = '/ggpht' + m[2];
    return u.replace(/=s\d+-/, '=s48-');
  }
  var subs = null, loading = false, expanded = false, AV = {};
  try { AV = JSON.parse(ls('ctAvatars') || '{}'); } catch (e) { AV = {}; }
  var avQueue = [], avBusy = 0;
  function loadAvatar(id) {
    var c = AV[id]; if (c && c.u && Date.now() - c.t < 7 * 864e5) return;
    if (avQueue.indexOf(id) < 0) avQueue.push(id); pump();
  }
  function pump() {
    var t = auth();
    while (avBusy < 3 && avQueue.length) {
      (function (id) {
        avBusy++;
        fetch('/api/v1/channels/' + id + '?fields=authorThumbnails', { credentials: 'same-origin' })
          .then(function (r) { return r.ok ? r.json() : null; })
          .then(function (j) {
            var th = (j && j.authorThumbnails) || [], best = null;
            th.forEach(function (x) { if (x.width >= 32 && (!best || x.width < best.width)) best = x; });
            if (!best && th.length) best = th[th.length - 1];
            if (!best) return; AV[id] = { u: imgUrl(best.url), t: Date.now() }; ls('ctAvatars', JSON.stringify(AV));
            document.querySelectorAll('.ct-subs img[data-id="' + id + '"]').forEach(function (im) { if (AV[id].u) im.src = AV[id].u; });
          })
          .catch(function () {})
          .then(function () { avBusy--; pump(); });
      })(avQueue.shift());
    }
  }
  function loadSubs() {
    if (loading) return;
    var t = auth(), key = 'ct:' + (t ? t.slice(-8) : '-');
    var c = null; try { c = JSON.parse(ls('ctSubsCache') || 'null'); } catch (e) {}
    if (c && c.k === key && Date.now() - c.t < 10 * 60e3) { subs = c.l; render(); return; }
    loading = true;
    function done(l) { subs = l; ls('ctSubsCache', JSON.stringify({ t: Date.now(), k: key, l: subs })); render(); }
    // список подписок — у сервиса ytsync (знает пользователя по паролю сайта; новые ролики — выше),
    // запасной путь — API Invidious с токеном Materialious
    fetch('/ctsubs/api/strip', { credentials: 'same-origin', cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw 0; return r.json(); })
      .then(function (l) { if (!Array.isArray(l)) throw 0; done(l.map(function (x) { return { a: x.author, id: x.id }; })); })
      .catch(function () {
        if (!t) return;
        return fetch('/api/v1/auth/subscriptions', { headers: hdr(t) })
          .then(function (r) { return r.ok ? r.json() : []; })
          .then(function (l) {
            done((l || []).map(function (x) { return { a: x.author, id: x.authorId }; })
              .sort(function (x, y) { return x.a.localeCompare(y.a, 'ru', { sensitivity: 'base' }); }));
          });
      })
      .catch(function () {}).then(function () { loading = false; });
  }
  var MORE = '<svg viewBox="0 0 24 24"><path d="M7.4 8.6 12 13.2l4.6-4.6L18 10l-6 6-6-6z"/></svg>';
  var LESS = '<svg viewBox="0 0 24 24"><path d="M7.4 15.4 12 10.8l4.6 4.6L18 14l-6-6-6 6z"/></svg>';
  var lastKey = '';
  function render() {
    var nav = document.getElementById('left-nav'); if (!nav) return;
    var box = nav.querySelector('.ct-subs');
    if (!subs || !subs.length) { if (box) box.remove(); lastKey = ''; return; }
    var cur = (location.pathname.match(/^\/channel\/([^\/?#]+)/) || [])[1] || '';
    var key = subs.length + '|' + expanded + '|' + cur;
    if (box && key === lastKey) return;
    lastKey = key;
    if (!box) { box = document.createElement('div'); box.className = 'ct-subs'; nav.insertBefore(box, nav.querySelector(':scope > .ct-explore')); }
    var N = 7, list = expanded ? subs : subs.slice(0, N);
    var h = '<h6>Подписки</h6>';
    list.forEach(function (s) {
      var u = AV[s.id] && AV[s.id].u;
      h += '<a href="/channel/' + encodeURIComponent(s.id) + '"' + (s.id === cur ? ' class="active"' : '') + ' title="' + esc(s.a) + '">' +
        '<img class="ct-av" data-id="' + esc(s.id) + '" alt="" loading="lazy"' + (u ? ' src="' + esc(u) + '"' : '') + '><span>' + esc(s.a) + '</span></a>';
    });
    if (subs.length > N) h += '<a class="ct-more" href="#">' + (expanded ? LESS + '<span>Свернуть</span>' : MORE + '<span>Показать ещё ' + (subs.length - N) + '</span>') + '</a>';
    box.innerHTML = h;
    var more = box.querySelector('.ct-more');
    if (more) more.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); expanded = !expanded; render(); });
    list.forEach(function (s) { loadAvatar(s.id); });
  }

  /* ---- «Навигатор»: разделы ---- */
  var SECS = [['shorts', 'smart_display', 'Shorts'], ['music', 'music_note', 'Музыка'], ['movies', 'movie', 'Фильмы и трейлеры'], ['live', 'sensors', 'Трансляции'],
              ['gaming', 'sports_esports', 'Видеоигры'], ['news', 'newspaper', 'Новости'], ['sport', 'emoji_events', 'Спорт'],
              ['podcasts', 'podcasts', 'Подкасты']];
  function curSection() { var m = decodeURIComponent(location.pathname).match(/^\/search\/ct:(\w+)/); return m ? m[1] : ''; }
  var lastExp = null;
  function renderExplore() {
    var nav = document.getElementById('left-nav'); if (!nav) return;
    var box = nav.querySelector(':scope > .ct-explore'), cur = curSection();
    if (box && lastExp === cur && nav.lastElementChild === box) return;
    if (!box) { box = document.createElement('div'); box.className = 'ct-explore'; }
    lastExp = cur;
    var h = '<h6>Навигатор</h6>';
    SECS.forEach(function (s) {
      h += '<a href="/search/ct:' + s[0] + '?type=video"' + (s[0] === cur ? ' class="ct-on"' : '') + '><i>' + s[1] + '</i><span>' + s[2] + '</span></a>';
    });
    box.innerHTML = h;
    nav.appendChild(box);
  }
  function sectionPage() {
    var cur = curSection(), main = document.getElementById('main-content');
    D.classList.toggle('ct-section', !!cur);
    D.classList.toggle('ct-sec-shorts', cur === 'shorts');
    document.querySelectorAll('#top-content input').forEach(function (i) { if (/^ct:/.test(i.value)) i.value = ''; });
    if (!cur || !main) return;
    var s = SECS.filter(function (x) { return x[0] === cur; })[0]; if (!s) return;
    var t = main.querySelector('.ct-sec-title');
    if (t && t.getAttribute('data-s') === cur) return;
    if (t) t.remove();
    var anchor = main.querySelector('nav.search-actions'); if (!anchor) return;
    t = document.createElement('div'); t.className = 'ct-sec-title'; t.setAttribute('data-s', cur);
    t.innerHTML = '<span class="ct-sec-ic"><i>' + s[1] + '</i></span><h4>' + s[2] + '</h4>';
    anchor.parentElement.insertBefore(t, anchor);
    document.title = s[2] + ' — CloudTube';
  }

  var lastPath = '';
  function tick() {
    ensureHead();
    if (location.pathname !== lastPath) {
      lastPath = location.pathname;
      D.classList.toggle('ct-watch', isWatch());
      closeDrawer();
      if (!subs) loadSubs();
    }
    render();
    renderExplore();
    sectionPage();
  }
  function start() {
    tick();
    setInterval(tick, 400);
    window.addEventListener('storage', function (e) { if (e.key === 'authToken') { subs = null; ls('ctSubsCache', ''); loadSubs(); } });
  }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();

/* ---- PWA: ссылка на манифест (если версия Materialious сама её не добавила) ---- ct-pwa-link */
(function () {
  function add() {
    if (document.querySelector('link[rel="manifest"]')) return;
    var l = document.createElement('link'); l.rel = 'manifest'; l.href = '/manifest.webmanifest'; document.head.appendChild(l);
  }
  setTimeout(add, 3000);
  var m = document.querySelector('meta[name="theme-color"]');
  if (!m) { m = document.createElement('meta'); m.name = 'theme-color'; document.head.appendChild(m); }
  m.content = '#0f0f0f';
})();

/* ---- мобильная версия: вкладки как в приложении YouTube, кнопка «Вы» с меню ---- */
(function () {
  var D = document.documentElement;
  var TABS = [['/', 'Главная'], ['/subscriptions', 'Подписки'], ['/search/ct:music?type=video', 'Музыка'], ['/search/ct:live?type=video', 'Сейчас в эфире'],
              ['/search/ct:news?type=video', 'Новости'], ['/search/ct:sport?type=video', 'Спорт'], ['/search/ct:gaming?type=video', 'Видеоигры'],
              ['/search/ct:podcasts?type=video', 'Подкасты'], ['/search/ct:movies?type=video', 'Фильмы']];
  var KEEP = ['search', 'notifications'];
  function user() { try { var a = JSON.parse(localStorage.getItem('authToken') || 'null'); return a && a.username ? String(a.username) : ''; } catch (e) { return ''; } }
  function icon(el) { var i = el.querySelector(':scope > i'); return i ? i.textContent.trim() : ''; }
  function btnBy(ic) {
    var t = document.getElementById('top-content'); if (!t) return null;
    return [].slice.call(t.querySelectorAll(':scope > button, :scope > a')).filter(function (b) { return icon(b) === ic; })[0] || null;
  }
  function path() { return decodeURIComponent(location.pathname); }
  function closeSheet() { D.classList.remove('ct-sheet-open'); }
  /* переход внутри приложения без перезагрузки: ссылка внутри корня SvelteKit */
  function spaGo(href) {
    var t = document.getElementById('top-content') || document.body, a = document.createElement('a');
    a.href = href; a.style.display = 'none'; t.appendChild(a); a.click(); setTimeout(function () { a.remove(); }, 0);
  }
  function openSheet() {
    var sh = document.querySelector('.ct-sheet'); if (!sh) return;
    var u = user(), prem = D.classList.contains('ct-premium'), admin = !!document.querySelector('#top-content a.ct-admin-top');
    var h = '<div class="ct-grip"></div><div class="ct-who"><span class="ct-me">' + (u ? u.charAt(0) : '<i>person</i>') + '</span><div><b>' +
      (u || 'Гость') + '</b><small>CloudTube</small></div></div>';
    h += '<button data-go="/history"><i>history</i>История</button><button data-go="/playlists"><i>video_library</i>Плейлисты</button>' +
         '<button data-go="/subscriptions"><i>subscriptions</i>Подписки</button>' +
         '<button data-href="/ctsubs/"><i>sync_alt</i>Импорт подписок с YouTube</button><hr>';
    h += '<button data-act="premium"><i>workspace_premium</i>Premium-режим<span class="ct-badge' + (prem ? ' on">ВКЛ' : '">ВЫКЛ') + '</span></button>';
    if (admin) h += '<button data-href="/ctadmin/"><i>group_add</i>Доступ для друзей</button>';
    h += '<button data-act="settings"><i>settings</i>Настройки</button>';
    if (btnBy('logout')) h += '<button data-act="logout"><i>logout</i>Выйти из аккаунта</button>';
    else if (btnBy('login')) h += '<button data-act="login"><i>login</i>Войти</button>';
    sh.innerHTML = h;
    D.classList.add('ct-sheet-open');
  }
  function act(a) {
    closeSheet();
    var b = a === 'premium' ? document.querySelector('.ct-premium-btn') : btnBy(a);
    if (b) setTimeout(function () { b.click(); }, 230);
  }
  function ensure() {
    var t = document.getElementById('top-content'); if (!t) return;
    [].forEach.call(t.querySelectorAll(':scope > button, :scope > a'), function (b) {
      if (b.classList.contains('ct-me')) return;
      var keep = KEEP.indexOf(icon(b)) >= 0;
      b.classList.toggle('ct-m-hide', !keep);
    });
    if (!t.querySelector(':scope > .ct-me')) {
      var m = document.createElement('button'); m.type = 'button'; m.className = 'ct-me'; m.title = 'Вы';
      m.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); openSheet(); });
      t.appendChild(m);
    }
    var me = t.querySelector(':scope > .ct-me'), u = user(), want = u ? u.charAt(0) : '<i>person</i>';
    if (me.innerHTML !== want) me.innerHTML = want;
    if (!t.querySelector(':scope > .ct-tabs')) {
      var tb = document.createElement('div'); tb.className = 'ct-tabs';
      tb.innerHTML = TABS.map(function (x) { return '<a href="' + x[0] + '">' + x[1] + '</a>'; }).join('');
      t.appendChild(tb);
    }
    if (!document.querySelector('body > .ct-sheet')) {
      var bg = document.createElement('div'); bg.className = 'ct-sheet-bg'; bg.addEventListener('click', closeSheet);
      var sh = document.createElement('div'); sh.className = 'ct-sheet';
      sh.addEventListener('click', function (e) {
        var b = e.target.closest('button'); if (!b) return;
        e.preventDefault();
        if (b.hasAttribute('data-act')) return act(b.getAttribute('data-act'));
        closeSheet();
        if (b.hasAttribute('data-href')) { location.href = b.getAttribute('data-href'); return; }
        if (b.hasAttribute('data-go')) spaGo(b.getAttribute('data-go'));
      });
      document.body.appendChild(bg); document.body.appendChild(sh);
    }
    var p = path(), onTabs = p === '/' || p === '/subscriptions' || /^\/search\/ct:/.test(p);
    D.classList.toggle('ct-tabs-on', onTabs);
    var tabs = t.querySelector(':scope > .ct-tabs');
    [].forEach.call(tabs.children, function (a) {
      var h = a.getAttribute('href').split('?')[0], on = h === p;
      if (a.classList.contains('on') !== on) {
        a.classList.toggle('on', on);
        if (on && tabs.scrollWidth > tabs.clientWidth) tabs.scrollLeft = Math.max(0, a.offsetLeft - 40);
      }
    });
  }
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeSheet(); });
  function start() { ensure(); setInterval(ensure, 400); }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();


/* ---- аватарки каналов в ленте: Materialious показывает их только для уже открытых каналов,
        остальные берём пачкой у нашего сервиса /ct-api/avatars ---- */
(function () {
  var C = {}, failed = {}, want = {}, busy = false;
  try { C = JSON.parse(localStorage.getItem('ctAv2') || '{}'); } catch (e) { C = {}; }
  function save() {
    try {
      var k = Object.keys(C);
      if (k.length > 1500) k.sort(function (a, b) { return C[a].t - C[b].t; }).slice(0, k.length - 1200).forEach(function (x) { delete C[x]; });
      localStorage.setItem('ctAv2', JSON.stringify(C));
    } catch (e) {}
  }
  function hiddenFallback(b) { return b.style.display === 'none' || b.hasAttribute('hidden'); }
  function apply(b, id, u) {
    var img = b.previousElementSibling;
    if (!(img && img.classList.contains('ct-avimg'))) {
      img = document.createElement('img'); img.className = 'circle small ct-avimg'; img.alt = '';
      img.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); b.click(); });
      img.addEventListener('error', function () { img.remove(); b.classList.remove('ct-av-hidden'); });
      b.parentElement.insertBefore(img, b);
    }
    if (img.getAttribute('data-id') !== id) { img.setAttribute('data-id', id); img.src = u; }
    b.classList.add('ct-av-hidden');
  }
  function scan() {
    var now = Date.now();
    document.querySelectorAll('#main-content button[data-melt-avatar-fallback]').forEach(function (b) {
      var prev = b.previousElementSibling, ours = prev && prev.classList.contains('ct-avimg');
      var box = b.closest('article') || b.parentElement;
      var a = box && box.querySelector('a[href*="/channel/UC"]');
      var m = a && a.getAttribute('href').match(/\/channel\/(UC[\w-]{22})/);
      if (!m) { if (ours) { prev.remove(); b.classList.remove('ct-av-hidden'); } return; }
      var id = m[1];
      if (hiddenFallback(b) && !b.classList.contains('ct-av-hidden')) { if (ours) prev.remove(); return; }   // родная аватарка есть
      if (ours && prev.getAttribute('data-id') !== id) { prev.remove(); b.classList.remove('ct-av-hidden'); ours = false; }
      var c = C[id];
      if (c && c.u) apply(b, id, c.u);
      else if (!failed[id] || now - failed[id] > 5 * 60e3) want[id] = 1;
    });
    pull();
  }
  function pull() {
    if (busy) return;
    var ids = Object.keys(want).slice(0, 40); if (!ids.length) return;
    ids.forEach(function (i) { delete want[i]; });
    busy = true;
    fetch('/ct-api/avatars?ids=' + ids.join(','), { credentials: 'same-origin' })
      .then(function (r) { return r.ok ? r.json() : {}; })
      .then(function (j) {
        var now = Date.now();
        ids.forEach(function (i) { if (j[i]) C[i] = { u: j[i], t: now }; else failed[i] = now; });
        save(); scan();
      })
      .catch(function () { var now = Date.now(); ids.forEach(function (i) { failed[i] = now; }); })
      .then(function () { busy = false; });
  }
  function start() { scan(); setInterval(scan, 1200); }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();

/* ---- Shorts в нижнем меню телефона ---- */
(function () {
  function ensure() {
    var nb = document.querySelector('nav.bottom'); if (!nb) return;
    var a = nb.querySelector(':scope > a.ct-shorts');
    if (!a) {
      a = document.createElement('a'); a.className = 'round ct-shorts'; a.href = '/search/ct:shorts?type=video';
      a.innerHTML = '<i>smart_display</i><span>Shorts</span>';
      var first = nb.querySelector(':scope > a');
      if (first && first.nextSibling) nb.insertBefore(a, first.nextSibling); else nb.appendChild(a);
    }
    var on = /^\/search\/ct:shorts/.test(decodeURIComponent(location.pathname));
    a.classList.toggle('active', on);
  }
  function start() { ensure(); setInterval(ensure, 500); }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();

/* ---- «Подписки»: плитки каналов над лентой, как в приложении CloudTube.
        «Все» — обычная лента; канал — его последние ролики там же. Данные — /ctsubs/api (сервис ytsync) ---- */
(function () {
  var D = document.documentElement, list = null, listAt = 0, loading = false, order = null;
  var sel = null, vids = [], page = 1, more = true, vLoading = false, lastKey = '';
  try { sel = sessionStorage.getItem('ctSubSel') || null; } catch (e) {}
  var AV = {}; try { AV = JSON.parse(localStorage.getItem('ctAv2') || '{}'); } catch (e) {}
  var avWant = {}, avBusy = false, avFailed = {};
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  function onPage() { return location.pathname.replace(/\/+$/, '') === '/subscriptions'; }
  function spaGo(href) {
    var t = document.getElementById('top-content') || document.body, a = document.createElement('a');
    a.href = href; a.style.display = 'none'; t.appendChild(a); a.click(); setTimeout(function () { a.remove(); }, 0);
  }
  function setSel(id) {
    sel = id; vids = []; page = 1; more = true; lastKey = '';
    try { id ? sessionStorage.setItem('ctSubSel', id) : sessionStorage.removeItem('ctSubSel'); } catch (e) {}
    if (id) loadVideos(); render();
    var s = document.querySelector('#main-content .ct-substrip');
    if (s) window.scrollTo({ top: Math.max(0, s.getBoundingClientRect().top + window.scrollY - 70), behavior: 'smooth' });
  }
  function ago(t) {
    var d = Date.now() / 1000 - t; if (!t || d < 0) return '';
    var u = [[31536000, 'год', 'года', 'лет'], [2592000, 'месяц', 'месяца', 'месяцев'], [604800, 'неделю', 'недели', 'недель'],
             [86400, 'день', 'дня', 'дней'], [3600, 'час', 'часа', 'часов'], [60, 'минуту', 'минуты', 'минут']];
    for (var i = 0; i < u.length; i++) {
      var n = Math.floor(d / u[i][0]); if (n < 1) continue;
      var m = n % 10, h = n % 100, w = m === 1 && h !== 11 ? u[i][1] : m >= 2 && m <= 4 && (h < 10 || h >= 20) ? u[i][2] : u[i][3];
      return n + ' ' + w + ' назад';
    }
    return 'только что';
  }
  function views(n) {
    if (!n) return '';
    function f(x) { return x.toFixed(1).replace(/\.0$/, '').replace('.', ','); }
    return (n >= 1e9 ? f(n / 1e9) + ' млрд' : n >= 1e6 ? f(n / 1e6) + ' млн' : n >= 1e3 ? Math.floor(n / 1e3) + ' тыс.' : String(n)) + ' просмотров';
  }
  function dur(s) {
    if (!s) return '';
    var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60;
    return (h ? h + ':' + (m < 10 ? '0' : '') : '') + m + ':' + (x < 10 ? '0' : '') + x;
  }
  function loadList(force) {
    if (loading || (!force && list && Date.now() - listAt < 120e3)) return;
    loading = true;
    fetch('/ctsubs/api/strip', { credentials: 'same-origin', cache: 'no-store' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (l) { if (Array.isArray(l)) { list = l; listAt = Date.now(); lastKey = ''; render(); } })
      .catch(function () {}).then(function () { loading = false; });
  }
  function loadVideos() {
    if (!sel || vLoading || !more) return;
    vLoading = true; var want = sel, p = page;
    fetch('/ctsubs/api/channel?id=' + encodeURIComponent(want) + '&page=' + p, { credentials: 'same-origin' })
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (l) {
        if (want !== sel) return;
        l = Array.isArray(l) ? l : [];
        vids = vids.concat(l); page = p + 1; more = l.length >= 30; lastKey = ''; render();
      })
      .catch(function () { more = false; }).then(function () { vLoading = false; lastKey = ''; render(); });
  }
  function pullAv() {
    if (avBusy) return;
    var ids = Object.keys(avWant).slice(0, 40); if (!ids.length) return;
    ids.forEach(function (i) { delete avWant[i]; }); avBusy = true;
    fetch('/ct-api/avatars?ids=' + ids.join(','), { credentials: 'same-origin' })
      .then(function (r) { return r.ok ? r.json() : {}; })
      .then(function (j) {
        var now = Date.now();
        ids.forEach(function (i) {
          if (!j[i]) { avFailed[i] = now; return; }
          AV[i] = { u: j[i], t: now };
          document.querySelectorAll('.ct-substrip img[data-id="' + i + '"]').forEach(function (im) { im.src = j[i]; im.classList.remove('ct-noav'); });
        });
        try { var C = JSON.parse(localStorage.getItem('ctAv2') || '{}'); ids.forEach(function (i) { if (AV[i]) C[i] = AV[i]; }); localStorage.setItem('ctAv2', JSON.stringify(C)); } catch (e) {}
      })
      .catch(function () {}).then(function () { avBusy = false; pullAv(); });
  }
  function avatar(c) {
    var a = AV[c.id];
    if (!a && !avFailed[c.id]) avWant[c.id] = 1;
    var letter = esc((c.author || '?').trim().charAt(0).toUpperCase());
    return '<span class="ct-sav"><b>' + letter + '</b>' + (a && a.u ? '<img data-id="' + esc(c.id) + '" src="' + esc(a.u) + '" alt="" loading="lazy">' :
           '<img class="ct-noav" data-id="' + esc(c.id) + '" alt="">') + '</span>';
  }
  function ordered() {
    if (!list) return [];
    if (!order) order = list.map(function (c) { return c.id; });   // порядок не прыгает, пока страница открыта
    var pos = {}; order.forEach(function (id, i) { pos[id] = i; });
    return list.slice().sort(function (a, b) { return (pos[a.id] == null ? 1e9 : pos[a.id]) - (pos[b.id] == null ? 1e9 : pos[b.id]); });
  }
  function cards() {
    var h = '';
    vids.forEach(function (v) {
      var meta = [views(v.viewCount), v.upcoming ? 'Премьера' : v.liveNow ? 'В эфире' : ago(v.published)].filter(Boolean).join(' • ');
      h += '<a class="ct-scard" href="/watch?v=' + esc(v.videoId) + '" data-v="' + esc(v.videoId) + '">' +
        '<span class="ct-sthumb"><img src="/vi/' + esc(v.videoId) + '/mqdefault.jpg" alt="" loading="lazy">' +
        (v.liveNow ? '<em class="live">В ЭФИРЕ</em>' : v.lengthSeconds ? '<em>' + dur(v.lengthSeconds) + '</em>' : '') + '</span>' +
        '<span class="ct-stitle">' + esc(v.title) + '</span><span class="ct-smeta">' + esc(meta) + '</span></a>';
    });
    return h;
  }
  function render() {
    var main = document.getElementById('main-content');
    var strip = main && main.querySelector(':scope > .ct-substrip'), box = main && main.querySelector(':scope > .ct-subch');
    if (!onPage() || !main) {
      if (strip) strip.remove(); if (box) box.remove();
      document.querySelectorAll('[data-ct-hid]').forEach(function (e) { e.removeAttribute('data-ct-hid'); });
      D.classList.remove('ct-subsel'); order = null; return;
    }
    var anchor = main.querySelector(':scope > nav.right-align') || main.querySelector(':scope > .space');
    if (!anchor || !list || !list.length) return;
    var chans = ordered();
    if (sel && !chans.some(function (c) { return c.id === sel; })) { sel = null; try { sessionStorage.removeItem('ctSubSel'); } catch (e) {} }
    var key = chans.map(function (c) { return c.id + c.fresh; }).join() + '|' + sel + '|' + vids.length + '|' + vLoading + '|' + more;
    if (!strip) {
      strip = document.createElement('div'); strip.className = 'ct-substrip'; strip.setAttribute('role', 'tablist');
      strip.addEventListener('click', function (e) {
        var t = e.target.closest('[data-ch]'); if (!t) return; e.preventDefault();
        var id = t.getAttribute('data-ch'); setSel(!id || id === sel ? null : id);
      });
      lastKey = '';
    }
    if (strip.previousElementSibling !== anchor) anchor.after(strip);
    if (key !== lastKey) {
      lastKey = key;
      var sl = strip.scrollLeft;
      var h = '<button class="ct-stile' + (sel ? '' : ' on') + '" data-ch=""><span class="ct-sav ct-all"><i>grid_view</i></span><span class="ct-sname">Все</span></button>';
      chans.forEach(function (c) {
        h += '<button class="ct-stile' + (c.id === sel ? ' on' : '') + '" data-ch="' + esc(c.id) + '" title="' + esc(c.author) + '">' + avatar(c) +
          (c.fresh ? '<span class="ct-fresh">' + (c.fresh > 9 ? '9+' : c.fresh) + '</span>' : '') + '<span class="ct-sname">' + esc(c.author) + '</span></button>';
      });
      strip.innerHTML = h; strip.scrollLeft = sl;
      strip.querySelectorAll('img.ct-noav').forEach(function (im) { im.addEventListener('error', function () { im.remove(); }); });
      pullAv();
      if (sel) {
        var c = chans.filter(function (x) { return x.id === sel; })[0];
        if (!box) {
          box = document.createElement('div'); box.className = 'ct-subch';
          box.addEventListener('click', function (e) {
            var a = e.target.closest('a[href]'); if (a) { e.preventDefault(); spaGo(a.getAttribute('href')); return; }
            if (e.target.closest('.ct-smore')) loadVideos();
          });
        }
        box.innerHTML = '<div class="ct-shead"><div><b>' + esc(c.author) + '</b><small>' + (c.fresh ? c.fresh + ' новых · последние ролики' : 'Последние ролики') +
          '</small></div><a class="ct-sgo" href="/channel/' + esc(c.id) + '">На канал<i>chevron_right</i></a></div>' +
          '<div class="ct-sgrid">' + cards() + '</div>' +
          (vLoading ? '<div class="ct-sload"><progress class="circle small indeterminate"></progress></div>' :
           !vids.length ? '<p class="ct-sempty">Роликов пока нет — Invidious ещё не загрузил этот канал.</p>' :
           more ? '<button class="ct-smore">Показать ещё</button>' : '');
      } else if (box) { box.remove(); box = null; }
    }
    if (box && box.previousElementSibling !== strip) strip.after(box);
    // родная лента Materialious скрыта, пока выбран канал
    var hide = !!sel, n = (box || strip).nextElementSibling;
    D.classList.toggle('ct-subsel', hide);
    while (n) { if (hide) n.setAttribute('data-ct-hid', ''); else n.removeAttribute('data-ct-hid'); n = n.nextElementSibling; }
  }
  var lastPath = '';
  function tick() {
    if (location.pathname !== lastPath) { lastPath = location.pathname; if (onPage()) loadList(true); }
    if (onPage()) loadList(false);
    render();
  }
  window.addEventListener('scroll', function () {
    if (!sel || !more || vLoading || !onPage()) return;
    if (window.innerHeight + window.scrollY > document.body.scrollHeight - 600) loadVideos();
  }, { passive: true });
  function start() { tick(); setInterval(tick, 500); }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();

/* ---- перевод интерфейса Materialious: строки, которых нет в его русском переводе (ошибки плеера и др.) ---- */
(function () {
  var T = {"File saved to Android Downloads folder": "Файл сохранён в папку «Загрузки»", "Login with password": "Войти с паролем", "Login with Quick connect": "Войти по быстрому коду", "Caption styles": "Стиль субтитров", "Very weak": "Очень слабый", "Weak": "Слабый", "Link Invidious account": "Привязать аккаунт Invidious", "Unlink Invidious account": "Отвязать аккаунт Invidious", "Materialious backend": "Сервер Materialious", "Invidious Instance": "Сервер Invidious", "Materialious Instance": "Сервер Materialious", "Remove Materialious instance": "Удалить сервер Materialious", "Login with Materialious account": "Войти через аккаунт Materialious", "Logout of Materialious account": "Выйти из аккаунта Materialious", "Registration currently disabled, contact instance owner.": "Регистрация закрыта — обратитесь к владельцу сервера.", "Your Invidious session is no longer valid. Please log in again.": "Сессия Invidious истекла. Войдите заново.", "Could not check your Invidious session or load notifications. Try again.": "Не удалось проверить сессию Invidious или загрузить уведомления. Попробуйте ещё раз.", "I want to use local video fallback": "Использовать локальный запасной источник видео", "Setup Required": "Требуется настройка", "Invidious is an Self-hostable YouTube interface.": "Invidious — интерфейс YouTube, который можно развернуть на своём сервере.", "Auto scroll": "Автопрокрутка", "Loading transcript": "Загружаю расшифровку", "Unable to load the transcript. Select a language to try again.": "Не удалось загрузить расшифровку. Выберите язык и попробуйте снова.", "Start a watch party": "Начать совместный просмотр", "Watch party": "Совместный просмотр", "Watch videos together in sync.": "Смотрите видео вместе и синхронно.", "Up next": "Далее", "Your queue is empty.": "Очередь пуста.", "Add to queue": "Добавить в очередь", "Remove from queue": "Убрать из очереди", "Move up in queue": "Выше в очереди", "Move down in queue": "Ниже в очереди", "Playlist storage": "Где хранить плейлист", "Private and encrypted with your Materialious account.": "Личный, зашифрован вашим аккаунтом Materialious.", "Video paused due to wifi network change": "Видео на паузе: сменилась сеть Wi-Fi", "Download type": "Что скачать", "Download failed": "Не удалось скачать", "Default subtitle language": "Язык субтитров по умолчанию", "Playback failed": "Не удалось воспроизвести", "The YouTube SABR stream could not be played. The playback session or video source may have expired.": "Поток YouTube (SABR) не воспроизводится: сессия или источник видео могли устареть.", "The video source could not be loaded from Invidious or the companion server.": "Не удалось получить видео от Invidious или сервера-компаньона: YouTube не отдал поток.", "The local YouTube.js video source could not be loaded.": "Не удалось загрузить видео через локальный YouTube.js.", "The video could not be played because of an unexpected error.": "Видео не воспроизводится из-за непредвиденной ошибки.", "Retry": "Повторить", "Retrying…": "Повторяю…", "Retrying...": "Повторяю…", "Hide controls": "Скрыть панель", "Playback controls": "Управление воспроизведением", "Video information": "О видео", "Playback speed": "Скорость воспроизведения", "Font family": "Шрифт", "Loading captions": "Загружаю субтитры", "Subtitle timing": "Сдвиг субтитров", "Quick connect": "Быстрый вход", "No password needed. Enter the 8-character code shown on your signed-in device.": "Без пароля: введите 8-значный код с устройства, где вы уже вошли.", "Find the code in Settings → Account → Quick connect on your signed-in device.": "Код — в «Настройки → Аккаунт → Быстрый вход» на устройстве, где вы вошли.", "Use quick connect": "Войти по коду", "Connecting…": "Подключаюсь…", "Waiting for the other device to send sign-in details…": "Жду, пока другое устройство отправит данные для входа…", "Signed in!": "Вход выполнен!", "That code isn't valid. Check it and try again.": "Код неверный. Проверьте и попробуйте снова.", "That code has already been used.": "Этот код уже использован.", "That code has expired. Ask for a new one.": "Код устарел. Получите новый.", "Press OK, then enter the code": "Нажмите OK и введите код", "Sign in on another device without a password.": "Вход на другом устройстве без пароля.", "Show code": "Показать код", "Couldn't create a code. Try again.": "Не удалось создать код. Попробуйте снова.", "Waiting for a device to enter this code…": "Жду, пока устройство введёт этот код…", "A device connected. Send your sign-in details?": "Устройство подключилось. Отправить ему данные для входа?", "Send sign-in details": "Отправить данные для входа", "Couldn't send sign-in details. Try again.": "Не удалось отправить данные. Попробуйте снова.", "Sign-in details sent.": "Данные для входа отправлены.", "Backend engine": "Движок", "Keybinds": "Горячие клавиши", "Play / Pause": "Пуск / пауза", "Toggle subtitles": "Субтитры вкл/выкл", "Toggle fullscreen": "Во весь экран", "Increase volume": "Громче", "Decrease volume": "Тише", "Decrease playback speed": "Медленнее", "Increase playback speed": "Быстрее", "Frame step backward": "Кадр назад", "Frame step forward": "Кадр вперёд", "Seek backward": "Перемотать назад", "Seek forward": "Перемотать вперёд", "Exit fullscreen / Close player": "Выйти из полноэкранного / закрыть плеер", "Tab 1": "Вкладка 1", "Tab 2": "Вкладка 2", "Tab 3": "Вкладка 3", "Tab 4": "Вкладка 4", "Reset to defaults": "Сбросить по умолчанию", "Are you sure you want to delete this user?": "Удалить этого пользователя?", "User deleted": "Пользователь удалён", "Don't sync settings on this device": "Не синхронизировать настройки на этом устройстве", "Keep this device's settings local instead of updating them from or sending them to your account.": "Хранить настройки только на этом устройстве, не обмениваясь с аккаунтом.", "Export settings to account": "Сохранить настройки в аккаунт", "Import settings from account": "Загрузить настройки из аккаунта", "Settings exported to account": "Настройки сохранены в аккаунт", "Settings imported from account": "Настройки загружены из аккаунта", "Delete account": "Удалить аккаунт", "Enter your current password to permanently delete your account. This action cannot be undone.": "Введите текущий пароль, чтобы удалить аккаунт навсегда. Это нельзя отменить.", "Could not delete your account. Check your current password and connection, then try again.": "Не удалось удалить аккаунт. Проверьте пароль и соединение и попробуйте снова.", "Reset password": "Сбросить пароль", "Current password": "Текущий пароль", "New password": "Новый пароль", "Confirm password": "Повторите пароль", "Passwords do not match": "Пароли не совпадают", "Password reset failed. Check your current password.": "Не удалось сменить пароль. Проверьте текущий пароль.", "Password reset successfully": "Пароль изменён", "Change password": "Сменить пароль", "Save watch history": "Сохранять историю просмотра", "Use original translation": "Оригинальные названия", "On screen navigation controls": "Кнопки навигации на экране", "Advanced theming": "Расширенная настройка темы", "Save as preset": "Сохранить как набор", "Export theme": "Экспорт темы", "Import theme": "Импорт темы", "Theme name": "Название темы", "Theme imported": "Тема загружена", "Failed to import theme": "Не удалось загрузить тему", "Theme exported": "Тема сохранена", "Theme saved": "Тема сохранена", "Delete preset": "Удалить набор", "Border radius": "Скругление углов", "Hide shorts": "Скрывать Shorts", "Advanced settings! For experienced users only. Do not change unless you know what you’re doing.": "Расширенные настройки — только для опытных. Не меняйте, если не уверены.", "Max feed items": "Максимум роликов в ленте", "Re-fetch channel hour cooldown": "Обновлять канал не чаще, ч", "Max amount of channels to parse before feed return": "Сколько каналов разобрать до показа ленты", "Automatic export/import": "Автоэкспорт и импорт", "Export to Invidious from Materialious": "Экспорт из Materialious в Invidious", "Import from Invidious to Materialious": "Импорт из Invidious в Materialious", "Importing to Materialious began": "Импорт в Materialious начат", "Importing to Materialious finished": "Импорт в Materialious завершён", "Exporting to Invidious began": "Экспорт в Invidious начат", "Exporting to Invidious finished": "Экспорт в Invidious завершён", "Fit screen by default": "По размеру экрана", "Automatically fullscreen videos": "Сразу во весь экран", "Rotate fullscreen video when tilting device": "Поворачивать видео при наклоне устройства", "Pause on network change": "Пауза при смене сети", "Automatically enter PiP on app exit": "«Картинка в картинке» при выходе из приложения", "Export to JSON": "Экспорт в JSON", "Non-musical segment": "Немузыкальная часть", "Auto skip": "Пропускать сразу", "Manual skip": "Пропускать по кнопке", "Timeline only": "Только на шкале", "Content Filters": "Фильтры контента", "Import Filters from URL": "Загрузить фильтры по ссылке", "Automatically update filter from URL": "Обновлять фильтры по ссылке автоматически", "Content type": "Тип контента", "Select your option": "Выберите вариант", "Add conditional": "Добавить условие", "Add filter": "Добавить фильтр", "Export/Import": "Экспорт и импорт", "Import subscriptions": "Импорт подписок", "How to export YouTube subscriptions": "Как выгрузить подписки из YouTube", "Importing subscriptions (this will take a moment)": "Импортирую подписки (это займёт немного времени)", "Subscriptions successfully imported": "Подписки импортированы", "Export subscriptions": "Экспорт подписок", "Export to clipboard": "В буфер обмена", "Export to file": "В файл", "Import from file": "Из файла", "Export to share URL": "Ссылкой", "Failed to subscribe": "Не удалось подписаться", "Failed to unsubscribe": "Не удалось отписаться", "Browser companion required": "Нужно расширение-компаньон", "Copy URL": "Скопировать адрес", "Instance URL": "Адрес сервера", "Login with token": "Войти по токену", "Recommended. Sign in on your Invidious instance and authorize Materialious.": "Рекомендуется: войдите на своём сервере Invidious и разрешите доступ Materialious.", "Login failed. Check your Invidious username and password.": "Не удалось войти. Проверьте логин и пароль Invidious.", "Unable to complete login. Check your connection and try again.": "Не удалось войти. Проверьте соединение и попробуйте снова.", "Two-factor authentication": "Двухфакторная защита", "Enable 2FA": "Включить 2FA", "Disable 2FA": "Выключить 2FA", "Authentication code": "Код подтверждения", "Enter the six-digit code from your authenticator app.": "Введите шестизначный код из приложения-аутентификатора.", "Verify and enable": "Проверить и включить", "Cancel setup": "Отменить настройку", "Copy secret": "Скопировать ключ", "Import playlists": "Импорт плейлистов", "Importing playlists…": "Импортирую плейлисты…", "Playlists imported.": "Плейлисты импортированы.", "Export playlists": "Экспорт плейлистов", "Export YouTube CSV": "Экспорт в CSV YouTube", "Exporting playlist…": "Экспортирую плейлист…", "Playlist exported.": "Плейлист экспортирован.", "Bulk actions": "Выбрать несколько", "Manage subscriptions": "Управление подписками"};
  var P = [["^Ends at (.+)$", "Закончится в $1"], ["^Copy (.+) link$", "Копировать ссылку: $1"], ["^Total users: (\\d+)$", "Всего пользователей: $1"], ["^Expires in (\\d+) seconds$", "Действует ещё $1 с"], ["^Click (\\d+) more time\\(s\\) to delete$", "Нажмите ещё $1 раз(а), чтобы удалить"], ["^(\\d[\\d:]*) of (\\d[\\d:]*)$", "$1 из $2"]].map(function (p) { return [new RegExp(p[0]), p[1]]; });
  var SKIP = 'a.video-title, .video-title, h5, h6, .description, .comment-info, input, textarea, script, style, .ct-substrip, .ct-subch';
  function skip(el) { return el.closest(SKIP) && !el.closest('.player-error'); }
  function tr(s) {
    var k = s.trim(); if (!k || k.length > 200) return null;
    if (T.hasOwnProperty(k)) return s.replace(k, T[k]);
    for (var i = 0; i < P.length; i++) if (P[i][0].test(k)) return s.replace(k, k.replace(P[i][0], P[i][1]));
    return null;
  }
  function fixEl(el) {
    ['aria-label', 'title', 'placeholder'].forEach(function (a) {
      var v = el.getAttribute && el.getAttribute(a); if (!v) return;
      var t = tr(v); if (t && t !== v) el.setAttribute(a, t);
    });
  }
  function walk(root) {
    if (!root) return;
    if (root.nodeType === 3) { var p = root.parentElement; if (p && !skip(p)) { var t = tr(root.nodeValue); if (t && t !== root.nodeValue) root.nodeValue = t; } return; }
    if (root.nodeType !== 1 || skip(root)) return;
    fixEl(root);
    root.querySelectorAll('[aria-label],[title],[placeholder]').forEach(fixEl);
    var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT), n;
    while ((n = w.nextNode())) {
      var pe = n.parentElement; if (!pe || skip(pe)) continue;
      var t2 = tr(n.nodeValue); if (t2 && t2 !== n.nodeValue) n.nodeValue = t2;
    }
  }
  var q = [], sch = false;
  function flush() { sch = false; var a = q; q = []; for (var i = 0; i < a.length; i++) walk(a[i]); }
  function start() {
    walk(document.body);
    new MutationObserver(function (ms) {
      for (var i = 0; i < ms.length; i++) {
        var m = ms[i];
        if (m.type === 'characterData') q.push(m.target);
        else if (m.type === 'attributes') q.push(m.target);
        else for (var j = 0; j < m.addedNodes.length; j++) q.push(m.addedNodes[j]);
      }
      if (!sch && q.length) { sch = true; requestAnimationFrame(flush); }
    }).observe(document.body, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ['aria-label', 'title', 'placeholder'] });
  }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();
