import 'package:PiliPlus/plugin/pl_player/models/hdr_peak_nits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default keeps the value calibrated before the setting existed', () {
    expect(HdrPeakNits.defaultValue, 1600);
  });

  group('HdrPeakNits.tryParse', () {
    test('accepts integers inside the range', () {
      expect(HdrPeakNits.tryParse('1600'), 1600);
      expect(HdrPeakNits.tryParse(' 1000 '), 1000);
      expect(HdrPeakNits.tryParse('${HdrPeakNits.min}'), HdrPeakNits.min);
      expect(HdrPeakNits.tryParse('${HdrPeakNits.max}'), HdrPeakNits.max);
    });

    test('rejects empty, non-integer and out-of-range input', () {
      expect(HdrPeakNits.tryParse(''), isNull);
      expect(HdrPeakNits.tryParse('abc'), isNull);
      expect(HdrPeakNits.tryParse('1600.5'), isNull);
      expect(HdrPeakNits.tryParse('${HdrPeakNits.min - 1}'), isNull);
      expect(HdrPeakNits.tryParse('${HdrPeakNits.max + 1}'), isNull);
    });
  });

  group('HdrPeakNits.sanitize', () {
    test('keeps a stored value inside the range', () {
      expect(HdrPeakNits.sanitize(1000), 1000);
    });

    test('falls back to the default for missing, mistyped or out-of-range '
        'values', () {
      expect(HdrPeakNits.sanitize(null), HdrPeakNits.defaultValue);
      expect(HdrPeakNits.sanitize('1000'), HdrPeakNits.defaultValue);
      expect(HdrPeakNits.sanitize(0), HdrPeakNits.defaultValue);
      expect(
        HdrPeakNits.sanitize(HdrPeakNits.max + 1),
        HdrPeakNits.defaultValue,
      );
    });
  });
}
