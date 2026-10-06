import 'package:flighthouse/flighthouse.dart';
import 'package:test/test.dart';

Result<int, String> parseInt(String text) => switch (int.tryParse(text)) {
  final value? => Ok(value),
  null => Err('not a number: $text'),
};

void main() {
  const Result<int, String> ok = Ok(2);
  const Result<int, String> err = Err('boom');

  group('fold', () {
    test('applies onOk to a value', () {
      expect(ok.fold((value) => 'ok $value', (error) => 'err $error'), 'ok 2');
    });

    test('applies onErr to an error', () {
      expect(
        err.fold((value) => 'ok $value', (error) => 'err $error'),
        'err boom',
      );
    });
  });

  group('map', () {
    test('transforms a value', () {
      expect(ok.map((value) => value * 10), const Ok<int, String>(20));
    });

    test('leaves an error unchanged', () {
      expect(err.map((value) => value * 10), const Err<int, String>('boom'));
    });
  });

  group('mapErr', () {
    test('transforms an error', () {
      expect(err.mapErr((error) => error.length), const Err<int, int>(4));
    });

    test('leaves a value unchanged', () {
      expect(ok.mapErr((error) => error.length), const Ok<int, int>(2));
    });
  });

  group('flatMap', () {
    test('chains a success', () {
      expect(
        const Ok<String, String>('7').flatMap(parseInt),
        const Ok<int, String>(7),
      );
    });

    test('chains into a failure', () {
      expect(
        const Ok<String, String>('x').flatMap(parseInt),
        const Err<int, String>('not a number: x'),
      );
    });

    test('skips the next step after an error', () {
      var called = false;
      final result = const Err<String, String>('first').flatMap((value) {
        called = true;
        return parseInt(value);
      });
      expect(result, const Err<int, String>('first'));
      expect(called, isFalse);
    });
  });

  group('equality', () {
    test('compares by contents and case', () {
      expect(const Ok<int, String>(1), const Ok<int, String>(1));
      expect(const Ok<int, String>(1), isNot(const Ok<int, String>(2)));
      expect(const Ok<int, int>(1), isNot(const Err<int, int>(1)));
      expect(
        const Err<int, String>('a').hashCode,
        const Err<int, String>('a').hashCode,
      );
    });
  });

  group('traverse', () {
    test('collects every value in order', () {
      final result = traverse(['1', '2', '3'], parseInt);
      expect(result.fold((values) => values, (_) => null), [1, 2, 3]);
    });

    test('returns the first error and stops', () {
      final seen = <String>[];
      final result = traverse(['1', 'x', 'y'], (String text) {
        seen.add(text);
        return parseInt(text);
      });
      expect(result, const Err<List<int>, String>('not a number: x'));
      expect(seen, ['1', 'x']);
    });

    test('returns an empty list for no items', () {
      expect(
        traverse(
          const <String>[],
          parseInt,
        ).fold((values) => values, (_) => null),
        isEmpty,
      );
    });

    test('returns an unmodifiable list', () {
      final values = traverse(['1'], parseInt).fold((v) => v, (_) => <int>[]);
      expect(() => values.add(2), throwsUnsupportedError);
    });
  });

  group('partition', () {
    test('splits values from errors, keeping order', () {
      final (values, errors) = partition(['1', 'x', '2', 'y'].map(parseInt));
      expect(values, [1, 2]);
      expect(errors, ['not a number: x', 'not a number: y']);
    });

    test('reads a lazy input only once', () {
      var calls = 0;
      partition(
        ['1', 'x'].map((text) {
          calls += 1;
          return parseInt(text);
        }),
      );
      expect(calls, 2);
    });

    test('returns unmodifiable lists', () {
      final (values, errors) = partition(['1', 'x'].map(parseInt));
      expect(() => values.add(3), throwsUnsupportedError);
      expect(() => errors.add('z'), throwsUnsupportedError);
    });
  });
}
