import 'dart:typed_data';

import 'package:flighthouse/flighthouse.dart';
import 'package:test/test.dart';

double plusOneUlp(double value) {
  final bytes = ByteData(8)..setFloat64(0, value);
  return (bytes..setInt64(0, bytes.getInt64(0) + 1)).getFloat64(0);
}

double minusOneUlp(double value) {
  final bytes = ByteData(8)..setFloat64(0, value);
  return (bytes..setInt64(0, bytes.getInt64(0) - 1)).getFloat64(0);
}

Matcher closeToTwoDigits(double expected) => closeTo(expected, 0.005);

void main() {
  group('the curve from Lighthouse statistics-test.js', () {
    const points = (median: 7300.0, p10: 3785.0);

    test('hits the control points exactly', () {
      expect(logNormalScore(points, 7300), 0.5);
      expect(logNormalScore(points, 3785), 0.9);
      expect(logNormalScore(points, 0), 1);
    });

    test('matches Lighthouse to two digits along the curve', () {
      expect(logNormalScore(points, 1000), closeToTwoDigits(1.00));
      expect(logNormalScore(points, 2500), closeToTwoDigits(0.98));
      expect(logNormalScore(points, 5000), closeToTwoDigits(0.77));
      expect(logNormalScore(points, 7500), closeToTwoDigits(0.48));
      expect(logNormalScore(points, 10000), closeToTwoDigits(0.27));
      expect(logNormalScore(points, 30000), closeToTwoDigits(0.00));
      expect(logNormalScore(points, 1000000), 0);
    });
  });

  test('returns 1 for all non-positive values', () {
    const points = (median: 1000.0, p10: 500.0);
    expect(logNormalScore(points, -100000), 1);
    expect(logNormalScore(points, -1), 1);
    expect(logNormalScore(points, 0), 1);
  });

  group('rejects invalid control points', () {
    test('a non-positive median', () {
      expect(
        () => logNormalScore((median: 0, p10: 500), 50),
        throwsArgumentError,
      );
      expect(
        () => logNormalScore((median: -100, p10: 500), 50),
        throwsArgumentError,
      );
    });

    test('a non-positive p10', () {
      expect(
        () => logNormalScore((median: 500, p10: 0), 50),
        throwsArgumentError,
      );
      expect(
        () => logNormalScore((median: 500, p10: -100), 50),
        throwsArgumentError,
      );
    });

    test('p10 not below the median', () {
      expect(
        () => logNormalScore((median: 500, p10: 500), 50),
        throwsArgumentError,
      );
      expect(
        () => logNormalScore((median: 500, p10: 1000), 50),
        throwsArgumentError,
      );
    });
  });

  group('scores land in the right pass, average, and fail bands', () {
    final controlPoints = <ControlPoints>[
      (p10: 200, median: 600),
      (p10: 3387, median: 5800),
      (p10: 0.1, median: 0.25),
      (p10: 28 * 1024, median: 128 * 1024),
      (p10: double.minPositive, median: plusOneUlp(double.minPositive)),
      (p10: double.minPositive, median: 21.239999999999977),
      (p10: 99.56000000000073, median: 99.56000000000074),
      (p10: minusOneUlp(double.maxFinite), median: double.maxFinite),
      (p10: double.minPositive, median: double.maxFinite),
    ];

    for (final points in controlPoints) {
      test('for p10 ${points.p10}, median ${points.median}', () {
        final (:p10, :median) = points;
        expect(logNormalScore(points, 0), 1);
        expect(logNormalScore(points, plusOneUlp(0)), lessThanOrEqualTo(1));
        expect(
          logNormalScore(points, minusOneUlp(p10)),
          greaterThanOrEqualTo(0.9),
        );
        expect(logNormalScore(points, p10), 0.9);
        expect(logNormalScore(points, plusOneUlp(p10)), lessThan(0.9));
        expect(
          logNormalScore(points, minusOneUlp(median)),
          greaterThanOrEqualTo(0.5),
        );
        expect(logNormalScore(points, median), 0.5);
        expect(logNormalScore(points, plusOneUlp(median)), lessThan(0.5));
        expect(logNormalScore(points, 1e9), greaterThanOrEqualTo(0));
        expect(
          logNormalScore(points, 9007199254740991),
          greaterThanOrEqualTo(0),
        );
        expect(
          logNormalScore(points, double.maxFinite),
          greaterThanOrEqualTo(0),
        );
      });
    }
  });

  test('the ULP helpers move by exactly one representable double', () {
    expect(plusOneUlp(1.0) > 1.0, isTrue);
    expect(minusOneUlp(plusOneUlp(1.0)), 1.0);
    expect(plusOneUlp(0), double.minPositive);
  });
}
