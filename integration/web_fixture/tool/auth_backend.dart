import 'dart:convert';
import 'dart:io';
import 'dart:math';

Future<void> main() async {
  final username = Platform.environment['FLIGHTHOUSE_USERNAME'] ?? '';
  final password = Platform.environment['FLIGHTHOUSE_PASSWORD'] ?? '';
  final port = int.parse(Platform.environment['FIXTURE_API_PORT'] ?? '8090');
  final logPath = Platform.environment['FIXTURE_API_LOG'];
  if (username.isEmpty || password.isEmpty) {
    stderr.writeln(
      'FLIGHTHOUSE_USERNAME and FLIGHTHOUSE_PASSWORD are required',
    );
    exitCode = 2;
    return;
  }
  final log = logPath == null ? null : File(logPath).openWrite();
  final tokens = <String>{};
  final random = Random.secure();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('auth backend listening on http://127.0.0.1:$port');
  try {
    await for (final request in server) {
      try {
        await _handle(request, username, password, tokens, random, log);
      } on FormatException {
        await _finish(request, HttpStatus.badRequest, log);
      }
    }
  } finally {
    await log?.close();
  }
}

Future<void> _handle(
  HttpRequest request,
  String username,
  String password,
  Set<String> tokens,
  Random random,
  IOSink? log,
) async {
  _cors(request);
  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
    return;
  }
  switch ((request.method, request.uri.path)) {
    case ('POST', '/login'):
      final body = jsonDecode(await utf8.decodeStream(request)) as Object?;
      final presented = body is Map<String, dynamic> ? body : null;
      final accepted =
          presented != null &&
          presented['username'] == username &&
          presented['password'] == password &&
          username.isNotEmpty;
      if (!accepted) {
        await _finish(request, HttpStatus.unauthorized, log);
        return;
      }
      final token = _token(random);
      tokens.add(token);
      request.response.headers.contentType = ContentType.json;
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({'token': token}));
      await request.response.close();
      await _log(log, 'POST /login 200');
    case ('GET', '/account'):
      final header = request.headers.value(HttpHeaders.authorizationHeader);
      final token = header != null && header.startsWith('Bearer ')
          ? header.substring('Bearer '.length)
          : '';
      final status = tokens.contains(token)
          ? HttpStatus.ok
          : HttpStatus.unauthorized;
      request.response.statusCode = status;
      if (status == HttpStatus.ok) request.response.write('ok');
      await request.response.close();
      await _log(log, 'GET /account $status');
    default:
      await _finish(request, HttpStatus.notFound, log);
  }
}

void _cors(HttpRequest request) {
  final origin = request.headers.value('origin');
  if (origin != null &&
      (origin.startsWith('http://127.0.0.1:') ||
          origin.startsWith('http://localhost:'))) {
    request.response.headers
      ..set('access-control-allow-origin', origin)
      ..set('vary', 'Origin');
  }
  request.response.headers
    ..set('access-control-allow-headers', 'authorization, content-type')
    ..set('access-control-allow-methods', 'GET, POST, OPTIONS');
}

Future<void> _finish(HttpRequest request, int status, IOSink? log) async {
  request.response.statusCode = status;
  await request.response.close();
  await _log(log, '${request.method} ${request.uri.path} $status');
}

Future<void> _log(IOSink? log, String line) async {
  if (log == null) return;
  log.writeln(line);
  await log.flush();
}

String _token(Random random) => [
  for (var index = 0; index < 32; index++)
    random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();
