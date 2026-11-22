/// How LiteHost talks to a host: the real SetLiteWeb (window.LiteHost) or
/// a MockHost.
abstract interface class HostTransport {
  /// A host is there to answer calls.
  bool get isAvailable;

  /// The host's bridge protocol version (0 when there's no host).
  int get bridgeVersion;

  /// Runs a bridge method. Throws LiteHostException.
  Future<Object?> invoke(String method, Map<String, Object?> params);

  /// Events named [event] while listened to.
  Stream<Object?> on(String event);

  /// The first screen is drawn: the host hides its splash.
  void ready();

  /// Closes the mini app.
  void close();
}
