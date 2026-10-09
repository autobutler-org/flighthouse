import 'dart:convert';
import 'dart:io';

import 'package:flighthouse/src/io/static_server.dart';
import 'package:flighthouse/src/result/failure.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

typedef Response = ({int status, String? contentType, String body});

Future<Response> request(Uri url, {String accept = '*/*'}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.acceptHeader, accept);
    final response = await request.close();
    return (
      status: response.statusCode,
      contentType: response.headers.contentType?.mimeType,
      body: await utf8.decoder.bind(response).join(),
    );
  } finally {
    client.close(force: true);
  }
}

Future<({int status, String response})> rawRequest(
  Uri origin,
  String target,
) async {
  final socket = await Socket.connect(origin.host, origin.port);
  try {
    socket.write(
      'GET $target HTTP/1.1\r\n'
      'Host: ${origin.host}:${origin.port}\r\n'
      'Connection: close\r\n\r\n',
    );
    await socket.flush();
    final response = await latin1.decoder.bind(socket).join();
    final status = int.parse(response.split(' ').elementAt(1));
    return (status: status, response: response);
  } finally {
    socket.destroy();
  }
}

StaticWebServer started(Result<StaticWebServer, IoFailure> result) =>
    result.fold((server) => server, (failure) => fail('$failure'));

void main() {
  late Directory parent;
  late Directory output;
  StaticWebServer? server;

  setUp(() async {
    parent = await Directory.systemTemp.createTemp('flighthouse-server');
    output = Directory(p.join(parent.path, 'web'))..createSync();
    File(p.join(output.path, 'index.html')).writeAsStringSync('app shell');
    File(p.join(output.path, 'main.js')).writeAsStringSync('main();');
    File(p.join(output.path, 'styles.css')).writeAsStringSync('body {}');
    File(p.join(parent.path, 'secret.txt')).writeAsStringSync('secret');
  });

  tearDown(() async {
    if (server case final running?) {
      await running.close();
    }
    await parent.delete(recursive: true);
  });

  Future<StaticWebServer> serve({
    List<String> routes = const ['/files'],
  }) async {
    final running = started(
      await startStaticWebServer(
        outputDir: output.path,
        port: 0,
        routes: routes,
      ),
    );
    server = running;
    return running;
  }

  test('binds loopback on an OS-assigned port', () async {
    final running = await serve();
    expect(running.origin.host, '127.0.0.1');
    expect(running.origin.port, greaterThan(0));
  });

  test('serves files with MIME types', () async {
    final running = await serve();
    expect(await request(running.origin), (
      status: HttpStatus.ok,
      contentType: 'text/html',
      body: 'app shell',
    ));
    expect(await request(running.origin.resolve('/main.js')), (
      status: HttpStatus.ok,
      contentType: 'application/javascript',
      body: 'main();',
    ));
    expect(await request(running.origin.resolve('/styles.css')), (
      status: HttpStatus.ok,
      contentType: 'text/css',
      body: 'body {}',
    ));
  });

  test('falls back for configured routes including an extension', () async {
    final running = await serve(routes: const ['/files', '/reports/today.pdf']);
    expect(await request(running.origin.resolve('/files')), (
      status: 200,
      contentType: 'text/html',
      body: 'app shell',
    ));
    expect(await request(running.origin.resolve('/reports/today.pdf')), (
      status: 200,
      contentType: 'text/html',
      body: 'app shell',
    ));
  });

  test('falls back for an HTML navigation', () async {
    final running = await serve();
    expect(
      await request(
        running.origin.resolve('/nested/page'),
        accept: 'text/html',
      ),
      (status: 200, contentType: 'text/html', body: 'app shell'),
    );
  });

  test('keeps missing assets missing', () async {
    final running = await serve();
    final response = await request(
      running.origin.resolve('/missing.js'),
      accept: 'text/html',
    );
    expect(response.status, HttpStatus.notFound);
    expect(response.body, isNot(contains('app shell')));
  });

  for (final path in [
    '/..%2Fsecret.txt',
    '/%2e%2e/secret.txt',
    '/%5c..%5csecret.txt',
  ]) {
    test('rejects encoded traversal $path', () async {
      final running = await serve();
      final response = await rawRequest(running.origin, path);
      expect(response.status, isNot(HttpStatus.ok));
      expect(response.response, isNot(contains('\r\nsecret')));
    });
  }

  test('rejects a symlink outside the output directory', () async {
    Link(p.join(output.path, 'linked.txt'))
        .createSync(p.join(parent.path, 'secret.txt'));
    final running = await serve();
    final response = await request(running.origin.resolve('/linked.txt'));
    expect(response.status, HttpStatus.notFound);
    expect(response.body, isNot(contains('secret')));
  });

  test('closes after success', () async {
    late Uri origin;
    final result = await useStaticWebServer<String>(
      outputDir: output.path,
      port: 0,
      routes: const ['/files'],
      run: (running) async {
        origin = running.origin;
        expect((await request(origin)).status, HttpStatus.ok);
        return const Ok('done');
      },
    );
    expect(result, const Ok<String, IoFailure>('done'));
    await expectLater(
      Socket.connect(origin.host, origin.port),
      throwsA(isA<SocketException>()),
    );
  });

  test('force closes a pending connection after failure', () async {
    late Uri origin;
    Socket? socket;
    final result = await useStaticWebServer<void>(
      outputDir: output.path,
      port: 0,
      routes: const ['/files'],
      run: (running) async {
        origin = running.origin;
        socket = await Socket.connect(origin.host, origin.port);
        socket!.write('GET /events HTTP/1.1\r\nHost: ${origin.host}\r\n');
        return const Err(
          IoFailure(operation: 'audit', path: '/files', reason: 'failed'),
        );
      },
    );
    expect(result, isA<Err<void, IoFailure>>());
    socket?.destroy();
    await expectLater(
      Socket.connect(origin.host, origin.port),
      throwsA(isA<SocketException>()),
    );
  });
}
