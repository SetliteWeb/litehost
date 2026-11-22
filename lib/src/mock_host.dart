import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'errors.dart';
import 'feature.dart';
import 'json.dart';
import 'transport.dart';

typedef MockHandler = FutureOr<Object?> Function(Map<String, Object?> params);

/// A stand-in for SetLiteWeb, for developing in a normal browser and for
/// tests. It checks features like the real host: undeclared features fail
/// with `undeclared`, missing ones with `unsupported`, and [denied] ones
/// with `denied`.
///
/// ```dart
/// void main() {
///   if (!LiteHost.isAvailable) {
///     LiteHost.useMock(MockHost(declared: {Feature.location, Feature.scanner}));
///   }
///   runApp(const MyApp());
/// }
/// ```
///
/// Every method has a sensible fake answer; replace one with [handle]:
/// `mock.handle('scanner.scan', (_) => {'text': 'TICKET-42'})`.
class MockHost implements HostTransport {
  MockHost({
    Set<Feature>? declared,
    Set<Feature>? available,
    Set<Feature>? denied,
    this.platform = 'android',
    this.bridgeVersion = 1,
    this.appId = 'com.example.app',
    this.profileName = 'Jane Doe',
    this.profilePhone = '+15555550100',
    this.profileEmail = 'jane@example.com',
  }) : declared = declared ?? Feature.values.toSet(),
       available = available ?? Feature.values.toSet(),
       denied = denied ?? {} {
    _installDefaults();
  }

  /// Features the app's manifest lists (default: all).
  final Set<Feature> declared;

  /// Features this pretend phone has (default: all).
  final Set<Feature> available;

  /// Features the pretend user refused.
  final Set<Feature> denied;

  final String platform;

  @override
  final int bridgeVersion;

  /// Used in links made by `LiteHost.links.create`.
  final String appId;

  String? profileName;
  String? profilePhone;
  String? profileEmail;

  /// Fixes `wifi.signal`'s reading (dBm); null: it drifts like a walk.
  int? mockRssi;

  /// Pretend no one is signed in to SetLiteWeb.
  bool signedOut = false;

  /// Every call made, in order: (method, params).
  final List<(String, Map<String, Object?>)> calls = [];

  /// What `storage.*` holds.
  final Map<String, String> storage = {};

  /// Shown or scheduled notifications by id (their params).
  final Map<String, Map<String, Object?>> notifications = {};

  /// What `biometric.confirm` answers.
  bool biometricConfirms = true;

  final Map<String, MockHandler> _handlers = {};
  final Map<String, StreamController<Object?>> _events = {};

  /// Times [ready] and [close] were called.
  int readyCount = 0;
  int closeCount = 0;

  /// Replaces the answer for [method].
  void handle(String method, MockHandler handler) =>
      _handlers[method] = handler;

  /// Sends an event to the app, as the host would.
  void emit(String event, [Object? data]) =>
      _events[event]?.add(_roundTrip(data));

  void pause() => emit('app.pause');
  void resume() => emit('app.resume');

  void openLink(
    String path, {
    Map<String, String> query = const {},
    String fragment = '',
  }) => emit('app.link', {'path': path, 'query': query, 'fragment': fragment});

  @override
  bool get isAvailable => true;

  @override
  void ready() => readyCount++;

  @override
  void close() => closeCount++;

  @override
  Stream<Object?> on(String event) {
    final c = _events.putIfAbsent(
      event,
      () => StreamController<Object?>.broadcast(),
    );
    return c.stream;
  }

  @override
  Future<Object?> invoke(String method, Map<String, Object?> params) async {
    final p = asMap(_roundTrip(params)) ?? {};
    calls.add((method, p));
    if (!bridgeMethods.containsKey(method)) {
      throw LiteHostException(
        LiteHostError.unsupported,
        'SetLiteWeb has no "$method".',
        code: 'unsupported',
        method: method,
      );
    }
    final feature = bridgeMethods[method];
    if (feature != null) _check(feature, method);
    final handler = _handlers[method];
    if (handler == null) {
      throw LiteHostException(
        LiteHostError.unsupported,
        'MockHost has no answer for "$method".',
        code: 'unsupported',
        method: method,
      );
    }
    // Like the real bridge: answers arrive asynchronously, as JSON.
    await Future<void>.delayed(Duration.zero);
    return _roundTrip(await handler(p));
  }

  void _check(Feature f, String method) {
    if (!available.contains(f)) {
      throw LiteHostException(
        LiteHostError.unsupported,
        '${f.id} isn\'t available on this phone.',
        code: 'unsupported',
        method: method,
      );
    }
    if (!declared.contains(f)) {
      throw LiteHostException(
        LiteHostError.undeclared,
        'Add "${f.id}" to litestore.yaml (requires or optional) to use it.',
        code: 'undeclared',
        method: method,
      );
    }
    if (denied.contains(f)) {
      throw LiteHostException(
        LiteHostError.denied,
        'The user didn\'t allow ${f.id}.',
        code: 'denied',
        method: method,
      );
    }
  }

  static Object? _roundTrip(Object? v) =>
      v == null ? null : jsonDecode(jsonEncode(v));

  int _nextId = 1;
  final Map<String, Timer> _running = {};

  void _installDefaults() {
    handle('host.capabilities', (_) {
      return {
        'bridgeVersion': bridgeVersion,
        'platform': platform,
        'features': {for (final f in available) f.id: 1},
        'methods': [
          for (final e in bridgeMethods.entries)
            if (e.value == null || available.contains(e.value)) e.key,
        ],
        'granted': {
          for (final f in declared)
            if (f.asksUser) f.id: denied.contains(f) ? 'denied' : null,
        },
      };
    });
    handle(
      'location.get',
      (p) => {
        'latitude': -1.2864,
        'longitude': 36.8172,
        'accuracy': p['precise'] == false ? 1000 : 12,
      },
    );
    handle('camera.request', (_) => true);
    handle('microphone.request', (_) => true);
    handle(
      'wifi.get',
      (_) => {'ssid': 'MockWiFi', 'bssid': null, 'ip': '192.168.1.20'},
    );
    handle('wifi.signal', (_) {
      // A slow walk towards the router and back.
      final t = DateTime.now().millisecondsSinceEpoch / 1000;
      final rssi = mockRssi ?? (-66 + 14 * math.sin(t / 6)).round();
      return {
        'connected': true,
        'rssi': rssi,
        'linkMbps': 72,
        'frequencyMhz': 5180,
        'band': '5 GHz',
      };
    });
    handle('clipboard.read', (_) => 'copied text');
    handle('clipboard.write', (_) => null);
    handle('profile.get', (p) {
      if (signedOut) {
        throw const LiteHostException(
          LiteHostError.signedOut,
          'Sign in to SetLiteWeb first.',
          code: 'signedOut',
        );
      }
      final fields = {for (final f in asList(p['fields'])) '$f'};
      final byField = {
        'name': (Feature.profileName, profileName),
        'phone': (Feature.profilePhone, profilePhone),
        'email': (Feature.profileEmail, profileEmail),
      };
      for (final f in fields) {
        final entry = byField[f];
        if (entry != null && !declared.contains(entry.$1)) {
          _check(entry.$1, 'profile.get');
        }
      }
      return {
        'id': 'mock-user-$appId',
        for (final f in fields)
          if (byField[f] case (
            final feature,
            final value,
          ) when !denied.contains(feature) && value != null)
            f: value,
      };
    });
    handle('auth.token', (_) {
      if (signedOut) {
        throw const LiteHostException(
          LiteHostError.signedOut,
          'Sign in to SetLiteWeb first.',
          code: 'signedOut',
        );
      }
      return {'token': 'mock-token-for-$appId', 'expiresIn': 300};
    });
    handle(
      'auth.browser',
      (_) => {'url': 'setliteweb-litestore://callback?code=mock-code'},
    );
    handle('scanner.scan', (_) => {'text': 'MOCK-QR-CODE'});
    // A 1x1 transparent PNG.
    handle(
      'image.pick',
      (_) => {
        'mime': 'image/png',
        'data':
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
      },
    );
    handle('share', (_) => null);
    handle('open.url', (_) => null);
    handle('haptics', (_) => null);
    handle('screen.keepOn', (_) => null);
    handle('storage.get', (p) => storage[asString(p['key'])]);
    handle('storage.set', (p) {
      storage[asString(p['key'])] = asString(p['value']);
      return null;
    });
    handle('storage.remove', (p) => storage.remove(asString(p['key'])));
    handle('storage.keys', (_) => storage.keys.toList());
    handle('storage.clear', (_) {
      storage.clear();
      return null;
    });
    handle(
      'device.info',
      (_) => {
        'platform': platform,
        'os': platform == 'ios' ? 'iOS 18.0' : 'Android 15',
        'model': 'Mock Phone',
        'manufacturer': 'MockHost',
        'hostVersion': '0.0.0-mock',
        'bridgeVersion': bridgeVersion,
        'locale': 'en_KE',
      },
    );
    handle('link.create', (p) {
      final path = asString(p['path'], '/');
      final query = {
        for (final e in (asMap(p['query']) ?? const {}).entries)
          e.key: asString(e.value),
      };
      return {
        'url': Uri.https(
          'portal.setliteweb.com',
          '/a/$appId$path',
          query.isEmpty ? null : query,
        ).toString(),
      };
    });

    handle('notifications.show', (p) {
      final id = asNullableString(p['id']) ?? 'n${_nextId++}';
      notifications[id] = p;
      return {'id': id};
    });
    handle('notifications.schedule', (p) {
      final at = DateTime.tryParse(asString(p['at']));
      if (at == null || !at.isAfter(DateTime.now())) {
        throw const LiteHostException(
          LiteHostError.invalid,
          '"at" must be a future time.',
          code: 'invalid',
        );
      }
      final id = asNullableString(p['id']) ?? 'n${_nextId++}';
      notifications[id] = p;
      return {'id': id};
    });
    handle('notifications.cancel', (p) {
      notifications.remove(asString(p['id']));
      return null;
    });
    handle('biometric.confirm', (_) => {'confirmed': biometricConfirms});
    handle(
      'contacts.pick',
      (_) => {
        'name': 'Amina Wanjiru',
        'phone': '+15555550101',
        'phones': ['+15555550101', '+15555550102'],
      },
    );

    // Bluetooth: one scan finds two pretend devices; notifications tick.
    final connected = <String>{};
    handle('bluetooth.scan', (_) {
      final id = 'scan-${_nextId++}';
      final devices = [
        {
          'id': 'AA:BB:CC:00:00:01',
          'name': 'Mock Scale',
          'rssi': -48,
          'connectable': true,
        },
        {
          'id': 'AA:BB:CC:00:00:02',
          'name': '',
          'rssi': -80,
          'connectable': false,
        },
      ];
      var i = 0;
      _running[id] = Timer.periodic(const Duration(milliseconds: 20), (t) {
        if (i < devices.length) {
          emit('bluetooth.device', {'scanId': id, ...devices[i++]});
        } else {
          t.cancel();
          _running.remove(id);
          emit('bluetooth.scanEnd', {'scanId': id});
        }
      });
      return {'scanId': id};
    });
    handle('bluetooth.stopScan', (p) {
      _running.remove(asString(p['scanId']))?.cancel();
      return null;
    });
    handle('bluetooth.connect', (p) {
      connected.add(asString(p['deviceId']));
      return null;
    });
    handle('bluetooth.disconnect', (p) {
      connected.remove(asString(p['deviceId']));
      return null;
    });
    void needConnected(Map<String, Object?> p) {
      if (!connected.contains(asString(p['deviceId']))) {
        throw const LiteHostException(
          LiteHostError.invalid,
          'Connect to the device first (bluetooth.connect).',
          code: 'invalid',
        );
      }
    }

    handle('bluetooth.services', (p) {
      needConnected(p);
      return [
        {
          'uuid': '0000181d-0000-1000-8000-00805f9b34fb',
          'characteristics': [
            {
              'uuid': '00002a9d-0000-1000-8000-00805f9b34fb',
              'properties': ['read', 'notify'],
            },
            {
              'uuid': '00002a9e-0000-1000-8000-00805f9b34fb',
              'properties': ['write'],
            },
          ],
        },
      ];
    });
    handle('bluetooth.read', (p) {
      needConnected(p);
      return base64Encode([1, 2, 3]);
    });
    handle('bluetooth.write', (p) {
      needConnected(p);
      return null;
    });
    handle('bluetooth.subscribe', (p) {
      needConnected(p);
      final id = 'notify-${_nextId++}';
      var n = 0;
      _running[id] = Timer.periodic(const Duration(milliseconds: 20), (_) {
        emit('bluetooth.value', {
          'subscriptionId': id,
          'value': base64Encode([n++ & 0xff]),
        });
      });
      return {'subscriptionId': id};
    });
    handle('bluetooth.unsubscribe', (p) {
      _running.remove(asString(p['subscriptionId']))?.cancel();
      return null;
    });
  }

  /// Stops pretend scans and notifications.
  void dispose() {
    for (final t in _running.values) {
      t.cancel();
    }
    _running.clear();
    for (final c in _events.values) {
      c.close();
    }
    _events.clear();
  }
}
