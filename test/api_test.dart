import 'package:litehost/litehost.dart';
import 'package:test/test.dart';

Matcher throwsHost(LiteHostError e) =>
    throwsA(isA<LiteHostException>().having((x) => x.error, 'error', e));

void main() {
  late MockHost mock;
  setUp(() => LiteHost.useMock(mock = MockHost()));
  tearDown(() {
    mock.dispose();
    LiteHost.reset();
  });

  test('outside SetLiteWeb, calls say notInHost', () async {
    LiteHost.reset();
    expect(LiteHost.isAvailable, isFalse);
    await expectLater(
      LiteHost.location.get(),
      throwsHost(LiteHostError.notInHost),
    );
  });

  test('typed results and the reason are passed', () async {
    final pos = await LiteHost.location.get(
      precise: false,
      reason: 'shops near you',
    );
    expect(pos.latitude, closeTo(-1.28, 0.01));
    expect(pos.accuracyMeters, 1000);
    expect(mock.calls.last.$2, {'precise': false, 'reason': 'shops near you'});
    expect((await LiteHost.device.info()).bridgeVersion, 1);
    expect((await LiteHost.wifi.get()).ssid, 'MockWiFi');
    expect(await LiteHost.scanner.scan(), 'MOCK-QR-CODE');
    expect((await LiteHost.image.pick())!.mime, 'image/png');
    expect((await LiteHost.auth.token()).expiresIn, const Duration(minutes: 5));
    expect(
      (await LiteHost.auth.browser(
        Uri.parse('https://accounts.example/x'),
      )).scheme,
      AuthApi.callbackScheme,
    );
  });

  test('declared, available and denied features are enforced', () async {
    LiteHost.useMock(mock = MockHost(declared: {Feature.storage}));
    await expectLater(
      LiteHost.wifi.get(),
      throwsHost(LiteHostError.undeclared),
    );
    LiteHost.useMock(mock = MockHost(available: {}));
    await expectLater(
      LiteHost.storage.keys(),
      throwsHost(LiteHostError.unsupported),
    );
    LiteHost.useMock(mock = MockHost(denied: {Feature.location}));
    await expectLater(
      LiteHost.location.get(),
      throwsHost(LiteHostError.denied),
    );
  });

  test('profile shares only allowed fields', () async {
    LiteHost.useMock(mock = MockHost(denied: {Feature.profilePhone}));
    final p = await LiteHost.profile.get({
      ProfileField.name,
      ProfileField.phone,
    });
    expect(p.name, 'Jane Doe');
    expect(p.phone, isNull);
    expect(p.id, isNotEmpty);
    mock.signedOut = true;
    await expectLater(
      LiteHost.profile.get({ProfileField.name}),
      throwsHost(LiteHostError.signedOut),
    );
  });

  test('storage, including JSON helpers', () async {
    await LiteHost.storage.setJson('cart', {
      'items': [1, 2],
    });
    expect(await LiteHost.storage.getJson('cart'), {
      'items': [1, 2],
    });
    expect(await LiteHost.storage.keys(), ['cart']);
    await LiteHost.storage.clear();
    expect(await LiteHost.storage.get('cart'), isNull);
  });

  test('links and events', () async {
    final url = await LiteHost.links.create(
      '/item/42',
      query: {'shop': 'njeri'},
    );
    expect(
      url.toString(),
      'https://portal.setliteweb.com/a/com.example.app/item/42?shop=njeri',
    );
    final links = <String>[];
    var paused = 0;
    final s1 = LiteHost.onLink.listen((l) => links.add(l.uri.toString()));
    final s2 = LiteHost.onPause.listen((_) => paused++);
    mock
      ..openLink('/cart', query: {'x': '1'})
      ..pause();
    await pumpEventQueue();
    expect(links, ['/cart?x=1']);
    expect(paused, 1);
    await s1.cancel();
    await s2.cancel();
  });

  test('bluetooth scan, connect, read, notifications', () async {
    final devices = await LiteHost.bluetooth.scan().toList();
    expect(devices.map((d) => d.name), ['Mock Scale', '']);
    final id = devices.first.id;
    await expectLater(
      LiteHost.bluetooth.services(id),
      throwsHost(LiteHostError.invalid),
    );
    await LiteHost.bluetooth.connect(id);
    final services = await LiteHost.bluetooth.services(id);
    final ch = services.single.characteristics.first;
    expect(ch.canNotify, isTrue);
    expect(await LiteHost.bluetooth.read(id, services.single.uuid, ch.uuid), [
      1,
      2,
      3,
    ]);
    final values = await LiteHost.bluetooth
        .notifications(id, services.single.uuid, ch.uuid)
        .take(3)
        .toList();
    expect(values.map((v) => v.single), [0, 1, 2]);
    await pumpEventQueue();
    expect(mock.calls.map((c) => c.$1), contains('bluetooth.unsubscribe'));
  });

  test('cancelling a scan stops it on the host', () async {
    final first = await LiteHost.bluetooth.scan().first;
    expect(first.name, 'Mock Scale');
    await pumpEventQueue();
    expect(mock.calls.map((c) => c.$1), contains('bluetooth.stopScan'));
  });

  test('a failed start ends the stream with the error', () async {
    LiteHost.useMock(mock = MockHost(denied: {Feature.bluetooth}));
    await expectLater(
      LiteHost.bluetooth.scan().toList(),
      throwsHost(LiteHostError.denied),
    );
  });

  test('notifications, biometric, contacts', () async {
    final id = await LiteHost.notifications.show(
      title: 'Order ready',
      id: 'order-7',
      path: '/orders/7',
    );
    expect(id, 'order-7');
    expect(mock.notifications['order-7']!['path'], '/orders/7');
    await LiteHost.notifications.schedule(
      at: DateTime.now().add(const Duration(hours: 1)),
      title: 'Reminder',
      id: 'r',
    );
    await LiteHost.notifications.cancel('r');
    expect(mock.notifications.keys, ['order-7']);
    await expectLater(
      LiteHost.notifications.schedule(at: DateTime(2001), title: 'x'),
      throwsHost(LiteHostError.invalid),
    );
    expect(await LiteHost.biometric.confirm('Pay KES 200'), isTrue);
    mock.biometricConfirms = false;
    expect(await LiteHost.biometric.confirm('Pay'), isFalse);
    expect((await LiteHost.contacts.pick())!.phone, '+15555550101');
  });

  test('capabilities', () async {
    LiteHost.useMock(
      mock = MockHost(
        available: {Feature.location},
        denied: {Feature.location},
      ),
    );
    final caps = await LiteHost.capabilities();
    expect(caps.has(Feature.location), isTrue);
    expect(caps.has(Feature.bluetooth), isFalse);
    expect(caps.methods, contains('location.get'));
    expect(caps.granted[Feature.location], Grant.denied);
  });

  test('unknown error codes keep the raw code', () {
    final e = LiteHostException(
      LiteHostError.fromCode('tooHot'),
      'x',
      code: 'tooHot',
    );
    expect(e.error, LiteHostError.failed);
    expect(e.toString(), contains('tooHot'));
  });
}
