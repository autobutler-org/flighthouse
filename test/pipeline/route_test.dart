import 'dart:math';

import 'package:flighthouse/flighthouse.dart';
import 'package:test/test.dart';

RoutePattern compiled(String pattern) => compileRoutePattern(
  pattern,
  'routes.patterns[0]',
).fold((value) => value, (failure) => fail('$failure'));

final quarkPatterns = [
  compiled('/files/:path(.*)'),
  compiled('/users/:tab'),
  compiled(r'/devices/:id(\d+)'),
];

String randomRoute(Random random) {
  const segments = ['files', 'users', 'devices', 'photos', 'a', 'B', '42', ''];
  const suffixes = ['', '/', '?album=x', '#top', '/?q=1#f', '?'];
  final depth = random.nextInt(4);
  final path = List.generate(
    depth,
    (_) => segments[random.nextInt(segments.length)],
  ).join('/');
  final prefix = random.nextBool() ? 'http://localhost:8080' : '';
  return '$prefix/$path${suffixes[random.nextInt(suffixes.length)]}';
}

void main() {
  group('compileRoutePattern', () {
    test('a plain parameter matches one segment', () {
      final pattern = compiled('/users/:tab');
      expect(pattern.matches('/users/groups'), isTrue);
      expect(pattern.matches('/users/groups/1'), isFalse);
      expect(pattern.matches('/users'), isFalse);
    });

    test('a constrained parameter uses its regular expression', () {
      final files = compiled('/files/:path(.*)');
      expect(files.matches('/files/a/b/c.txt'), isTrue);
      expect(files.matches('/files/'), isTrue);
      final devices = compiled(r'/devices/:id(\d+)');
      expect(devices.matches('/devices/42'), isTrue);
      expect(devices.matches('/devices/abc'), isFalse);
    });

    test('literal text is matched exactly, including regex characters', () {
      final pattern = compiled('/a.b');
      expect(pattern.matches('/a.b'), isTrue);
      expect(pattern.matches('/aXb'), isFalse);
    });

    test('matching is anchored and case-sensitive', () {
      final pattern = compiled('/photos');
      expect(pattern.matches('/photos/x'), isFalse);
      expect(pattern.matches('/x/photos'), isFalse);
      expect(pattern.matches('/Photos'), isFalse);
    });

    test('a pattern must start with a slash', () {
      final failure = compileRoutePattern(
        'files',
        'routes.patterns[2]',
      ).fold((_) => fail('expected a failure'), (failure) => failure);
      expect(failure.keyPath, 'routes.patterns[2]');
    });

    test('an invalid regular expression is a config failure', () {
      expect(
        compileRoutePattern('/x/:id([a-)', 'routes.patterns[0]'),
        isA<Err<RoutePattern, ConfigFailure>>(),
      );
    });
  });

  group('normalizeRoute', () {
    test('strips query, fragment, and trailing slash, and keeps case', () {
      expect(normalizeRoute('/Photos/?album=x#top', const []), '/Photos');
    });

    test('strips every trailing slash', () {
      expect(normalizeRoute('/users//', const []), '/users');
      expect(normalizeRoute('///', const []), '/');
    });

    test('a later literal pattern does not beat an earlier match', () {
      final patterns = [compiled('/users/:tab'), compiled('/users/groups')];
      expect(normalizeRoute('/users/groups', patterns), '/users/:tab');
      expect(normalizeRoute('/users/:tab', patterns), '/users/:tab');
    });

    test('keeps the root route', () {
      expect(normalizeRoute('/', const []), '/');
      expect(normalizeRoute('/?q=1', const []), '/');
      expect(normalizeRoute('', const []), '/');
    });

    test('takes the path of an absolute URL', () {
      expect(
        normalizeRoute('http://localhost:8080/login?from=%2Ffiles', const []),
        '/login',
      );
      expect(normalizeRoute('http://localhost:8080', const []), '/');
    });

    test('replaces a matching path with its pattern', () {
      expect(
        normalizeRoute('/files/a/b.txt?x=1', quarkPatterns),
        '/files/:path(.*)',
      );
      expect(
        normalizeRoute('/devices/42', quarkPatterns),
        r'/devices/:id(\d+)',
      );
      expect(normalizeRoute('/devices/abc', quarkPatterns), '/devices/abc');
    });

    test('the first matching pattern wins', () {
      final patterns = [compiled('/users/:tab'), compiled('/users/groups')];
      expect(normalizeRoute('/users/groups', patterns), '/users/:tab');
    });

    test('a route that is a pattern stays unchanged', () {
      expect(
        normalizeRoute(r'/devices/:id(\d+)', quarkPatterns),
        r'/devices/:id(\d+)',
      );
    });

    test('is idempotent over 2000 random routes', () {
      final random = Random(7);
      for (var index = 0; index < 2000; index += 1) {
        final route = randomRoute(random);
        final once = normalizeRoute(route, quarkPatterns);
        expect(normalizeRoute(once, quarkPatterns), once, reason: route);
      }
    });

    test('never keeps a query or fragment over 2000 random routes', () {
      final random = Random(11);
      for (var index = 0; index < 2000; index += 1) {
        final route = randomRoute(random);
        final normalized = normalizeRoute(route, const []);
        expect(normalized, isNot(contains('?')), reason: route);
        expect(normalized, isNot(contains('#')), reason: route);
        expect(normalized, startsWith('/'), reason: route);
      }
    });
  });
}
