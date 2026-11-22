/// Why a LiteHost call failed.
enum LiteHostError {
  /// The phone or this version of SetLiteWeb doesn't offer it. Hide the
  /// option or fall back.
  unsupported,

  /// The feature isn't listed in the app's `litestore.yaml`.
  undeclared,

  /// The user said no, now or earlier, for this app.
  denied,

  /// The user backed out of the host's screen (scanner, picker, sign-in).
  cancelled,

  /// Bad or missing parameters.
  invalid,

  /// The user isn't signed in to SetLiteWeb.
  signedOut,

  /// The app's storage is full (1 MB).
  quota,

  /// Blocked for SetLiteWeb in the phone's settings.
  blocked,

  /// Turned off on the phone (e.g. Bluetooth or location services).
  disabled,

  /// The phone couldn't provide it right now (no fix, device out of range).
  unavailable,

  /// Not running inside SetLiteWeb (plain browser) and no MockHost set.
  notInHost,

  /// Anything else.
  failed;

  static LiteHostError fromCode(String? code) => LiteHostError.values
      .firstWhere((e) => e.name == code, orElse: () => LiteHostError.failed);
}

class LiteHostException implements Exception {
  const LiteHostException(this.error, this.message, {this.code, this.method});

  final LiteHostError error;
  final String message;

  /// The host's code as sent, for codes newer than this package.
  final String? code;

  /// The bridge method that failed, e.g. `location.get`.
  final String? method;

  factory LiteHostException.notInHost(String method) => LiteHostException(
    LiteHostError.notInHost,
    'Not running inside SetLiteWeb. Open the app from LiteStore, or call '
    'LiteHost.useMock(MockHost()) while developing.',
    code: 'notInHost',
    method: method,
  );

  @override
  String toString() =>
      'LiteHostException(${code ?? error.name}${method == null ? '' : ', $method'}): $message';
}
