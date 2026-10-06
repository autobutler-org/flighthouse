import 'dart:math' as math;

import '../config/config.dart';

const double _minPassingScore =
    0.90000000000000002220446049250313080847263336181640625;
const double _maxAverageScore =
    0.899999999999999911182158029987476766109466552734375;
const double _minAverageScore = 0.5;
const double _maxFailingScore =
    0.499999999999999944488848768742172978818416595458984375;

const double _inverseErfcOneFifth = 0.9061938024368232;

double erf(double x) {
  final sign = x.sign;
  final magnitude = x.abs();
  const a1 = 0.254829592;
  const a2 = -0.284496736;
  const a3 = 1.421413741;
  const a4 = -1.453152027;
  const a5 = 1.061405429;
  const p = 0.3275911;
  final t = 1 / (1 + p * magnitude);
  final y = t * (a1 + t * (a2 + t * (a3 + t * (a4 + t * a5))));
  return sign * (1 - y * math.exp(-magnitude * magnitude));
}

/// Scores [value] from 0 to 1 on a log-normal curve, exactly as Lighthouse does.
///
/// A value at `p10` scores 0.9, a value at `median` scores 0.5, lower is
/// better, and a value of 0 or less scores 1. Scores are clamped into
/// Lighthouse's bands: `[0.9, 1]` up to `p10`, `[0.5, 0.9)` up to `median`,
/// and `[0, 0.5)` above it. Ported from Lighthouse's `shared/statistics.js`
/// (Apache-2.0).
///
/// Throws an [ArgumentError] when the control points are not
/// `0 < p10 < median`; config parsing rejects those before scoring runs.
double logNormalScore(ControlPoints points, double value) {
  final (:p10, :median) = points;
  if (median <= 0) {
    throw ArgumentError.value(median, 'median', 'must be greater than zero');
  }
  if (p10 <= 0) {
    throw ArgumentError.value(p10, 'p10', 'must be greater than zero');
  }
  if (p10 >= median) {
    throw ArgumentError.value(p10, 'p10', 'must be less than the median');
  }
  if (value <= 0) {
    return 1;
  }
  final xLogRatio = math.log(math.max(double.minPositive, value / median));
  final p10LogRatio = -math.log(math.max(double.minPositive, p10 / median));
  final standardizedX = xLogRatio * _inverseErfcOneFifth / p10LogRatio;
  final complementaryPercentile = (1 - erf(standardizedX)) / 2;
  return switch (value) {
    _ when value <= p10 =>
      complementaryPercentile.clamp(_minPassingScore, 1).toDouble(),
    _ when value <= median =>
      complementaryPercentile
          .clamp(_minAverageScore, _maxAverageScore)
          .toDouble(),
    _ => complementaryPercentile.clamp(0, _maxFailingScore).toDouble(),
  };
}
