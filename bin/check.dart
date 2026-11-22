import 'dart:io';

import 'package:litehost/src/tool/cli.dart';

/// Checks that the features lib/ uses are declared in litestore.yaml.
void main() => exitCode = runCheck(Directory.current, stdout);
