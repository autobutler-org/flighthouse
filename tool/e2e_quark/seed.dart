import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'png.dart';

/// Seeds a Quark household idempotently through Quark's real auth flow.
///
/// Since Quark v0.47 a client never sends a password: `quark auth-key`
/// derives the key from the password and the salt `GET /auth/salt` returns,
/// which works before the account exists. So the owner is created with
/// `POST /auth/setup`, no browser needed.
///
/// Environment: QUARK_URL, QUARK_BIN, CREDENTIALS (an env file it creates
/// once, mode 0600), STATE (uploaded-file list), SEED_SCALE (photo count).
Future<void> main() async {
  final env = Platform.environment;
  final url = _required(env, 'QUARK_URL');
  final quarkBin = _required(env, 'QUARK_BIN');
  final credentials = File(_required(env, 'CREDENTIALS'));
  final state = File(_required(env, 'STATE'));
  final scale = int.parse(env['SEED_SCALE'] ?? '6');

  final creds = await _loadOrCreateCredentials(credentials, url);
  final user = creds['FLIGHTHOUSE_USERNAME']!;
  final password = creds['FLIGHTHOUSE_PASSWORD']!;
  final client = HttpClient();
  try {
    final status = await _json(client, 'GET', '$url/api/v0/auth/status');
    if (status['setup'] != true) {
      final authKey = await _authKey(quarkBin, url, user, password);
      final recoveryKey = await _authKey(
        quarkBin,
        url,
        user,
        'flighthouse e2e recovery $password',
        recovery: true,
      );
      await _json(
        client,
        'POST',
        '$url/api/v0/auth/setup',
        body: {
          'username': user,
          'authKey': authKey,
          'recoveryKey': recoveryKey,
        },
      );
      stdout.writeln('created owner $user');
    }
    final login = await _json(
      client,
      'POST',
      '$url/api/v0/auth/login',
      body: {
        'username': user,
        'authKey': await _authKey(quarkBin, url, user, password),
      },
    );
    final token = (login['data'] is Map
        ? login['data'] as Map
        : login)['token'];
    if (token is! String) throw StateError('login returned no token');

    final done = state.existsSync()
        ? state.readAsLinesSync().toSet()
        : <String>{};
    final sink = state.openWrite(mode: FileMode.append);
    var uploaded = 0;
    Future<void> upload(String folder, String name, List<int> bytes) async {
      final key = '$folder/$name';
      if (done.contains(key)) return;
      await _upload(
        client,
        '$url/api/v0/files/upload/users/$user/$folder',
        token,
        name,
        bytes,
      );
      sink.writeln(key);
      uploaded++;
    }

    for (var i = 1; i <= scale; i++) {
      await upload(
        'Photos',
        'photo-${i.toString().padLeft(5, '0')}.png',
        seedPhoto(i),
      );
    }
    await upload(
      'Documents',
      'inventory.csv',
      utf8.encode('item,qty\nwidget,3\ngadget,7\n'),
    );
    await upload(
      'Documents',
      'readme.txt',
      utf8.encode('flighthouse e2e seed\n'),
    );
    await sink.close();

    final photos = await _json(
      client,
      'GET',
      '$url/api/v0/photos',
      headers: {'Authorization': 'Bearer $token'},
    );
    final total = (photos['data'] is Map
        ? photos['data'] as Map
        : photos)['total'];
    stdout.writeln(
      'seeded: $uploaded new uploads, photos total $total (SEED_SCALE=$scale)',
    );
  } finally {
    client.close();
  }
}

String _required(Map<String, String> env, String name) {
  final value = env[name];
  if (value == null || value.isEmpty) {
    stderr.writeln('seed: $name is not set');
    exit(2);
  }
  return value;
}

Future<Map<String, String>> _loadOrCreateCredentials(
  File file,
  String url,
) async {
  if (!file.existsSync()) {
    final random = Random.secure();
    final password = List.generate(
      24,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      'FLIGHTHOUSE_QUARK_NAME=Local\n'
      'FLIGHTHOUSE_QUARK_HOST=$url\n'
      'FLIGHTHOUSE_USERNAME=flighthouse-owner\n'
      'FLIGHTHOUSE_PASSWORD=$password\n',
    );
    await Process.run('chmod', ['600', file.path]);
  }
  return {
    for (final line in file.readAsLinesSync())
      if (line.contains('='))
        line.substring(0, line.indexOf('=')): line.substring(
          line.indexOf('=') + 1,
        ),
  };
}

Future<String> _authKey(
  String quarkBin,
  String url,
  String user,
  String secret, {
  bool recovery = false,
}) async {
  final process = await Process.start(quarkBin, [
    'auth-key',
    '--host',
    url,
    '-u',
    user,
    if (recovery) '--recovery',
  ]);
  process.stdin.write(secret);
  await process.stdin.close();
  final out = await process.stdout.transform(utf8.decoder).join();
  final err = await process.stderr.transform(utf8.decoder).join();
  if (await process.exitCode != 0) {
    throw StateError('quark auth-key failed: ${err.trim()}');
  }
  return out.trim();
}

Future<Map<String, Object?>> _json(
  HttpClient client,
  String method,
  String url, {
  Map<String, Object?>? body,
  Map<String, String> headers = const {},
}) async {
  final request = await client.openUrl(method, Uri.parse(url));
  headers.forEach(request.headers.set);
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  if (response.statusCode >= 300) {
    throw HttpException('$method $url -> ${response.statusCode}');
  }
  return (jsonDecode(text) as Map).cast<String, Object?>();
}

Future<void> _upload(
  HttpClient client,
  String url,
  String token,
  String name,
  List<int> bytes,
) async {
  const boundary = 'flighthouse-e2e-boundary';
  final request = await client.postUrl(Uri.parse(url));
  request.headers
    ..set('Authorization', 'Bearer $token')
    ..set('Content-Type', 'multipart/form-data; boundary=$boundary');
  request
    ..add(
      utf8.encode(
        '--$boundary\r\nContent-Disposition: form-data; name="files"; filename="$name"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n',
      ),
    )
    ..add(bytes)
    ..add(utf8.encode('\r\n--$boundary--\r\n'));
  final response = await request.close();
  await response.drain<void>();
  if (response.statusCode >= 300) {
    throw HttpException('upload $name -> ${response.statusCode}');
  }
}
