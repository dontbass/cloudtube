import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

final _log = Logger('CtMediaCaps');

/// Что умеют аппаратные декодеры устройства — от этого зависит, какое качество включать
/// по умолчанию (4K, варианты IPTV со звуком MP2/AC-3).
class CtMediaCaps {
  final bool avc4k, hevc4k, vp94k, av14k, mp2, ac3, eac3, tunnel;
  const CtMediaCaps({
    this.avc4k = false,
    this.hevc4k = false,
    this.vp94k = false,
    this.av14k = false,
    this.mp2 = false,
    this.ac3 = false,
    this.eac3 = false,
    this.tunnel = false,
  });

  static CtMediaCaps I = const CtMediaCaps();
  static bool _loaded = false;

  /// Запрос к Android один раз за запуск (MediaCodecList — то же, что выбирает ExoPlayer).
  static Future<CtMediaCaps> load() async {
    if (_loaded || !Platform.isAndroid) return I;
    _loaded = true;
    try {
      final m = await const MethodChannel('cloudtube/media').invokeMapMethod<String, dynamic>('caps') ?? const {};
      bool b(String k) => m[k] == true;
      I = CtMediaCaps(
        avc4k: b('avc4k'),
        hevc4k: b('hevc4k'),
        vp94k: b('vp94k'),
        av14k: b('av14k'),
        mp2: b('mp2'),
        ac3: b('ac3'),
        eac3: b('eac3'),
        tunnel: b('tunnel'),
      );
      _log.info('декодеры: $I');
    } catch (e) {
      _log.warning('caps: $e');
    }
    return I;
  }

  @override
  String toString() =>
      'H.264 4K: $avc4k, HEVC 4K: $hevc4k, VP9 4K: $vp94k, AV1 4K: $av14k, MP2: $mp2, AC-3: $ac3, E-AC-3: $eac3, tunnel: $tunnel';
}
