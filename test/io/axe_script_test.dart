import 'dart:async';
import 'dart:io';

import 'package:flighthouse/src/config/config.dart';
import 'package:flighthouse/src/io/axe_script.dart';
import 'package:flighthouse/src/result/failure.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _version = '4.11.1';
const _script = '/* axe-core 4.11.1 */';
const _pinned = WebAxeConfig(version: _version, scriptPath: null);
final _url = Uri.parse(
  'https://cdnjs.cloudflare.com/ajax/libs/axe-core/4.11.1/axe.min.js',
);

({String operation, String path, String reason}) _io(
  Result<String, Failure> result,
) => switch (result) {
  Err(error: IoFailure(:final operation, :final path, :final reason)) => (
    operation: operation,
    path: path,
    reason: reason,
  ),
  _ => fail('expected an IoFailure, got $result'),
};

void main() {
  late Directory root;
  late String cacheDir;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('flighthouse-axe-script');
    cacheDir = p.join(root.path, 'cache');
  });

  tearDown(() => root.delete(recursive: true));

  Future<Result<String, Failure>> acquire({
    WebAxeConfig config = _pinned,
    AxeScriptDownload? download,
  }) => acquireAxeScript(
    config: config,
    configBaseDir: root.path,
    cacheDir: cacheDir,
    download: download ?? (_) async => fail('unexpected download'),
  );

  String cachedPath() => p.join(cacheDir, _version, 'axe.min.js');

  test('the default cache lives under .cache/flighthouse/axe', () {
    expect(
      defaultAxeCacheDir(),
      endsWith(p.join('.cache', 'flighthouse', 'axe')),
    );
  });

  group('a local script path', () {
    test('resolves against the config directory', () async {
      File(p.join(root.path, 'vendor', 'axe.js'))
        ..parent.createSync()
        ..writeAsStringSync(_script);
      final result = await acquire(
        config: const WebAxeConfig(
          version: _version,
          scriptPath: 'vendor/../vendor/axe.js',
        ),
      );
      expect(result, const Ok<String, Failure>(_script));
    });

    test('rejects an empty file', () async {
      final path = p.join(root.path, 'axe.js');
      File(path).writeAsStringSync('  \n');
      final result = await acquire(
        config: const WebAxeConfig(version: _version, scriptPath: 'axe.js'),
      );
      expect(_io(result), (
        operation: 'read axe-core script',
        path: path,
        reason: 'file is empty',
      ));
    });

    test('reports a missing file by its resolved path', () async {
      final path = p.join(root.path, 'missing.js');
      final result = await acquire(
        config: WebAxeConfig(version: _version, scriptPath: path),
      );
      expect(_io(result).path, path);
    });
  });

  group('the cache', () {
    test(
      'downloads again when the cached script names another version',
      () async {
        File(cachedPath())
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('/* axe-core 4.10.0 */');
        final downloads = <Uri>[];
        final result = await acquire(
          download: (url) async {
            downloads.add(url);
            return _script;
          },
        );
        expect(result, const Ok<String, Failure>(_script));
        expect(downloads, [_url]);
        expect(File(cachedPath()).readAsStringSync(), _script);
      },
    );

    test('reports a cached script it cannot read', () async {
      File(cachedPath())
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(const [0xff, 0xfe, 0xfd]);
      final result = await acquire();
      expect(_io(result).path, cachedPath());
    });

    test('reports a cache directory it cannot write', () async {
      File(cacheDir).writeAsStringSync('not a directory');
      final result = await acquire(download: (_) async => _script);
      expect(_io(result).path, '${cachedPath()}.partial');
    });

    test('reports a cache entry it cannot replace', () async {
      Directory(p.join(cachedPath(), 'occupied')).createSync(recursive: true);
      final result = await acquire(download: (_) async => _script);
      expect(_io(result).operation, 'cache axe-core');
      expect(_io(result).path, cachedPath());
    });
  });

  group('a failed download', () {
    final cases = <String, (Exception, String)>{
      'a timeout': (TimeoutException('slow'), 'timed out after 30000 ms'),
      'an HTTP error': (HttpException('HTTP 503', uri: _url), 'HTTP 503'),
      'a socket error': (const SocketException('refused'), 'refused'),
      'a TLS error': (const TlsException('bad certificate'), 'bad certificate'),
      'another IO error': (
        const StdinException('closed'),
        'StdinException: closed',
      ),
      'undecodable text': (const FormatException('bad UTF-8'), 'bad UTF-8'),
    };
    for (final MapEntry(key: name, value: (error, reason)) in cases.entries) {
      test('names the URL and the reason for $name', () async {
        final result = await acquire(download: (_) async => throw error);
        expect(_io(result), (
          operation: 'download axe-core',
          path: '$_url',
          reason: reason,
        ));
        expect(File(cachedPath()).existsSync(), isFalse);
      });
    }

    test('rejects a response that is not the pinned script', () async {
      final result = await acquire(download: (_) async => '<html>404</html>');
      expect(_io(result), (
        operation: 'download axe-core',
        path: '$_url',
        reason: 'response did not contain axe-core 4.11.1',
      ));
      expect(File(cachedPath()).existsSync(), isFalse);
    });
  });
}
