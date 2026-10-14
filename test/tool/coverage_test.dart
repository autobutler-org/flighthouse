import 'package:test/test.dart';

import '../../tool/coverage.dart';

const _lcov = '''
SF:/repo/lib/src/b.dart
DA:1,1
DA:2,0
LF:4
LH:3
end_of_record
SF:/repo/lib/src/a.dart
DA:1,1
LF:2
LH:2
end_of_record
''';

void main() {
  final files = parseLcov(_lcov, root: '/repo');

  test('parses each record relative to the root, sorted by path', () {
    expect(files, [
      (path: 'lib/src/a.dart', found: 2, hit: 2),
      (path: 'lib/src/b.dart', found: 4, hit: 3),
    ]);
  });

  test('totals lines across files', () {
    expect(total(files), (found: 6, hit: 5));
  });

  test('treats a file with no lines as fully covered', () {
    expect(percent(0, 0), 100);
  });

  test('meets a floor at or below the total', () {
    expect(meetsFloor(files, 83.33), isTrue);
  });

  test('fails a floor above the total', () {
    expect(meetsFloor(files, 83.34), isFalse);
  });

  test('summarizes every file and the total as a markdown table', () {
    expect(
      summary(files, 80),
      contains(
        '| `lib/src/a.dart` | 2 | 2 | 100.00% |\n'
        '| `lib/src/b.dart` | 3 | 4 | 75.00% |\n'
        '| **Total** | 5 | 6 | 83.33% |',
      ),
    );
    expect(summary(files, 80), contains('Total 83.33%, floor 80.00%.'));
  });
}
