import 'package:litehost_example/lab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:litehost/litehost.dart';

void main() {
  tearDown(LiteHost.reset);

  test('storage round trip passes against the mock host', () async {
    LiteHost.useMock(MockHost());
    final o = await attempt(storageRoundTrip);
    expect(o.status, Status.ok, reason: o.text);
  });

  test('host errors become their code, with an explanation', () async {
    LiteHost.useMock(MockHost(denied: {Feature.location}));
    final o = await attempt(() async => '${(await LiteHost.location.get()).latitude}');
    expect(o.status, Status.failed);
    expect(o.code, 'denied');
    expect(explain(o.code), contains('said no'));
    LiteHost.useMock(MockHost(declared: {Feature.storage}));
    expect((await attempt(() async => '${await LiteHost.wifi.signal()}')).code, 'undeclared');
  });

  test('outside SetLiteWeb every call says notInHost', () async {
    final o = await attempt(() async => '${await LiteHost.device.info()}');
    expect(o.code, 'notInHost');
  });

  test('the quiet tests all pass against the mock', () async {
    LiteHost.useMock(MockHost());
    for (final body in <Future<String> Function()>[
      () async => '${(await LiteHost.capabilities()).features.length}',
      () async => (await LiteHost.device.info()).model,
      () async => '${(await LiteHost.wifi.signal()).percent}',
      () async => '${await LiteHost.links.create('/lab')}',
      storageRoundTrip,
    ]) {
      final o = await attempt(body);
      expect(o.status, Status.ok, reason: o.text);
    }
  });
}
