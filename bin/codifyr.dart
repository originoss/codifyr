import 'dart:io';

import 'package:codifyr/src/command_runner.dart';

Future<void> main(List<String> args) async {
  await _flushThenExit(await CodifyrCommandRunner().run(args));
}
Future<void> _flushThenExit(int status) {
  return Future.wait<void>([stdout.close(), stderr.close()])
      .then<void>((_) => exit(status));
}
