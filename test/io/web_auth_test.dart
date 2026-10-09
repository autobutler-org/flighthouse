import 'dart:async';

import 'package:flighthouse/src/config/config.dart';
import 'package:flighthouse/src/io/browser.dart';
import 'package:flighthouse/src/io/web_auth.dart';
import 'package:flighthouse/src/result/failure.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:test/test.dart';

const _timeout = Duration(seconds: 1);
final _origin = Uri.parse('http://127.0.0.1:4321/');
const _readiness = WebReadinessConfig(timeout: _timeout, selector: '#ready');
final _auth = WebAuthConfig(
  url: '/login',
  steps: [
    const WebTypeAuthStep(
      selector: '#username',
      valueFromEnv: 'FLIGHTHOUSE_USERNAME',
    ),
    const WebTypeAuthStep(
      selector: '#password',
      valueFromEnv: 'FLIGHTHOUSE_PASSWORD',
    ),
    const WebClickAuthStep(selector: '#submit'),
    const WebWaitAuthStep(selector: '#signed-in'),
  ],
);
const _environment = {
  'FLIGHTHOUSE_USERNAME': 'owner@example.test',
  'FLIGHTHOUSE_PASSWORD': 'correct horse battery staple',
};

void main() {
  test(
    'authenticates once, then opens the protected route in that session',
    () async {
      final fake = FakeBrowser();
      final result = await authenticateWeb(
        browser: fake.session,
        origin: _origin,
        config: _auth,
        protectedRoute: '/files?sort=name#top',
        readiness: _readiness,
        environment: _environment,
      );

      expect(
        result,
        Ok<Uri, IoFailure>(_origin.resolve('/files?sort=name#top')),
      );
      expect(fake.typedSelectors, ['#username', '#password']);
      expect(fake.authenticated, isTrue);
      expect(fake.events, [
        'navigate /login',
        'first frame',
        'location /login',
        'semantics',
        'wait #ready',
        'location /login',
        'wait #username',
        'focus #username',
        'focused #username',
        'settle',
        'type #username',
        'settle',
        'read #username',
        'wait #password',
        'focus #password',
        'focused #password',
        'settle',
        'type #password',
        'settle',
        'read #password',
        'click #submit',
        'wait #signed-in',
        'navigate /files?sort=name#top',
        'first frame',
        'location /files?sort=name#top',
        'semantics',
        'wait #ready',
        'location /files?sort=name#top',
      ]);
    },
  );

  test(
    'rejects a page with no Flutter semantics before app readiness',
    () async {
      final fake = FakeBrowser(semanticsNodes: 0);
      final result = await openReadyWebRoute(
        browser: fake.session,
        origin: _origin,
        route: '/login',
        readiness: _readiness,
      );
      final failure = (result as Err<Uri, IoFailure>).error;
      expect(failure.operation, 'verify Flutter semantics');
      expect(failure.reason, contains('enable startup semantics'));
      expect(fake.events, [
        'navigate /login',
        'first frame',
        'location /login',
        'semantics',
      ]);
    },
  );

  test('rejects a redirect after readiness with both routes', () async {
    final fake = FakeBrowser(redirectProtectedRoute: '/login');
    final result = await openReadyWebRoute(
      browser: fake.session,
      origin: _origin,
      route: '/files',
      readiness: _readiness,
    );
    final failure = (result as Err<Uri, IoFailure>).error;
    expect(failure.operation, 'verify displayed web route');
    expect(failure.path, '/files');
    expect(failure.reason, contains('/login'));
  });

  test('checks every credential before browser interaction', () async {
    final fake = FakeBrowser();
    final result = await authenticateWeb(
      browser: fake.session,
      origin: _origin,
      config: _auth,
      protectedRoute: '/files',
      readiness: _readiness,
      environment: const {'FLIGHTHOUSE_USERNAME': 'owner@example.test'},
    );
    final failure = (result as Err<Uri, IoFailure>).error;
    expect(failure.operation, 'read web authentication credential');
    expect(failure.path, contains('steps[1]'));
    expect(failure.path, contains('FLIGHTHOUSE_PASSWORD'));
    expect(failure.reason, contains('missing or empty'));
    expect(failure.toString(), isNot(contains('owner@example.test')));
    expect(fake.events, isEmpty);
  });

  test('an empty credential is missing', () async {
    final fake = FakeBrowser();
    final result = await authenticateWeb(
      browser: fake.session,
      origin: _origin,
      config: _auth,
      protectedRoute: '/files',
      readiness: _readiness,
      environment: const {
        'FLIGHTHOUSE_USERNAME': 'owner@example.test',
        'FLIGHTHOUSE_PASSWORD': '',
      },
    );
    expect(result, isA<Err<Uri, IoFailure>>());
    expect(fake.events, isEmpty);
  });

  test('a bad selector names its step without exposing credentials', () async {
    final fake = FakeBrowser(failSelector: '#password');
    final result = await authenticateWeb(
      browser: fake.session,
      origin: _origin,
      config: _auth,
      protectedRoute: '/files',
      readiness: _readiness,
      environment: _environment,
    );
    final failure = (result as Err<Uri, IoFailure>).error;
    expect(failure.operation, 'run web authentication step 2 (type)');
    expect(failure.path, '#password');
    expect(failure.reason, contains('selected input was unavailable'));
    expect(failure.toString(), isNot(contains(_environment.values.last)));
  });

  test('an auth step timeout remains actionable', () async {
    final fake = FakeBrowser(pendingSelector: '#signed-in');
    final result = await authenticateWeb(
      browser: fake.session,
      origin: _origin,
      config: _auth,
      protectedRoute: '/files',
      readiness: const WebReadinessConfig(
        timeout: Duration(milliseconds: 1),
        selector: null,
      ),
      environment: _environment,
    );
    final failure = (result as Err<Uri, IoFailure>).error;
    expect(failure.operation, 'run web authentication step 4 (wait)');
    expect(failure.path, '#signed-in');
    expect(failure.reason, 'timed out after 1 ms');
  });

  test('rejected credentials fail on the protected-route redirect', () async {
    final fake = FakeBrowser(acceptCredentials: false);
    final result = await authenticateWeb(
      browser: fake.session,
      origin: _origin,
      config: _auth,
      protectedRoute: '/files',
      readiness: _readiness,
      environment: _environment,
    );
    final failure = (result as Err<Uri, IoFailure>).error;
    expect(failure.operation, 'verify displayed web route');
    expect(failure.reason, contains('/login'));
    expect(failure.toString(), isNot(contains(_environment.values.last)));
  });

  test('an authentication failure still closes the browser', () async {
    final fake = FakeBrowser(failSelector: '#password');
    final result = await useBrowser<Uri>(
      launch: () async => Ok(fake.session),
      run: (browser) => authenticateWeb(
        browser: browser,
        origin: _origin,
        config: _auth,
        protectedRoute: '/files',
        readiness: _readiness,
        environment: _environment,
      ),
      closeTimeout: _timeout,
    );
    expect(result, isA<Err<Uri, IoFailure>>());
    expect(fake.closes, 1);
  });
}

final class FakeBrowser {
  FakeBrowser({
    this.semanticsNodes = 3,
    this.redirectProtectedRoute,
    this.failSelector,
    this.pendingSelector,
    this.acceptCredentials = true,
  }) {
    session = BrowserSession(
      BrowserBindings(
        info: _info,
        navigate: _navigate,
        waitForFirstFrame: (_) async => events.add('first frame'),
        currentUrl: _currentUrl,
        waitForSelector: _waitForSelector,
        click: _click,
        focus: (selector) async => events.add('focus $selector'),
        waitForFocus: (selector, _) async => events.add('focused $selector'),
        settleInput: () async => events.add('settle'),
        replaceInput: _replaceInput,
        readInput: _readInput,
        evaluate: _evaluate,
        close: () async {
          closes++;
        },
      ),
    );
  }

  final int semanticsNodes;
  final String? redirectProtectedRoute;
  final String? failSelector;
  final String? pendingSelector;
  final bool acceptCredentials;
  late final BrowserSession session;
  final List<String> events = [];
  final List<String> typedSelectors = [];
  final Map<String, String> _values = {};
  Uri _url = _origin;
  bool authenticated = false;
  int closes = 0;

  Future<void> _navigate(Uri url, Duration timeout) async {
    events.add('navigate ${_routeOf(url)}');
    if (url.path != '/login' &&
        (!authenticated || redirectProtectedRoute != null)) {
      _url = _origin.resolve(redirectProtectedRoute ?? '/login');
      return;
    }
    _url = url;
  }

  String _currentUrl() {
    events.add('location ${_routeOf(_url)}');
    return _url.toString();
  }

  Future<void> _waitForSelector(String selector, Duration timeout) async {
    events.add('wait $selector');
    if (selector == pendingSelector) {
      await Completer<void>().future;
    }
    if (selector == failSelector) {
      throw Exception('selector not found');
    }
  }

  Future<void> _click(String selector) async {
    events.add('click $selector');
    if (selector == failSelector) throw Exception('selector not found');
    if (selector == '#submit') authenticated = acceptCredentials;
  }

  Future<void> _replaceInput(String selector, String value) async {
    events.add('type $selector');
    typedSelectors.add(selector);
    _values[selector] = value;
  }

  Future<String?> _readInput(String selector) async {
    events.add('read $selector');
    return _values[selector];
  }

  Future<Object?> _evaluate(String script, List<Object?> arguments) async {
    events.add('semantics');
    return semanticsNodes;
  }
}

String _routeOf(Uri uri) => uri.hasQuery
    ? '${uri.path}?${uri.query}${uri.hasFragment ? '#${uri.fragment}' : ''}'
    : '${uri.path}${uri.hasFragment ? '#${uri.fragment}' : ''}';

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
