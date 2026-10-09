import 'dart:async';
import 'dart:convert';

import 'package:flighthouse/src/result/failure.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:path/path.dart' as p;

import 'required_tools.dart';

const chromeNoSandboxSwitch = 'FLIGHTHOUSE_CI_CHROME_NO_SANDBOX';

bool chromeSandboxDisabled(Map<String, String> environment) =>
    environment[chromeNoSandboxSwitch] == 'true';

String chromeCacheDirectory({
  String? home,
  String? userProfile,
  required String fallback,
}) {
  final root = _nonEmpty(home) ?? _nonEmpty(userProfile) ?? fallback;
  return p.join(root, '.cache', 'flighthouse', 'chrome');
}

String? _nonEmpty(String? value) =>
    value == null || value.trim().isEmpty ? null : value;

typedef AcquireBrowser = Future<BrowserInstallation> Function(String cachePath);
typedef LaunchBrowser = Future<BrowserBindings> Function(
  BrowserInstallation installation,
  BrowserViewport viewport,
  Duration timeout,
);

final class BrowserInstallation {
  const BrowserInstallation({
    required this.cachePath,
    required this.executablePath,
    required this.version,
  });

  final String cachePath;
  final String executablePath;
  final String version;
}

final class BrowserViewport {
  const BrowserViewport({
    required this.width,
    required this.height,
    required this.deviceScaleFactor,
  });

  final int width;
  final int height;
  final double deviceScaleFactor;
}

final class BrowserInfo {
  const BrowserInfo({
    required this.installation,
    required this.browserVersion,
    required this.debuggingPort,
  });

  final BrowserInstallation installation;
  final String browserVersion;
  final int debuggingPort;
}

final class BrowserBindings {
  const BrowserBindings({
    required this.info,
    required this.navigate,
    required this.waitForFirstFrame,
    required this.currentUrl,
    required this.waitForSelector,
    required this.click,
    required this.focus,
    required this.waitForFocus,
    required this.settleInput,
    required this.replaceInput,
    required this.readInput,
    required this.evaluate,
    required this.close,
  });

  final BrowserInfo info;
  final Future<void> Function(Uri url, Duration timeout) navigate;
  final Future<void> Function(Duration timeout) waitForFirstFrame;
  final String Function() currentUrl;
  final Future<void> Function(String selector, Duration timeout)
  waitForSelector;
  final Future<void> Function(String selector) click;
  final Future<void> Function(String selector) focus;
  final Future<void> Function(String selector, Duration timeout) waitForFocus;
  final Future<void> Function() settleInput;
  final Future<void> Function(String selector, String value) replaceInput;
  final Future<String?> Function(String selector) readInput;
  final Future<Object?> Function(String script, List<Object?> arguments)
  evaluate;
  final Future<void> Function() close;
}

final class BrowserSession {
  const BrowserSession(this._bindings);

  final BrowserBindings _bindings;

  BrowserInfo get info => _bindings.info;

  Future<Result<Uri, IoFailure>> open(Uri url, {required Duration timeout}) =>
      _attempt(
        operation: 'open browser page',
        target: url.toString(),
        timeout: timeout,
        action: () async {
          await _bindings.navigate(url, timeout);
          await _bindings.waitForFirstFrame(timeout);
          return Uri.parse(_bindings.currentUrl());
        },
      );

  Future<Result<void, IoFailure>> waitForSelector(
    String selector, {
    required Duration timeout,
  }) => _attempt(
    operation: 'wait for browser selector',
    target: selector,
    timeout: timeout,
    action: () => _bindings.waitForSelector(selector, timeout),
  );

  Future<Result<void, IoFailure>> click(
    String selector, {
    required Duration timeout,
  }) => _attempt(
    operation: 'click browser selector',
    target: selector,
    timeout: timeout,
    action: () => _bindings.click(selector),
  );

  Future<Result<void, IoFailure>> type(
    String selector,
    String value, {
    required Duration timeout,
  }) async {
    final result = await _attempt(
      operation: 'type into browser selector',
      target: selector,
      timeout: timeout,
      action: () async {
        await _bindings.waitForSelector(selector, timeout);
        await _bindings.focus(selector);
        await _bindings.waitForFocus(selector, timeout);
        await _bindings.settleInput();
        await _bindings.replaceInput(selector, value);
        await _bindings.settleInput();
        return _bindings.readInput(selector);
      },
    );
    return switch (result) {
      Err(:final error) => Err(error),
      Ok(value: final actual) when actual == value => const Ok(null),
      Ok() => Err(
        IoFailure(
          operation: 'type into browser selector',
          path: selector,
          reason: 'input did not retain the typed value',
        ),
      ),
    };
  }

  Future<Result<Object?, IoFailure>> evaluateJson(
    String script, {
    List<Object?> arguments = const [],
    required Duration timeout,
  }) => _attempt(
    operation: 'evaluate browser script',
    target: 'browser page',
    timeout: timeout,
    action: () async {
      final value = await _bindings.evaluate(script, arguments);
      return jsonDecode(jsonEncode(value));
    },
  );

  Future<Result<Uri, IoFailure>> location({required Duration timeout}) =>
      _attempt(
        operation: 'read browser location',
        target: 'browser page',
        timeout: timeout,
        action: () async => Uri.parse(_bindings.currentUrl()),
      );

  Future<Result<void, IoFailure>> close({required Duration timeout}) =>
      _attempt(
        operation: 'close browser',
        target: info.installation.executablePath,
        timeout: timeout,
        action: _bindings.close,
      );
}

Future<Result<BrowserSession, IoFailure>> launchBrowser({
  required String cachePath,
  required BrowserViewport viewport,
  required Duration acquireTimeout,
  required Duration launchTimeout,
  required AcquireBrowser acquire,
  required LaunchBrowser launch,
}) async {
  late BrowserInstallation installation;
  try {
    installation = await acquire(cachePath).timeout(acquireTimeout);
  } on TimeoutException catch (_) {
    return Err(
      IoFailure(
        operation: 'acquire Chrome into',
        path: cachePath,
        reason: 'timed out after ${_durationText(acquireTimeout)}',
      ),
    );
  } on Exception catch (error) {
    return Err(
      IoFailure(
        operation: 'acquire Chrome into',
        path: cachePath,
        reason: chromeAcquireHint(error.toString()),
      ),
    );
  }
  if (installation.version.trim().isEmpty) {
    return Err(
      IoFailure(
        operation: 'read the Chrome version of',
        path: installation.executablePath,
        reason: 'no version was reported; remove $cachePath and run again',
      ),
    );
  }

  final pendingLaunch = launch(installation, viewport, launchTimeout);
  try {
    final bindings = await pendingLaunch.timeout(launchTimeout);
    return Ok(BrowserSession(bindings));
  } on TimeoutException catch (_) {
    unawaited(_closeLateLaunch(pendingLaunch));
    return Err(
      IoFailure(
        operation: 'launch Chrome',
        path: installation.executablePath,
        reason: 'timed out after ${_durationText(launchTimeout)}',
      ),
    );
  } on Exception catch (error) {
    return Err(
      IoFailure(
        operation: 'launch Chrome',
        path: installation.executablePath,
        reason: _launchFailureReason(error),
      ),
    );
  }
}

Future<void> _closeLateLaunch(Future<BrowserBindings> pendingLaunch) async {
  try {
    final bindings = await pendingLaunch;
    await bindings.close();
  } on Exception catch (_) {}
}

Future<Result<T, IoFailure>> useBrowser<T>({
  required Future<Result<BrowserSession, IoFailure>> Function() launch,
  required Future<Result<T, IoFailure>> Function(BrowserSession browser) run,
  required Duration closeTimeout,
}) async {
  final launched = await launch();
  switch (launched) {
    case Err(:final error):
      return Err(error);
    case Ok(:final value):
      late Result<T, IoFailure> result;
      late Result<void, IoFailure> closed;
      try {
        result = await run(value);
      } finally {
        closed = await value.close(timeout: closeTimeout);
      }
      return switch ((result, closed)) {
        (Err(:final error), _) => Err(error),
        (_, Err(:final error)) => Err(error),
        (Ok(:final value), Ok()) => Ok(value),
      };
  }
}

Future<Result<T, IoFailure>> _attempt<T>({
  required String operation,
  required String target,
  required Duration timeout,
  required Future<T> Function() action,
}) async {
  try {
    return Ok(await action().timeout(timeout));
  } on TimeoutException catch (_) {
    return Err(
      IoFailure(
        operation: operation,
        path: target,
        reason: 'timed out after ${_durationText(timeout)}',
      ),
    );
  } on JsonUnsupportedObjectError catch (error) {
    return Err(
      IoFailure(operation: operation, path: target, reason: error.toString()),
    );
  } on Exception catch (error) {
    return Err(
      IoFailure(operation: operation, path: target, reason: error.toString()),
    );
  }
}

String _launchFailureReason(Exception error) {
  final detail = error.toString();
  if (detail.toLowerCase().contains('no usable sandbox')) {
    return 'Chrome could not start with its sandbox enabled. Configure a '
        'supported Chrome sandbox for this host; flighthouse does not disable '
        'the sandbox automatically.';
  }
  return chromeAcquireHint(detail);
}

String _durationText(Duration duration) => '${duration.inMilliseconds} ms';
