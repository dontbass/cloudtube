import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../cloudtube/theme.dart';
import '../router.dart';
import 'package:auto_route/auto_route.dart';
import 'store.dart';

final _log = Logger('IptvLink');

/// Добавление плейлиста на ТВ: QR со ссылкой на страничку в домашней сети (как вход на свой
/// сервер) — с телефона вводят ссылку или выбирают файл M3U; либо ввод ссылки с пульта.
class IptvAddScreen extends StatefulWidget {
  const IptvAddScreen({super.key});

  @override
  State<IptvAddScreen> createState() => _IptvAddScreenState();
}

class _IptvAddScreenState extends State<IptvAddScreen> {
  HttpServer? _http;
  String? _link;
  String _status = 'Запускаю…';
  bool _ok = false;
  bool _busy = false;
  final _manual = TextEditingController();
  late final String _token = () {
    const abc = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(10, (_) => abc[r.nextInt(abc.length)]).join();
  }();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _http?.close(force: true);
    _manual.dispose();
    super.dispose();
  }

  Future<String?> _lanIp() async {
    final list = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    String? fallback;
    for (final i in list) {
      for (final a in i.addresses) {
        final ip = a.address;
        if (ip.startsWith('192.168.') || ip.startsWith('10.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
          return ip;
        }
        fallback ??= ip;
      }
    }
    return fallback;
  }

  Future<void> _start() async {
    try {
      final ip = await _lanIp();
      if (ip == null) {
        setState(() => _status = 'Телевизор не подключён к сети — проверьте Wi-Fi или кабель');
        return;
      }
      HttpServer srv;
      try {
        srv = await HttpServer.bind(InternetAddress.anyIPv4, 8687);
      } catch (_) {
        srv = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
      _http = srv;
      srv.listen(_handle, onError: (e) => _log.warning('http: $e'));
      if (!mounted) return;
      setState(() {
        _link = 'http://$ip:${srv.port}/$_token';
        _status = 'Ждём плейлист с телефона…';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Не удалось запустить: $e');
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.uri.path != '/$_token') {
        res.statusCode = 404;
      } else if (req.method == 'GET') {
        res.headers.contentType = ContentType.html;
        res.write(_page);
      } else if (req.method == 'POST') {
        final body = await utf8.decoder.bind(req).join();
        final f = (jsonDecode(body) as Map).cast<String, dynamic>();
        final (ok, msg) = _busy ? (false, 'Телевизор уже добавляет плейлист, подождите') : await _apply(f);
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'ok': ok, 'msg': msg}));
      } else {
        res.statusCode = 405;
      }
    } catch (e) {
      res.statusCode = 500;
      res.write('$e');
    } finally {
      await res.close();
    }
  }

  Future<(bool, String)> _apply(Map<String, dynamic> f) async {
    _busy = true;
    if (mounted) setState(() => _status = 'Получен плейлист, загружаю…');
    try {
      final name = '${f['name'] ?? ''}';
      final epg = '${f['epg'] ?? ''}';
      final text = '${f['text'] ?? ''}';
      final p = text.trim().isNotEmpty
          ? await IptvStore.I.addText(text, name: name, epgUrl: epg)
          : await IptvStore.I.addUrl('${f['url'] ?? ''}', name: name, userAgent: '${f['ua'] ?? ''}', epgUrl: epg);
      final n = (await IptvStore.I.channels(p)).channels.length;
      final done = 'Готово: «${p.name}», каналов: $n';
      if (mounted) {
        setState(() {
          _ok = true;
          _status = done;
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.of(context).pop(true);
        });
      }
      return (true, done);
    } catch (e) {
      final m = 'Не получилось: $e';
      if (mounted) setState(() => _status = m);
      return (false, m);
    } finally {
      _busy = false;
    }
  }

  Future<void> _addManual(String url) async {
    if (url.trim().isEmpty || _busy) return;
    _busy = true;
    setState(() => _status = 'Загружаю плейлист…');
    try {
      final p = await IptvStore.I.addUrl(url);
      final n = (await IptvStore.I.channels(p)).channels.length;
      if (!mounted) return;
      setState(() {
        _ok = true;
        _status = 'Готово: «${p.name}», каналов: $n';
      });
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) Navigator.of(context).pop(true);
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Не получилось: $e');
    } finally {
      _busy = false;
    }
  }

  static const _page = '''<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>CloudTube — плейлист IPTV</title>
<style>
:root{color-scheme:light dark}
body{font-family:system-ui,-apple-system,Roboto,sans-serif;margin:0;background:#0f0f0f;color:#f1f1f1}
main{max-width:460px;margin:0 auto;padding:24px 18px 40px}
h1{font-size:22px;margin:4px 0 2px}h1 b{color:#E85D4A}
p.sub{color:#aaa;margin:0 0 18px;font-size:14px}
fieldset{border:1px solid #303030;border-radius:14px;padding:12px 14px 6px;margin:0 0 14px}
legend{padding:0 6px;color:#aaa;font-size:13px}
label{display:block;font-size:13px;color:#aaa;margin:8px 0 4px}
input{width:100%;box-sizing:border-box;font-size:16px;padding:12px;border-radius:10px;border:1px solid #3f3f3f;background:#181818;color:#f1f1f1}
input[type=file]{padding:10px}
input:focus{outline:2px solid #3EA6FF;border-color:transparent}
button{width:100%;font-size:17px;font-weight:600;padding:14px;border:0;border-radius:24px;background:#f1f1f1;color:#0f0f0f;margin-top:6px}
button:disabled{opacity:.5}
#msg{margin-top:16px;padding:12px;border-radius:10px;display:none;font-size:15px}
.ok{background:#12351f;color:#9ff0b8}.err{background:#3d1214;color:#ffb4b4}
small{display:block;color:#717171;margin-top:18px;font-size:12px;line-height:1.4}
</style></head><body><main>
<h1>CLOUD<b>TUBE</b> · IPTV</h1>
<p class="sub">Плейлист уйдёт прямо на телевизор в вашей домашней сети.</p>
<form id="f">
<fieldset><legend>Плейлист — ссылка или файл</legend>
<label for="url">Ссылка на плейлист (M3U / M3U8)</label>
<input id="url" name="url" type="url" inputmode="url" autocomplete="off" placeholder="http://провайдер/playlist.m3u8">
<label for="file">…или файл с телефона</label>
<input id="file" type="file" accept=".m3u,.m3u8,audio/x-mpegurl,application/x-mpegurl,text/plain">
</fieldset>
<fieldset><legend>Необязательно</legend>
<label for="name">Название</label><input id="name" name="name" autocomplete="off" placeholder="Например: Домашний IPTV">
<label for="epg">Ссылка на телепрограмму (XMLTV)</label><input id="epg" name="epg" type="url" inputmode="url" autocomplete="off" placeholder="если провайдер даёт свою">
<label for="ua">User-Agent (если провайдер требует)</label><input id="ua" name="ua" autocomplete="off">
</fieldset>
<button id="b">Отправить на телевизор</button>
</form>
<div id="msg"></div>
<small>Связь идёт по вашей локальной сети. Ссылка одноразовая и работает, пока на ТВ открыт экран добавления плейлиста.</small>
</main><script>
const f=document.getElementById('f'),b=document.getElementById('b'),m=document.getElementById('msg');
f.addEventListener('submit',async e=>{e.preventDefault();
const d={url:f.url.value.trim(),name:f.name.value,epg:f.epg.value.trim(),ua:f.ua.value.trim(),text:''};
const file=document.getElementById('file').files[0];
if(file){d.text=await file.text();if(!d.name)d.name=file.name.replace(/\\.m3u8?\$/i,'');}
if(!d.url&&!d.text){m.className='err';m.textContent='Укажите ссылку или выберите файл';m.style.display='block';return;}
b.disabled=true;b.textContent='Отправляю…';m.style.display='none';
try{const r=await fetch(location.pathname,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d)});
const j=await r.json();m.className=j.ok?'ok':'err';m.textContent=j.msg;}catch(err){m.className='err';m.textContent='Нет связи с телевизором: '+err;}
m.style.display='block';b.disabled=false;b.textContent='Отправить на телевизор';});
</script></body></html>''';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 27),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: _link == null
                  ? const SizedBox(width: 240, height: 240, child: Center(child: CircularProgressIndicator()))
                  : QrImageView(data: _link!, size: 240, backgroundColor: Colors.white),
            ),
            const SizedBox(width: 44),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Добавить плейлист IPTV', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                Text('1. Подключите телефон к той же сети, что и телевизор.', style: text.titleMedium),
                Text('2. Наведите камеру телефона на QR-код.', style: text.titleMedium),
                Text('3. Вставьте ссылку на плейлист или выберите файл и нажмите «Отправить».', style: text.titleMedium),
                if (_link != null) ...[
                  const SizedBox(height: 10),
                  Text('Или откройте на телефоне: $_link', style: text.titleSmall?.copyWith(color: colors.onSurfaceVariant)),
                ],
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _ok ? Colors.green.withValues(alpha: 0.15) : colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_ok ? Icons.check_circle : Icons.wifi_tethering, color: _ok ? Colors.green : ctAccent(colors)),
                    const SizedBox(width: 12),
                    Flexible(child: Text(_status, style: text.titleMedium)),
                  ]),
                ),
                const SizedBox(height: 20),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  FilledButton.tonalIcon(
                    autofocus: true,
                    icon: const Icon(Icons.keyboard),
                    label: const Text('Ввести ссылку с пульта'),
                    onPressed: () => AutoRouter.of(context).push(TvTextFieldRoute(
                        controller: _manual,
                        autocorrect: false,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (v) => _addManual(v))),
                  ),
                  OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Назад')),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
