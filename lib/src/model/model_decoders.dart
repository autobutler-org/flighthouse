import '../result/result.dart';
import 'enums.dart';
import 'json_decode.dart';

final _fingerprintPattern = RegExp(r'^[0-9a-f]{64}$');

Decoded<String> decodeFingerprint(Object? json, String path) => switch (json) {
  final String text when _fingerprintPattern.hasMatch(text) => Ok(text),
  _ => mismatch(path, '64 lowercase hex characters', json),
};

String categoryId(Category category) => category.id;

String sourceId(Source source) => source.id;

final Decoder<Category> decodeCategory = enumDecoder(
  Category.values,
  categoryId,
);

final Decoder<Severity> decodeSeverity = enumDecoder(
  Severity.values,
  (severity) => severity.id,
);

final Decoder<Source> decodeSource = enumDecoder(Source.values, sourceId);

final Decoder<MetricUnit> decodeUnit = enumDecoder(
  MetricUnit.values,
  (unit) => unit.id,
);
