import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../result/failure.dart';
import '../result/result.dart';
import 'files.dart';

const _downloadTimeout = Duration(seconds: 30);

final _versionPattern = RegExp(
  r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.]+)?$',
);

typedef AxeScriptDownload = Future<String> Function(Uri url);

String defaultAxeCacheDir() {
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  return p.join(home, '.cache', 'flighthouse', 'axe');
}

Future<String> downloadAxeScript(Uri url) async {
  final client = HttpClient();
  try {
    client.connectionTimeout = _downloadTimeout;
    final request = await client.getUrl(url).timeout(_downloadTimeout);
    request.followRedirects = true;
    request.headers.set(HttpHeaders.userAgentHeader, 'flighthouse');
    final response = await request.close().timeout(_downloadTimeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().timeout(_downloadTimeout);
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    return await response
        .transform(utf8.decoder)
        .join()
        .timeout(_downloadTimeout);
  } finally {
    client.close(force: true);
  }
}

Future<Result<String, Failure>> acquireAxeScript({
  required WebAxeConfig config,
  required String configBaseDir,
  required String cacheDir,
  AxeScriptDownload download = downloadAxeScript,
}) async {
  if (config.scriptPath case final scriptPath?) {
    return _readLocal(configBaseDir, scriptPath);
  }
  final version = config.version;
  if (!_versionPattern.hasMatch(version)) {
    return Err(
      IoFailure(
        operation: 'download axe-core',
        path: version,
        reason: 'version must be an axe-core release such as 4.11.1',
      ),
    );
  }
  final cached = p.join(cacheDir, version, 'axe.min.js');
  if (await fileExists(cached)) {
    switch (await readText(cached)) {
      case Ok(value: final text) when _scriptMatches(text, version):
        return Ok(text);
      case Ok():
        break;
      case Err(:final error):
        return Err(error);
    }
  }
  final url = _axeCoreUrl(version);
  final String text;
  try {
    text = await download(url).timeout(_downloadTimeout);
  } on TimeoutException {
    return Err(_downloadFailure(url, _timeoutReason));
  } on HttpException catch (error) {
    if (error.message == 'HTTP ${HttpStatus.notFound}') {
      return Err(
        MissingToolFailure(
          tool: 'axe-core $version',
          installHint:
              'set web.axe.scriptPath to a local axe.min.js or choose a '
              'published axe-core version',
        ),
      );
    }
    return Err(_downloadFailure(url, error.message));
  } on SocketException catch (error) {
    return Err(_downloadFailure(url, error.message));
  } on TlsException catch (error) {
    return Err(_downloadFailure(url, error.message));
  } on IOException catch (error) {
    return Err(_downloadFailure(url, error.toString()));
  } on FormatException catch (error) {
    return Err(_downloadFailure(url, error.message));
  }
  if (!_scriptMatches(text, version)) {
    return Err(
      _downloadFailure(url, 'response did not contain axe-core $version'),
    );
  }
  final stored = await _store(cached, text);
  return switch (stored) {
    Err(:final error) => Err(error),
    Ok() => Ok(text),
  };
}

Future<Result<String, IoFailure>> _readLocal(
  String configBaseDir,
  String scriptPath,
) async {
  final resolved = p.normalize(
    p.isAbsolute(scriptPath) ? scriptPath : p.join(configBaseDir, scriptPath),
  );
  switch (await readText(resolved)) {
    case Ok(value: final text) when text.trim().isEmpty:
      return Err(
        IoFailure(
          operation: 'read axe-core script',
          path: resolved,
          reason: 'file is empty',
        ),
      );
    case Ok(value: final text):
      return Ok(text);
    case Err(:final error):
      return Err(error);
  }
}

Uri _axeCoreUrl(String version) =>
    Uri.https('cdnjs.cloudflare.com', 'ajax/libs/axe-core/$version/axe.min.js');

bool _scriptMatches(String text, String version) =>
    text.contains('axe') && text.contains(version);

IoFailure _downloadFailure(Uri url, String reason) => IoFailure(
  operation: 'download axe-core',
  path: url.toString(),
  reason: reason,
);

String get _timeoutReason =>
    'timed out after ${_downloadTimeout.inMilliseconds} ms';

Future<Result<void, IoFailure>> _store(String path, String contents) async {
  final partial = '$path.partial';
  switch (await writeText(partial, contents)) {
    case Err(:final error):
      return Err(error);
    case Ok():
      try {
        await File(partial).rename(path);
        return const Ok(null);
      } on FileSystemException catch (error) {
        return Err(
          IoFailure(
            operation: 'cache axe-core',
            path: path,
            reason: error.osError?.message ?? error.message,
          ),
        );
      }
  }
}
