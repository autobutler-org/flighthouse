import 'package:flighthouse/src/config/config.dart';
import 'package:flighthouse/src/config/hosts.dart';
import 'package:flighthouse/src/config/parse_config.dart';
import 'package:flighthouse/src/result/failure.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:test/test.dart';

const _path = '.flighthouse/hosts.yaml';
const _secret = 'p4ss-9c1e';
const _user = 'audit-user-5d2b';
const _one =
    '''
hosts:
  https://app.example.com:
    username: $_user
    password: $_secret
''';
const _two =
    '''
$_one  http://127.0.0.1:8080:
    username: local
    password: local-pass
''';

List<HostCredentials> _hosts(String text) =>
    (parseHosts(text) as Ok<List<HostCredentials>, ConfigFailure>).value;

ConfigFailure _failed(String text) =>
    (parseHosts(text) as Err<List<HostCredentials>, ConfigFailure>).error;

Config _config(String steps) => (parseConfig('''
app: example
web:
  routes: [/files]
  auth:
    url: /login
    steps:
$steps
''') as Ok<Config, ConfigFailure>).value;

void main() {
  group('parseHosts', () {
    test('reads each host with its credentials, in file order', () {
      expect(_hosts(_two), [
        (url: 'https://app.example.com', username: _user, password: _secret),
        (
          url: 'http://127.0.0.1:8080',
          username: 'local',
          password: 'local-pass',
        ),
      ]);
    });

    test('an empty hosts mapping defines no hosts', () {
      expect(_hosts('hosts:\n'), isEmpty);
      expect(_hosts('hosts: {}\n'), isEmpty);
    });

    test('names the dotted path of a missing field', () {
      final failure = _failed('''
hosts:
  https://app.example.com:
    username: $_user
''');
      expect(failure.keyPath, 'hosts.https://app.example.com.password');
      expect(failure.problem, 'is required');
      expect(failure.location?.line, 3);
    });

    for (final (name, text, keyPath, problem) in [
      ('an empty file', '', 'hosts', 'is required'),
      ('a list at the root', '- a\n', '(root)', 'expected a mapping'),
      ('an unknown root key', 'host: {}\n', 'host', 'unknown key'),
      ('a list of hosts', 'hosts: [a]\n', 'hosts', 'expected a mapping'),
      (
        'a scalar entry',
        'hosts:\n  https://app.example.com: $_secret\n',
        'hosts.https://app.example.com',
        'expected a mapping',
      ),
      (
        'an unknown entry key',
        'hosts:\n  a:\n    username: u\n    password: p\n    token: $_secret\n',
        'hosts.a.token',
        'unknown key',
      ),
      (
        'a numeric password',
        'hosts:\n  a:\n    username: u\n    password: 12345\n',
        'hosts.a.password',
        'expected a non-empty string',
      ),
      (
        'an empty username',
        'hosts:\n  a:\n    username: ""\n    password: $_secret\n',
        'hosts.a.username',
        'expected a non-empty string',
      ),
    ]) {
      test('rejects $name', () {
        final failure = _failed(text);
        expect(failure.keyPath, keyPath);
        expect(failure.problem, contains(problem));
        expect(describe(failure), isNot(contains(_secret)));
      });
    }

    test('invalid YAML gives a location and none of the text', () {
      final failure = _failed(
        'hosts:\n  a:\n    username: [$_user\n    password: $_secret\n',
      );
      expect(failure.keyPath, '(root)');
      expect(failure.problem, 'invalid YAML');
      expect(failure.location, isNotNull);
      expect(describe(failure), isNot(contains(_secret)));
      expect(describe(failure), isNot(contains(_user)));
    });
  });

  group('selectHost', () {
    HostSelection selected(String? text, String? requested) => (selectHost(
      hosts: text == null ? null : _hosts(text),
      requested: requested,
      hostsPath: _path,
    ) as Ok<HostSelection, IoFailure>).value;

    IoFailure refused(String? text, String requested) => (selectHost(
      hosts: text == null ? null : _hosts(text),
      requested: requested,
      hostsPath: _path,
    ) as Err<HostSelection, IoFailure>).error;

    test('--host picks the named entry', () {
      expect(selected(_two, 'http://127.0.0.1:8080').host?.username, 'local');
    });

    test('the only entry is selected without --host', () {
      expect(selected(_one, null).host?.url, 'https://app.example.com');
    });

    test('several entries and no --host select none and list them', () {
      final selection = selected(_two, null);
      expect(selection.host, isNull);
      expect(
        selection.unselectedReason,
        'pass --host; defined hosts: https://app.example.com, '
        'http://127.0.0.1:8080',
      );
    });

    test('no entries and no --host select none', () {
      final selection = selected('hosts:\n', null);
      expect(selection.host, isNull);
      expect(selection.unselectedReason, contains('$_path defines no hosts'));
    });

    test('no file and no --host select none and name the file', () {
      final selection = selected(null, null);
      expect(selection.host, isNull);
      expect(selection.unselectedReason, contains('$_path was not found'));
    });

    test('--host with no file fails naming the file', () {
      final failure = refused(null, 'https://app.example.com');
      expect(failure.path, _path);
      expect(failure.reason, contains('not found'));
    });

    test('--host naming an absent entry lists the defined hosts', () {
      final failure = refused(_two, 'https://other.example.com');
      expect(
        describe(failure),
        'could not select host https://other.example.com: no entry in '
        '$_path; defined hosts: https://app.example.com, '
        'http://127.0.0.1:8080',
      );
      expect(describe(failure), isNot(contains(_secret)));
      expect(describe(failure), isNot(contains(_user)));
    });
  });

  group('needsHosts', () {
    test('is false for a config with no web section', () {
      final config =
          (parseConfig('app: example\n') as Ok<Config, ConfigFailure>).value;
      expect(needsHosts(config), isFalse);
    });

    test('is false when every type step reads the environment', () {
      expect(
        needsHosts(
          _config(
            '      - type: type\n        selector: input\n'
            '        valueFromEnv: SECRET\n'
            '      - type: click\n        selector: button',
          ),
        ),
        isFalse,
      );
    });

    test('is true when a step sets valueFromHost', () {
      expect(
        needsHosts(
          _config(
            '      - type: type\n        selector: input\n'
            '        valueFromHost: password\n        valueFromEnv: SECRET',
          ),
        ),
        isTrue,
      );
    });
  });

  test('hostValueOf reads each value of an entry', () {
    const host = (url: 'https://a', username: 'u', password: 'p');
    expect(
      [for (final value in HostValue.values) hostValueOf(host, value)],
      ['https://a', 'u', 'p'],
    );
  });
}
