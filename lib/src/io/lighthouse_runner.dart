import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../model/json_decode.dart';
import '../result/failure.dart';
import '../result/result.dart';
import 'browser.dart';
import 'files.dart';
import 'required_tools.dart';
import 'web_build.dart';

const _scoredCategories = <String>[
  'performance',
  'accessibility',
  'best-practices',
];

typedef _Accepted = ({String name, String contents});

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.run(executable, arguments, workingDirectory: workingDirectory);

Future<Result<List<String>, Failure>> runLighthouseRoutes({
  required WebLighthouseConfig lighthouse,
  required WebViewportConfig viewport,
  required BrowserSession browser,
  required Uri origin,
  required List<String> routes,
  required String outputDir,
  ProcessRun run = _runProcess,
}) async {
  final accepted = <_Accepted>[];
  for (final route in routes) {
    switch (await _collectRoute(
      lighthouse: lighthouse,
      viewport: viewport,
      browser: browser,
      origin: origin,
      route: route,
      run: run,
    )) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        accepted.add(value);
    }
  }
  return _publish(outputDir, accepted);
}

Future<Result<_Accepted, Failure>> _collectRoute({
  required WebLighthouseConfig lighthouse,
  required WebViewportConfig viewport,
  required BrowserSession browser,
  required Uri origin,
  required String route,
  required ProcessRun run,
}) async {
  final requested = origin.resolve(route);
  final arguments = _arguments(
    command: lighthouse.command,
    url: requested,
    port: browser.info.debuggingPort,
    viewport: viewport,
  );
  final started = await _start(lighthouse.command.first, arguments, run);
  switch (started) {
    case Err(:final error):
      return Err(error);
    case Ok(:final value):
      final stdout = '${value.stdout}';
      return switch ((_decode(route, stdout), value.exitCode)) {
        (Ok(value: {'runtimeError': final Object error?}), _) => Err(
          _runtimeFailure(route, error),
        ),
        (_, final exitCode) when exitCode != 0 => Err(
          ProcessFailure(
            command: _commandText(lighthouse.command.first, arguments),
            exitCode: exitCode,
            stderr: '${value.stderr}',
          ),
        ),
        (Err(:final error), _) => Err(error),
        (Ok(value: final json), _) => _validate(
          route: route,
          requested: requested,
          json: json,
        ).map((_) => (name: _artifactName(route), contents: stdout)),
      };
  }
}

Future<Result<ProcessResult, Failure>> _start(
  String executable,
  List<String> arguments,
  ProcessRun run,
) async {
  try {
    return Ok(await run(executable, arguments));
  } on ProcessException {
    return const Err(missingLighthouse);
  }
}

List<String> _arguments({
  required List<String> command,
  required Uri url,
  required int port,
  required WebViewportConfig viewport,
}) => [
  ...command.skip(1),
  url.toString(),
  '--hostname=127.0.0.1',
  '--port=$port',
  '--output=json',
  '--disable-storage-reset',
  '--form-factor=desktop',
  '--screenEmulation.mobile=false',
  '--screenEmulation.width=${viewport.width}',
  '--screenEmulation.height=${viewport.height}',
  '--screenEmulation.deviceScaleFactor=${_scale(viewport.deviceScaleFactor)}',
];

String _scale(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

String _commandText(String executable, List<String> arguments) =>
    [executable, ...arguments].join(' ');

String _artifactName(String route) =>
    '${sha256.convert(utf8.encode(route))}.json';

Result<Object?, Failure> _decode(String route, String stdout) {
  try {
    return Ok(jsonDecode(stdout));
  } on FormatException catch (error) {
    return Err(_rejected(route, 'not valid JSON: ${error.message}'));
  }
}

Result<void, Failure> _validate({
  required String route,
  required Uri requested,
  required Object? json,
}) => switch (_checkStructure(json)) {
  Err(:final error) => Err(_rejected(route, describe(error))),
  Ok(:final value) => _matchingRoute(route, requested, value),
};

AdapterFailure _rejected(String route, String problem) =>
    AdapterFailure(tool: 'lighthouse', artifactPath: route, problem: problem);

AdapterFailure _runtimeFailure(String route, Object error) =>
    _rejected(route, switch (error) {
      {'code': 'TARGET_CRASHED'} =>
        "Chrome's renderer crashed while Lighthouse loaded the page "
            '(TARGET_CRASHED). Check free memory and system load on this '
            "machine, and whether its sandbox policy lets Chrome's renderer "
            'run (docs/adr/0026-linux-chrome-launch.md), then run again',
      _ => 'Lighthouse reported a runtime error: ${_runtimeErrorText(error)}',
    });

String _runtimeErrorText(Object error) => switch (error) {
  final Map<String, Object?> details =>
    '${_label(details['code'], 'UNKNOWN')}: ${_label(details['message'], '')}',
  _ => describeJson(error),
};

String _label(Object? value, String fallback) =>
    value is String && value.isNotEmpty ? value : fallback;

Result<String, SchemaFailure> _checkStructure(Object? json) =>
    switch (decodeAnyObject(json, rootPath)) {
      Err(:final error) => Err(error),
      Ok(:final value) => _readReport(value),
    };

Result<String, SchemaFailure> _readReport(
  JsonObject object,
) => readField(object, 'lighthouseVersion', rootPath, decodeNonEmptyString)
    .flatMap(
      (_) => readField(
        object,
        'finalDisplayedUrl',
        rootPath,
        decodeNonEmptyString,
      ),
    )
    .flatMap(
      (displayed) =>
          readField(
            object,
            'categories',
            rootPath,
            _decodeScoredCategories,
          ).flatMap(
            (categories) =>
                readField(object, 'audits', rootPath, decodeAnyObject).flatMap(
                  (audits) =>
                      _checkAudits(categories, audits).map((_) => displayed),
                ),
          ),
    );

Decoded<Map<String, List<String>>> _decodeScoredCategories(
  Object? json,
  String path,
) => switch (decodeAnyObject(json, path)) {
  Err(:final error) => Err(error),
  Ok(:final value) => _readScoredCategories(value, path),
};

Decoded<Map<String, List<String>>> _readScoredCategories(
  JsonObject object,
  String path,
) {
  final categories = <String, List<String>>{};
  for (final name in _scoredCategories) {
    switch (readField(object, name, path, _decodeCategoryRefs)) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        categories[name] = value;
    }
  }
  return Ok(Map.unmodifiable(categories));
}

Decoded<List<String>> _decodeCategoryRefs(Object? json, String path) =>
    switch (decodeAnyObject(json, path)) {
      Err(:final error) => Err(error),
      Ok(:final value) => readField(
        value,
        'auditRefs',
        path,
        listDecoder(_decodeAuditRefId),
      ),
    };

Decoded<String> _decodeAuditRefId(Object? json, String path) =>
    switch (decodeAnyObject(json, path)) {
      Err(:final error) => Err(error),
      Ok(:final value) => _readAuditRefId(value, path),
    };

Decoded<String> _readAuditRefId(JsonObject object, String path) =>
    readField(object, 'id', path, decodeNonEmptyString).flatMap(
      (id) =>
          readField(object, 'weight', path, decodeNonNegative).map((_) => id),
    );

Result<void, SchemaFailure> _checkAudits(
  Map<String, List<String>> categories,
  JsonObject audits,
) {
  for (final ids in categories.values) {
    for (final id in ids) {
      final audit = readField(audits, id, r'$.audits', _decodeAuditShape);
      if (audit case Err(:final error)) return Err(error);
    }
  }
  return const Ok(null);
}

Decoded<void> _decodeAuditShape(Object? json, String path) =>
    switch (decodeAnyObject(json, path)) {
      Err(:final error) => Err(error),
      Ok(:final value) => _readAuditShape(value, path),
    };

Decoded<void> _readAuditShape(JsonObject object, String path) {
  final id = readField(object, 'id', path, decodeNonEmptyString);
  if (id case Err(:final error)) return Err(error);
  final title = readField(object, 'title', path, decodeString);
  if (title case Err(:final error)) return Err(error);
  final score = readField(object, 'score', path, nullable(decodeUnitInterval));
  if (score case Err(:final error)) return Err(error);
  final mode = readField(
    object,
    'scoreDisplayMode',
    path,
    decodeNonEmptyString,
  );
  if (mode case Err(:final error)) return Err(error);
  return const Ok(null);
}

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
    _rejected(route, 'final displayed URL was $displayed; requested $route'),
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
        operation: 'prepare lighthouse output',
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
