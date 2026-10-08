import 'dart:async';
import 'dart:convert';

import 'package:flighthouse/src/io/browser.dart';
import 'package:flighthouse/src/result/failure.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:test/test.dart';

const _timeout = Duration(seconds: 1);
const _viewport = BrowserViewport(
  width: 1280,
  height: 800,
  deviceScaleFactor: 1,
);
const _installation = BrowserInstallation(
  cachePath: '/cache/chrome',
  executablePath: '/cache/chrome/152/chrome',
  version: '152.0.7977.42',
);
const _info = BrowserInfo(
  installation: _installation,
  browserVersion: 'Chrome/152.0.7977.42',
  debuggingPort: 40123,
);

void main() {
  test(
    'launch acquires pinned Chrome once and captures its metadata',
    () async {
      var acquisitions = 0;
      var launches = 0;
      final result = await launchBrowser(
        cachePath: _installation.cachePath,
        viewport: _viewport,
        acquireTimeout: _timeout,
        launchTimeout: _timeout,
        acquire: (cachePath) async {
          acquisitions++;
          expect(cachePath, _installation.cachePath);
          return _installation;
        },
        launch: (installation, viewport, timeout) async {
          launches++;
          expect(installation, same(_installation));
          expect(viewport, same(_viewport));
          expect(timeout, _timeout);
          return _bindings();
        },
      );

      expect(acquisitions, 1);
      expect(launches, 1);
      switch (result) {
        case Ok(:final value):
          expect(value.info.installation.cachePath, _installation.cachePath);
          expect(value.info.installation.version, _installation.version);
          expect(value.info.browserVersion, 'Chrome/152.0.7977.42');
          expect(value.info.debuggingPort, 40123);
        case Err(:final error):
          fail('$error');
      }
    },
  );

  test('launch explains a host without a usable Chrome sandbox', () async {
    final result = await launchBrowser(
      cachePath: _installation.cachePath,
      viewport: _viewport,
      acquireTimeout: _timeout,
      launchTimeout: _timeout,
      acquire: (_) async => _installation,
      launch: (_, _, _) async =>
          throw Exception('Websocket url not found.\nNo usable sandbox!'),
    );

    switch (result) {
      case Err(:final error):
        expect(error.operation, 'launch Chrome');
        expect(error.reason, contains('sandbox enabled'));
        expect(error.reason, contains('does not disable'));
      case Ok():
        fail('a failed launch must return an IO failure');
    }
  });

  test('a launch that completes after its deadline is closed', () async {
    final pending = Completer<BrowserBindings>();
    var closes = 0;
    final result = await launchBrowser(
      cachePath: _installation.cachePath,
      viewport: _viewport,
      acquireTimeout: _timeout,
      launchTimeout: const Duration(milliseconds: 1),
      acquire: (_) async => _installation,
      launch: (_, _, _) => pending.future,
    );
    expect(result, isA<Err<BrowserSession, IoFailure>>());

    pending.complete(
      _bindings(
        close: () async {
          closes++;
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(closes, 1);
  });

  test(
    'open waits for the first frame before separate app readiness',
    () async {
      final events = <String>[];
      final browser = BrowserSession(
        _bindings(
          navigate: (_, _) async => events.add('navigate'),
          waitForFirstFrame: (_) async => events.add('first frame'),
          waitForSelector: (_, _) async => events.add('app ready'),
        ),
      );

      final opened = await browser.open(
        Uri.parse('http://127.0.0.1:8080/files'),
        timeout: _timeout,
      );
      expect(opened, isA<Ok<Uri, IoFailure>>());
      expect(events, ['navigate', 'first frame']);

      final ready = await browser.waitForSelector(
        'flt-semantics-host',
        timeout: _timeout,
      );
      expect(ready, isA<Ok<void, IoFailure>>());
      expect(events, ['navigate', 'first frame', 'app ready']);
    },
  );

  test('type waits for focus, inserts once, and verifies the value', () async {
    final events = <String>[];
    String? inputValue;
    const credential = 'correct horse battery staple';
    final browser = BrowserSession(
      _bindings(
        waitForSelector: (_, _) async => events.add('visible'),
        focus: (_) async => events.add('focus'),
        waitForFocus: (_, _) async => events.add('focused'),
        settleInput: () async => events.add('frame'),
        replaceInput: (_, value) async {
          events.add('insert');
          inputValue = value;
        },
        readInput: (_) async {
          events.add('verify');
          return inputValue;
        },
      ),
    );

    final result = await browser.type(
      '#password',
      credential,
      timeout: _timeout,
    );

    expect(result, isA<Ok<void, IoFailure>>());
    expect(events, [
      'visible',
      'focus',
      'focused',
      'frame',
      'insert',
      'frame',
      'verify',
    ]);
  });

  test('type mismatch never includes the intended value', () async {
    const credential = 'never-print-this-secret';
    final browser = BrowserSession(
      _bindings(readInput: (_) async => 'truncated'),
    );
    final result = await browser.type(
      '#password',
      credential,
      timeout: _timeout,
    );

    switch (result) {
      case Err(:final error):
        expect(error.operation, 'type into browser selector');
        expect(error.path, '#password');
        expect(error.reason, contains('did not retain the typed value'));
        expect(error.toString(), isNot(contains(credential)));
      case Ok():
        fail('a mismatched input value must fail');
    }
  });

  test('evaluate JSON preserves a complete large nested result', () async {
    final padding = List.filled(2100, 'x').join();
    final nodes = <Object?>[
      for (var index = 0; index < 500; index++)
        <String, Object?>{
          'target': <Object?>[
            <Object?>['iframe#gallery'],
            <Object?>['button:nth-child(${index + 1})'],
          ],
          'checks': <Object?>[
            <String, Object?>{'id': 'button-name', 'data': padding},
          ],
        },
    ];
    final payload = <String, Object?>{'violations': nodes};
    expect(utf8.encode(jsonEncode(payload)).length, greaterThan(1000000));
    final browser = BrowserSession(
      _bindings(evaluate: (_, _) async => payload),
    );

    final result = await browser.evaluateJson(
      '() => axe.run()',
      timeout: _timeout,
    );

    switch (result) {
      case Ok(:final value):
        final object = value! as Map<String, Object?>;
        final violations = object['violations']! as List<Object?>;
        expect(violations, hasLength(500));
        final last = violations.last! as Map<String, Object?>;
        expect(last['target'], [
          ['iframe#gallery'],
          ['button:nth-child(500)'],
        ]);
        final checks = last['checks']! as List<Object?>;
        final check = checks.single! as Map<String, Object?>;
        expect((check['data']! as String).length, 2100);
      case Err(:final error):
        fail('$error');
    }
  });

  test('evaluate JSON rejects a value with a live object', () async {
    final browser = BrowserSession(
      _bindings(evaluate: (_, _) async => DateTime.utc(2026)),
    );
    final result = await browser.evaluateJson(
      '() => document.body',
      timeout: _timeout,
    );
    expect(result, isA<Err<Object?, IoFailure>>());
  });

  final failedOperations =
      <
        String,
        Future<Result<Object?, IoFailure>> Function(BrowserSession browser)
      >{
        'navigate': (browser) async => (await browser.open(
          Uri.parse('http://127.0.0.1:8080'),
          timeout: _timeout,
        )).map<Object?>((value) => value),
        'wait': (browser) async => (await browser.waitForSelector(
          '#ready',
          timeout: _timeout,
        )).map<Object?>((value) => value),
        'click': (browser) async => (await browser.click(
          '#submit',
          timeout: _timeout,
        )).map<Object?>((value) => value),
        'replace': (browser) async => (await browser.type(
          '#username',
          'user@example.test',
          timeout: _timeout,
        )).map<Object?>((value) => value),
        'evaluate': (browser) =>
            browser.evaluateJson('() => ({ok: true})', timeout: _timeout),
      };

  for (final MapEntry(key: operation, value: invoke)
      in failedOperations.entries) {
    test('a failed $operation operation still closes the browser', () async {
      var closes = 0;
      final browser = BrowserSession(
        _bindings(
          failAt: operation,
          close: () async {
            closes++;
          },
        ),
      );
      final result = await useBrowser<Object?>(
        launch: () async => Ok(browser),
        run: invoke,
        closeTimeout: _timeout,
      );
      expect(result, isA<Err<Object?, IoFailure>>());
      expect(closes, 1);
    });
  }

  test('a successful browser run closes exactly once', () async {
    var closes = 0;
    final browser = BrowserSession(
      _bindings(
        close: () async {
          closes++;
        },
      ),
    );
    final result = await useBrowser<String>(
      launch: () async => Ok(browser),
      run: (browser) async {
        final waited = await browser.waitForSelector(
          '#ready',
          timeout: _timeout,
        );
        return waited.map((_) => 'ready');
      },
      closeTimeout: _timeout,
    );
    expect(result, const Ok<String, IoFailure>('ready'));
    expect(closes, 1);
  });

  test('an operation timeout is a typed failure', () async {
    final pending = Completer<void>();
    final browser = BrowserSession(_bindings(click: (_) => pending.future));
    final result = await browser.click(
      '#submit',
      timeout: const Duration(milliseconds: 1),
    );
    switch (result) {
      case Err(:final error):
        expect(error.operation, 'click browser selector');
        expect(error.reason, 'timed out after 1 ms');
      case Ok():
        fail('a timed-out browser operation must fail');
    }
  });
}

BrowserBindings _bindings({
  String? failAt,
  Future<void> Function(Uri url, Duration timeout)? navigate,
  Future<void> Function(Duration timeout)? waitForFirstFrame,
  Future<void> Function(String selector, Duration timeout)? waitForSelector,
  Future<void> Function(String selector)? click,
  Future<void> Function(String selector)? focus,
  Future<void> Function(String selector, Duration timeout)? waitForFocus,
  Future<void> Function()? settleInput,
  Future<void> Function(String selector, String value)? replaceInput,
  Future<String?> Function(String selector)? readInput,
  Future<Object?> Function(String script, List<Object?> arguments)? evaluate,
  Future<void> Function()? close,
}) {
  Future<void> run(String operation) async {
    if (failAt == operation) throw Exception('$operation failed');
  }

  return BrowserBindings(
    info: _info,
    navigate: navigate ?? (_, _) => run('navigate'),
    waitForFirstFrame: waitForFirstFrame ?? (_) => run('first frame'),
    currentUrl: () => 'http://127.0.0.1:8080/files',
    waitForSelector: waitForSelector ?? (_, _) => run('wait'),
    click: click ?? (_) => run('click'),
    focus: focus ?? (_) => run('focus'),
    waitForFocus: waitForFocus ?? (_, _) => run('focused'),
    settleInput: settleInput ?? () => run('frame'),
    replaceInput: replaceInput ?? (_, _) => run('replace'),
    readInput: readInput ?? (_) async => failAt == 'replace' ? null : '',
    evaluate:
        evaluate ??
        (_, _) async {
          await run('evaluate');
          return <String, Object?>{'ok': true};
        },
    close: close ?? () => run('close'),
  );
}
