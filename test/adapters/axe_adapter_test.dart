import 'dart:convert';
import 'dart:io';

import 'package:flighthouse/flighthouse.dart';
import 'package:flighthouse/src/adapters/axe/axe_adapter.dart';
import 'package:test/test.dart';

const fixtures = 'test/fixtures/axe/4.11.1/quark-48a76ae';

String fixture(String name) => File('$fixtures/$name').readAsStringSync();

Map<String, Object?> fixtureJson(String name) =>
    jsonDecode(fixture(name)) as Map<String, Object?>;

RawArtifact artifactOf(String contents) =>
    (source: Source.axe, path: 'axe/results.json', contents: contents);

AdapterOutput parsed(String contents) =>
    parseAxe(artifactOf(contents))
        .fold((output) => output, (failure) => fail('$failure'));

String failureOf(Object? json) =>
    parseAxe(artifactOf(json is String ? json : jsonEncode(json)))
        .fold((_) => fail('expected a failure'), describe);

Map<String, Object?> document({
  String version = '4.11.1',
  String name = 'axe-core',
  String url = 'http://127.0.0.1:8771/login',
  List<Object?> violations = const [],
  List<Object?> passes = const [],
  List<Object?> incomplete = const [],
  List<Object?> inapplicable = const [],
}) => {
  'testEngine': {'name': name, 'version': version},
  'url': url,
  'violations': violations,
  'passes': passes,
  'incomplete': incomplete,
  'inapplicable': inapplicable,
};

Map<String, Object?> rule(
  String id,
  Object? impact,
  List<Object?> nodes, {
  String? help,
}) => {
  'id': id,
  'impact': impact,
  'help': help ?? 'Help for $id',
  'nodes': nodes,
};

Map<String, Object?> axeNode({
  Object? impact = 'serious',
  Object? target = const ['#main'],
  Object? ancestry = const ['#main'],
  bool includeAncestry = true,
  Object? html = '<main id="main">',
  Object? failureSummary = 'Fix any of the following:\n  label',
  bool includeSummary = true,
}) => {
  'impact': impact,
  'html': html,
  'target': target,
  if (includeAncestry) 'ancestry': ancestry,
  if (includeSummary) 'failureSummary': failureSummary,
};

List<Object?> rulesOf(Map<String, Object?> json, String group) =>
    (json[group]! as List<Object?>);

List<Map<String, Object?>> objectsOf(List<Object?> values) => [
  for (final value in values) value! as Map<String, Object?>,
];

List<String> idsOf(Map<String, Object?> json, String group) => [
  for (final rule in objectsOf(rulesOf(json, group))) rule['id']! as String,
];

int nodeCount(Map<String, Object?> json, String group) {
  var count = 0;
  for (final rule in objectsOf(rulesOf(json, group))) {
    count += (rule['nodes']! as List<Object?>).length;
  }
  return count;
}

void main() {
  group('quark 4.11.1 fixtures', () {
    for (final name in ['login.json', 'files.json', 'photos.json']) {
      final json = fixtureJson(name);
      final output = parsed(fixture(name));
      final violationCount = nodeCount(json, 'violations');
      final incompleteCount = nodeCount(json, 'incomplete');

      test('$name keeps the engine version and every result group', () {
        expect(output.toolVersion, '4.11.1');
        expect(output.measurements, isEmpty);
        expect(output.findings, hasLength(violationCount + incompleteCount));
        expect(
          output.findings.where(
            (finding) => !finding.message.startsWith('Needs review:'),
          ),
          hasLength(violationCount),
        );
        expect(
          output.findings.where(
            (finding) => finding.message.startsWith('Needs review:'),
          ),
          hasLength(incompleteCount),
        );
        expect(output.ruleOutcomes.map((outcome) => outcome.rule), [
          ...idsOf(json, 'violations'),
          ...idsOf(json, 'passes'),
          ...idsOf(json, 'inapplicable'),
        ]);
        expect(output.ruleOutcomes.map((outcome) => outcome.passed), [
          for (final _ in idsOf(json, 'violations')) false,
          for (final _ in idsOf(json, 'passes')) true,
          for (final _ in idsOf(json, 'inapplicable')) true,
        ]);
        expect(output.findings.map((finding) => finding.category).toSet(), {
          Category.a11y,
        });
        expect(output.ruleOutcomes.map((outcome) => outcome.category).toSet(), {
          Category.a11y,
        });
      });

      test('$name fingerprints the normalized target and keeps it stable', () {
        for (final finding in output.findings) {
          expect(
            finding.fingerprint,
            fingerprint(
              source: Source.axe,
              rule: finding.rule,
              route: finding.route,
              target: finding.target,
            ),
          );
          expect(normalizeAxeTarget(finding.target), finding.target);
          expect(finding.route, json['url']);
        }
        expect(
          output.findings.map((finding) => finding.fingerprint).toSet(),
          hasLength(output.findings.length),
        );
      });
    }

    test('login region nodes stay distinct and anchor at the Flutter view', () {
      final output = parsed(fixture('login.json'));
      final regions = output.findings
          .where(
            (finding) =>
                finding.rule == 'region' &&
                !finding.message.startsWith('Needs review:'),
          )
          .toList();
      expect(regions, hasLength(6));
      expect(regions.map((finding) => finding.target).toSet(), hasLength(6));
      expect(
        regions.map((finding) => finding.severity),
        everyElement(Severity.moderate),
      );
      for (final finding in regions) {
        final selectors = jsonDecode(finding.target!) as List<Object?>;
        final selector = selectors.single! as String;
        expect(selector, startsWith('flutter-view > '));
        expect(selector, isNot(contains('html > body')));
        expect(selector, isNot(contains('flutter-view:nth-child')));
        expect(selector, contains('flt-semantics-host:nth-child(3)'));
        expect(selector, isNot(contains('flt-semantic-node')));
      }
      expect(jsonDecode(regions.last.target!) as List<Object?>, [
        'flutter-view > flt-semantics-host:nth-child(3) > flt-semantics > '
            'flt-semantics > flt-semantics > flt-semantics > form > '
            'flt-semantics:nth-child(6) > input:nth-child(1)',
      ]);
      expect(regions.last.message, contains('aria-label=\\"Password\\"'));
      expect(regions.last.message, contains('<input'));
      expect(regions.first.message, contains('#flt-semantic-node-5'));
      expect(regions.first.message, contains('<flt-semantics'));
    });

    test(
      'files nested-interactive and region nodes keep descendant ordinals',
      () {
        final output = parsed(fixture('files.json'));
        final nested = output.findings
            .where((finding) => finding.rule == 'nested-interactive')
            .map(
              (finding) =>
                  (jsonDecode(finding.target!) as List<Object?>).single!
                      as String,
            )
            .toList();
        expect(nested, hasLength(2));
        expect(nested.toSet(), hasLength(2));
        expect(nested[0], contains('flt-semantics:nth-child(1)'));
        expect(nested[1], contains('flt-semantics:nth-child(2)'));
        expect(
          nested,
          everyElement(contains('flt-semantics-host:nth-child(3)')),
        );
        expect(nested, everyElement(startsWith('flutter-view > ')));
        final regions = output.findings
            .where(
              (finding) =>
                  finding.rule == 'region' &&
                  !finding.message.startsWith('Needs review:'),
            )
            .map((finding) => finding.target)
            .toSet();
        expect(regions, hasLength(4));
      },
    );

    test('photos keeps a critical label and a moderate region', () {
      final output = parsed(fixture('photos.json'));
      final label = output.findings.singleWhere(
        (finding) => finding.rule == 'label',
      );
      expect(label.severity, Severity.critical);
      expect(label.message, contains('["input"]'));
      expect(
        (jsonDecode(label.target!) as List<Object?>).single,
        contains('flutter-view > '),
      );
      final region = output.findings.singleWhere(
        (finding) =>
            finding.rule == 'region' &&
            !finding.message.startsWith('Needs review:'),
      );
      expect(region.severity, Severity.moderate);
      expect(region.message, contains('["flt-semantics-host"]'));
    });

    test('incomplete is needs review and does not fail a passing rule', () {
      final login = parsed(fixture('login.json'));
      final contrast = login.ruleOutcomes.where(
        (outcome) => outcome.rule == 'color-contrast',
      );
      expect(contrast, hasLength(1));
      expect(contrast.single.passed, isTrue);
      expect(contrast.single.weight, 7);
      final reviews = login.findings.where(
        (finding) => finding.rule == 'color-contrast',
      );
      expect(reviews, isNotEmpty);
      expect(
        reviews,
        everyElement(
          predicate<Finding>(
            (finding) => finding.message.startsWith('Needs review:'),
          ),
        ),
      );
      expect(
        reviews.map((finding) => finding.severity),
        everyElement(Severity.serious),
      );

      final files = parsed(fixture('files.json'));
      expect(
        files.ruleOutcomes.where((outcome) => outcome.rule == 'color-contrast'),
        isEmpty,
      );
      expect(
        files.findings.where((finding) => finding.rule == 'color-contrast'),
        isNotEmpty,
      );
    });

    test('a rule that both passes and fails stays failed after dedupe', () {
      final output = parsed(fixture('login.json'));
      final region = output.ruleOutcomes
          .where((outcome) => outcome.rule == 'region')
          .toList();
      expect(region.map((outcome) => outcome.passed), [false, true]);
      expect(region.map((outcome) => outcome.weight), [3, 3]);
      final deduped = dedupe(
        normalize((
          findings: output.findings,
          ruleOutcomes: output.ruleOutcomes,
          measurements: output.measurements,
        ), const []),
      );
      expect(
        deduped.ruleOutcomes
            .singleWhere((outcome) => outcome.rule == 'region')
            .passed,
        isFalse,
      );
      expect(deduped.findings.map((finding) => finding.route).toSet(), {
        '/login',
      });
      expect(
        deduped.findings.map((finding) => finding.target),
        output.findings.map((finding) => finding.target),
      );
    });

    test(
      'passes with a null impact count at minor weight, inapplicable at zero',
      () {
        final output = parsed(fixture('login.json'));
        final lang = output.ruleOutcomes.singleWhere(
          (outcome) => outcome.rule == 'aria-allowed-attr',
        );
        expect(lang.passed, isTrue);
        expect(lang.weight, 1);
        final accesskeys = output.ruleOutcomes.singleWhere(
          (outcome) => outcome.rule == 'accesskeys',
        );
        expect(accesskeys.passed, isTrue);
        expect(accesskeys.weight, 0);
        expect(
          output.findings.where((finding) => finding.rule == 'accesskeys'),
          isEmpty,
        );
      },
    );

    test(
      'shadow ancestry stays a nested array and keeps descendant ordinals',
      () {
        final login = fixtureJson('login.json');
        final rule = objectsOf(rulesOf(login, 'passes'))
            .singleWhere((item) => item['id'] == 'aria-hidden-focus');
        final node = objectsOf(rule['nodes']! as List<Object?>)
            .firstWhere((item) {
              final target = item['target'];
              return target is List<Object?> &&
                  target.any((part) => part is List<Object?>);
            });
        final normalized = jsonDecode(
          normalizeAxeTarget(jsonEncode(node['ancestry']))!,
        ) as List<Object?>;
        expect(normalized, [
          [
            'flutter-view > flt-glass-pane:nth-child(1)',
            'flt-scene-host:nth-child(1) > flt-scene > flt-canvas-container > canvas',
          ],
        ]);
        expect(normalized.single, isA<List<Object?>>());
      },
    );
  });

  group('ancestry across quark builds', () {
    final evidence = jsonDecode(
      File('docs/evidence/quark-targets.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final results = (evidence['results']! as List<Object?>)
        .cast<Map<String, Object?>>();

    Map<String, Object?> resultFor(String build, String route) =>
        results.singleWhere(
          (item) => item['build'] == build && item['route'] == route,
        );

    List<String> identities(String build, String route, String ruleId) {
      final rules = (resultFor(build, route)['rules']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final rule = rules.singleWhere((item) => item['id'] == ruleId);
      return [
        for (final node
            in (rule['nodes']! as List<Object?>).cast<Map<String, Object?>>())
          normalizeAxeTarget(jsonEncode(node['ancestry']))!,
      ];
    }

    test('the same node matches across both builds and later activation', () {
      const builds = ['semantics-1', 'semantics-2', 'default-activated'];
      for (final route in ['login', 'files', 'photos']) {
        final rules =
            (resultFor(builds.first, route)['rules']! as List<Object?>)
                .cast<Map<String, Object?>>();
        for (final rule in rules) {
          final id = rule['id']! as String;
          final count = (rule['nodes']! as List<Object?>).length;
          for (var index = 0; index < count; index++) {
            final seen = {
              for (final build in builds) identities(build, route, id)[index],
            };
            expect(seen, hasLength(1), reason: '$route $id node $index');
          }
        }
      }
    });

    test('repeated nodes and raw generated ids stay distinct', () {
      expect(
        identities('semantics-1', 'login', 'region').toSet(),
        hasLength(6),
      );
      expect(
        identities('semantics-1', 'files', 'nested-interactive').toSet(),
        hasLength(2),
      );
      expect(
        identities('semantics-1', 'files', 'region').toSet(),
        hasLength(4),
      );
      final first =
          (resultFor('semantics-1', 'files')['rules']! as List<Object?>)
              .cast<Map<String, Object?>>();
      final later =
          (resultFor('default-activated', 'files')['rules']! as List<Object?>)
              .cast<Map<String, Object?>>();
      String raw(List<Map<String, Object?>> rules) => jsonEncode(
        ((rules.singleWhere(
                      (item) => item['id'] == 'nested-interactive',
                    )['nodes']!
                    as List<Object?>)
                .first!
            as Map<String, Object?>)['target'],
      );
      expect(raw(first), contains('flt-semantic-node-40'));
      expect(raw(later), contains('flt-semantic-node-12'));
      expect(raw(first), isNot(raw(later)));
    });
  });

  group('normalized targets', () {
    test('anchors a Flutter view and is idempotent', () {
      final raw = jsonEncode([
        'html > body > flutter-view:nth-child(5) > '
            'flt-semantics-host:nth-child(3) > #keep-me > button:nth-child(2)',
      ]);
      final once = normalizeAxeTarget(raw);
      expect(jsonDecode(once!), [
        'flutter-view > flt-semantics-host:nth-child(3) > #keep-me > '
            'button:nth-child(2)',
      ]);
      expect(normalizeAxeTarget(once), once);
      expect(once, isNot(contains('flutter-view:nth-child')));
      expect(once, isNot(contains('html > body')));
    });

    test('keeps a non-Flutter target exact, including ids and ordinals', () {
      final raw = jsonEncode(['#main > .card:nth-child(2)']);
      expect(normalizeAxeTarget(raw), raw);
    });

    test('keeps frame and shadow boundaries distinct', () {
      final frame = jsonEncode(['iframe#pay', 'button:nth-child(1)']);
      final joined = jsonEncode(['iframe#pay > button:nth-child(1)']);
      final shadow = jsonEncode([
        ['flt-glass-pane', 'canvas'],
      ]);
      expect(jsonDecode(normalizeAxeTarget(frame)!), [
        'iframe#pay',
        'button:nth-child(1)',
      ]);
      expect(normalizeAxeTarget(frame), isNot(normalizeAxeTarget(joined)));
      expect(normalizeAxeTarget(frame), isNot(normalizeAxeTarget(shadow)));
      expect(jsonDecode(normalizeAxeTarget(shadow)!), [
        ['flt-glass-pane', 'canvas'],
      ]);
    });

    test('leaves null and non-selector text unchanged', () {
      expect(normalizeAxeTarget(null), isNull);
      expect(normalizeAxeTarget('not json'), 'not json');
      expect(normalizeAxeTarget('[]'), '[]');
    });

    test('the default pipeline normalizer anchors axe targets only', () {
      final raw = jsonEncode([
        'html > body > flutter-view:nth-child(5) > button',
      ]);
      final normalized = normalize((
        findings: [
          (
            fingerprint: 'pending',
            source: Source.axe,
            category: Category.a11y,
            severity: Severity.moderate,
            rule: 'region',
            route: 'http://127.0.0.1:8771/login',
            target: raw,
            message: 'kept',
            metric: null,
          ),
          (
            fingerprint: 'pending',
            source: Source.lighthouse,
            category: Category.a11y,
            severity: Severity.moderate,
            rule: 'region',
            route: 'http://127.0.0.1:8771/login',
            target: raw,
            message: 'kept',
            metric: null,
          ),
        ],
        ruleOutcomes: const [],
        measurements: const [],
      ), const []);
      expect(jsonDecode(normalized.findings.first.target!), [
        'flutter-view > button',
      ]);
      expect(normalized.findings.last.target, raw);
      expect(normalized.findings.first.route, '/login');
    });
  });

  group('failures', () {
    test('invalid JSON names the artifact', () {
      expect(failureOf('{'), contains('not valid JSON'));
      expect(failureOf('{'), contains('axe: axe/results.json'));
    });

    test('a missing required field names its JSON path', () {
      expect(failureOf({}), contains(r'$.testEngine'));
      expect(failureOf({}), isNot(contains('cannot read axe output yet')));
      final withoutUrl = document()..remove('url');
      expect(failureOf(withoutUrl), contains(r'$.url'));
      final withoutViolations = document()..remove('violations');
      expect(failureOf(withoutViolations), contains(r'$.violations'));
      expect(
        failureOf(
          document(
            violations: [
              rule('region', 'moderate', [
                {
                  'impact': 'moderate',
                  'target': const ['#main'],
                },
              ]),
            ],
          ),
        ),
        contains(r'$.violations[0].nodes[0].html'),
      );
    });

    test('an empty or malformed target names its JSON path', () {
      String targetFailure(Object? target) => failureOf(
        document(
          violations: [
            rule('region', 'moderate', [axeNode(target: target)]),
          ],
        ),
      );
      expect(
        targetFailure(const []),
        contains(r'$.violations[0].nodes[0].target'),
      );
      expect(targetFailure('button'), contains('a non-empty selector array'));
      expect(targetFailure(1), contains(r'$.violations[0].nodes[0].target'));
      expect(
        targetFailure(const ['']),
        contains(r'$.violations[0].nodes[0].target[0]'),
      );
      expect(
        targetFailure(const [<Object?>[]]),
        contains(r'$.violations[0].nodes[0].target[0]'),
      );
    });

    test('a bad impact is rejected', () {
      expect(
        failureOf(
          document(
            violations: [
              rule('region', 'huge', [axeNode()]),
            ],
          ),
        ),
        contains(r'$.violations[0].impact'),
      );
    });

    test('a violation with no impact fails', () {
      expect(
        failureOf(
          document(
            violations: [
              rule('region', null, [axeNode(impact: null)]),
            ],
          ),
        ),
        contains(r'$.violations[0].impact'),
      );
    });

    test('a generated id without ancestry asks for a recapture', () {
      expect(
        failureOf(
          document(
            violations: [
              rule('region', 'moderate', [
                axeNode(
                  target: const ['#flt-semantic-node-5'],
                  includeAncestry: false,
                ),
              ]),
            ],
          ),
        ),
        'axe: axe/results.json: \$.violations[0].nodes[0].target: expected '
        'output captured with ancestry: true, found a generated id '
        '(#flt-semantic-node-5) and no ancestry',
      );
      expect(
        failureOf(
          document(
            passes: [
              rule('label', null, [
                axeNode(
                  impact: null,
                  target: const [
                    ['#host', '#flt-semantic-node-3'],
                  ],
                  includeAncestry: false,
                  includeSummary: false,
                ),
              ]),
            ],
          ),
        ),
        contains('a generated id (#flt-semantic-node-3) and no ancestry'),
      );
      expect(
        failureOf(
          document(
            passes: [
              rule('label', null, [
                axeNode(
                  impact: null,
                  target: const [
                    ['#host', '#flt-semantic-node-3'],
                  ],
                  includeAncestry: false,
                  includeSummary: false,
                ),
              ]),
            ],
          ),
        ),
        contains(r'$.passes[0].nodes[0].target'),
      );
    });

    test('malformed ancestry fails instead of falling back', () {
      expect(
        failureOf(
          document(
            violations: [
              rule('region', 'moderate', [axeNode(ancestry: const [])]),
            ],
          ),
        ),
        contains(r'$.violations[0].nodes[0].ancestry'),
      );
      expect(
        failureOf(
          document(
            violations: [
              rule('region', 'moderate', [axeNode(ancestry: 'div')]),
            ],
          ),
        ),
        contains(r'$.violations[0].nodes[0].ancestry'),
      );
    });

    test('a non-Flutter target without ancestry is kept exact', () {
      final output = parsed(
        jsonEncode(
          document(
            violations: [
              rule('region', 'moderate', [
                axeNode(
                  target: const ['#main > .card:nth-child(2)'],
                  includeAncestry: false,
                ),
              ]),
            ],
          ),
        ),
      );
      expect(
        output.findings.single.target,
        jsonEncode(['#main > .card:nth-child(2)']),
      );
      expect(
        output.findings.single.message,
        contains('#main > .card:nth-child(2)'),
      );
    });

    test('ancestry wins over a generated id in the raw target', () {
      final output = parsed(
        jsonEncode(
          document(
            violations: [
              rule('region', 'moderate', [
                axeNode(
                  target: const ['#flt-semantic-node-5'],
                  ancestry: const [
                    'html > body > flutter-view:nth-child(5) > #app-header > button:nth-child(2)',
                  ],
                  html: '<flt-semantics id="flt-semantic-node-5">',
                ),
              ]),
            ],
          ),
        ),
      );
      final finding = output.findings.single;
      expect(jsonDecode(finding.target!), [
        'flutter-view > #app-header > button:nth-child(2)',
      ]);
      expect(finding.message, contains('#flt-semantic-node-5'));
      expect(finding.target, isNot(contains('flt-semantic-node')));
      expect(finding.target, contains('#app-header'));
    });

    test('minor impact maps onto minor and weight 1', () {
      final output = parsed(
        jsonEncode(
          document(
            violations: [
              rule('region', 'minor', [axeNode(impact: 'minor')]),
            ],
          ),
        ),
      );
      expect(output.findings.single.severity, Severity.minor);
      expect(output.ruleOutcomes.single.weight, 1);
      expect(output.ruleOutcomes.single.passed, isFalse);
    });

    test('an incomplete-only rule is a finding and not an outcome', () {
      final output = parsed(
        jsonEncode(
          document(
            incomplete: [
              rule(
                'color-contrast',
                'serious',
                [axeNode()],
                help: 'Elements must meet minimum color contrast ratio thresholds',
              ),
            ],
          ),
        ),
      );
      expect(output.ruleOutcomes, isEmpty);
      expect(output.findings.single.severity, Severity.serious);
      expect(
        output.findings.single.message,
        startsWith(
          'Needs review: Elements must meet minimum color contrast ratio thresholds',
        ),
      );
    });

    test('an untested major names the version and the tested majors', () {
      for (final version in ['5.0.0', '3.5.0', 'axe-core']) {
        expect(
          failureOf(document(version: version)),
          contains('axe-core $version is untested; tested majors are 4'),
        );
      }
    });

    test('a different engine name fails', () {
      expect(
        failureOf(document(name: 'lighthouse')),
        contains(r'$.testEngine.name'),
      );
      expect(failureOf(document(name: 'lighthouse')), contains('axe-core'));
    });

    test('an empty result parses', () {
      final output = parsed(jsonEncode(document()));
      expect(output.toolVersion, '4.11.1');
      expect(output.findings, isEmpty);
      expect(output.ruleOutcomes, isEmpty);
    });
  });
}
