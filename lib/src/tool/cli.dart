import 'dart:io';

import 'package:path/path.dart' as p;

import '../manifest.dart';
import 'check.dart';
import 'package.dart';

const _manifestFile = 'litestore.yaml';

/// Reads and validates litestore.yaml in [root]. Prints problems; returns
/// null when there are errors.
LiteStoreManifest? loadManifest(Directory root, IOSink log) {
  final f = File(p.join(root.path, _manifestFile));
  if (!f.existsSync()) {
    log.writeln(
      'No $_manifestFile in ${root.path}. Create one, e.g.:\n'
      '  id: com.example.myapp\n  name: My App\n  version: 1.0.0\n'
      '  requires: []\n  optional: [storage]',
    );
    return null;
  }
  final LiteStoreManifest m;
  try {
    m = LiteStoreManifest.parse(f.readAsStringSync());
  } on FormatException catch (e) {
    log.writeln('$_manifestFile: ${e.message}');
    return null;
  }
  for (final w in m.warnings()) {
    log.writeln('warning: $w');
  }
  final errors = m.errors();
  for (final e in errors) {
    log.writeln('error: $e');
  }
  return errors.isEmpty ? m : null;
}

/// `dart run litehost:check`. Exit code 1 if code (Dart in lib/, JavaScript
/// in web/) uses undeclared features.
int runCheck(Directory root, IOSink log) {
  final m = loadManifest(root, log);
  if (m == null) return 1;
  // lib/ for Dart apps; web/ for apps written in JavaScript.
  final result = checkUses(m, [
    ...scanUses(Directory(p.join(root.path, 'lib'))),
    ...scanUses(Directory(p.join(root.path, 'web'))),
  ]);
  for (final u in result.undeclared) {
    log.writeln(
      'error: ${p.relative(u.file, from: root.path)}:${u.line} '
      'uses "${u.feature.id}", which $_manifestFile doesn\'t declare; '
      'the host will refuse it.',
    );
  }
  for (final id in result.unused) {
    log.writeln('note: "$id" is declared but not used in lib/ or web/.');
  }
  if (result.ok) log.writeln('${m.name} ${m.version}: features OK.');
  return result.ok ? 0 : 1;
}

/// `dart run litehost:build [options]`.
Future<int> runBuild(List<String> args, Directory root, IOSink log) async {
  String? opt(String name) {
    final i = args.indexOf('--$name');
    if (i >= 0 && i + 1 < args.length) return args[i + 1];
    for (final a in args) {
      if (a.startsWith('--$name=')) return a.substring(name.length + 3);
    }
    return null;
  }

  if (args.contains('-h') || args.contains('--help')) {
    log.writeln('''
Builds a LiteStore bundle: dist/litestore/<id>-<version>.zip and .json.

  --dir <folder>        Package an already built site (any framework)
                        instead of running `flutter build web`.
  --base-href </path/>  Base path the app is served from (default /).
  --bundle-url <url>    Where the zip will be hosted, for the listing.
  --out <folder>        Output folder (default build/litestore).
  --target <file>       Entry point for flutter build (default lib/main.dart).
  --wasm                Build with WebAssembly (Flutter; keeps every engine
                        file).
  --no-trim             Keep all of Flutter's engine files and symbols.
  --cdn                 Load Flutter's engine from Google's CDN instead of
                        bundling it (smaller, but needs internet to open).
  --skip-check          Don't check feature use against litestore.yaml.''');
    return 0;
  }

  final m = loadManifest(root, log);
  if (m == null) return 1;
  if (!args.contains('--skip-check') && runCheck(root, log) != 0) return 1;

  final dir = opt('dir');
  final Directory site;
  if (dir != null) {
    site = Directory(p.isAbsolute(dir) ? dir : p.join(root.path, dir));
  } else {
    final cmd = [
      'build',
      'web',
      '--release',
      '--base-href',
      opt('base-href') ?? '/',
      if (!args.contains('--cdn')) '--no-web-resources-cdn',
      if (args.contains('--wasm')) '--wasm',
      // SetLiteWeb stores and serves the bundle itself: no offline worker.
      '--pwa-strategy=none',
      if (opt('target') case final t?) ...['--target', t],
    ];
    log.writeln('flutter ${cmd.join(' ')}');
    final proc = await Process.start(
      'flutter',
      cmd,
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    if (await proc.exitCode != 0) {
      log.writeln('error: flutter build web failed.');
      return 1;
    }
    site = Directory(p.join(root.path, 'build', 'web'));
  }

  try {
    final out = opt('out');
    final app = packageApp(
      manifest: m,
      site: site,
      out: Directory(
        out == null
            ? p.join(root.path, 'build', 'litestore')
            : (p.isAbsolute(out) ? out : p.join(root.path, out)),
      ),
      bundleUrlBase: opt('bundle-url') ?? '',
      trimFlutterEngine:
          !args.contains('--wasm') && !args.contains('--no-trim'),
    );
    log
      ..writeln('Bundle:  ${app.zip.path}')
      ..writeln('Listing: ${app.listing.path}')
      ..writeln('Size:    ${(app.sizeBytes / 1024).toStringAsFixed(0)} KB')
      ..writeln('SHA-256: ${app.sha256}');
    return 0;
  } on StateError catch (e) {
    log.writeln('error: ${e.message}');
    return 1;
  }
}
