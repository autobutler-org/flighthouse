import 'package:yaml/yaml.dart';

import '../result/failure.dart';
import '../result/result.dart';

typedef Parsed<T> = Result<T, ConfigFailure>;

typedef YamlReader<T> = Parsed<T> Function(YamlNode node, String keyPath);

SourceLocation locationOf(YamlNode node) =>
    (line: node.span.start.line + 1, column: node.span.start.column + 1);

Parsed<T> invalid<T>(YamlNode node, String keyPath, String problem) => Err(
  ConfigFailure(
    keyPath: keyPath.isEmpty ? '(root)' : keyPath,
    problem: problem,
    location: locationOf(node),
  ),
);

String childPath(String keyPath, String key) =>
    keyPath.isEmpty ? key : '$keyPath.$key';

bool isEmptyNode(YamlNode node) => node is YamlScalar && node.value == null;

ConfigFailure firstConfigError(List<Result<Object?, ConfigFailure>> results) =>
    results.whereType<Err<Object?, ConfigFailure>>().first.error;

Parsed<Map<String, YamlNode>> readMapping(
  YamlNode node,
  String keyPath,
  List<String> keys, {
  List<String> required = const [],
}) {
  if (isEmptyNode(node)) {
    return required.isEmpty
        ? const Ok({})
        : invalid(node, childPath(keyPath, required.first), 'is required');
  }
  if (node is! YamlMap) {
    return invalid(node, keyPath, 'expected a mapping');
  }
  final entries = [
    for (final MapEntry(:key, :value) in node.nodes.entries)
      (key as YamlNode, value),
  ];
  for (final (keyNode, _) in entries) {
    final key = keyNode.value;
    if (key is! String || !keys.contains(key)) {
      return invalid(
        keyNode,
        childPath(keyPath, '$key'),
        'unknown key; expected one of ${keys.join(', ')}',
      );
    }
  }
  final present = {
    for (final (keyNode, value) in entries) keyNode.value as String: value,
  };
  final missing = required.where((key) => !present.containsKey(key));
  if (missing.isNotEmpty) {
    return invalid(node, childPath(keyPath, missing.first), 'is required');
  }
  return Ok(Map.unmodifiable(present));
}

Parsed<T> optionalField<T>(
  Map<String, YamlNode> mapping,
  String key,
  String keyPath,
  YamlReader<T> read,
  T fallback,
) => switch (mapping[key]) {
  final node? when !isEmptyNode(node) => read(node, childPath(keyPath, key)),
  _ => Ok(fallback),
};

Parsed<T> requiredField<T>(
  Map<String, YamlNode> mapping,
  String key,
  String keyPath,
  YamlReader<T> read,
) => read(mapping[key]!, childPath(keyPath, key));

Parsed<String> readNonEmptyString(YamlNode node, String keyPath) =>
    switch (node) {
      YamlScalar(value: final String text) when text.trim().isNotEmpty => Ok(
        text,
      ),
      _ => invalid(node, keyPath, 'expected a non-empty string'),
    };

Parsed<double> readNonNegative(YamlNode node, String keyPath) => switch (node) {
  YamlScalar(value: final num number) when number.isFinite && number >= 0 => Ok(
    number.toDouble(),
  ),
  _ => invalid(node, keyPath, 'expected a number of at least 0'),
};

Parsed<double> readPositive(YamlNode node, String keyPath) => switch (node) {
  YamlScalar(value: final num number) when number.isFinite && number > 0 => Ok(
    number.toDouble(),
  ),
  _ => invalid(node, keyPath, 'expected a number greater than 0'),
};

Parsed<double> readUnitInterval(YamlNode node, String keyPath) =>
    switch (node) {
      YamlScalar(value: final num number) when number >= 0 && number <= 1 => Ok(
        number.toDouble(),
      ),
      _ => invalid(node, keyPath, 'expected a number from 0 to 1'),
    };

YamlReader<T> enumReader<T>(List<T> values, String Function(T value) idOf) =>
    (node, keyPath) => switch (values.where(
      (value) => node is YamlScalar && idOf(value) == node.value,
    )) {
      final matches when matches.isNotEmpty => Ok(matches.first),
      _ => invalid(
        node,
        keyPath,
        'expected one of ${values.map(idOf).join(', ')}',
      ),
    };

YamlReader<List<T>> listReader<T>(YamlReader<T> readItem) =>
    (node, keyPath) => switch (node) {
      YamlList(:final nodes) => traverse(
        List.generate(nodes.length, (index) => index),
        (index) => readItem(nodes[index], '$keyPath[$index]'),
      ),
      _ => invalid(node, keyPath, 'expected a list'),
    };

YamlReader<Map<K, V>> keyedReader<K, V>(
  List<K> keys,
  String Function(K key) idOf,
  YamlReader<V> readValue,
) =>
    (node, keyPath) =>
        readMapping(node, keyPath, keys.map(idOf).toList(growable: false))
            .flatMap(
              (mapping) => traverse(
                keys.where((key) => mapping.containsKey(idOf(key))),
                (key) => requiredField(
                  mapping,
                  idOf(key),
                  keyPath,
                  readValue,
                ).map((value) => MapEntry(key, value)),
              ),
            )
            .map((entries) => Map<K, V>.unmodifiable(Map.fromEntries(entries)));

YamlReader<Map<String, V>> openMappingReader<V>(YamlReader<V> readValue) =>
    (node, keyPath) {
      if (isEmptyNode(node)) {
        return const Ok({});
      }
      if (node is! YamlMap) {
        return invalid(node, keyPath, 'expected a mapping');
      }
      return traverse<
            MapEntry<dynamic, YamlNode>,
            MapEntry<String, V>,
            ConfigFailure
          >(node.nodes.entries, (entry) {
            final keyNode = entry.key as YamlNode;
            return switch (keyNode.value) {
              final String key when key.isNotEmpty => readValue(
                entry.value,
                childPath(keyPath, key),
              ).map((value) => MapEntry(key, value)),
              _ => invalid<MapEntry<String, V>>(
                keyNode,
                keyPath,
                'expected a non-empty string key',
              ),
            };
          })
          .map(
            (entries) => Map<String, V>.unmodifiable(Map.fromEntries(entries)),
          );
    };
