import 'dart:convert';
import 'dart:typed_data';

import 'feature.dart';
import 'json.dart';

/// What the host offers on this phone, and what the user already answered
/// for this app.
class HostCapabilities {
  const HostCapabilities({
    required this.bridgeVersion,
    required this.platform,
    required this.features,
    required this.methods,
    this.granted = const {},
  });

  factory HostCapabilities.fromJson(Map<String, Object?> j) => HostCapabilities(
    bridgeVersion: asInt(j['bridgeVersion']),
    platform: asString(j['platform']),
    features: {
      for (final e in (asMap(j['features']) ?? const {}).entries)
        e.key: asInt(e.value, 1),
    },
    methods: {for (final m in asList(j['methods'])) '$m'},
    granted: {
      for (final e in (asMap(j['granted']) ?? const {}).entries)
        if (Feature.fromId(e.key) case final f?)
          f: e.value == null ? null : Grant.fromName('${e.value}'),
    },
  );

  final int bridgeVersion;

  /// `android` or `ios`.
  final String platform;

  /// Feature id -> version this phone provides.
  final Map<String, int> features;

  /// Bridge methods that work here.
  final Set<String> methods;

  /// Earlier answers for features that ask the user (null: not asked yet).
  final Map<Feature, Grant?> granted;

  bool has(Feature f, {int version = 1}) => (features[f.id] ?? 0) >= version;
}

enum Grant {
  allowed,
  once,
  denied;

  static Grant? fromName(String name) {
    for (final g in values) {
      if (g.name == name) return g;
    }
    return null;
  }
}

class Position {
  const Position({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
  });

  factory Position.fromJson(Map<String, Object?> j) => Position(
    latitude: asDouble(j['latitude']),
    longitude: asDouble(j['longitude']),
    accuracyMeters: asDouble(j['accuracy']),
  );

  final double latitude;
  final double longitude;
  final double accuracyMeters;

  @override
  String toString() => 'Position($latitude, $longitude ±${accuracyMeters}m)';
}

class WifiInfo {
  const WifiInfo({this.ssid, this.bssid, this.ip});

  factory WifiInfo.fromJson(Map<String, Object?> j) => WifiInfo(
    ssid: asNullableString(j['ssid']),
    bssid: asNullableString(j['bssid']),
    ip: asNullableString(j['ip']),
  );

  /// Null when the phone won't say (not on Wi-Fi, or iOS limits).
  final String? ssid;
  final String? bssid;
  final String? ip;
}

/// How good a Wi-Fi signal is, from [WifiSignal.rssi].
enum WifiQuality {
  excellent('Excellent'),
  good('Good'),
  fair('Fair'),
  weak('Weak'),
  veryWeak('Very weak');

  const WifiQuality(this.label);

  /// For people: "Excellent", "Very weak", ...
  final String label;

  static WifiQuality fromRssi(int dbm) {
    if (dbm >= -55) return excellent;
    if (dbm >= -65) return good;
    if (dbm >= -72) return fair;
    if (dbm >= -80) return weak;
    return veryWeak;
  }
}

/// How strong the phone's Wi-Fi signal is where it is now. Never the
/// network's name, so the user isn't asked (Android only; iOS doesn't let
/// apps read signal strength).
class WifiSignal {
  const WifiSignal({
    required this.connected,
    this.rssi,
    this.linkMbps,
    this.frequencyMhz,
    this.band,
  });

  factory WifiSignal.fromJson(Map<String, Object?> j) {
    int? n(Object? v) => v is num ? v.toInt() : null;
    final rssi = n(j['rssi']);
    return WifiSignal(
      connected: j['connected'] == true,
      rssi: rssi != null && rssi < 0 && rssi > -127 ? rssi : null,
      linkMbps: n(j['linkMbps']),
      frequencyMhz: n(j['frequencyMhz']),
      band: asNullableString(j['band']),
    );
  }

  /// On Wi-Fi at all.
  final bool connected;

  /// Signal in dBm: about -45 (next to the router) to -90 (barely there).
  /// Null until the phone has measured it.
  final int? rssi;

  /// The Wi-Fi link's speed (phone to router, not the internet).
  final int? linkMbps;
  final int? frequencyMhz;

  /// "2.4 GHz", "5 GHz" or "6 GHz".
  final String? band;

  /// 0-100 for a meter: -45 dBm or better is 100, -95 is 0.
  int? get percent =>
      rssi == null ? null : ((rssi! + 95) / 50 * 100).round().clamp(0, 100);

  WifiQuality? get quality => rssi == null ? null : WifiQuality.fromRssi(rssi!);

  @override
  String toString() => connected
      ? 'WifiSignal($rssi dBm, $band, $linkMbps Mbps)'
      : 'WifiSignal(not on Wi-Fi)';
}

enum ProfileField { name, phone, email }

/// Only the fields the user agreed to share. [id] is stable for this user
/// in this app, but can't be matched across apps.
class Profile {
  const Profile({required this.id, this.name, this.phone, this.email});

  factory Profile.fromJson(Map<String, Object?> j) => Profile(
    id: asString(j['id']),
    name: asNullableString(j['name']),
    phone: asNullableString(j['phone']),
    email: asNullableString(j['email']),
  );

  final String id;
  final String? name;
  final String? phone;
  final String? email;
}

/// "Sign in with SetLiteWeb": send [token] to your own server, which
/// verifies it (signature, audience = your app id, expiry).
class AppToken {
  const AppToken({required this.token, required this.expiresIn});

  factory AppToken.fromJson(Map<String, Object?> j) => AppToken(
    token: asString(j['token']),
    expiresIn: Duration(seconds: asInt(j['expiresIn'], 300)),
  );

  final String token;
  final Duration expiresIn;
}

enum ImageSource { camera, gallery }

class PickedImage {
  const PickedImage({required this.mime, required this.bytes});

  factory PickedImage.fromJson(Map<String, Object?> j) => PickedImage(
    mime: asString(j['mime'], 'image/jpeg'),
    bytes: base64Decode(asString(j['data'])),
  );

  final String mime;
  final Uint8List bytes;
}

enum HapticStyle { light, medium, heavy, selection }

/// The contact the user picked; nothing else from their address book.
class PickedContact {
  const PickedContact({required this.name, this.phone, this.phones = const []});

  factory PickedContact.fromJson(Map<String, Object?> j) => PickedContact(
    name: asString(j['name']),
    phone: asNullableString(j['phone']),
    phones: [for (final p in asList(j['phones'])) '$p'],
  );

  final String name;

  /// The number the user chose.
  final String? phone;
  final List<String> phones;
}

class DeviceInfo {
  const DeviceInfo({
    required this.platform,
    required this.os,
    required this.model,
    required this.manufacturer,
    required this.hostVersion,
    required this.bridgeVersion,
    required this.locale,
  });

  factory DeviceInfo.fromJson(Map<String, Object?> j) => DeviceInfo(
    platform: asString(j['platform']),
    os: asString(j['os']),
    model: asString(j['model']),
    manufacturer: asString(j['manufacturer']),
    hostVersion: asString(j['hostVersion']),
    bridgeVersion: asInt(j['bridgeVersion']),
    locale: asString(j['locale']),
  );

  final String platform;
  final String os;
  final String model;
  final String manufacturer;

  /// SetLiteWeb's version.
  final String hostVersion;
  final int bridgeVersion;
  final String locale;
}

/// A shared link that opened (or was sent to) this app.
class AppLink {
  const AppLink({
    required this.path,
    this.query = const {},
    this.fragment = '',
  });

  factory AppLink.fromJson(Map<String, Object?> j) => AppLink(
    path: asString(j['path'], '/'),
    query: {
      for (final e in (asMap(j['query']) ?? const {}).entries)
        e.key: asString(e.value),
    },
    fragment: asString(j['fragment']),
  );

  final String path;
  final Map<String, String> query;
  final String fragment;

  /// As a relative URI, e.g. `/item/42?shop=njeri`, for routers.
  Uri get uri => Uri(
    path: path,
    queryParameters: query.isEmpty ? null : query,
    fragment: fragment.isEmpty ? null : fragment,
  );
}

class BleDevice {
  const BleDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.connectable,
  });

  factory BleDevice.fromJson(Map<String, Object?> j) => BleDevice(
    id: asString(j['id']),
    name: asString(j['name']),
    rssi: asInt(j['rssi']),
    connectable: j['connectable'] == null || asBool(j['connectable']),
  );

  final String id;

  /// Empty when the device doesn't advertise one.
  final String name;
  final int rssi;
  final bool connectable;
}

class BleService {
  const BleService({required this.uuid, required this.characteristics});

  factory BleService.fromJson(Map<String, Object?> j) => BleService(
    uuid: asString(j['uuid']),
    characteristics: [
      for (final c in asList(j['characteristics']))
        if (asMap(c) case final m?) BleCharacteristic.fromJson(m),
    ],
  );

  final String uuid;
  final List<BleCharacteristic> characteristics;
}

class BleCharacteristic {
  const BleCharacteristic({required this.uuid, required this.properties});

  factory BleCharacteristic.fromJson(Map<String, Object?> j) =>
      BleCharacteristic(
        uuid: asString(j['uuid']),
        properties: {for (final p in asList(j['properties'])) '$p'},
      );

  final String uuid;

  /// e.g. `read`, `write`, `writeWithoutResponse`, `notify`, `indicate`.
  final Set<String> properties;

  bool get canRead => properties.contains('read');
  bool get canWrite =>
      properties.contains('write') ||
      properties.contains('writeWithoutResponse');
  bool get canNotify =>
      properties.contains('notify') || properties.contains('indicate');
}
