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

/// A phone sensor `LiteHost.sensors` can read (Android).
enum SensorType {
  accelerometer,
  gyroscope,
  magnetometer,
  gravity,
  linearAcceleration,
  rotation,
  light,
  pressure,
  proximity,

  /// Air temperature (°C). Few phones have it; every phone reports its
  /// battery temperature in [Battery.temperatureC].
  temperature,
  humidity,
  stepCounter;

  static SensorType? fromName(String n) {
    for (final t in values) {
      if (t.name == n) return t;
    }
    return null;
  }
}

class SensorInfo {
  const SensorInfo({
    required this.type,
    required this.name,
    required this.vendor,
    this.maxRange,
    this.resolution,
  });

  factory SensorInfo.fromJson(Map<String, Object?> j) => SensorInfo(
    type: SensorType.fromName(asString(j['type'])) ?? SensorType.accelerometer,
    name: asString(j['name']),
    vendor: asString(j['vendor']),
    maxRange: (j['maxRange'] as num?)?.toDouble(),
    resolution: (j['resolution'] as num?)?.toDouble(),
  );

  final SensorType type;
  final String name;
  final String vendor;
  final double? maxRange;
  final double? resolution;
}

/// One reading. [values] as Android gives them: x, y, z in m/s² or rad/s
/// for motion; one value for light (lux), pressure (hPa), proximity (cm),
/// temperature (°C), humidity (%), steps since boot.
class SensorReading {
  const SensorReading({required this.values, this.accuracy = 0});

  factory SensorReading.fromJson(Map<String, Object?> j) => SensorReading(
    values: [for (final v in asList(j['values'])) (v as num).toDouble()],
    accuracy: (j['accuracy'] as num?)?.toInt() ?? 0,
  );

  final List<double> values;

  /// 0 (unreliable) to 3 (high).
  final int accuracy;
}

class Battery {
  const Battery({this.level, required this.charging, this.temperatureC});

  factory Battery.fromJson(Map<String, Object?> j) => Battery(
    level: (j['level'] as num?)?.toInt(),
    charging: j['charging'] == true,
    temperatureC: (j['temperatureC'] as num?)?.toDouble(),
  );

  /// 0-100.
  final int? level;
  final bool charging;

  /// The battery's temperature: every phone has this one.
  final double? temperatureC;
}

enum PhoneGesture { shake, faceDown, faceUp, tiltLeft, tiltRight, wave }

/// One NDEF record from an NFC tag.
class NfcRecord {
  const NfcRecord({
    required this.kind,
    required this.type,
    required this.data,
    this.text,
    this.uri,
    this.lang,
    this.mime,
  });

  factory NfcRecord.fromJson(Map<String, Object?> j) => NfcRecord(
    kind: asString(j['kind'], 'other'),
    type: asString(j['type']),
    data: base64Decode(asString(j['data'])),
    text: asNullableString(j['text']),
    uri: asNullableString(j['uri']),
    lang: asNullableString(j['lang']),
    mime: asNullableString(j['mime']),
  );

  /// `text`, `uri`, `mime`, `external` or `other`.
  final String kind;
  final String type;
  final Uint8List data;
  final String? text;
  final String? uri;
  final String? lang;
  final String? mime;
}

/// A tag or card held to the phone. Only what it offers as NDEF: SetLiteWeb
/// sends no commands to cards, so a bank card gives just a random [id].
class NfcTagInfo {
  const NfcTagInfo({
    this.id,
    required this.techs,
    required this.records,
    this.writable,
    this.maxSize,
  });

  factory NfcTagInfo.fromJson(Map<String, Object?> j) => NfcTagInfo(
    id: asNullableString(j['id']),
    techs: [for (final t in asList(j['techs'])) '$t'],
    records: [
      for (final r in asList(j['ndef']))
        NfcRecord.fromJson(asMap(r) ?? const {}),
    ],
    writable: j['writable'] as bool?,
    maxSize: (j['maxSize'] as num?)?.toInt(),
  );

  /// "04:A2:2B:1A:…".
  final String? id;

  /// "NfcA", "IsoDep", "Ndef", …
  final List<String> techs;
  final List<NfcRecord> records;
  final bool? writable;
  final int? maxSize;
}

/// One background location fix ([LiteHost.location.track]).
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.speed,
    this.heading,
    this.altitude,
    this.at,
  });

  factory LocationFix.fromJson(Map<String, Object?> j) => LocationFix(
    latitude: (j['latitude'] as num).toDouble(),
    longitude: (j['longitude'] as num).toDouble(),
    accuracyMeters: (j['accuracy'] as num?)?.toDouble() ?? 0,
    speed: (j['speed'] as num?)?.toDouble(),
    heading: (j['heading'] as num?)?.toDouble(),
    altitude: (j['altitude'] as num?)?.toDouble(),
    at: DateTime.tryParse(asString(j['at'])),
  );

  final double latitude;
  final double longitude;
  final double accuracyMeters;

  /// m/s.
  final double? speed;

  /// Degrees from north.
  final double? heading;
  final double? altitude;
  final DateTime? at;
}

/// A one-time-code SMS the user let the app read.
class OtpSms {
  const OtpSms({required this.sms, this.code});
  factory OtpSms.fromJson(Map<String, Object?> j) =>
      OtpSms(sms: asString(j['sms']), code: asNullableString(j['code']));

  final String sms;

  /// The code found in it (4-8 digits), if any.
  final String? code;
}

class Screenshot {
  const Screenshot({
    required this.png,
    required this.width,
    required this.height,
  });
  factory Screenshot.fromJson(Map<String, Object?> j) => Screenshot(
    png: base64Decode(asString(j['data'])),
    width: (j['width'] as num?)?.toInt() ?? 0,
    height: (j['height'] as num?)?.toInt() ?? 0,
  );

  final Uint8List png;
  final int width;
  final int height;
}
