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
    var t = auth(); if (!t || loading) return;
    var c = null; try { c = JSON.parse(ls('ctSubsCache') || 'null'); } catch (e) {}
    if (c && c.k === t.slice(-8) && Date.now() - c.t < 10 * 60e3) { subs = c.l; render(); return; }
    loading = true;
    fetch('/api/v1/auth/subscriptions', { headers: hdr(t) })
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (l) {
        subs = (l || []).map(function (x) { return { a: x.author, id: x.authorId }; })
          .sort(function (x, y) { return x.a.localeCompare(y.a, 'ru', { sensitivity: 'base' }); });
        ls('ctSubsCache', JSON.stringify({ t: Date.now(), k: t.slice(-8), l: subs })); render();
      })
      .catch(function () {}).then(function () { loading = false; });
  }
  var MORE = '<svg viewBox="0 0 24 24"><path d="M7.4 8.6 12 13.2l4.6-4.6L18 10l-6 6-6-6z"/></svg>';
  var LESS = '<svg viewBox="0 0 24 24"><path d="M7.4 15.4 12 10.8l4.6 4.6L18 14l-6-6-6 6z"/></svg>';
  var lastKey = '';
  function render() {
    var nav = document.getElementById('left-nav'); if (!nav) return;
    var box = nav.querySelector('.ct-subs');
    if (!subs || !subs.length || !auth()) { if (box) box.remove(); lastKey = ''; return; }
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
         '<button data-go="/subscriptions"><i>subscriptions</i>Подписки</button><hr>';
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
