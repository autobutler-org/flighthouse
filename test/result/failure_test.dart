import 'package:flighthouse/flighthouse.dart';
import 'package:flighthouse/src/result/failure.dart' show firstLine;
import 'package:test/test.dart';

void main() {
  group('describe', () {
    test('config failure without a location', () {
      expect(
        describe(
          const ConfigFailure(
            keyPath: 'gate.minSeverity',
            problem: 'unknown severity "huge"',
          ),
        ),
        'config: gate.minSeverity: unknown severity "huge"',
      );
    });

    test('config failure with a location', () {
      expect(
        describe(
          const ConfigFailure(
            keyPath: 'scoring.weights',
            problem: 'weights sum to 0.9, not 1',
            location: (line: 12, column: 3),
          ),
        ),
        'config: scoring.weights (line 12, column 3): weights sum to 0.9, not 1',
      );
    });

    test('schema failure names the JSON path', () {
      expect(
        describe(
          const SchemaFailure(
            jsonPath: r'$.findings[3].severity',
            expected: 'one of critical, serious, moderate, minor, info',
            found: '"high"',
          ),
        ),
        r'$.findings[3].severity: expected one of critical, serious, moderate, minor, info, found "high"',
      );
    });

    test('adapter failure keeps only the first line of the problem', () {
      expect(
        describe(
          const AdapterFailure(
            tool: 'lighthouse',
            artifactPath: 'raw/lighthouse/login.json',
            problem: 'unsupported lighthouseVersion 9.0.0\nstack trace',
          ),
        ),
        'lighthouse: raw/lighthouse/login.json: unsupported lighthouseVersion 9.0.0',
      );
    });

    test('missing tool says how to install it', () {
      expect(
        describe(
          const MissingToolFailure(
            tool: 'Lighthouse',
            installHint: 'npm install -g lighthouse',
          ),
        ),
        'Lighthouse not found. Install it with: npm install -g lighthouse',
      );
    });

    test('io failure', () {
      expect(
        describe(
          const IoFailure(
            operation: 'read',
            path: 'flighthouse.yaml',
            reason: 'No such file or directory\n(OS Error: errno = 2)',
          ),
        ),
        'could not read flighthouse.yaml: No such file or directory',
      );
    });

    test('process failure with stderr', () {
      expect(
        describe(
          const ProcessFailure(
            command: 'lighthouse http://localhost:8080/login',
            exitCode: 1,
            stderr: '\n  Runtime error encountered: Chrome not found  \nmore',
          ),
        ),
        'lighthouse http://localhost:8080/login exited with code 1: Runtime error encountered: Chrome not found',
      );
    });

    test('process failure with empty stderr', () {
      expect(
        describe(
          const ProcessFailure(
            command: 'flutter build web',
            exitCode: 2,
            stderr: '  \n',
          ),
        ),
        'flutter build web exited with code 2',
      );
    });

    test('baseline failure says how to fix it', () {
      expect(
        describe(
          const BaselineFailure(
            path: 'flighthouse-baseline.json',
            problem: 'it uses fingerprint scheme v0, this run uses v1',
          ),
        ),
        'baseline flighthouse-baseline.json: it uses fingerprint scheme v0, '
        'this run uses v1. Run: flighthouse baseline --update',
      );
    });

    test('toString is the description', () {
      const failure = MissingToolFailure(
        tool: 'Chrome',
        installHint: 'see https://www.google.com/chrome/',
      );
      expect(failure.toString(), describe(failure));
    });
  });

  group('firstLine', () {
    test('skips blank lines and trims', () {
      expect(firstLine('\n \n  hello  \nworld'), 'hello');
    });

    test('is empty for blank text', () {
      expect(firstLine(' \n\t\n'), '');
    });
  });
}
