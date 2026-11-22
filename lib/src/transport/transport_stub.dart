import '../errors.dart';
import '../transport.dart';

/// Outside the browser (tests, tools): no host.
HostTransport defaultTransport() => const NoHost();

class NoHost implements HostTransport {
  const NoHost();

  @override
  bool get isAvailable => false;

  @override
  int get bridgeVersion => 0;

  @override
  Future<Object?> invoke(String method, Map<String, Object?> params) =>
      Future.error(LiteHostException.notInHost(method));

  @override
  Stream<Object?> on(String event) => const Stream.empty();

  @override
  void ready() {}

  @override
  void close() {}
}
