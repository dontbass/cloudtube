import 'dart:convert';

import '../globals.dart';
import '../settings/models/db/settings.dart';

/// Типизированная настройка CloudTube: ключ, значение по умолчанию и разбор.
/// Испорченное или старое значение не роняет приложение — возвращается умолчание.
class CtPref<T> {
  final String key;
  final T def;
  final T? Function(String raw) _decode;
  final String Function(T v) _encode;

  const CtPref._(this.key, this.def, this._decode, this._encode);

  /// Сохранено ли значение вообще (а не умолчание).
  bool get isSet => db.getSettings(key) != null;

  T get value {
    try {
      final raw = db.getSettings(key)?.value;
      if (raw == null) return def;
      return _decode(raw) ?? def;
    } catch (_) {
      return def;
    }
  }

  Future<void> set(T v) => db.saveSetting(SettingsValue(key, _encode(v)));

  Future<void> clear() => db.deleteSetting(key);
}

CtPref<bool> _bool(String key, bool def) =>
    CtPref._(key, def, (r) => r == 'true' || r == '1' ? true : (r == 'false' || r == '0' ? false : null), (v) => '$v');

CtPref<int> _int(String key, int def, {int min = -1 << 31, int max = 1 << 31}) => CtPref._(key, def, (r) {
      final v = int.tryParse(r);
      return v != null && v >= min && v <= max ? v : null;
    }, (v) => '$v');

CtPref<double> _double(String key, double def, {double min = double.negativeInfinity, double max = double.infinity}) =>
    CtPref._(key, def, (r) {
      final v = double.tryParse(r);
      return v != null && v >= min && v <= max ? v : null;
    }, (v) => '$v');

CtPref<String> _string(String key, [String def = '']) => CtPref._(key, def, (r) => r, (v) => v);

CtPref<List<String>> _stringList(String key) => CtPref._(
    key, const [], (r) => (jsonDecode(r) as List).map((e) => '$e').toList(), (v) => jsonEncode(v));

/// Все настройки CloudTube в одном месте (раньше — строки-ключи по разным файлам).
/// Ключи не менялись — сохранённые значения пользователей подхватываются как есть.
abstract final class CtPrefs {
  /// Первый запуск пройден (выбор режима: напрямую / свой сервер).
  static final onboardingDone = _bool('ct-onboarding-done', false);

  /// Потолок качества: ТВ (по умолчанию 4K) и телефон (1080p) — отдельно.
  static final tvQuality = _int('ct-tv-quality', 2160, min: 144, max: 2160);
  static final phoneQuality = _int('ct-phone-quality', 1080, min: 144, max: 2160);

  /// Масштаб интерфейса на ТВ.
  static final tvScale = _double('ct-tv-scale', 0.8, min: 0.5, max: 1.0);

  /// «Мягкая» тема (тёплые цвета).
  static final softTheme = _bool('ct-theme-soft', false);

  /// Пропущенная версия обновления: «версия|время».
  static final updateSkip = _string('ct-update-skip');

  /// Кэш аватарок каналов (JSON).
  static final avatars = _string('ct-avatars');

  /// Вход в YouTube через сайт: cookie и выбранный канал (JSON).
  static final ytWebCookie = _string('ct_yt_web_cookie');
  static final ytWebIdentity = _string('ct_yt_web_identity');

  /// Shorts: просмотренные ролики и скрытые каналы.
  static final shortsSeen = _stringList('ct-shorts-seen');
  static final shortsBlocked = _stringList('ct-shorts-blocked-channels');
}
