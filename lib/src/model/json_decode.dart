import '../result/failure.dart';
import '../result/result.dart';

typedef Decoded<T> = Result<T, SchemaFailure>;

typedef Decoder<T> = Decoded<T> Function(Object? json, String path);

typedef JsonObject = Map<String, Object?>;

const rootPath = r'$';

String describeJson(Object? json) => switch (json) {
  null => 'null',
  String() when json.length > 40 => '"${json.substring(0, 40)}..."',
  String() => '"$json"',
  num() || bool() => '$json',
  List() => 'a list',
  Map() => 'an object',
  _ => 'a ${json.runtimeType}',
};

Decoded<T> mismatch<T>(String path, String expected, Object? found) => Err(
  SchemaFailure(jsonPath: path, expected: expected, found: describeJson(found)),
);

SchemaFailure firstError(List<Result<Object?, SchemaFailure>> results) =>
    results.whereType<Err<Object?, SchemaFailure>>().first.error;

Decoded<JsonObject> readObject(
  Object? json,
  String path,
  List<String> keys, {
  bool requireAll = true,
}) {
  if (json is! Map<String, Object?>) {
    return mismatch(path, 'an object', json);
  }
  final unknown = json.keys.where((key) => !keys.contains(key));
  if (unknown.isNotEmpty) {
    return mismatch(path, 'only the keys ${keys.join(', ')}', unknown.first);
  }
  final missing = keys.where((key) => !json.containsKey(key));
  if (requireAll && missing.isNotEmpty) {
    return Err(
      SchemaFailure(
        jsonPath: '$path.${missing.first}',
        expected: 'a value',
        found: 'nothing',
      ),
    );
  }
  return Ok(json);
}

Decoded<T> readField<T>(
  JsonObject object,
  String key,
  String path,
  Decoder<T> decode,
) => decode(object[key], '$path.$key');

Decoded<String> decodeString(Object? json, String path) => switch (json) {
  final String text => Ok(text),
  _ => mismatch(path, 'a string', json),
};

Decoded<String> decodeNonEmptyString(Object? json, String path) =>
    switch (json) {
      final String text when text.isNotEmpty => Ok(text),
      _ => mismatch(path, 'a non-empty string', json),
    };

Decoded<double> decodeNumber(Object? json, String path) => switch (json) {
  final num number when number.isFinite => Ok(number.toDouble()),
  _ => mismatch(path, 'a finite number', json),
};

Decoded<double> decodeNonNegative(Object? json, String path) => switch (json) {
  final num number when number.isFinite && number >= 0 => Ok(number.toDouble()),
  _ => mismatch(path, 'a number of at least 0', json),
};

Decoded<double> decodeUnitInterval(Object? json, String path) => switch (json) {
  final num number when number >= 0 && number <= 1 => Ok(number.toDouble()),
  _ => mismatch(path, 'a number from 0 to 1', json),
};

Decoded<int> decodeInt(Object? json, String path) => switch (json) {
  final int number => Ok(number),
  _ => mismatch(path, 'an integer', json),
};

Decoded<bool> decodeBool(Object? json, String path) => switch (json) {
  final bool flag => Ok(flag),
  _ => mismatch(path, 'true or false', json),
};

Decoded<DateTime> decodeUtcTimestamp(Object? json, String path) =>
    switch (json) {
      final String text when text.endsWith('Z') => switch (DateTime.tryParse(
        text,
      )) {
        final DateTime time => Ok(time),
        _ => mismatch(path, 'a UTC ISO-8601 timestamp', json),
      },
      _ => mismatch(path, 'a UTC ISO-8601 timestamp', json),
    };

Decoder<T?> nullable<T extends Object>(Decoder<T> decode) =>
    (json, path) => json == null ? const Ok(null) : decode(json, path);

Decoder<T> enumDecoder<T>(List<T> values, String Function(T value) idOf) =>
    (json, path) => switch (values.where((value) => idOf(value) == json)) {
      final matches when matches.isNotEmpty => Ok(matches.first),
      _ => mismatch(path, 'one of ${values.map(idOf).join(', ')}', json),
    };

Decoder<List<T>> listDecoder<T>(Decoder<T> decodeItem) =>
    (json, path) => switch (json) {
      final List<Object?> items => traverse(
        List.generate(items.length, (index) => index),
        (index) => decodeItem(items[index], '$path[$index]'),
      ),
      _ => mismatch(path, 'a list', json),
    };

Decoder<Map<K, V>> keyedDecoder<K, V>(
  List<K> keys,
  String Function(K key) idOf,
  Decoder<V> decodeValue, {
  bool requireAll = true,
}) =>
    (json, path) =>
        readObject(
          json,
          path,
          keys.map(idOf).toList(growable: false),
          requireAll: requireAll,
        ).flatMap((object) {
          final present = keys.where((key) => object.containsKey(idOf(key)));
          return traverse(
            present,
            (key) => readField(
              object,
              idOf(key),
              path,
              decodeValue,
            ).map((value) => MapEntry(key, value)),
          ).map((entries) => Map<K, V>.unmodifiable(Map.fromEntries(entries)));
        });
