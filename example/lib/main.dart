import 'dart:async';

import 'package:flutter/material.dart';
import 'package:litehost/litehost.dart';

void main() {
  // In a normal browser (flutter run -d chrome) there's no SetLiteWeb:
  // answer with a MockHost so every button still works.
  if (!LiteHost.isAvailable) LiteHost.useMock(MockHost());
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LiteHost Demo',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF0E7C66)),
    home: const DemoPage(),
  );
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _log = <String>[];
  final _subs = <StreamSubscription<Object?>>[];
  HostCapabilities? _caps;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(LiteHost.onPause.listen((_) => _say('app.pause')))
      ..add(LiteHost.onResume.listen((_) => _say('app.resume')))
      ..add(LiteHost.onLink.listen((l) => _say('app.link ${l.uri}')));
    LiteHost.capabilities().then(
      (c) => setState(() => _caps = c),
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _say(String line) => setState(() => _log.insert(0, line));

  Future<void> _try(String label, Future<Object?> Function() run) async {
    try {
      final result = await run();
      _say('$label → ${result ?? 'done'}');
    } on LiteHostException catch (e) {
      _say('$label ✕ ${e.error.name}: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mock = LiteHost.transport is MockHost;
    final actions = <(String, Feature?, Future<Object?> Function())>[
      (
        'Location',
        Feature.location,
        () async {
          final p = await LiteHost.location.get(reason: 'To show the demo');
          return '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}';
        },
      ),
      ('Wi-Fi', Feature.wifi, () async => (await LiteHost.wifi.get()).ssid),
      (
        'Profile',
        Feature.profileName,
        () async {
          final p = await LiteHost.profile.get(ProfileField.values.toSet());
          return [p.name, p.phone, p.email].whereType<String>().join(' · ');
        },
      ),
      (
        'Sign in token',
        Feature.authToken,
        () async => '${(await LiteHost.auth.token()).token.substring(0, 12)}…',
      ),
      ('Scan QR', Feature.scanner, () => LiteHost.scanner.scan()),
      (
        'Pick photo',
        Feature.imagePick,
        () async {
          final img = await LiteHost.image.pick();
          return img == null
              ? 'cancelled'
              : '${img.mime}, ${img.bytes.length} bytes';
        },
      ),
      (
        'Bluetooth scan',
        Feature.bluetooth,
        () async {
          final names = await LiteHost.bluetooth
              .scan(duration: const Duration(seconds: 5))
              .map((d) => d.name.isEmpty ? d.id : d.name)
              .toList();
          return names.isEmpty ? 'nothing nearby' : names.join(', ');
        },
      ),
      (
        'Storage',
        Feature.storage,
        () async {
          final n =
              int.tryParse(await LiteHost.storage.get('opens') ?? '') ?? 0;
          await LiteHost.storage.set('opens', '${n + 1}');
          return 'opened ${n + 1} times';
        },
      ),
      (
        'Copy',
        Feature.clipboardWrite,
        () => LiteHost.clipboard.write('Hello from LiteHost'),
      ),
      ('Paste', Feature.clipboardRead, () => LiteHost.clipboard.read()),
      (
        'Share link',
        Feature.links,
        () async {
          final url = await LiteHost.links.create('/demo');
          await LiteHost.share('Try this: $url');
          return url;
        },
      ),
      ('Vibrate', Feature.haptics, () => LiteHost.haptics(HapticStyle.medium)),
      (
        'Device',
        Feature.deviceInfo,
        () async {
          final d = await LiteHost.device.info();
          return '${d.manufacturer} ${d.model}, ${d.os}, SetLiteWeb ${d.hostVersion}';
        },
      ),
      (
        'Unknown feature',
        null,
        () => LiteHost.transport.invoke('nfc.read', const {}),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('LiteHost Demo'),
        actions: [
          if (!mock)
            IconButton(
              onPressed: LiteHost.close,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (mock)
            const Card(
              child: ListTile(
                leading: Icon(Icons.science_outlined),
                title: Text('Mock host'),
                subtitle: Text('Not inside SetLiteWeb: answers are pretend.'),
              ),
            ),
          if (_caps case final c?)
            Text(
              '${c.platform}, bridge ${c.bridgeVersion}, '
              '${c.features.length} features',
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, feature, run) in actions)
                FilledButton.tonal(
                  onPressed: feature == null || (_caps?.has(feature) ?? true)
                      ? () => _try(label, run)
                      : null,
                  child: Text(label),
                ),
            ],
          ),
          const Divider(height: 32),
          for (final line in _log)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                line,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
        ],
      ),
    );
  }
}
