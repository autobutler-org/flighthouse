import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../result/failure.dart';
import '../result/result.dart';

final class StaticWebServer {
  const StaticWebServer({required this.origin, required this._server});

  final Uri origin;
  final HttpServer _server;

  Future<Result<void, IoFailure>> close() async {
    try {
      await _server.close(force: true);
      return const Ok(null);
    } on SocketException catch (error) {
      return Err(
        IoFailure(
          operation: 'close web server',
          path: origin.toString(),
          reason: error.osError?.message ?? error.message,
        ),
      );
    }
  }
}

Future<Result<StaticWebServer, IoFailure>> startStaticWebServer({
  required String outputDir,
  required int port,
  required List<String> routes,
}) async {
  try {
    final root = await Directory(outputDir).resolveSymbolicLinks();
    final indexPath = p.join(root, 'index.html');
    if (!await File(indexPath).exists()) {
      return Err(
        IoFailure(
          operation: 'serve web build',
          path: indexPath,
          reason: 'not found',
        ),
      );
    }
    final routePaths = Set<String>.unmodifiable(
      routes.map((route) => Uri.parse(route).path),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    server.listen((request) {
      unawaited(_handleRequest(request, root, indexPath, routePaths));
    });
    return Ok(
      StaticWebServer(
        origin: Uri(
          scheme: 'http',
          host: InternetAddress.loopbackIPv4.address,
          port: server.port,
          path: '/',
        ),
        server: server,
      ),
    );
  } on FileSystemException catch (error) {
    return Err(
      IoFailure(
        operation: 'serve web build',
        path: outputDir,
        reason: error.osError?.message ?? error.message,
      ),
    );
  } on SocketException catch (error) {
    return Err(
      IoFailure(
        operation: 'bind web server',
        path: '127.0.0.1:$port',
        reason: error.osError?.message ?? error.message,
      ),
    );
  } on FormatException catch (error) {
    return Err(
      IoFailure(
        operation: 'serve configured route',
        path: outputDir,
        reason: error.message,
      ),
    );
  }
}

Future<Result<T, IoFailure>> useStaticWebServer<T>({
  required String outputDir,
  required int port,
  required List<String> routes,
  required Future<Result<T, IoFailure>> Function(StaticWebServer server) run,
}) async {
  final started = await startStaticWebServer(
    outputDir: outputDir,
    port: port,
    routes: routes,
  );
  switch (started) {
    case Err(:final error):
      return Err(error);
    case Ok(:final value):
      late Result<T, IoFailure> result;
      late Result<void, IoFailure> closed;
      try {
        result = await run(value);
      } finally {
        closed = await value.close();
      }
      return switch ((result, closed)) {
        (Err(:final error), _) => Err(error),
        (_, Err(:final error)) => Err(error),
        (Ok(:final value), Ok()) => Ok(value),
      };
  }
}

Future<void> _handleRequest(
  HttpRequest request,
  String root,
  String indexPath,
  Set<String> routes,
) async {
  try {
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await request.response.close();
      return;
    }
    final relativePath = _relativePath(request.uri);
    if (relativePath == null) {
      await _notFound(request.response);
      return;
    }
    if (relativePath.isEmpty) {
      await _sendFile(request, indexPath);
      return;
    }
    final candidate = p.normalize(p.join(root, relativePath));
    if (!_inside(root, candidate)) {
      await _notFound(request.response);
      return;
    }
    final file = File(candidate);
    if (await file.exists()) {
      final resolved = await file.resolveSymbolicLinks();
      if (_inside(root, resolved)) {
        await _sendFile(request, resolved);
        return;
      }
    }
    if (routes.contains(request.uri.path) ||
        (_acceptsHtml(request) && p.extension(request.uri.path).isEmpty)) {
      await _sendFile(request, indexPath);
      return;
    }
    await _notFound(request.response);
  } on FileSystemException catch (_) {
    await _serverError(request.response);
  } on HttpException catch (_) {
    await _safeClose(request.response);
  } on SocketException catch (_) {
    await _safeClose(request.response);
  }
}

String? _relativePath(Uri uri) {
  final segments = uri.pathSegments;
  if (segments.any(
    (segment) =>
        segment == '.' ||
        segment == '..' ||
        segment.contains('/') ||
        segment.contains(r'\') ||
        segment.contains('\u0000'),
  )) {
    return null;
  }
  return p.joinAll(segments.where((segment) => segment.isNotEmpty));
}

bool _inside(String root, String path) =>
    p.equals(root, path) || p.isWithin(root, path);

bool _acceptsHtml(HttpRequest request) =>
    request.headers.value(HttpHeaders.acceptHeader)?.contains('text/html') ??
    false;

Future<void> _sendFile(HttpRequest request, String path) async {
  final bytes = await File(path).readAsBytes();
  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.parse(_mimeType(path))
    ..contentLength = bytes.length;
  if (request.method != 'HEAD') {
    request.response.add(bytes);
  }
  await request.response.close();
}

Future<void> _notFound(HttpResponse response) async {
  response
    ..statusCode = HttpStatus.notFound
    ..headers.contentType = ContentType.text
    ..write('Not found');
  await response.close();
}

Future<void> _serverError(HttpResponse response) async {
  response
    ..statusCode = HttpStatus.internalServerError
    ..headers.contentType = ContentType.text
    ..write('Could not read web build output');
  await response.close();
}

Future<void> _safeClose(HttpResponse response) async {
  try {
    await response.close();
  } on HttpException catch (_) {
  } on SocketException catch (_) {}
}

String _mimeType(String path) => switch (p.extension(path).toLowerCase()) {
  '.html' => 'text/html; charset=utf-8',
  '.js' || '.mjs' => 'application/javascript; charset=utf-8',
  '.css' => 'text/css; charset=utf-8',
  '.json' || '.map' => 'application/json; charset=utf-8',
  '.svg' => 'image/svg+xml',
  '.png' => 'image/png',
  '.jpg' || '.jpeg' => 'image/jpeg',
  '.gif' => 'image/gif',
  '.webp' => 'image/webp',
  '.ico' => 'image/x-icon',
  '.wasm' => 'application/wasm',
  '.woff' => 'font/woff',
  '.woff2' => 'font/woff2',
  '.ttf' => 'font/ttf',
  _ => 'application/octet-stream',
};
