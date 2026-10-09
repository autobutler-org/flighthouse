import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../result/failure.dart';
import '../result/result.dart';
import 'browser.dart';
import 'static_server.dart';
import 'web_auth.dart';
import 'web_build.dart';

typedef WebBrowserLauncher = Future<Result<BrowserSession, IoFailure>> Function(
  BrowserViewport viewport,
);

typedef WebRouteCollector<T> = Future<Result<T, Failure>> Function(
  BrowserSession browser,
  Uri origin,
  List<String> routes,
);

Future<Result<T, Failure>> runWebCollection<T>({
  required String configBaseDir,
  required WebConfig config,
  required Map<String, String> environment,
  required ProcessRun runProcess,
  required WebBrowserLauncher launch,
  required WebRouteCollector<T> collect,
  required Duration closeTimeout,
}) async {
  final projectDir = p.isAbsolute(config.projectDir)
      ? p.normalize(config.projectDir)
      : p.normalize(p.join(configBaseDir, config.projectDir));
  final built = await buildWebApp(
    projectDir: projectDir,
    config: config.build,
    run: runProcess,
  );
  switch (built) {
    case Err(:final error):
      return Err(error);
    case Ok(:final value):
      final started = await startStaticWebServer(
        outputDir: value.outputDir,
        port: config.serve.port,
        routes: config.routes,
      );
      switch (started) {
        case Err(:final error):
          return Err(error);
        case Ok(:final value):
          final result = await _runWithBrowser(
            server: value,
            config: config,
            environment: environment,
            launch: launch,
            collect: collect,
            closeTimeout: closeTimeout,
          );
          final closed = await value.close();
          return _withCleanup(result, closed);
      }
  }
}

Future<Result<T, Failure>> _runWithBrowser<T>({
  required StaticWebServer server,
  required WebConfig config,
  required Map<String, String> environment,
  required WebBrowserLauncher launch,
  required WebRouteCollector<T> collect,
  required Duration closeTimeout,
}) async {
  final launched = await launch(
    BrowserViewport(
      width: config.viewport.width,
      height: config.viewport.height,
      deviceScaleFactor: config.viewport.deviceScaleFactor,
    ),
  );
  switch (launched) {
    case Err(:final error):
      return Err(error);
    case Ok(:final value):
      final result = await _prepareAndCollect(
        browser: value,
        origin: server.origin,
        config: config,
        environment: environment,
        collect: collect,
      );
      final closed = await value.close(timeout: closeTimeout);
      return _withCleanup(result, closed);
  }
}

Future<Result<T, Failure>> _prepareAndCollect<T>({
  required BrowserSession browser,
  required Uri origin,
  required WebConfig config,
  required Map<String, String> environment,
  required WebRouteCollector<T> collect,
}) async {
  final firstRoute = config.routes.first;
  final prepared = switch (config.auth) {
    null => await openReadyWebRoute(
      browser: browser,
      origin: origin,
      route: firstRoute,
      readiness: config.readiness,
    ),
    final auth => await authenticateWeb(
      browser: browser,
      origin: origin,
      config: auth,
      protectedRoute: firstRoute,
      readiness: config.readiness,
      environment: environment,
    ),
  };
  return switch (prepared) {
    Err(:final error) => Err(error),
    Ok() => collect(browser, origin, config.routes),
  };
}

Result<T, Failure> _withCleanup<T>(
  Result<T, Failure> result,
  Result<void, IoFailure> cleanup,
) => switch ((result, cleanup)) {
  (Err(:final error), _) => Err(error),
  (_, Err(:final error)) => Err(error),
  (Ok(:final value), Ok()) => Ok(value),
};
