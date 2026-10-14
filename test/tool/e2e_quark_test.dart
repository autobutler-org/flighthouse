import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../tool/e2e_quark/png.dart';
import '../../tool/e2e_quark/summary.dart';

void main() {
  group('encodePng', () {
    test('writes a PNG signature, an RGB header, and the pixel rows', () {
      final rgb = Uint8List.fromList([
        255,
        0,
        0,
        0,
        255,
        0,
        0,
        0,
        255,
        9,
        9,
        9,
      ]);
      final png = encodePng(2, 2, rgb);
      expect(png.sublist(0, 8), [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);
      final data = ByteData.sublistView(png);
      expect(String.fromCharCodes(png.sublist(12, 16)), 'IHDR');
      expect(data.getUint32(16), 2);
      expect(data.getUint32(20), 2);
      expect(png[25], 2, reason: 'colour type RGB');
      final idatLength = data.getUint32(33);
      expect(String.fromCharCodes(png.sublist(37, 41)), 'IDAT');
      final raw = ZLibDecoder().convert(png.sublist(41, 41 + idatLength));
      expect(raw, [0, 255, 0, 0, 0, 255, 0, 0, 0, 0, 255, 9, 9, 9]);
    });

    test('rejects a buffer of the wrong size', () {
      expect(() => encodePng(2, 2, Uint8List(3)), throwsArgumentError);
    });

    test('seed photos are deterministic and differ by index', () {
      expect(
        seedPhoto(1, width: 8, height: 8),
        seedPhoto(1, width: 8, height: 8),
      );
      expect(
        seedPhoto(1, width: 8, height: 8),
        isNot(seedPhoto(2, width: 8, height: 8)),
      );
    });
  });

  group('summary', () {
    const versions = {'quark': 'v0.50.1'};
    const paths = {'logs': 'logs'};

    test('a passing run reports scores and gate counts', () {
      final summary = buildSummary(
        results: parseSteps('quark-up\t0\t0.5\nci\t0\t8.0\n'),
        exitCode: 0,
        versions: versions,
        paths: paths,
        report: {
          'scores': {'overall': 0.8},
        },
        ciOutput:
            'quark: overall 80\n0 new, 2 fixed, 166 unchanged\ngate passed\n',
      );
      expect(summary['verdict'], 'passed');
      expect(summary['failedStep'], isNull);
      expect(summary['gate'], {'new': 0, 'fixed': 2, 'unchanged': 166});
      expect(summary['scores'], {'overall': 0.8});
      expect((summary['steps']! as List).length, 2);
    });

    test('a gate failure is a result, not a broken run', () {
      final summary = buildSummary(
        results: parseSteps('collect\t0\t50\nci\t1\t8\n'),
        exitCode: 1,
        versions: versions,
        paths: paths,
      );
      expect(summary['verdict'], 'gate-failed');
      expect(summary['failedStep'], 'ci');
    });

    test('a failed step before ci is broken and named', () {
      final summary = buildSummary(
        results: parseSteps('quark-up\t0\t0.5\nseed\t255\t0.3\n'),
        exitCode: 11,
        versions: versions,
        paths: paths,
      );
      expect(summary['verdict'], 'broken');
      expect(summary['failedStep'], 'seed');
      expect(summary['scores'], isNull);
      expect(summary['gate'], isNull);
    });

    test('parseSteps rejects a malformed line', () {
      expect(() => parseSteps('seed 0 1\n'), throwsFormatException);
    });
  });
}
