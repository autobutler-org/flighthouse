import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../model/json_decode.dart';
import '../result/failure.dart';
import '../result/result.dart';
import 'axe_script.dart';
import 'browser.dart';
import 'files.dart';
import 'web_auth.dart';

const _runAxe = r'''
async (source) => {
  const parent = document.head || document.documentElement;
  if (document.querySelector('script[data-flighthouse-axe]') === null) {
    const element = document.createElement('script');
    element.setAttribute('data-flighthouse-axe', 'true');
    element.textContent = source;
    parent.appendChild(element);
  }
  if (typeof axe === 'undefined' || typeof axe.run !== 'function') {
    throw new Error('axe-core did not load');
  }
  const result = await axe.run(document, { ancestry: true });
  return JSON.stringify(result);
}
''';

const _resultGroups = <String>[
  'violations',
  'passes',
  'incomplete',
  'inapplicable',
];

typedef _Accepted = ({String name, String contents});

Future<Result<List<String>, Failure>> runAxeRoutes({
  required WebAxeConfig axe,
  required String configBaseDir,
  required WebReadinessConfig readiness,
  required BrowserSession browser,
  required Uri origin,
  required List<String> routes,
  required String outputDir,
  required String cacheDir,
  AxeScriptDownload download = downloadAxeScript,
}) async {
  final acquired = await acquireAxeScript(
    config: axe,
    configBaseDir: configBaseDir,
    cacheDir: cacheDir,
    download: download,
  );
  switch (acquired) {
    case Err(:final error):
      return Err(error);
    case Ok(value: final script):
      final accepted = <_Accepted>[];
      for (final route in routes) {
        switch (await _collectRoute(
          script: script,
          readiness: readiness,
          browser: browser,
          origin: origin,
          route: route,
        )) {
          case Err(:final error):
            return Err(error);
          case Ok(:final value):
            accepted.add(value);
        }
      }
      return _publish(outputDir, accepted);
  }
}

Future<Result<_Accepted, Failure>> _collectRoute({
  required String script,
  required WebReadinessConfig readiness,
  required BrowserSession browser,
  required Uri origin,
  required String route,
}) async {
  final requested = origin.resolve(route);
  final ready = await openReadyWebRoute(
    browser: browser,
    origin: origin,
    route: route,
    readiness: readiness,
  );
  switch (ready) {
    case Err(:final error):
      return Err(error);
    case Ok():
      final evaluated = await browser.evaluateJson(
        _runAxe,
        arguments: [script],
        timeout: readiness.timeout,
      );
      switch (evaluated) {
        case Err(:final error):
          return Err(_runFailure(route, error));
        case Ok(value: final String raw):
          return _validate(
            route: route,
            requested: requested,
            raw: raw,
          ).map((contents) => (name: _artifactName(route), contents: contents));
        case Ok(:final value):
          return Err(
            AdapterFailure(
              tool: 'axe',
              artifactPath: route,
              problem:
                  'axe-core returned ${describeJson(value)} instead of '
                  'JSON text',
            ),
          );
      }
  }
}

IoFailure _runFailure(String route, IoFailure failure) =>
    IoFailure(operation: 'run axe-core', path: route, reason: failure.reason);

String _artifactName(String route) =>
    '${sha256.convert(utf8.encode(route))}.json';

Result<String, Failure> _validate({
  required String route,
  required Uri requested,
  required String raw,
}) {
  final Object? json;
  try {
    json = jsonDecode(raw);
  } on FormatException catch (error) {
    return Err(_rejected(route, 'not valid JSON: ${error.message}'));
  }
  switch (_checkStructure(json)) {
    case Err(:final error):
      return Err(_rejected(route, describe(error)));
    case Ok(value: final displayed):
      final matched = _matchingRoute(route, requested, displayed);
      return switch (matched) {
        Err(:final error) => Err(error),
        Ok() => Ok(raw),
      };
  }
}

AdapterFailure _rejected(String route, String problem) =>
    AdapterFailure(tool: 'axe', artifactPath: route, problem: problem);

Result<String, SchemaFailure> _checkStructure(Object? json) =>
    switch (decodeAnyObject(json, rootPath)) {
      Err(:final error) => Err(error),
      Ok(:final value) => _readResult(value),
    };

Result<String, SchemaFailure> _readResult(JsonObject object) =>
    readField(object, 'testEngine', rootPath, _decodeEngine).flatMap(
      (_) => readField(
        object,
        'url',
        rootPath,
        decodeNonEmptyString,
      ).flatMap((url) => _readGroups(object).map((_) => url)),
    );

Decoded<void> _decodeEngine(Object? json, String path) =>
    switch (decodeAnyObject(json, path)) {
      Err(:final error) => Err(error),
      Ok(:final value) => _readEngine(value, path),
    };

Decoded<void> _readEngine(JsonObject object, String path) {
  final name = readField(object, 'name', path, decodeNonEmptyString);
  if (name case Err(:final error)) return Err(error);
  final version = readField(object, 'version', path, decodeNonEmptyString);
  if (version case Err(:final error)) return Err(error);
  return const Ok(null);
}

Decoded<void> _readGroups(JsonObject object) {
  for (final name in _resultGroups) {
    final group = readField(object, name, rootPath, _decodeResultGroup);
    if (group case Err(:final error)) return Err(error);
  }
  return const Ok(null);
}

Decoded<void> _decodeResultGroup(Object? json, String path) => switch (json) {
  final List<Object?> _ => const Ok(null),
  _ => mismatch(path, 'a list', json),
};

Result<void, Failure> _matchingRoute(
  String route,
  Uri requested,
  String displayed,
) {
  final actual = Uri.tryParse(displayed);
  if (actual != null && _sameLocation(requested, actual)) {
    return const Ok(null);
  }
  return Err(
    _rejected(route, 'displayed URL was $displayed; requested $route'),
  );
}

bool _sameLocation(Uri requested, Uri actual) =>
    requested.scheme == actual.scheme &&
    requested.host == actual.host &&
    requested.port == actual.port &&
    requested.path == actual.path &&
    requested.query == actual.query &&
    requested.fragment == actual.fragment;

Future<Result<List<String>, Failure>> _publish(
  String outputDir,
  List<_Accepted> accepted,
) async {
  final directory = Directory(outputDir);
  try {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);
  } on FileSystemException catch (error) {
    return Err(
      IoFailure(
        operation: 'prepare axe output',
        path: outputDir,
        reason: error.osError?.message ?? error.message,
      ),
    );
  }
  final written = <String>[];
  for (final result in accepted) {
    switch (await writeText(p.join(outputDir, result.name), result.contents)) {
      case Ok(:final value):
        written.add(value);
      case Err(:final error):
        return Err(error);
    }
  }
  return Ok(List.unmodifiable(written));
}
