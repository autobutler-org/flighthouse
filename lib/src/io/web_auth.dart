import '../config/config.dart';
import '../result/failure.dart';
import '../result/result.dart';
import 'browser.dart';

const _semanticsNodeCount = '''
() => document.querySelectorAll('flt-semantics-host flt-semantics').length
''';

Future<Result<Uri, IoFailure>> openReadyWebRoute({
  required BrowserSession browser,
  required Uri origin,
  required String route,
  required WebReadinessConfig readiness,
}) async {
  final requested = origin.resolve(route);
  final opened = await browser.open(requested, timeout: readiness.timeout);
  if (opened case Err(:final error)) return Err(error);

  final semantics = await browser.evaluateJson(
    _semanticsNodeCount,
    timeout: readiness.timeout,
  );
  switch (semantics) {
    case Err(:final error):
      return Err(
        IoFailure(
          operation: 'verify Flutter semantics',
          path: _routeText(requested),
          reason: _safeBrowserReason(error, 'semantics could not be inspected'),
        ),
      );
    case Ok(value: final num count) when count > 0:
      break;
    case Ok():
      return Err(
        IoFailure(
          operation: 'verify Flutter semantics',
          path: _routeText(requested),
          reason:
              'no Flutter semantics nodes were exposed; enable startup '
              'semantics in the application build',
        ),
      );
  }

  if (readiness.selector case final selector?) {
    final ready = await browser.waitForSelector(
      selector,
      timeout: readiness.timeout,
    );
    if (ready case Err(:final error)) return Err(error);
  }

  final location = await browser.location(timeout: readiness.timeout);
  switch (location) {
    case Err(:final error):
      return Err(error);
    case Ok(:final value) when _sameLocation(requested, value):
      return Ok(value);
    case Ok(:final value):
      return Err(
        IoFailure(
          operation: 'verify displayed web route',
          path: _routeText(requested),
          reason: 'browser displayed ${_routeText(value)} after readiness',
        ),
      );
  }
}

Future<Result<Uri, IoFailure>> authenticateWeb({
  required BrowserSession browser,
  required Uri origin,
  required WebAuthConfig config,
  required String protectedRoute,
  required WebReadinessConfig readiness,
  required Map<String, String> environment,
}) async {
  final credentials = _credentials(config.steps, environment);
  if (credentials case Err(:final error)) return Err(error);

  final opened = await openReadyWebRoute(
    browser: browser,
    origin: origin,
    route: config.url,
    readiness: readiness,
  );
  if (opened case Err(:final error)) return Err(error);

  final values = (credentials as Ok<Map<int, String>, IoFailure>).value;
  for (var index = 0; index < config.steps.length; index++) {
    final step = config.steps[index];
    final result = await switch (step) {
      WebTypeAuthStep() => browser.type(
        step.selector,
        values[index]!,
        timeout: readiness.timeout,
      ),
      WebClickAuthStep() => browser.click(
        step.selector,
        timeout: readiness.timeout,
      ),
      WebWaitAuthStep() => browser.waitForSelector(
        step.selector,
        timeout: readiness.timeout,
      ),
    };
    if (result case Err(:final error)) {
      return Err(_authStepFailure(index, step, error));
    }
  }

  return openReadyWebRoute(
    browser: browser,
    origin: origin,
    route: protectedRoute,
    readiness: readiness,
  );
}

Result<Map<int, String>, IoFailure> _credentials(
  List<WebAuthStep> steps,
  Map<String, String> environment,
) {
  final values = <int, String>{};
  for (var index = 0; index < steps.length; index++) {
    final step = steps[index];
    if (step case WebTypeAuthStep(:final valueFromEnv)) {
      final value = environment[valueFromEnv];
      if (value == null || value.isEmpty) {
        return Err(
          IoFailure(
            operation: 'read web authentication credential',
            path: 'web.auth.steps[$index].valueFromEnv ($valueFromEnv)',
            reason: 'environment variable is missing or empty',
          ),
        );
      }
      values[index] = value;
    }
  }
  return Ok(Map.unmodifiable(values));
}

IoFailure _authStepFailure(int index, WebAuthStep step, IoFailure failure) =>
    IoFailure(
      operation:
          'run web authentication step ${index + 1} (${_stepKind(step)})',
      path: step.selector,
      reason: _stepFailureReason(step, failure),
    );

String _stepKind(WebAuthStep step) => switch (step) {
  WebTypeAuthStep() => 'type',
  WebClickAuthStep() => 'click',
  WebWaitAuthStep() => 'wait',
};

String _stepFailureReason(WebAuthStep step, IoFailure failure) {
  if (failure.reason.startsWith('timed out after')) return failure.reason;
  return switch (step) {
    WebTypeAuthStep()
        when failure.reason == 'input did not retain the typed value' =>
      failure.reason,
    WebTypeAuthStep() => 'selected input was unavailable',
    WebClickAuthStep() => 'selected element could not be clicked',
    WebWaitAuthStep() => 'selector did not become ready',
  };
}

String _safeBrowserReason(IoFailure failure, String fallback) =>
    failure.reason.startsWith('timed out after') ? failure.reason : fallback;

bool _sameLocation(Uri requested, Uri actual) =>
    requested.scheme == actual.scheme &&
    requested.host == actual.host &&
    requested.port == actual.port &&
    requested.path == actual.path &&
    requested.query == actual.query &&
    requested.fragment == actual.fragment;

String _routeText(Uri uri) => [
  uri.path,
  if (uri.hasQuery) '?${uri.query}',
  if (uri.hasFragment) '#${uri.fragment}',
].join();
