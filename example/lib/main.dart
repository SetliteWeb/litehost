import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:litehost/litehost.dart';

import 'lab.dart';
import 'media.dart';

void main() {
  // `flutter run -d chrome`, or `?mock=1`: pretend to be inside SetLiteWeb.
  if ((kDebugMode || Uri.base.queryParameters['mock'] == '1') && !LiteHost.isAvailable) {
    LiteHost.useMock(MockHost());
  }
  runApp(const FeatureLabApp());
}

class C {
  static const bg = Color(0xFF0B1510);
  static const surface = Color(0xFF13221A);
  static const inset = Color(0xFF0E1A14);
  static const border = Color(0xFF2E4A3A);
  static const ink = Color(0xFFEAF4EE);
  static const soft = Color(0xFFC9DAD0);
  static const muted = Color(0xFF9DB5A6);
  static const green = Color(0xFF45D684);
  static const brand = Color(0xFF17803D);
  static const gold = Color(0xFFFFC93C);
  static const red = Color(0xFFFF7A7A);
}

TextStyle t(double size, {FontWeight w = FontWeight.w400, Color color = C.ink, double? height}) => TextStyle(
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: color,
      height: height,
    );

class FeatureLabApp extends StatelessWidget {
  const FeatureLabApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Feature Lab',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: C.bg,
          colorScheme: const ColorScheme.dark(primary: C.green, surface: C.surface),
        ),
        home: const LabScreen(),
      );
}

typedef LabAction = (String label, Future<String> Function() run);

class Test {
  const Test(this.key, this.title, this.feature, this.icon, this.about, this.actions, {this.asks = false});
  final String key;
  final String title;

  /// The litestore.yaml feature id(s) it uses.
  final String feature;
  final IconData icon;
  final String about;
  final List<LabAction> actions;
  final bool asks;
}

class LabScreen extends StatefulWidget {
  const LabScreen({super.key});
  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  final _outcomes = <String, Outcome>{};
  final _log = <String>[];
  final _subs = <StreamSubscription<Object?>>[];
  Uint8List? _photo;
  Uint8List? _shot;
  final _ble = <BleDevice>[];
  bool _screenOn = false;
  String? _lastNotification;
  bool _runningAll = false;

  @override
  void initState() {
    super.initState();
    if (LiteHost.isAvailable) {
      _subs
        ..add(LiteHost.onPause.listen((_) => _event('app.pause: left the app')))
        ..add(LiteHost.onResume.listen((_) => _event('app.resume: back on screen')))
        ..add(LiteHost.onLink.listen((l) => _event('app.link: ${l.path}${l.query.isEmpty ? '' : ' ${l.query}'}')));
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _event(String e) {
    final now = TimeOfDay.now();
    setState(() => _log.insert(0, '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}  $e'));
  }

  Future<void> _run(String key, String label, Future<String> Function() body) async {
    setState(() => _outcomes[key] = const Outcome(Status.running, ''));
    final o = await attempt(body);
    if (!mounted) return;
    setState(() => _outcomes[key] = o);
    _event('$label: ${o.status == Status.ok ? 'OK' : o.code} (${o.ms} ms)');
  }

  late final List<(String, List<Test>)> _groups = [
    ('The host', [
      Test('capabilities', 'What this phone offers', 'host.capabilities', Icons.verified_outlined, 'Bridge version, platform, every feature and method, and your answers so far.', [
        ('Check', () async {
          final c = await LiteHost.capabilities();
          final granted = c.granted.entries.where((e) => e.value != null).map((e) => '${e.key.id}=${e.value!.name}').join(', ');
          return 'bridge ${c.bridgeVersion} on ${c.platform}\n${c.features.length} features: ${c.features.keys.join(', ')}\n'
              '${c.methods.length} methods${granted.isEmpty ? '' : '\nanswers: $granted'}';
        }),
      ]),
      Test('device', 'Device info', 'device.info', Icons.phone_android_rounded, 'Model, OS, language and SetLiteWeb version.', [
        ('Read', () async {
          final d = await LiteHost.device.info();
          return '${d.manufacturer} ${d.model}\n${d.platform} ${d.os} · ${d.locale}\nSetLiteWeb ${d.hostVersion}, bridge ${d.bridgeVersion}';
        }),
      ]),
    ]),
    ('Where you are', [
      Test('location', 'Location', 'location', Icons.location_on_outlined, 'Asks once. Precise uses GPS; approximate is about 1 km.', [
        ('Precise', () async {
          final p = await LiteHost.location.get(reason: 'Feature Lab is testing location.');
          return '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)} ±${p.accuracyMeters.round()} m';
        }),
        ('Approximate', () async {
          final p = await LiteHost.location.get(precise: false, reason: 'Feature Lab is testing approximate location.');
          return '${p.latitude.toStringAsFixed(3)}, ${p.longitude.toStringAsFixed(3)} ±${p.accuracyMeters.round()} m';
        }),
      ], asks: true),
      Test('wifi.get', 'Wi-Fi network', 'wifi', Icons.wifi_rounded, "The network's name and address. Android shows it only with location permission.", [
        ('Read', () async {
          final w = await LiteHost.wifi.get(reason: 'Feature Lab is testing Wi-Fi details.');
          return 'name ${w.ssid ?? '(hidden)'} · BSSID ${w.bssid ?? '–'} · IP ${w.ip ?? '–'}';
        }),
      ], asks: true),
      Test('wifi.signal', 'Wi-Fi signal', 'wifi.signal', Icons.network_wifi_3_bar_rounded, 'Signal strength only, no name: no prompt. SetLiteWeb 1.6.4+, Android.', [
        ('Read', () async {
          final s = await LiteHost.wifi.signal();
          if (!s.connected) return 'not on Wi-Fi';
          return '${s.rssi ?? '?'} dBm (${s.percent ?? '?'}%, ${s.quality?.label ?? 'measuring'}) · ${s.band ?? '?'} · link ${s.linkMbps ?? '?'} Mbps';
        }),
      ]),
    ]),
    ('Bluetooth', [
      Test('bluetooth', 'Bluetooth LE', 'bluetooth', Icons.bluetooth_searching_rounded, 'Scans 8 s for nearby devices. Tap a device below to connect and list its services.', [
        ('Scan', () async {
          _ble.clear();
          await for (final d in LiteHost.bluetooth.scan(reason: 'Feature Lab is testing Bluetooth.')) {
            if (_ble.every((x) => x.id != d.id)) setState(() => _ble.add(d));
          }
          return '${_ble.length} device${_ble.length == 1 ? '' : 's'} found';
        }),
      ], asks: true),
    ]),
    ('Camera, microphone and photos', [
      Test('camera', 'Camera', 'camera', Icons.photo_camera_outlined, 'Asks permission, then opens the camera for a moment to prove the page gets it.', [
        ('Request + open', () async {
          await LiteHost.camera.request(reason: 'Feature Lab is testing the camera.');
          return 'allowed; ${await openStream(video: true)}';
        }),
      ], asks: true),
      Test('microphone', 'Microphone', 'microphone', Icons.mic_none_rounded, 'Asks permission, then opens the microphone for a moment.', [
        ('Request + open', () async {
          await LiteHost.microphone.request(reason: 'Feature Lab is testing the microphone.');
          return 'allowed; ${await openStream(video: false)}';
        }),
      ], asks: true),
      Test('image', 'Photo picker', 'image.pick', Icons.image_outlined, "The host's own picker: the app gets only the photo chosen.", [
        ('Gallery', () => _pick(ImageSource.gallery)),
        ('Camera', () => _pick(ImageSource.camera)),
      ]),
      Test('scanner', 'QR scanner', 'scanner', Icons.qr_code_scanner_rounded, "The host's scanner screen. Scan any QR or barcode.", [
        ('Scan', () async => (await LiteHost.scanner.scan(prompt: 'Scan any code to test')) ?? 'backed out (null)'),
      ]),
    ]),
    ('You', [
      Test('profile', 'Profile', 'profile.name, profile.phone, profile.email', Icons.person_outline_rounded, 'Asks which fields to share, one by one.', [
        ('Name + phone + email', () async {
          final p = await LiteHost.profile.get(ProfileField.values.toSet(), reason: 'Feature Lab is testing your profile.');
          return 'id ${p.id}\nname ${p.name ?? '–'} · phone ${p.phone ?? '–'} · email ${p.email ?? '–'}';
        }),
      ], asks: true),
      Test('auth.token', 'Sign in with SetLiteWeb', 'auth.token', Icons.key_rounded, 'A signed token (5 min) for an app server to check.', [
        ('Get token', () async {
          final tok = await LiteHost.auth.token(reason: 'Feature Lab is testing sign-in.');
          return '${tok.token.length} chars, starts ${tok.token.substring(0, tok.token.length < 16 ? tok.token.length : 16)}… · valid ${tok.expiresIn.inMinutes} min';
        }),
      ], asks: true),
      Test('auth.browser', 'Browser sign-in', 'auth.browser', Icons.open_in_browser_rounded, 'Opens a sign-in page and waits for the return address. Back out to see "cancelled".', [
        ('Open', () async => 'returned to ${await LiteHost.auth.browser(Uri.parse('https://setliteweb.com'))}'),
      ]),
      Test('biometric', 'Confirm it\'s you', 'biometric', Icons.fingerprint_rounded, "The phone's fingerprint, face or screen-lock prompt.", [
        ('Confirm', () async => (await LiteHost.biometric.confirm('Feature Lab test: confirm it\'s you')) ? 'confirmed' : 'not confirmed'),
      ]),
      Test('contacts', 'Pick a contact', 'contacts.pick', Icons.contacts_outlined, 'Opens your contacts; the app sees only the one you pick.', [
        ('Pick', () async {
          final c = await LiteHost.contacts.pick();
          return c == null ? 'backed out (null)' : '${c.name}: ${c.phone ?? '–'} (${c.phones.length} number${c.phones.length == 1 ? '' : 's'})';
        }),
      ]),
    ]),
    ('Sharing and links', [
      Test('share', 'Share sheet', 'share', Icons.ios_share_rounded, "The phone's share sheet.", [
        ('Share text', () async {
          await LiteHost.share('Testing SetLiteWeb Feature Lab', subject: 'Feature Lab');
          return 'share sheet opened';
        }),
      ]),
      Test('openUrl', 'Open links', 'open.url', Icons.open_in_new_rounded, 'Web pages, calls, SMS, email and maps, in their own apps.', [
        ('Web page', () async {
          await LiteHost.openUrl(Uri.parse('https://setliteweb.com'));
          return 'opened https://setliteweb.com';
        }),
        ('Phone call', () async {
          await LiteHost.openUrl(Uri.parse('tel:0700000000'));
          return 'opened the dialer';
        }),
      ]),
      Test('links', 'Shareable link', 'links', Icons.link_rounded, 'An https link that opens this app at a page. Open it later to see app.link in the log.', [
        ('Create', () async => '${await LiteHost.links.create('/lab', query: {'from': 'test'})}'),
      ]),
      Test('clipboard.write', 'Copy', 'clipboard.write', Icons.copy_rounded, 'Puts text on the clipboard: no prompt.', [
        ('Copy', () async {
          await LiteHost.clipboard.write('Feature Lab ${DateTime.now().toIso8601String()}');
          return 'copied';
        }),
      ]),
      Test('clipboard.read', 'Paste', 'clipboard.read', Icons.content_paste_rounded, 'Reads the clipboard: asks first.', [
        ('Paste', () async => 'clipboard: ${await LiteHost.clipboard.read(reason: 'Feature Lab is testing paste.') ?? '(empty)'}'),
      ], asks: true),
    ]),
    ('Phone', [
      Test('haptics', 'Vibration', 'haptics', Icons.vibration_rounded, 'Four kinds of tap.', [
        for (final s in HapticStyle.values)
          (s.name, () async {
            await LiteHost.haptics(s);
            return 'vibrated: ${s.name}';
          }),
      ]),
      Test('keepOn', 'Keep screen on', 'screen.keepOn', Icons.light_mode_outlined, 'While the app is open; it turns off by itself when you leave.', [
        ('Toggle', () async {
          _screenOn = !_screenOn;
          await LiteHost.keepScreenOn(_screenOn);
          return _screenOn ? 'screen stays on' : 'screen can sleep again';
        }),
      ]),
      Test('storage', 'App storage', 'storage', Icons.save_outlined, "This app's own store on the phone (1 MB).", [
        ('Round trip', storageRoundTrip),
      ]),
    ]),
    ('Switch on', [
      Test('bluetooth.enable', 'Turn on Bluetooth', 'bluetooth', Icons.bluetooth_rounded, "Android's own \"turn on Bluetooth?\" dialog.", [
        ('Turn on', () async => (await LiteHost.bluetooth.enable(reason: 'Feature Lab is testing Bluetooth.')) ? 'Bluetooth is on' : 'still off'),
      ], asks: true),
      Test('wifi.enable', 'Turn on Wi-Fi', 'wifi.enable', Icons.wifi_rounded, "Opens Android's Wi-Fi panel: you switch it on, then come back.", [
        ('Turn on', () async => (await LiteHost.wifi.enable()) ? 'Wi-Fi is on' : 'still off'),
      ]),
      Test('torch', 'Torch', 'torch', Icons.flashlight_on_outlined, 'On and off. It goes off by itself when you leave the app.', [
        ('On', () async => (await LiteHost.torch.set(true)) ? 'torch on' : 'torch off'),
        ('Off', () async => (await LiteHost.torch.set(false)) ? 'torch on' : 'torch off'),
        ('Is it on?', () async => (await LiteHost.torch.isOn()) ? 'on' : 'off'),
      ]),
    ]),
    ('NFC', [
      Test('nfc', 'Read an NFC tag', 'nfc', Icons.nfc_rounded, 'Hold a tag, sticker or transport card to the back of the phone. Bank cards give only a random id.', [
        ('Read', () async {
          final tag = await LiteHost.nfc.read(prompt: 'Feature Lab: hold a tag near the phone');
          final recs = [
            for (final r in tag.records)
              '${r.kind}: ${r.text ?? r.uri ?? r.mime ?? '${r.data.length} bytes'}',
          ];
          return 'id ${tag.id ?? '–'} · ${tag.techs.join(', ')}'
              '${tag.writable == null ? '' : ' · ${tag.writable! ? 'writable' : 'read-only'}, ${tag.maxSize} bytes'}'
              '\n${recs.isEmpty ? 'no NDEF records' : recs.join('\n')}';
        }),
      ]),
    ]),
    ('Sensors and gestures', [
      Test('sensors', 'Sensors', 'sensors', Icons.sensors_rounded, 'Lists this phone\'s sensors, or reads one for 2 seconds.', [
        ('List', () async {
          final list = await LiteHost.sensors.list();
          return list.isEmpty ? 'no sensors reported' : list.map((s) => '${s.type.name}: ${s.name}').join('\n');
        }),
        for (final type in [SensorType.accelerometer, SensorType.gyroscope, SensorType.magnetometer, SensorType.light, SensorType.proximity, SensorType.pressure, SensorType.temperature, SensorType.humidity, SensorType.stepCounter])
          (type.name, () => _readSensor(type)),
      ]),
      Test('battery', 'Battery and temperature', 'device.info', Icons.battery_std_rounded, 'Level, charging and the battery\'s temperature (every phone has this one).', [
        ('Read', () async {
          final b = await LiteHost.device.battery();
          return '${b.level ?? '?'}% · ${b.charging ? 'charging' : 'not charging'} · battery ${b.temperatureC?.toStringAsFixed(1) ?? '?'} °C';
        }),
      ]),
      Test('gestures', 'Phone gestures', 'gestures', Icons.back_hand_outlined, 'Watches for 15 s: shake, put face down and up, tilt, wave a hand over the top.', [
        ('Watch 15 s', () async {
          final seen = <String>[];
          final sub = LiteHost.gestures.watch().listen((g) {
            seen.add(g.name);
            _event('gesture: ${g.name}');
          });
          await Future<void>.delayed(const Duration(seconds: 15));
          await sub.cancel();
          return seen.isEmpty ? 'none seen in 15 s' : 'seen: ${seen.join(', ')}';
        }),
      ]),
    ]),
    ('Background, calls and screen', [
      Test('track', 'Background location', 'location.background', Icons.share_location_rounded, 'Shares your location for 20 s, even after you leave the app (a notification shows). Leave and come back to see the fixes kept coming.', [
        ('Track 20 s', () async {
          final fixes = <LocationFix>[];
          final sub = LiteHost.location.track(interval: const Duration(seconds: 5), distanceMeters: 0, reason: 'Feature Lab is testing background location.').listen(fixes.add);
          await Future<void>.delayed(const Duration(seconds: 20));
          await sub.cancel();
          if (fixes.isEmpty) return 'no fixes in 20 s';
          final l = fixes.last;
          return '${fixes.length} fixes · last ${l.latitude.toStringAsFixed(5)}, ${l.longitude.toStringAsFixed(5)} ±${l.accuracyMeters.round()} m'
              '${l.speed == null ? '' : ' · ${(l.speed! * 3.6).toStringAsFixed(0)} km/h'}';
        }),
      ], asks: true),
      Test('call', 'Make a call', 'phone.call', Icons.call_outlined, 'SetLiteWeb asks "Call …?" first, then calls (or opens the dialer). Tests with *144# (balance).', [
        ('Call *144#', () async => 'result: ${await LiteHost.phone.call('*144#')}'),
      ]),
      Test('otp', 'Read a code SMS', 'sms.otp', Icons.sms_outlined, 'Waits up to 5 minutes for the next SMS; Google asks you to allow it. Send yourself a text with a 6-digit code.', [
        ('Wait for SMS', () async {
          final o = await LiteHost.sms.otp();
          return 'code ${o.code ?? '(none found)'}\n${o.sms}';
        }),
      ]),
      Test('capture', 'Screenshot', 'screen.capture', Icons.screenshot_outlined, 'Captures this app\'s screen.', [
        ('Capture', () async {
          final s = await LiteHost.screen.capture();
          setState(() => _shot = s.png);
          return '${s.width}×${s.height} PNG, ${(s.png.length / 1024).toStringAsFixed(0)} KB';
        }),
      ]),
      Test('pip', 'Picture-in-picture', 'pip', Icons.picture_in_picture_alt_outlined, 'Shrinks SetLiteWeb to a small window showing this app. "Auto on" does it when you press Home.', [
        ('Now', () async => (await LiteHost.pip.enter()) ? 'in picture-in-picture' : 'not available on this phone'),
        ('Auto on', () async {
          await LiteHost.pip.auto(true);
          return 'press Home to see it';
        }),
        ('Auto off', () async {
          await LiteHost.pip.auto(false);
          return 'auto off';
        }),
      ]),
    ]),
    ('Notifications', [
      Test('notifications', 'Notifications', 'notifications', Icons.notifications_none_rounded, 'Asks once. Tapping one opens this app at /lab (see app.link in the log).', [
        ('Show now', () async {
          _lastNotification = await LiteHost.notifications.show(title: 'Feature Lab', body: 'A test notification. Tap me.', path: '/lab', query: {'from': 'notification'}, reason: 'Feature Lab is testing notifications.');
          return 'shown, id $_lastNotification';
        }),
        ('In 1 minute', () async {
          _lastNotification = await LiteHost.notifications.schedule(at: DateTime.now().add(const Duration(minutes: 1)), title: 'Feature Lab', body: 'Scheduled a minute ago. Tap me.', path: '/lab', query: {'from': 'scheduled'});
          return 'scheduled, id $_lastNotification (phones may delay it a little)';
        }),
        ('Cancel last', () async {
          final id = _lastNotification;
          if (id == null) return 'nothing to cancel yet';
          await LiteHost.notifications.cancel(id);
          return 'cancelled $id';
        }),
      ], asks: true),
    ]),
  ];

  static const _units = {
    SensorType.accelerometer: 'm/s²', SensorType.gyroscope: 'rad/s', SensorType.magnetometer: 'µT',
    SensorType.light: 'lux', SensorType.proximity: 'cm', SensorType.pressure: 'hPa',
    SensorType.temperature: '°C', SensorType.humidity: '%', SensorType.stepCounter: 'steps',
  };

  /// Two seconds of readings: how many, and the last one with units.
  Future<String> _readSensor(SensorType type) async {
    final readings = <SensorReading>[];
    final sub = LiteHost.sensors.watch(type, hz: 20).listen(readings.add);
    final done = Completer<void>();
    sub.onError((Object e) {
      if (!done.isCompleted) done.completeError(e);
    });
    await Future.any([done.future, Future<void>.delayed(const Duration(seconds: 2))]);
    await sub.cancel();
    if (readings.isEmpty) return 'no readings in 2 s';
    final v = readings.last.values.map((x) => x.toStringAsFixed(2)).join(', ');
    return '${readings.length} readings · last: $v ${_units[type] ?? ''}';
  }

  Future<String> _pick(ImageSource source) async {
    final img = await LiteHost.image.pick(source: source, maxWidth: 800);
    if (img == null) return 'backed out (null)';
    setState(() => _photo = img.bytes);
    return '${img.mime}, ${(img.bytes.length / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _connect(BleDevice d) => _run('bluetooth', 'bluetooth.connect', () async {
        await LiteHost.bluetooth.connect(d.id);
        try {
          final services = await LiteHost.bluetooth.services(d.id);
          final chars = services.fold<int>(0, (s, x) => s + x.characteristics.length);
          return '${d.name.isEmpty ? d.id : d.name}: ${services.length} services, $chars characteristics\n${services.map((s) => s.uuid).join('\n')}';
        } finally {
          await LiteHost.bluetooth.disconnect(d.id);
        }
      });

  Future<void> _runQuiet() async {
    setState(() => _runningAll = true);
    for (final (_, tests) in _groups) {
      for (final tst in tests) {
        if (quietTests.contains(tst.key)) {
          final (label, run) = tst.actions.first;
          await _run(tst.key, '${tst.feature} $label', run);
        }
      }
    }
    if (mounted) setState(() => _runningAll = false);
  }

  @override
  Widget build(BuildContext context) {
    final done = _outcomes.values.where((o) => o.status == Status.ok).length;
    final failed = _outcomes.values.where((o) => o.status == Status.failed).length;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.science_outlined, color: Colors.white, size: 21),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Feature Lab', style: t(18, w: FontWeight.w700)),
                      Text(
                        LiteHost.isAvailable ? 'Inside SetLiteWeb · bridge ${LiteHost.bridgeVersion}' : 'Not inside SetLiteWeb: every test will say notInHost',
                        style: t(12, color: LiteHost.isAvailable ? C.muted : C.gold),
                      ),
                    ]),
                  ),
                  IconButton(onPressed: LiteHost.close, tooltip: 'Close the app (host.close)', icon: const Icon(Icons.close_rounded)),
                ]),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Tests every feature the litehost SDK offers. Cards marked "asks" show SetLiteWeb\'s consent sheet the first time.',
                        style: t(13.5, color: C.soft, height: 1.45)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: Text('$done OK · $failed failed · ${_outcomes.length} run', style: t(13, w: FontWeight.w600))),
                      FilledButton.icon(
                        onPressed: _runningAll ? null : _runQuiet,
                        icon: _runningAll
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.play_arrow_rounded),
                        label: const Text('Run safe tests'),
                        style: FilledButton.styleFrom(backgroundColor: C.brand, foregroundColor: Colors.white),
                      ),
                    ]),
                  ]),
                ),
                for (final (group, tests) in _groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                    child: Text(group.toUpperCase(), style: t(12, w: FontWeight.w700, color: C.muted).copyWith(letterSpacing: .8)),
                  ),
                  for (final tst in tests) _card(tst),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                  child: Text('EVENTS AND CALLS', style: t(12, w: FontWeight.w700, color: C.muted).copyWith(letterSpacing: .8)),
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16)),
                  child: _log.isEmpty
                      ? Text('Leave the app and come back, or open a link or notification: app.pause, app.resume and app.link show here.',
                          style: t(13, color: C.muted, height: 1.45))
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          for (final l in _log.take(60)) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l, style: t(12.5, color: C.soft))),
                        ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(Test tst) {
    final o = _outcomes[tst.key] ?? const Outcome.idle();
    final (chip, chipColor) = switch (o.status) {
      Status.idle => ('not run', C.muted),
      Status.running => ('running…', C.gold),
      Status.ok => ('OK${o.ms == null ? '' : ' · ${o.ms} ms'}', C.green),
      Status.failed => ('${o.code}${o.ms == null ? '' : ' · ${o.ms} ms'}', C.red),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: o.status == Status.failed ? C.red.withValues(alpha: .35) : Colors.transparent)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(tst.icon, color: C.green, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(tst.title, style: t(15, w: FontWeight.w700)),
                if (tst.asks)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(border: Border.all(color: C.gold), borderRadius: BorderRadius.circular(999)),
                    child: Text('asks', style: t(10.5, w: FontWeight.w700, color: C.gold)),
                  ),
              ]),
              const SizedBox(height: 2),
              Text(tst.feature, style: t(11.5, color: C.muted).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: chipColor.withValues(alpha: .15), borderRadius: BorderRadius.circular(999)),
            child: Text(chip, style: t(11.5, w: FontWeight.w700, color: chipColor)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(tst.about, style: t(13, color: C.soft, height: 1.4)),
        if (o.status == Status.ok || o.status == Status.failed) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.inset, borderRadius: BorderRadius.circular(10)),
            child: SelectableText(
              o.status == Status.failed && explain(o.code).isNotEmpty ? '${o.text}\n→ ${explain(o.code)}' : o.text,
              style: t(12.5, color: o.status == Status.failed ? C.red : C.ink, height: 1.4),
            ),
          ),
        ],
        if (tst.key == 'image' && _photo != null) ...[
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(_photo!, height: 140, fit: BoxFit.cover)),
        ],
        if (tst.key == 'capture' && _shot != null) ...[
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(_shot!, height: 220, fit: BoxFit.contain)),
        ],
        if (tst.key == 'bluetooth' && _ble.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final d in _ble.take(12))
            InkWell(
              onTap: d.connectable ? () => _connect(d) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(child: Text(d.name.isEmpty ? d.id : d.name, style: t(13), overflow: TextOverflow.ellipsis)),
                  Text('${d.rssi} dBm${d.connectable ? ' · tap to connect' : ''}', style: t(12, color: C.muted)),
                ]),
              ),
            ),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (label, run) in tst.actions)
            OutlinedButton(
              onPressed: o.status == Status.running ? null : () => _run(tst.key, '${tst.feature.split(',').first} $label', run),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: C.border, width: 1.5),
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text(label, style: t(13.5, w: FontWeight.w600)),
            ),
        ]),
      ]),
    );
  }
}
