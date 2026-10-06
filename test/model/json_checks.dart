import 'dart:convert';

import 'package:flighthouse/flighthouse.dart';
import 'package:test/test.dart';

typedef Decode = Result<Object?, SchemaFailure> Function(Object? json);

Object? viaJsonText(Map<String, Object?> json) => jsonDecode(jsonEncode(json));

String pathOf(Result<Object?, SchemaFailure> result) => result.fold(
  (value) => fail('expected a failure, got $value'),
  (failure) => failure.jsonPath,
);

void expectEveryFieldIsChecked(
  String name,
  Map<String, Object?> valid,
  Decode decode,
) {
  group('$name rejects', () {
    test('nothing when valid', () {
      expect(decode(viaJsonText(valid)), isA<Ok<Object?, SchemaFailure>>());
    });

    for (final key in valid.keys) {
      test('a missing $key', () {
        expect(pathOf(decode({...valid}..remove(key))), '\$.$key');
      });

      test('a wrongly typed $key', () {
        expect(
          pathOf(
            decode({
              ...valid,
              key: {'wrong': true},
            }),
          ),
          '\$.$key',
        );
      });
    }

    test('an unknown key', () {
      expect(pathOf(decode({...valid, 'extra': 1})), r'$');
    });

    test('a non-object', () {
      expect(pathOf(decode('text')), r'$');
    });
  });
}
