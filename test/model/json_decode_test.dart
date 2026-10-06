import 'package:flighthouse/flighthouse.dart';
import 'package:flighthouse/src/model/json_decode.dart';
import 'package:test/test.dart';

SchemaFailure? failureOf<T>(Result<T, SchemaFailure> result) =>
    result.fold((_) => null, (failure) => failure);

T? valueOf<T>(Result<T, SchemaFailure> result) =>
    result.fold((value) => value, (_) => null);

void main() {
  group('describeJson', () {
    test('describes each JSON kind', () {
      expect(describeJson(null), 'null');
      expect(describeJson('hi'), '"hi"');
      expect(describeJson(3), '3');
      expect(describeJson(false), 'false');
      expect(describeJson(<Object?>[]), 'a list');
      expect(describeJson(<String, Object?>{}), 'an object');
    });

    test('truncates long strings', () {
      expect(describeJson('x' * 50), '"${'x' * 40}..."');
    });
  });

  group('readObject', () {
    test('accepts an object with exactly the keys', () {
      expect(valueOf(readObject({'a': 1, 'b': null}, r'$', ['a', 'b'])), {
        'a': 1,
        'b': null,
      });
    });

    test('rejects a non-object', () {
      final failure = failureOf(readObject([1], r'$.x', ['a']))!;
      expect(failure.jsonPath, r'$.x');
      expect(failure.expected, 'an object');
      expect(failure.found, 'a list');
    });

    test('rejects an unknown key', () {
      final failure = failureOf(readObject({'a': 1, 'z': 2}, r'$', ['a']))!;
      expect(failure.jsonPath, r'$');
      expect(failure.expected, 'only the keys a');
      expect(failure.found, '"z"');
    });

    test('names a missing key', () {
      final failure = failureOf(readObject({'a': 1}, r'$', ['a', 'b']))!;
      expect(failure.jsonPath, r'$.b');
      expect(failure.found, 'nothing');
    });

    test('allows missing keys when not all are required', () {
      expect(
        valueOf(readObject({'a': 1}, r'$', ['a', 'b'], requireAll: false)),
        {'a': 1},
      );
    });
  });

  group('scalar decoders', () {
    test('string', () {
      expect(valueOf(decodeString('', r'$')), '');
      expect(failureOf(decodeString(1, r'$'))!.expected, 'a string');
    });

    test('non-empty string', () {
      expect(failureOf(decodeNonEmptyString('', r'$')), isNotNull);
    });

    test('number accepts ints and doubles as doubles', () {
      expect(valueOf(decodeNumber(3, r'$')), 3.0);
      expect(valueOf(decodeNumber(-2.5, r'$')), -2.5);
      expect(failureOf(decodeNumber('3', r'$')), isNotNull);
      expect(failureOf(decodeNumber(double.nan, r'$')), isNotNull);
    });

    test('non-negative', () {
      expect(valueOf(decodeNonNegative(0, r'$')), 0.0);
      expect(failureOf(decodeNonNegative(-1, r'$')), isNotNull);
    });

    test('unit interval', () {
      expect(valueOf(decodeUnitInterval(1, r'$')), 1.0);
      expect(failureOf(decodeUnitInterval(1.01, r'$')), isNotNull);
      expect(failureOf(decodeUnitInterval(-0.01, r'$')), isNotNull);
    });

    test('int and bool', () {
      expect(valueOf(decodeInt(4, r'$')), 4);
      expect(failureOf(decodeInt(4.5, r'$')), isNotNull);
      expect(valueOf(decodeBool(true, r'$')), isTrue);
      expect(failureOf(decodeBool(0, r'$')), isNotNull);
    });

    test('UTC timestamp', () {
      expect(
        valueOf(decodeUtcTimestamp('2026-10-06T19:30:00.000Z', r'$')),
        DateTime.utc(2026, 10, 6, 19, 30),
      );
      expect(
        failureOf(decodeUtcTimestamp('2026-10-06T19:30:00.000', r'$')),
        isNotNull,
      );
      expect(failureOf(decodeUtcTimestamp('yesterday', r'$')), isNotNull);
      expect(
        failureOf(decodeUtcTimestamp('2026-10-06T19:30:00+02:00', r'$')),
        isNotNull,
      );
    });
  });

  group('combinators', () {
    test('nullable passes null through', () {
      expect(valueOf(nullable(decodeString)(null, r'$')), isNull);
      expect(failureOf(nullable(decodeString)(1, r'$')), isNotNull);
    });

    test('enumDecoder matches by id and lists the choices', () {
      final decode = enumDecoder(Severity.values, (severity) => severity.id);
      expect(valueOf(decode('minor', r'$')), Severity.minor);
      expect(
        failureOf(decode('high', r'$'))!.expected,
        'one of critical, serious, moderate, minor, info',
      );
    });

    test('listDecoder names the index of the bad item', () {
      final failure = failureOf(
        listDecoder(decodeInt)([1, 2, 'x'], r'$.items'),
      )!;
      expect(failure.jsonPath, r'$.items[2]');
    });

    test('listDecoder rejects a non-list', () {
      expect(failureOf(listDecoder(decodeInt)({}, r'$')), isNotNull);
    });

    test('keyedDecoder maps ids to keys', () {
      final decode = keyedDecoder(
        Source.values,
        (source) => source.id,
        decodeString,
        requireAll: false,
      );
      expect(valueOf(decode({'axe': '4.10.3'}, r'$')), {Source.axe: '4.10.3'});
      expect(failureOf(decode({'eslint': '9'}, r'$')), isNotNull);
    });
  });
}
