import 'dart:convert';
import 'dart:ffi';

import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/media_kit.dart';

abstract class MediaKitAdapt {
  static void setPlayerHeader(
    Map<String, String> headers,
    generated.MPV mpv,
    Pointer<generated.mpv_handle> ctx,
  ) {
    final property = 'http-header-fields'.toNativeUtf8();
    // Allocate & fill the [mpv_node] with the headers.
    final value = calloc<generated.mpv_node>();
    final valRef = value.ref
      ..format = generated.mpv_format.MPV_FORMAT_NODE_ARRAY;
    valRef.u.list = calloc<generated.mpv_node_list>();
    final valList = valRef.u.list.ref
      ..num = headers.length
      ..values = calloc<generated.mpv_node>(headers.length);

    int i = 0;
    for (var e in headers.entries) {
      valList.values[i++]
        ..format = generated.mpv_format.MPV_FORMAT_STRING
        ..u.string = '${e.key}: ${e.value}'.toNativeUtf8().cast();
    }
    mpv.mpv_set_property(
      ctx,
      property.cast(),
      generated.mpv_format.MPV_FORMAT_NODE,
      value.cast(),
    );
    // Free the allocated memory.
    calloc.free(property);
    for (int i = 0; i < valList.num; i++) {
      calloc.free(valList.values[i].u.string);
    }
    calloc
      ..free(valList.values)
      ..free(valRef.u.list)
      ..free(value);
  }
}

extension Uint8Pointer on Pointer<Int8> {
  /// The number of UTF-8 code units in this zero-terminated UTF-8 string.
  ///
  /// The UTF-8 code units of the strings are the non-zero code units up to the
  /// first zero code unit.
  int get length {
    _ensureNotNullptr('length');
    return _length(this);
  }

  /// Converts this UTF-8 encoded string to a Dart string.
  ///
  /// Decodes the UTF-8 code units of this zero-terminated byte array as
  /// Unicode code points and creates a Dart string containing those code
  /// points.
  ///
  /// If [length] is provided, zero-termination is ignored and the result can
  /// contain NUL characters.
  ///
  /// If [length] is not provided, the returned string is the string up til
  /// but not including  the first NUL character.
  String toDartString({int? length}) {
    _ensureNotNullptr('toDartString');
    if (length != null) {
      RangeError.checkNotNegative(length, 'length');
    } else {
      length = _length(this);
    }
    return utf8.decode(asTypedList(length));
  }

  static int _length(Pointer<Int8> codeUnits) {
    var length = 0;
    while (codeUnits[length] != 0) {
      length++;
    }
    return length;
  }

  void _ensureNotNullptr(String operation) {
    if (this == nullptr) {
      throw UnsupportedError(
        "Operation '$operation' not allowed on a 'nullptr'.",
      );
    }
  }
}

extension PlatformPlayerExtension on PlatformPlayer {
  NativePlayer get maybeAsNativePlayer {
    if (this is! NativePlayer) {
      throw Exception('PlatformPlayer is not NativePlayer');
    }
    return this as NativePlayer;
  }
}
