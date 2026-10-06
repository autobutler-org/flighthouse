import 'dart:io';

import 'package:path/path.dart' as p;

import '../result/failure.dart';
import '../result/result.dart';

IoFailure _failure(String operation, String path, FileSystemException error) =>
    IoFailure(
      operation: operation,
      path: path,
      reason: error.osError?.message ?? error.message,
    );

Future<Result<String, IoFailure>> readText(String path) async {
  try {
    return Ok(await File(path).readAsString());
  } on FileSystemException catch (error) {
    return Err(_failure('read', path, error));
  }
}

Future<Result<String, IoFailure>> writeText(
  String path,
  String contents,
) async {
  try {
    await File(path).parent.create(recursive: true);
    await File(path).writeAsString(contents);
    return Ok(path);
  } on FileSystemException catch (error) {
    return Err(_failure('write', path, error));
  }
}

Future<bool> fileExists(String path) => File(path).exists();

Future<Result<List<String>, IoFailure>> listJsonFiles(String directory) async {
  try {
    final entries = await Directory(directory).list().toList();
    return Ok(
      List.unmodifiable(
        entries
            .whereType<File>()
            .map((file) => file.path)
            .where((path) => p.extension(path) == '.json')
            .toList()
          ..sort(),
      ),
    );
  } on FileSystemException catch (error) {
    return Err(_failure('list', directory, error));
  }
}

Future<Result<List<String>, IoFailure>> replaceJsonFiles({
  required String from,
  required String to,
}) async {
  final sources = await listJsonFiles(from);
  switch (sources) {
    case Err(:final error):
      return Err(error);
    case Ok(value: final paths):
      try {
        final target = Directory(to);
        if (await target.exists()) {
          await target.delete(recursive: true);
        }
        await target.create(recursive: true);
        return Ok(
          List.unmodifiable([
            for (final path in paths)
              (await File(path).copy(p.join(to, p.basename(path)))).path,
          ]),
        );
      } on FileSystemException catch (error) {
        return Err(_failure('copy into', to, error));
      }
  }
}
