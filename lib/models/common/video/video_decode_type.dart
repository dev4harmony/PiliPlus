// ignore_for_file: constant_identifier_names

enum VideoDecodeFormatType {
  DVH1(['dvh1', 'dvhe']),
  AV1(['av01']),
  HEVC(['hev1', 'hvc1']),
  AVC(['avc1']),
  ;

  String get description => name;
  final List<String> codes;

  const VideoDecodeFormatType(this.codes);

  /// Falls back to [AVC] rather than throwing: the codec string comes from the
  /// API, and an unrecognised one reaches a list builder where a StateError
  /// would take down the quality picker.
  static VideoDecodeFormatType fromString(String val) => values.firstWhere(
    (i) => i.codes.any(val.startsWith),
    orElse: () => AVC,
  );
}
