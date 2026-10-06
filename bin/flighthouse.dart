import 'dart:io';

import 'package:flighthouse/flighthouse.dart';
import 'package:flighthouse/src/cli/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runCli(arguments, version: packageVersion);
}
