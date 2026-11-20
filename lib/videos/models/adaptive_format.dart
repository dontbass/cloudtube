import 'package:json_annotation/json_annotation.dart';

part 'adaptive_format.g.dart';

@JsonSerializable()
class AdaptiveFormat {
  String? index;
  String? bitrate;
  String? init;
  String url;
  String itag;
  String type;
  String clen;
  String lmt;
  String projectionType;
  String? container;
  String? encoding;
  String? qualityLabel;
  String? resolution;

  /// Звуковая дорожка ролика с несколькими дорожками: {id, displayName, isDefault /
  /// audioIsDefault} — оригинал или дубляж.
  Map<String, dynamic>? audioTrack;

  AdaptiveFormat(
      this.index,
      this.bitrate,
      this.init,
      this.url,
      this.itag,
      this.type,
      this.clen,
      this.lmt,
      this.projectionType,
      this.container,
      this.encoding,
      this.qualityLabel,
      this.resolution);

  factory AdaptiveFormat.fromJson(Map<String, dynamic> json) =>
      _$AdaptiveFormatFromJson(json);

  Map<String, dynamic> toJson() => _$AdaptiveFormatToJson(this);
}
