import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef FileCoverage = ({String path, int found, int hit});

List<FileCoverage> parseLcov(String lcov, {required String root}) {
  final files = <FileCoverage>[];
  String? path;
  var found = 0;
  var hit = 0;
  for (final line in const LineSplitter().convert(lcov)) {
    if (line.startsWith('SF:')) {
      path = p.relative(line.substring(3), from: root).replaceAll(r'\', '/');
      found = 0;
      hit = 0;
    } else if (line.startsWith('LF:')) {
      found = int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      hit = int.parse(line.substring(3));
    } else if (line == 'end_of_record' && path != null) {
      files.add((path: path, found: found, hit: hit));
      path = null;
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return List.unmodifiable(files);
}

double percent(int hit, int found) => found == 0 ? 100 : 100 * hit / found;

({int found, int hit}) total(Iterable<FileCoverage> files) => (
  found: files.fold(0, (sum, file) => sum + file.found),
  hit: files.fold(0, (sum, file) => sum + file.hit),
);

String summary(List<FileCoverage> files, double floor) {
  final sum = total(files);
  String row(String name, int hit, int found) =>
      '| $name | $hit | $found | ${percent(hit, found).toStringAsFixed(2)}% |';
  return [
    '## Line coverage of lib/',
    '',
    'Total ${percent(sum.hit, sum.found).toStringAsFixed(2)}%, '
        'floor ${floor.toStringAsFixed(2)}%.',
    '',
    '| File | Hit | Lines | Coverage |',
    '| --- | ---: | ---: | ---: |',
    for (final file in files) row('`${file.path}`', file.hit, file.found),
    row('**Total**', sum.hit, sum.found),
    '',
  ].join('\n');
}

bool meetsFloor(List<FileCoverage> files, double floor) {
  final sum = total(files);
  return percent(sum.hit, sum.found) >= floor;
}

void main(List<String> arguments) {
  if (arguments.length != 3) {
    stderr.writeln(
      'usage: dart run tool/coverage.dart <lcov.info> <floor file> <summary.md>',
    );
    exit(64);
  }
  final [lcovPath, floorPath, summaryPath] = arguments;
  final lcov = File(lcovPath);
  if (!lcov.existsSync()) {
    stderr.writeln('$lcovPath is missing. Run make test/coverage first.');
    exit(1);
  }
  final floor = double.tryParse(File(floorPath).readAsStringSync().trim());
  if (floor == null) {
    stderr.writeln('$floorPath must hold one number, the percent floor.');
    exit(1);
  }
  final files = parseLcov(
    lcov.readAsStringSync(),
    root: Directory.current.path,
  );
  final report = summary(files, floor);
  File(summaryPath).writeAsStringSync(report);
  stdout.write(report);
  if (!meetsFloor(files, floor)) {
    stderr.writeln(
      'Line coverage of lib/ fell below the floor in $floorPath. '
      'Add tests, or lower the floor in the same PR with a reason.',
    );
    exit(1);
  }
}
