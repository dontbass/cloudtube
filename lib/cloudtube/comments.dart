import 'server_caps.dart';
import 'direct.dart';
import 'yt_account.dart';
import 'yt_comments.dart';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:clipious/globals.dart';
import 'package:clipious/settings/models/db/server.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

final _log = Logger('CtComments');

/// Комментарий в упрощённом виде — читаем JSON сами, без строгих моделей Clipious
/// (у Shorts Invidious часто отдаёт неполный ответ, и строгий разбор падает).
class CtComment {
  final String author;
  final String avatar;
  final String text;
  final String published;
  final int likes;
  final int replies;
  final bool owner;
  final bool heart;
  final bool edited;
  final String? repliesContinuation;

  CtComment(this.author, this.avatar, this.text, this.published, this.likes, this.replies,
      this.owner, this.heart, this.edited, [this.repliesContinuation]);

  static CtComment? fromJson(dynamic j) {
    if (j is! Map) return null;
    String avatar = '';
    final th = j['authorThumbnails'];
    // новые версии Invidious присылают одну строку authorThumbnail вместо списка
    if (j['authorThumbnail'] is String) avatar = j['authorThumbnail'] as String;
    if (th is List && th.isNotEmpty) {
      Map? best;
      for (final t in th) {
        if (t is! Map) continue;
        final w = (t['width'] as num?)?.toInt() ?? 0;
        if (best == null || (w >= 48 && w < ((best['width'] as num?)?.toInt() ?? 9999))) best = t;
      }
      avatar = (best?['url'] ?? '') as String;
    }
    final rep = j['replies'];
    return CtComment(
      (j['author'] ?? '') as String,
      avatar,
      (j['content'] ?? j['contentHtml'] ?? '') as String,
      (j['publishedText'] ?? '') as String,
      (j['likeCount'] as num?)?.toInt() ?? 0,
      rep is Map ? ((rep['replyCount'] as num?)?.toInt() ?? 0) : 0,
      j['authorIsChannelOwner'] == true,
      j['creatorHeart'] != null,
      j['isEdited'] == true,
      rep is Map ? rep['continuation'] as String? : null,
    );
  }
}

class CtCommentsPage {
  final int? count;
  final List<CtComment> items;
  final String? continuation;

  CtCommentsPage(this.count, this.items, this.continuation);
}

String ctShortNumber(int n) {
  String f(double v) {
    final s = v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return s.replaceAll(RegExp(r'[.,]0$'), '').replaceAll('.', ',');
  }

  if (n >= 1000000) return '${f(n / 1000000)} млн';
  if (n >= 1000) return '${f(n / 1000)} тыс.';
  return '$n';
}

class CtComments {
  static final Map<String, CtCommentsPage> _cache = {};

  static Future<Map<String, dynamic>?> _get(String path, Map<String, String> query) async {
    final req = await service.buildRequest(path, query: query);
    final r = await service.httpClient.get(req.uri, headers: req.headers);
    if (r.statusCode != 200) {
      _log.info('$path -> ${r.statusCode}');
      return null;
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    return j is Map<String, dynamic> ? j : null;
  }

  static CtCommentsPage? _parse(Map<String, dynamic>? j) {
    if (j == null || j['comments'] is! List) return null;
    final items = (j['comments'] as List).map(CtComment.fromJson).whereType<CtComment>().toList();
    return CtCommentsPage((j['commentCount'] as num?)?.toInt(), items, j['continuation'] as String?);
  }

  static Future<List<CtComment>> replies(String videoId, String continuation) async {
    try {
      final p = _parse(await _get('/api/v1/comments/$videoId', {'continuation': continuation}));
      return p?.items ?? [];
    } catch (_) {
      return [];
    }
  }

  /// 1) Invidious /api/v1/comments, 2) если пусто/ошибка — сервер CloudTube /ct-api/comments (yt-dlp).
  static Future<CtCommentsPage> load(String videoId,
      {String sort = 'top', String? continuation, bool invidiousOnly = false}) async {
    final key = '$videoId|$sort|${continuation ?? ''}';
    final hit = _cache[key];
    if (hit != null) return hit;
    CtCommentsPage? page;
    try {
      final q = <String, String>{'sort_by': sort};
      if (continuation != null) q['continuation'] = continuation;
      page = _parse(await _get('/api/v1/comments/$videoId', q));
    } catch (e) {
      _log.info('invidious comments failed: $e');
    }
    if ((page == null || page.items.isEmpty) && continuation == null && !invidiousOnly &&
        await CtServer.hasAddons()) {
      try {
        page = _parse(await _get('/ct-api/comments', {'v': videoId, 'sort': sort}));
      } catch (e) {
        _log.info('ct comments failed: $e');
      }
    }
    page ??= CtCommentsPage(null, [], null);
    if (page.items.isNotEmpty || invidiousOnly) _cache[key] = page;
    return page;
  }
}

/// Шторка комментариев как в YouTube: заголовок с числом, сортировка, крестик, список.
Future<void> ctShowComments(BuildContext context, String videoId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (c, scroll) => _CommentsSheet(videoId: videoId, scroll: scroll),
    ),
  );
}

class _CommentsSheet extends StatefulWidget {
  final String videoId;
  final ScrollController scroll;

  const _CommentsSheet({required this.videoId, required this.scroll});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  String sort = 'top';
  final List<CtComment> items = [];
  int? count;
  String? continuation;
  bool loading = true;
  bool more = false;
  Server? server;

  @override
  void initState() {
    super.initState();
    db.getCurrentlySelectedServer().then((s) {
      if (mounted) setState(() => server = s);
    });
    _load();
    widget.scroll.addListener(() {
      final p = widget.scroll.position;
      if (p.pixels > p.maxScrollExtent - 400) _more();
    });
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      items.clear();
      continuation = null;
    });
    final page = await CtComments.load(widget.videoId, sort: sort);
    if (!mounted) return;
    setState(() {
      items.addAll(page.items);
      count = page.count;
      continuation = page.continuation;
      loading = false;
    });
  }

  Future<void> _more() async {
    if (more || loading || continuation == null) return;
    more = true;
    final page = await CtComments.load(widget.videoId, sort: sort, continuation: continuation);
    if (mounted) {
      setState(() {
        items.addAll(page.items);
        continuation = page.continuation;
      });
    }
    more = false;
  }

  String _img(String u) {
    if (u.startsWith('//')) u = 'https:$u';
    if (ctDirectActive) return u; // без сервера картинки берём прямо у Google
    final m = RegExp(r'^https?://(yt3\.ggpht\.com|yt3\.googleusercontent\.com)(/.*)$').firstMatch(u);
    if (m != null && server != null) return '${server!.url}/ggpht${m.group(2)}';
    if (u.startsWith('/') && server != null) return server!.url + u;
    return u;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget sortChip(String value, String label) {
      final on = sort == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: on ? colors.onSurface : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: on
                ? null
                : () {
                    sort = value;
                    _load();
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: on ? colors.surface : colors.onSurface)),
            ),
          ),
        ),
      );
    }

    final header = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      Center(
        child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: colors.outline, borderRadius: BorderRadius.circular(2))),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 6),
        child: Row(children: [
          const Text('Комментарии', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          if (count != null && count! > 0)
            Text(ctShortNumber(count!), style: TextStyle(fontSize: 15, color: colors.onSurfaceVariant)),
          const Spacer(),
          IconButton(icon: const Icon(Icons.close, size: 28), onPressed: () => Navigator.of(context).pop()),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(children: [
          sortChip('top', 'Сначала популярные'),
          sortChip('new', 'Сначала новые'),
        ]),
      ),
      if (ctDirectActive && ctYtRefreshToken != null) _composer(colors),
      Divider(height: 1, color: colors.outlineVariant),
    ]);

    Widget body;
    if (loading) {
      body = const Padding(
          padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    } else if (items.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Text('Комментариев нет или они отключены',
              textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant)),
          TextButton(onPressed: _load, child: const Text('Обновить')),
        ]),
      );
    } else {
      body = Column(children: items.map((c) => _tile(c, colors)).toList());
    }

    return ListView(
      controller: widget.scroll,
      padding: EdgeInsets.zero,
      children: [header, body, if (continuation != null) const SizedBox(height: 60)],
    );
  }

  final _input = TextEditingController();
  bool _sending = false;

  Widget _composer(ColorScheme colors) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Оставьте комментарий…',
                isDense: true,
                filled: true,
                fillColor: colors.surfaceContainerHigh,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Отправить',
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.send, color: colors.primary),
          ),
        ]),
      );

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      final j = await CtYtComments.post(widget.videoId, text);
      _input.clear();
      FocusScope.of(context).unfocus();
      final c = CtComment.fromJson(j) ?? CtComment('Вы', '', text, 'только что', 0, 0, false, false, false);
      if (mounted) setState(() => items.insert(0, c));
      messenger.showSnackBar(const SnackBar(content: Text('Комментарий опубликован')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  final Map<CtComment, List<CtComment>?> _replies = {};
  final Set<CtComment> _loadingReplies = {};

  Future<void> _toggleReplies(CtComment c) async {
    if (_replies.containsKey(c)) {
      setState(() => _replies.remove(c));
      return;
    }
    if (c.repliesContinuation == null) return;
    setState(() => _loadingReplies.add(c));
    final r = await CtComments.replies(widget.videoId, c.repliesContinuation!);
    if (!mounted) return;
    setState(() {
      _loadingReplies.remove(c);
      _replies[c] = r;
    });
  }

  Widget _avatar(CtComment c, ColorScheme colors, double size) {
    final letter = CircleAvatar(
      radius: size / 2,
      backgroundColor: colors.secondaryContainer,
      child: Text(c.author.replaceFirst('@', '').characters.firstOrNull?.toUpperCase() ?? '',
          style: TextStyle(color: colors.onSurface, fontSize: size * 0.42)),
    );
    if (c.avatar.isEmpty || server == null) return letter;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: _img(c.avatar),
        httpHeaders: server!.headersForUrl(_img(c.avatar)),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => letter,
        placeholder: (_, __) => letter,
      ),
    );
  }

  Widget _tile(CtComment c, ColorScheme colors, {bool reply = false}) {
    final size = reply ? 26.0 : 36.0;
    final hasReplies = !reply && c.replies > 0;
    final open = _replies[c];
    final author = c.author.startsWith('@') ? c.author : '@${c.author}';
    return Padding(
      padding: EdgeInsets.fromLTRB(reply ? 0 : 16, reply ? 8 : 16, reply ? 0 : 8, 0),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // аватар и линия ветки
          SizedBox(
            width: size,
            child: Column(children: [
              _avatar(c, colors, size),
              if (hasReplies)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 1.5,
                    color: colors.outlineVariant,
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: author,
                          style: c.owner
                              ? TextStyle(
                                  backgroundColor: colors.surfaceContainerHigh, color: colors.onSurface)
                              : null),
                      TextSpan(text: ' • ${c.published}${c.edited ? ' (изменено)' : ''}'),
                    ]),
                    style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
                  ),
                ),
                Icon(Icons.more_horiz, size: 20, color: colors.onSurfaceVariant),
              ]),
              const SizedBox(height: 3),
              Text(c.text, style: const TextStyle(fontSize: 15, height: 1.38)),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.thumb_up_outlined, size: 20),
                if (c.likes > 0) ...[
                  const SizedBox(width: 6),
                  Text(ctShortNumber(c.likes), style: const TextStyle(fontSize: 13)),
                ],
                const SizedBox(width: 26),
                const Icon(Icons.thumb_down_outlined, size: 20),
                const SizedBox(width: 26),
                const Icon(Icons.chat_outlined, size: 20),
                if (c.heart) ...[
                  const SizedBox(width: 26),
                  const Icon(Icons.favorite, size: 18, color: Color(0xFFFF0033)),
                ],
              ]),
              if (hasReplies)
                InkWell(
                  onTap: c.repliesContinuation == null ? null : () => _toggleReplies(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(children: [
                      Text(
                          '${c.replies} ${_plural(c.replies, 'ответ', 'ответа', 'ответов')}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      if (_loadingReplies.contains(c))
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      else if (c.repliesContinuation != null)
                        Icon(open != null ? Icons.expand_less : Icons.chevron_right, size: 22),
                    ]),
                  ),
                )
              else
                const SizedBox(height: 6),
              if (open != null) ...open.map((r) => _tile(r, colors, reply: true)),
              if (open != null) const SizedBox(height: 8),
            ]),
          ),
        ]),
      ),
    );
  }
}

String _plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}
