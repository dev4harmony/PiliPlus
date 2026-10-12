import 'package:PiliPlus/plugin/pl_player/models/hdr_peak_nits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default is the 1000 nit HDR reference', () {
    expect(HdrPeakNits.defaultValue, 1000);
  });

  group('HdrPeakNits.snap', () {
    test('rounds slider positions to the step', () {
      expect(HdrPeakNits.snap(1049), 1000);
      expect(HdrPeakNits.snap(1050), 1100);
      expect(HdrPeakNits.snap(1600), 1600);
    });

    test('stays inside the range', () {
      expect(HdrPeakNits.snap(0), HdrPeakNits.min);
      expect(HdrPeakNits.snap(20000), HdrPeakNits.max);
    });

    test('the slider range divides evenly into steps', () {
      expect((HdrPeakNits.max - HdrPeakNits.min) % HdrPeakNits.step, 0);
    });
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
