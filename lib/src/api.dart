import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'errors.dart';
import 'json.dart';
import 'models.dart';
import 'transport.dart';
import 'transport/default_transport.dart';

/// SetLiteWeb's features, from inside a LiteStore mini app.
///
/// ```dart
/// if (LiteHost.isAvailable) {
///   final pos = await LiteHost.location.get(reason: 'To find shops near you');
/// }
/// ```
///
/// Calls throw [LiteHostException]; check `e.error` (e.g.
/// [LiteHostError.denied]) to react. Features that ask the user show the
/// host's own consent sheet the first time; pass `reason` to explain why.
abstract final class LiteHost {
  static HostTransport _transport = defaultTransport();

  /// The transport in use (the real host, or a MockHost).
  static HostTransport get transport => _transport;

  /// Answers calls with [host] instead of SetLiteWeb: for development in a
  /// normal browser and for tests. E.g.
  /// `if (!LiteHost.isAvailable) LiteHost.useMock(MockHost());`
  static void useMock(HostTransport host) => _transport = host;

  /// Back to the real host.
  static void reset() => _transport = defaultTransport();

  /// Running inside SetLiteWeb (or a mock is set).
  static bool get isAvailable => _transport.isAvailable;

  /// The host's bridge version (0 when there's none).
  static int get bridgeVersion => _transport.bridgeVersion;

  /// What this phone offers. Use it to hide options that can't work.
  static Future<HostCapabilities> capabilities() async =>
      HostCapabilities.fromJson(
        asMap(await _call('host.capabilities')) ?? const {},
      );

  /// Tells the host the first screen is drawn, so it hides its splash.
  /// Flutter apps don't need this (the host sees the first frame).
  static void ready() => _transport.ready();

  /// Closes the mini app.
  static void close() => _transport.close();

  static const location = LocationApi._();
  static const camera = PermissionApi._('camera.request');
  static const microphone = PermissionApi._('microphone.request');
  static const bluetooth = BluetoothApi._();
  static const wifi = WifiApi._();
  static const clipboard = ClipboardApi._();
  static const profile = ProfileApi._();
  static const auth = AuthApi._();
  static const scanner = ScannerApi._();
  static const image = ImageApi._();
  static const storage = StorageApi._();
  static const device = DeviceApi._();
  static const links = LinksApi._();
  static const notifications = NotificationsApi._();
  static const biometric = BiometricApi._();
  static const contacts = ContactsApi._();

  /// Opens the phone's share sheet.
  static Future<void> share(String text, {String? subject}) =>
      _call('share', {'text': text, 'subject': ?subject});

  /// Opens [url] (https, http, tel, sms, mailto, geo) in the app that
  /// handles it, outside the mini app.
  static Future<void> openUrl(Uri url) =>
      _call('open.url', {'url': url.toString()});

  static Future<void> haptics([HapticStyle style = HapticStyle.light]) =>
      _call('haptics', {'style': style.name});

  /// Keeps the screen on while the app is open (until set off).
  static Future<void> keepScreenOn([bool on = true]) =>
      _call('screen.keepOn', {'on': on});

  /// The user left the app (it stays warm), or SetLiteWeb went to the
  /// background. Save drafts, pause media.
  static Stream<void> get onPause => _transport.on('app.pause');

  /// The app is back on screen.
  static Stream<void> get onResume => _transport.on('app.resume');

  /// A shared link for this app was opened while it runs. While you listen,
  /// the host doesn't navigate for you; route to [AppLink.uri] yourself.
  static Stream<AppLink> get onLink => _transport
      .on('app.link')
      .map((d) => AppLink.fromJson(asMap(d) ?? const {}));
}

Future<Object?> _call(
  String method, [
  Map<String, Object?> params = const {},
  String? reason,
]) => LiteHost._transport.invoke(method, {...params, 'reason': ?reason});

/// The stream of [event]s tagged `idKey == id`, for an operation started
/// by [start] (which returns the id). Ends on [endEvent]; cancelling calls
/// [stop]. Events that arrive before the id is known are kept and replayed.
Stream<T> _operationStream<T>({
  required Future<String> Function() start,
  required Future<void> Function(String id) stop,
  required String event,
  required String endEvent,
  required String idKey,
  required T Function(Map<String, Object?> data) convert,
}) {
  final t = LiteHost._transport;
  late final StreamController<T> out;
  final subs = <StreamSubscription<Object?>>[];
  final early = <(bool, Map<String, Object?>)>[];
  String? id;
  var done = false;

  Future<void> finish([Object? error]) async {
    if (done) return;
    done = true;
    for (final s in subs) {
      await s.cancel();
    }
    if (error != null) out.addError(error);
    await out.close();
  }

  void handle(bool isEnd, Object? raw) {
    final m = asMap(raw);
    if (m == null || done) return;
    if (id == null) {
      early.add((isEnd, m));
      return;
    }
    if (m[idKey] != id) return;
    if (!isEnd) {
      out.add(convert(m));
      return;
    }
    final err = asMap(m['error']);
    finish(
      err == null
          ? null
          : LiteHostException(
              LiteHostError.fromCode(asNullableString(err['code'])),
              asString(err['message']),
              code: asNullableString(err['code']),
            ),
    );
  }

  out = StreamController<T>(
    onListen: () async {
      subs
        ..add(t.on(event).listen((d) => handle(false, d)))
        ..add(t.on(endEvent).listen((d) => handle(true, d)));
      try {
        id = await start();
      } catch (e) {
        await finish(e);
        return;
      }
      for (final (isEnd, m) in early) {
        handle(isEnd, m);
      }
      early.clear();
    },
    onCancel: () async {
      if (done) return;
      done = true;
      for (final s in subs) {
        await s.cancel();
      }
      final started = id;
      if (started != null) {
        try {
          await stop(started);
        } catch (_) {}
      }
    },
  );
  return out.stream;
}

class LocationApi {
  const LocationApi._();

  /// Where the phone is now. [precise] false asks only for an approximate
  /// position.
  Future<Position> get({bool precise = true, String? reason}) async =>
      Position.fromJson(
        asMap(await _call('location.get', {'precise': precise}, reason)) ??
            const {},
      );
}

/// Camera or microphone for the page's own web APIs (getUserMedia).
/// Asking here first shows the host's consent sheet with your [reason].
class PermissionApi {
  const PermissionApi._(this._method);

  final String _method;

  Future<void> request({String? reason}) => _call(_method, const {}, reason);
}

class BluetoothApi {
  const BluetoothApi._();

  /// Nearby Bluetooth Low Energy devices, for [duration] (max 30 s) or
  /// until you cancel. Only one scan at a time per app. Filter by
  /// advertised [services] UUIDs to save battery.
  Stream<BleDevice> scan({
    Duration duration = const Duration(seconds: 8),
    List<String> services = const [],
    String? reason,
  }) => _operationStream(
    start: () async => asString(
      asMap(
        await _call('bluetooth.scan', {
          'seconds': duration.inSeconds.clamp(1, 30),
          'services': services,
        }, reason),
      )?['scanId'],
    ),
    stop: (id) => _call('bluetooth.stopScan', {'scanId': id}),
    event: 'bluetooth.device',
    endEvent: 'bluetooth.scanEnd',
    idKey: 'scanId',
    convert: BleDevice.fromJson,
  );

  /// Connects to a device your scan found.
  Future<void> connect(String deviceId) =>
      _call('bluetooth.connect', {'deviceId': deviceId});

  Future<void> disconnect(String deviceId) =>
      _call('bluetooth.disconnect', {'deviceId': deviceId});

  Future<List<BleService>> services(String deviceId) async => [
    for (final s in asList(
      await _call('bluetooth.services', {'deviceId': deviceId}),
    ))
      if (asMap(s) case final m?) BleService.fromJson(m),
  ];

  Future<Uint8List> read(
    String deviceId,
    String service,
    String characteristic,
  ) async => base64Decode(
    asString(
      await _call('bluetooth.read', {
        'deviceId': deviceId,
        'service': service,
        'characteristic': characteristic,
      }),
    ),
  );

  Future<void> write(
    String deviceId,
    String service,
    String characteristic,
    List<int> value, {
    bool withoutResponse = false,
  }) => _call('bluetooth.write', {
    'deviceId': deviceId,
    'service': service,
    'characteristic': characteristic,
    'value': base64Encode(value),
    'withoutResponse': withoutResponse,
  });

  /// Values the device sends (notify/indicate) until you cancel.
  Stream<Uint8List> notifications(
    String deviceId,
    String service,
    String characteristic,
  ) => _operationStream(
    start: () async => asString(
      asMap(
        await _call('bluetooth.subscribe', {
          'deviceId': deviceId,
          'service': service,
          'characteristic': characteristic,
        }),
      )?['subscriptionId'],
    ),
    stop: (id) => _call('bluetooth.unsubscribe', {'subscriptionId': id}),
    event: 'bluetooth.value',
    endEvent: 'bluetooth.subscriptionEnd',
    idKey: 'subscriptionId',
    convert: (m) => base64Decode(asString(m['value'])),
  );
}

class WifiApi {
  const WifiApi._();

  Future<WifiInfo> get({String? reason}) async => WifiInfo.fromJson(
    asMap(await _call('wifi.get', const {}, reason)) ?? const {},
  );

  /// How strong the Wi-Fi signal is (feature `wifi.signal`). No network
  /// name, so no consent sheet. Call it about once a second for a live
  /// meter; phones refresh the reading every few seconds.
  Future<WifiSignal> signal() async =>
      WifiSignal.fromJson(asMap(await _call('wifi.signal')) ?? const {});
}

class ClipboardApi {
  const ClipboardApi._();

  Future<String?> read({String? reason}) async =>
      asNullableString(await _call('clipboard.read', const {}, reason));

  Future<void> write(String text) => _call('clipboard.write', {'text': text});
}

class ProfileApi {
  const ProfileApi._();

  /// The user's profile; the host asks them which [fields] to share, and
  /// leaves out the ones they don't. Declare `profile.name` etc. for each.
  Future<Profile> get(Set<ProfileField> fields, {String? reason}) async =>
      Profile.fromJson(
        asMap(
              await _call('profile.get', {
                'fields': [for (final f in fields) f.name],
              }, reason),
            ) ??
            const {},
      );
}

class AuthApi {
  const AuthApi._();

  /// "Sign in with SetLiteWeb": a short-lived token for your server.
  Future<AppToken> token({String? reason}) async => AppToken.fromJson(
    asMap(await _call('auth.token', const {}, reason)) ?? const {},
  );

  /// Signs in with another account (Google, your own server...): opens
  /// [url] in the phone's secure browser and returns the URL the sign-in
  /// sent the user back to (`setliteweb-litestore://...`), with its code or
  /// token. Use [callbackScheme] as your OAuth redirect scheme.
  Future<Uri> browser(Uri url) async => Uri.parse(
    asString(
      asMap(await _call('auth.browser', {'url': url.toString()}))?['url'],
    ),
  );

  static const callbackScheme = 'setliteweb-litestore';
}

class ScannerApi {
  const ScannerApi._();

  /// Opens SetLiteWeb's QR scanner. Null if the user backs out.
  Future<String?> scan({String? prompt}) async => asNullableString(
    asMap(await _call('scanner.scan', {'prompt': ?prompt}))?['text'],
  );
}

class ImageApi {
  const ImageApi._();

  /// A photo from the camera or gallery, resized to [maxWidth]. Null if the
  /// user backs out.
  Future<PickedImage?> pick({
    ImageSource source = ImageSource.gallery,
    int maxWidth = 1280,
  }) async {
    final m = asMap(
      await _call('image.pick', {'source': source.name, 'maxWidth': maxWidth}),
    );
    return m == null ? null : PickedImage.fromJson(m);
  }
}

/// This app's own key-value store on the phone (1 MB). Survives restarts
/// and updates; cleared if the user removes the app.
class StorageApi {
  const StorageApi._();

  Future<String?> get(String key) async =>
      (await _call('storage.get', {'key': key})) as String?;

  Future<void> set(String key, String value) =>
      _call('storage.set', {'key': key, 'value': value});

  Future<void> remove(String key) => _call('storage.remove', {'key': key});

  Future<List<String>> keys() async => [
    for (final k in asList(await _call('storage.keys'))) '$k',
  ];

  Future<void> clear() => _call('storage.clear');

  Future<Object?> getJson(String key) async {
    final v = await get(key);
    return v == null ? null : jsonDecode(v);
  }

  Future<void> setJson(String key, Object? value) =>
      set(key, jsonEncode(value));
}

class DeviceApi {
  const DeviceApi._();

  Future<DeviceInfo> info() async =>
      DeviceInfo.fromJson(asMap(await _call('device.info')) ?? const {});
}

class LinksApi {
  const LinksApi._();

  /// An https link that opens this app at [path] in SetLiteWeb (or the
  /// app's web page for people without it). Pair with [LiteHost.share].
  Future<Uri> create(
    String path, {
    Map<String, String> query = const {},
    String fragment = '',
  }) async => Uri.parse(
    asString(
      asMap(
        await _call('link.create', {
          'path': path,
          'query': query,
          'fragment': fragment,
        }),
      )?['url'],
    ),
  );
}

/// Notifications shown under your app's name; tapping one opens your app
/// at [path]. Asks the user once. At most 5 shown a minute and 32
/// scheduled, up to 60 days ahead. Reuse an [id] to replace one.
class NotificationsApi {
  const NotificationsApi._();

  /// Shows it now. Returns its id.
  Future<String> show({
    required String title,
    String body = '',
    String? id,
    String path = '/',
    Map<String, String> query = const {},
    String? reason,
  }) async => asString(
    asMap(
      await _call('notifications.show', {
        'title': title,
        'body': body,
        'id': ?id,
        'path': path,
        'query': query,
      }, reason),
    )?['id'],
  );

  /// Shows it around [at] (the phone may delay it a little to save
  /// battery). Survives restarts. Returns its id.
  Future<String> schedule({
    required DateTime at,
    required String title,
    String body = '',
    String? id,
    String path = '/',
    Map<String, String> query = const {},
    String? reason,
  }) async => asString(
    asMap(
      await _call('notifications.schedule', {
        'at': at.toUtc().toIso8601String(),
        'title': title,
        'body': body,
        'id': ?id,
        'path': path,
        'query': query,
      }, reason),
    )?['id'],
  );

  Future<void> cancel(String id) => _call('notifications.cancel', {'id': id});
}

class BiometricApi {
  const BiometricApi._();

  /// Asks the phone's owner to confirm with fingerprint, face or screen
  /// lock, showing your app's name and [reason] (e.g. "Pay KES 200").
  /// True if confirmed, false if they cancelled. This proves the phone's
  /// owner is there; it is not a login: don't send it to your server as
  /// proof of identity.
  Future<bool> confirm(String reason) async => asBool(
    asMap(await _call('biometric.confirm', {'reason': reason}))?['confirmed'],
  );
}

class ContactsApi {
  const ContactsApi._();

  /// Opens the phone's contacts for the user to pick a phone number. Your
  /// app sees only that contact. Null if they back out.
  Future<PickedContact?> pick() async {
    final m = asMap(await _call('contacts.pick'));
    return m == null ? null : PickedContact.fromJson(m);
  }
}
