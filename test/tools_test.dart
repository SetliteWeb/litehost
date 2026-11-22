import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:litehost/manifest.dart';
import 'package:litehost/src/tool/check.dart';
import 'package:litehost/src/tool/cli.dart';
import 'package:litehost/src/tool/package.dart';
import 'package:test/test.dart';

const _yaml = '''
id: com.example.duka
name: Duka
version: 1.2.0
summary: Order from shops near you.
requires: [location]
optional: [scanner, profile.name, storage, bluetooth@2]
''';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('litehost'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('manifest', () {
    test('parses', () {
      final m = LiteStoreManifest.parse(_yaml);
      expect(m.errors(), isEmpty);
      expect(m.declaredIds, containsAll(['location', 'scanner', 'bluetooth']));
      expect(m.toJson()['optional'], contains('bluetooth@2'));
    });

    test('reports problems', () {
      final m = LiteStoreManifest.parse(
        'id: "bad id"\nname: ""\nversion: one\n'
        'requires: [teleport]\noptional: [teleport]',
      );
      expect(
        m.errors().join('\n'),
        allOf(
          contains('id'),
          contains('name'),
          contains('version'),
          contains('both'),
        ),
      );
      expect(m.warnings().join('\n'), contains('unknown'));
    });
  });

  test('check finds undeclared and unused features', () {
    final lib = Directory('${tmp.path}/lib')..createSync();
    File('${lib.path}/main.dart').writeAsStringSync('''
final a = LiteHost.location.get();
final b = LiteHost.wifi.get();
final c = LiteHost.profile.get({ProfileField.name, ProfileField.phone});
final d = LiteHost.clipboard.write('x');
final e = ProfileField.values;
// LiteHost.camera.request();  (comment: ignored)
''');
    final r = checkUses(LiteStoreManifest.parse(_yaml), scanUses(lib));
    expect(
      {for (final u in r.undeclared) u.feature.id},
      {'wifi', 'profile.phone', 'profile.email', 'profile.photo', 'clipboard.write'},
    );
    expect(r.unused, containsAll(['scanner', 'storage', 'bluetooth']));
    expect(r.ok, isFalse);
  });

  test('check reads JavaScript too, and tells wifi.get from wifi.signal', () {
    final web = Directory('${tmp.path}/web')..createSync();
    File('${web.path}/index.html').writeAsStringSync('''
<script>
if (window.LiteHost) LiteHost.haptics({ style: 'light' });
const s = await LiteHost.wifi.signal();
// LiteHost.scanner.scan()  (comment: ignored)
</script>''');
    final uses = scanUses(web);
    expect({for (final u in uses) u.feature.id}, {'haptics', 'wifi.signal'});
    final r = checkUses(
      LiteStoreManifest.parse(
        'id: a.b\nname: A\nversion: 1.0.0\nrequires: [wifi.signal]\noptional: [haptics]',
      ),
      uses,
    );
    expect(r.ok, isTrue);
    expect(r.unused, isEmpty);
  });

  test('check knows the 1.2 and 1.3 features', () {
    final lib = Directory('${tmp.path}/lib2')..createSync();
    File('${lib.path}/main.dart').writeAsStringSync('''
LiteHost.torch.set(true);
LiteHost.nfc.read();
LiteHost.sensors.watch(SensorType.light);
LiteHost.gestures.watch();
LiteHost.wifi.enable();
LiteHost.bluetooth.enable();
LiteHost.device.battery();
LiteHost.location.track();
LiteHost.phone.call('1');
LiteHost.sms.otp();
LiteHost.screen.capture();
LiteHost.pip.enter();
''');
    expect(
      {for (final u in scanUses(lib)) u.feature.id},
      {
        'torch',
        'nfc',
        'sensors',
        'gestures',
        'wifi.enable',
        'bluetooth',
        'device.info',
        'location.background',
        'phone.call',
        'sms.otp',
        'screen.capture',
        'pip',
      },
    );
  });

  test('package leaves out engine files a WebView never loads', () {
    final site = Directory('${tmp.path}/site')..createSync();
    for (final f in [
      'index.html',
      'main.dart.js',
      'version.json',
      'canvaskit/canvaskit.js',
      'canvaskit/canvaskit.wasm',
      'canvaskit/canvaskit.js.symbols',
      'canvaskit/skwasm.wasm',
      'canvaskit/chromium/canvaskit.wasm',
      'canvaskit/chromium/canvaskit.js',
      'canvaskit/wimp.wasm',
    ]) {
      File('${site.path}/$f')
        ..createSync(recursive: true)
        ..writeAsStringSync(f);
    }
    List<String> names(bool trim) => ZipDecoder()
        .decodeBytes(
          packageApp(
            manifest: LiteStoreManifest.parse(_yaml),
            site: site,
            out: Directory('${tmp.path}/o-$trim'),
            trimFlutterEngine: trim,
          ).zip.readAsBytesSync(),
        )
        .map((f) => f.name)
        .toList();
    expect(names(true)..sort(), [
      'canvaskit/canvaskit.js',
      'canvaskit/canvaskit.wasm',
      'canvaskit/chromium/canvaskit.js',
      'canvaskit/chromium/canvaskit.wasm',
      'index.html',
      'litestore.json',
      'main.dart.js',
    ]);
    expect(names(false), contains('canvaskit/skwasm.wasm'));
  });

  test('package makes a reproducible zip with listing', () {
    final site = Directory('${tmp.path}/web')..createSync();
    File('${site.path}/index.html').writeAsStringSync('<html></html>');
    Directory('${site.path}/assets').createSync();
    File('${site.path}/assets/a.txt').writeAsStringSync('A');
    final m = LiteStoreManifest.parse(_yaml);
    final one = packageApp(
      manifest: m,
      site: site,
      out: Directory('${tmp.path}/o1'),
      bundleUrlBase: 'https://cdn.example.com/apps',
    );
    final two = packageApp(
      manifest: m,
      site: site,
      out: Directory('${tmp.path}/o2'),
    );
    expect(one.sha256, two.sha256, reason: 'same input, same zip');
    expect(sha256.convert(one.zip.readAsBytesSync()).toString(), one.sha256);
    final names = ZipDecoder()
        .decodeBytes(one.zip.readAsBytesSync())
        .map((f) => f.name);
    expect(
      names,
      containsAll(['index.html', 'assets/a.txt', 'litestore.json']),
    );
    final listing = jsonDecode(one.listing.readAsStringSync()) as Map;
    expect(
      listing['bundleUrl'],
      'https://cdn.example.com/apps/com.example.duka-1.2.0.zip',
    );
    expect(listing['bundleSha256'], one.sha256);
    expect(listing['requires'], ['location']);
  });

  test('build --dir packages an existing site and checks first', () async {
    File('${tmp.path}/litestore.yaml').writeAsStringSync(_yaml);
    Directory('${tmp.path}/lib').createSync();
    File(
      '${tmp.path}/lib/main.dart',
    ).writeAsStringSync('LiteHost.location.get();');
    final site = Directory('${tmp.path}/dist')..createSync();
    File('${site.path}/index.html').writeAsStringSync('<html></html>');
    final log = _Log();
    expect(await runBuild(['--dir', 'dist'], tmp, log), 0, reason: log.text);
    expect(
      File(
        '${tmp.path}/build/litestore/com.example.duka-1.2.0.zip',
      ).existsSync(),
      isTrue,
    );

    File('${tmp.path}/lib/main.dart').writeAsStringSync('LiteHost.wifi.get();');
    expect(await runBuild(['--dir', 'dist'], tmp, _Log()), 1);
  });
}

class _Log implements IOSink {
  final _b = StringBuffer();
  String get text => _b.toString();
  @override
  void writeln([Object? o = '']) => _b.writeln(o);
  @override
  dynamic noSuchMethod(Invocation i) => null;
}
