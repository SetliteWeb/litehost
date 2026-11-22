import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../manifest.dart';

/// Largest bundle SetLiteWeb will install.
const maxBundleBytes = 60 * 1024 * 1024;

class PackagedApp {
  const PackagedApp({
    required this.zip,
    required this.listing,
    required this.sha256,
    required this.sizeBytes,
  });

  final File zip;
  final File listing;
  final String sha256;
  final int sizeBytes;
}

/// The CanvasKit build SetLiteWeb's WebView loads: Chromium's, plus the
/// full one as a fallback. `flutter build web` also ships skwasm, the
/// experimental renderers and debug symbols (several MB) a non-wasm app
/// never fetches.
const _keptEngine = {
  'canvaskit/canvaskit.js',
  'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js',
  'canvaskit/chromium/canvaskit.wasm',
};

bool _unusedEngineFile(String rel) {
  final posix = p.posix.joinAll(p.split(rel));
  if (posix.endsWith('.symbols')) return true;
  if (posix == 'version.json') return true;
  return posix.startsWith('canvaskit/') && !_keptEngine.contains(posix);
}

/// Zips the built site in [site] (index.html at its root) for LiteStore,
/// with litestore.json beside it, and writes the store listing next to the
/// zip. Files are added in a fixed order so the same build gives the same
/// zip and checksum.
PackagedApp packageApp({
  required LiteStoreManifest manifest,
  required Directory site,
  required Directory out,
  String bundleUrlBase = '',
  bool trimFlutterEngine = true,
}) {
  if (!File(p.join(site.path, 'index.html')).existsSync()) {
    throw StateError('${site.path} has no index.html. Build the app first.');
  }
  final files =
      site
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .map((f) => p.relative(f.path, from: site.path))
          .where(
            (rel) =>
                rel != 'litestore.json' &&
                !p.split(rel).first.startsWith('.') &&
                !(trimFlutterEngine && _unusedEngineFile(rel)),
          )
          .toList()
        ..sort();

  final archive = Archive();
  final stamp = DateTime.utc(2000).millisecondsSinceEpoch ~/ 1000;
  for (final rel in files) {
    final bytes = File(p.join(site.path, rel)).readAsBytesSync();
    archive.addFile(
      ArchiveFile(p.posix.joinAll(p.split(rel)), bytes.length, bytes)
        ..lastModTime = stamp,
    );
  }
  final manifestBytes = utf8.encode(
    const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
  );
  archive.addFile(
    ArchiveFile('litestore.json', manifestBytes.length, manifestBytes)
      ..lastModTime = stamp,
  );
  // Nullable in archive 3, not in 4: works with both.
  final List<int>? encoded = ZipEncoder().encode(archive);
  final zipBytes = encoded!;
  if (zipBytes.length > maxBundleBytes) {
    throw StateError(
      'The bundle is ${(zipBytes.length / 1048576).toStringAsFixed(1)} MB; '
      'LiteStore takes up to 60 MB.',
    );
  }

  out.createSync(recursive: true);
  final base = '${manifest.id}-${manifest.version}';
  final zip = File(p.join(out.path, '$base.zip'))..writeAsBytesSync(zipBytes);
  final digest = sha256.convert(zipBytes).toString();
  final listing = File(p.join(out.path, '$base.json'))
    ..writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        ...manifest.toJson(),
        'bundleUrl': bundleUrlBase.isEmpty
            ? ''
            : '${bundleUrlBase.endsWith('/') ? bundleUrlBase : '$bundleUrlBase/'}$base.zip',
        'bundleSha256': digest,
        'sizeBytes': zipBytes.length,
      }),
    );
  return PackagedApp(
    zip: zip,
    listing: listing,
    sha256: digest,
    sizeBytes: zipBytes.length,
  );
}
