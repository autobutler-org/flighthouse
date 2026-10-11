import 'package:yaml/yaml.dart';

import '../result/failure.dart';
import '../result/result.dart';
import 'config.dart';
import 'yaml_read.dart';

typedef HostCredentials = ({String url, String username, String password});

typedef HostSelection = ({HostCredentials? host, String unselectedReason});

String hostValueOf(HostCredentials host, HostValue value) => switch (value) {
  HostValue.url => host.url,
  HostValue.username => host.username,
  HostValue.password => host.password,
};

bool needsHosts(Config config) =>
    config.web?.auth?.steps.any(
      (step) => step is WebTypeAuthStep && step.valueFromHost != null,
    ) ??
    false;

Parsed<({String username, String password})> _readEntry(
  YamlNode node,
  String keyPath,
) =>
    readMapping(
      node,
      keyPath,
      const ['username', 'password'],
      required: const ['username', 'password'],
    ).flatMap(
      (fields) => switch ((
        requiredField(fields, 'username', keyPath, readNonEmptyString),
        requiredField(fields, 'password', keyPath, readNonEmptyString),
      )) {
        (Ok(value: final username), Ok(value: final password)) => Ok((
          username: username,
          password: password,
        )),
        (final username, final password) => Err(
          firstConfigError([username, password]),
        ),
      },
    );

Parsed<List<HostCredentials>> parseHosts(String text) {
  final YamlNode root;
  try {
    root = loadYamlNode(text);
  } on YamlException catch (exception) {
    return Err(
      ConfigFailure(
        keyPath: '(root)',
        problem: 'invalid YAML',
        location: switch (exception.span) {
          final span? => (
            line: span.start.line + 1,
            column: span.start.column + 1,
          ),
          null => null,
        },
      ),
    );
  }
  return readMapping(root, '', const ['hosts'], required: const ['hosts'])
      .flatMap(
        (mapping) =>
            requiredField(mapping, 'hosts', '', openMappingReader(_readEntry)),
      )
      .map(
        (entries) => List.unmodifiable([
          for (final MapEntry(key: url, value: entry) in entries.entries)
            (url: url, username: entry.username, password: entry.password),
        ]),
      );
}

Result<HostSelection, IoFailure> selectHost({
  required List<HostCredentials>? hosts,
  required String? requested,
  required String hostsPath,
}) {
  if (hosts == null) {
    return requested == null
        ? Ok((
            host: null,
            unselectedReason:
                '$hostsPath was not found; create it with an entry under hosts',
          ))
        : Err(
            IoFailure(
              operation: 'read',
              path: hostsPath,
              reason:
                  'not found; --host needs an entry under hosts in this file',
            ),
          );
  }
  final defined = hosts.isEmpty
      ? '$hostsPath defines no hosts; add an entry under hosts'
      : 'defined hosts: ${hosts.map((host) => host.url).join(', ')}';
  if (requested == null) {
    return Ok(switch (hosts) {
      [final only] => (host: only, unselectedReason: ''),
      _ => (host: null, unselectedReason: 'pass --host; $defined'),
    });
  }
  return switch (hosts.where((host) => host.url == requested).firstOrNull) {
    final host? => Ok((host: host, unselectedReason: '')),
    null => Err(
      IoFailure(
        operation: 'select host',
        path: requested,
        reason: 'no entry in $hostsPath; $defined',
      ),
    ),
  };
}
