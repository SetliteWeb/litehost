import 'dart:io';

import '../feature.dart';
import '../manifest.dart';

/// A LiteHost API used in code, and where.
class FeatureUse {
  const FeatureUse(this.feature, this.file, this.line);

  final Feature feature;
  final String file;
  final int line;

  @override
  String toString() => '$file:$line (${feature.id})';
}

final _call = RegExp(r'LiteHost\s*\.\s*(\w+)(?:\s*\.\s*(\w+))?');
final _profileField = RegExp(
  r'ProfileField\s*\.\s*(name|phone|email|values)\b',
);

const _byApi = {
  'location': Feature.location,
  'camera': Feature.camera,
  'microphone': Feature.microphone,
  'bluetooth': Feature.bluetooth,
  'wifi': Feature.wifi,
  'scanner': Feature.scanner,
  'image': Feature.imagePick,
  'share': Feature.share,
  'openUrl': Feature.openUrl,
  'haptics': Feature.haptics,
  'keepScreenOn': Feature.keepScreenOn,
  'storage': Feature.storage,
  'device': Feature.deviceInfo,
  'links': Feature.links,
  'notifications': Feature.notifications,
  'biometric': Feature.biometric,
  'contacts': Feature.contactsPick,
  'torch': Feature.torch,
  'nfc': Feature.nfc,
  'sensors': Feature.sensors,
  'gestures': Feature.gestures,
  'phone': Feature.phoneCall,
  'sms': Feature.smsOtp,
  'screen': Feature.screenCapture,
  'pip': Feature.pip,
};

const _bySubApi = {
  'wifi.get': Feature.wifi,
  'wifi.signal': Feature.wifiSignal,
  'wifi.enable': Feature.wifiEnable,
  'location.track': Feature.locationBackground,
  'clipboard.read': Feature.clipboardRead,
  'clipboard.write': Feature.clipboardWrite,
  'auth.token': Feature.authToken,
  'auth.browser': Feature.authBrowser,
};

const _profile = {
  'name': Feature.profileName,
  'phone': Feature.profilePhone,
  'email': Feature.profileEmail,
  'photo': Feature.profilePhoto,
};

/// Dart, and JavaScript for apps that call `window.LiteHost` directly.
const _scanned = ['.dart', '.js', '.mjs', '.html'];

/// Features the code under [dir] uses through LiteHost.
List<FeatureUse> scanUses(Directory dir) {
  final uses = <FeatureUse>[];
  if (!dir.existsSync()) return uses;
  final files =
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => _scanned.any(f.path.endsWith))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) continue;
      for (final m in _call.allMatches(line)) {
        final api = m.group(1)!;
        final feature = _bySubApi['$api.${m.group(2)}'] ?? _byApi[api];
        if (feature != null) uses.add(FeatureUse(feature, f.path, i + 1));
      }
      for (final m in _profileField.allMatches(line)) {
        final field = m.group(1)!;
        for (final feature
            in field == 'values' ? _profile.values : [_profile[field]!]) {
          uses.add(FeatureUse(feature, f.path, i + 1));
        }
      }
    }
  }
  return uses;
}

class CheckResult {
  CheckResult(this.undeclared, this.unused);

  /// Used in code but not in litestore.yaml: the host will refuse them.
  final List<FeatureUse> undeclared;

  /// Declared but never used: users may be asked about them for nothing.
  final List<String> unused;

  bool get ok => undeclared.isEmpty;
}

CheckResult checkUses(LiteStoreManifest manifest, List<FeatureUse> uses) {
  final declared = manifest.declaredIds;
  final used = {for (final u in uses) u.feature.id};
  return CheckResult(
    [
      for (final u in uses)
        if (!declared.contains(u.feature.id)) u,
    ],
    [
      for (final id in declared)
        // `account` is a requirement, not something code calls.
        if (!used.contains(id) && id != 'account' && Feature.fromId(id) != null) id,
    ],
  );
}
