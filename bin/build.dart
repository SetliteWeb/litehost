import 'dart:io';

import 'package:litehost/src/tool/cli.dart';

/// Builds and packages the app for LiteStore. `--help` for options.
Future<void> main(List<String> args) async =>
    exitCode = await runBuild(args, Directory.current, stdout);
