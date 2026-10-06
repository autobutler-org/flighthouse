import 'dart:io';

import 'package:test/test.dart';

const shellDirectories = ['lib/src/io/', 'lib/src/cli/'];
const shellOnlyImports = ['dart:io', 'dart:isolate', 'package:puppeteer/'];
const flutterImports = [
  'package:flutter/',
  'package:flutter_test/',
  'package:integration_test/',
];

final importPattern = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

List<File> dartFilesUnder(String directory) {
  final root = Directory(directory);
  if (!root.existsSync()) {
    return const [];
  }
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
}

String relativePath(File file) => file.path.replaceAll(r'\', '/');

Iterable<String> importsOf(File file) => importPattern
    .allMatches(file.readAsStringSync())
    .map((match) => match.group(1)!);

bool isShell(String path) => shellDirectories.any(path.startsWith);

List<String> violations(
  Iterable<File> files,
  bool Function(String path, String uri) forbidden,
) => [
  for (final file in files)
    for (final uri in importsOf(file))
      if (forbidden(relativePath(file), uri))
        '${relativePath(file)} imports $uri',
];

void main() {
  final libraryFiles = dartFilesUnder('lib');

  test('only io and cli touch the outside world', () {
    expect(
      violations(
        libraryFiles,
        (path, uri) => !isShell(path) && shellOnlyImports.any(uri.startsWith),
      ),
      isEmpty,
    );
  });

  test('nothing under lib depends on Flutter', () {
    expect(
      violations(libraryFiles, (_, uri) => flutterImports.any(uri.startsWith)),
      isEmpty,
    );
  });

  test('the import scanner sees imports', () {
    expect(
      importPattern
          .allMatches(
            "import 'dart:io';\nexport \"package:flutter/widgets.dart\";",
          )
          .length,
      2,
    );
  });
}
