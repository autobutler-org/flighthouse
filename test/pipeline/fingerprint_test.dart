import 'package:flighthouse/flighthouse.dart';
import 'package:flighthouse/src/pipeline/fingerprint.dart'
    show fingerprintInput;
import 'package:test/test.dart';

void main() {
  group('fingerprint matches SHA-256 computed outside Dart', () {
    test('with a target', () {
      expect(
        fingerprint(
          source: Source.axe,
          rule: 'color-contrast',
          route: '/login',
          target: 'flt-semantics[role="button"]',
        ),
        'd9ee8772f574e69872a4b8cc729c33c1bbf7cb80df66ab3e8420e5891eacaee0',
      );
    });

    test('without a target', () {
      expect(
        fingerprint(
          source: Source.timeline,
          rule: 'frame-budget',
          route: '/photos',
          target: null,
        ),
        'a26d6416747225f331757fd497ee13848449dd979f73b7ea56791214c64ff962',
      );
    });

    test('with separators and backslashes escaped', () {
      expect(
        fingerprint(
          source: Source.attest,
          rule: 'a|b',
          route: '/x',
          target: r't\',
        ),
        'd8a13685402e5c07a881c7334e1562411ec6ce47cd93fd1055c81818ea298038',
      );
    });
  });

  group('fingerprint input', () {
    test('starts with the scheme version', () {
      expect(
        fingerprintInput(
          source: Source.axe,
          rule: 'r',
          route: '/',
          target: null,
        ),
        startsWith('$fingerprintVersion|'),
      );
    });

    test('a separator cannot move between fields', () {
      String of(String rule, String route) => fingerprint(
        source: Source.axe,
        rule: rule,
        route: route,
        target: null,
      );
      expect(of('a|b', 'c'), isNot(of('a', 'b|c')));
    });

    test('an escaped backslash cannot fake a separator', () {
      String of(String rule, String route) => fingerprint(
        source: Source.axe,
        rule: rule,
        route: route,
        target: null,
      );
      expect(of(r'a\', '|b'), isNot(of(r'a\|', 'b')));
    });

    test('no target differs from an empty target and a literal \\N', () {
      String of(String? target) => fingerprint(
        source: Source.axe,
        rule: 'r',
        route: '/',
        target: target,
      );
      expect(of(null), isNot(of('')));
      expect(of(null), isNot(of(r'\N')));
    });

    test('every identity field changes the fingerprint', () {
      final base = fingerprint(
        source: Source.axe,
        rule: 'r',
        route: '/a',
        target: 't',
      );
      expect(
        fingerprint(
          source: Source.lighthouse,
          rule: 'r',
          route: '/a',
          target: 't',
        ),
        isNot(base),
      );
      expect(
        fingerprint(source: Source.axe, rule: 's', route: '/a', target: 't'),
        isNot(base),
      );
      expect(
        fingerprint(source: Source.axe, rule: 'r', route: '/b', target: 't'),
        isNot(base),
      );
      expect(
        fingerprint(source: Source.axe, rule: 'r', route: '/a', target: 'u'),
        isNot(base),
      );
    });

    test('is 64 lowercase hex characters', () {
      expect(
        fingerprint(source: Source.axe, rule: 'r', route: '/', target: null),
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
    });
  });
}
