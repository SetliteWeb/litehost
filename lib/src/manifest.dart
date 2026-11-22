import 'package:yaml/yaml.dart';

import 'feature.dart';

final _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
final _versionPattern = RegExp(r'^\d+\.\d+\.\d+([-+][0-9A-Za-z.-]+)?$');

/// A required or optional feature: `bluetooth` or `bluetooth@2`.
class FeatureRef {
  const FeatureRef(this.id, [this.version = 1]);

  factory FeatureRef.parse(String raw) {
    final at = raw.indexOf('@');
    if (at < 0) return FeatureRef(raw.trim());
    return FeatureRef(
      raw.substring(0, at).trim(),
      int.tryParse(raw.substring(at + 1).trim()) ?? 0,
    );
  }

  final String id;
  final int version;

  Feature? get feature => Feature.fromId(id);

  @override
  String toString() => version == 1 ? id : '$id@$version';
}

/// `litestore.yaml`: who the app is and what it needs from the host.
///
/// ```yaml
/// id: com.example.duka
/// name: Duka
/// version: 1.0.0
/// summary: Order from shops near you.
/// developer: Example Ltd
/// category: shopping
/// requires: [location]          # hidden on phones without these
/// optional: [scanner, profile.name, storage]
/// ```
class LiteStoreManifest {
  const LiteStoreManifest({
    required this.id,
    required this.name,
    required this.version,
    this.summary = '',
    this.developer = '',
    this.category = '',
    this.icon,
    this.requires = const [],
    this.optional = const [],
    this.minBridgeVersion = 1,
  });

  factory LiteStoreManifest.parse(String yaml) {
    final doc = loadYaml(yaml);
    if (doc is! YamlMap) {
      throw const FormatException('litestore.yaml must be a map of fields.');
    }
    String str(String k) => doc[k] == null ? '' : '${doc[k]}'.trim();
    List<FeatureRef> refs(String k) {
      final v = doc[k];
      if (v == null) return const [];
      if (v is! YamlList) throw FormatException('"$k" must be a list.');
      return [for (final e in v) FeatureRef.parse('$e')];
    }

    return LiteStoreManifest(
      id: str('id'),
      name: str('name'),
      version: str('version'),
      summary: str('summary'),
      developer: str('developer'),
      category: str('category'),
      icon: doc['icon'] == null ? null : str('icon'),
      requires: refs('requires'),
      optional: refs('optional'),
      minBridgeVersion: doc['minBridgeVersion'] is int
          ? doc['minBridgeVersion'] as int
          : 1,
    );
  }

  /// Stable id, e.g. `com.example.duka`: also the link path
  /// (`/a/<id>/...`) and the key for the app's permissions and storage.
  final String id;
  final String name;

  /// Semantic version; the store compares it to decide on updates.
  final String version;
  final String summary;
  final String developer;
  final String category;

  /// Path to the icon, relative to litestore.yaml.
  final String? icon;
  final List<FeatureRef> requires;
  final List<FeatureRef> optional;
  final int minBridgeVersion;

  Set<String> get declaredIds => {
    for (final r in requires) r.id,
    for (final r in optional) r.id,
  };

  /// Problems that would make the store refuse the app.
  List<String> errors() => [
    if (!_idPattern.hasMatch(id))
      'id "$id" must be letters, digits, ".", "_" or "-" (e.g. com.example.duka).',
    if (name.isEmpty) 'name is missing.',
    if (name.length > 40) 'name is longer than 40 characters.',
    if (!_versionPattern.hasMatch(version))
      'version "$version" must look like 1.0.0.',
    if (minBridgeVersion < 1) 'minBridgeVersion must be 1 or more.',
    for (final r in [...requires, ...optional])
      if (r.version < 1) 'feature "$r" has a bad version.',
    for (final id in requires.map((r) => r.id).toSet())
      if (optional.any((o) => o.id == id))
        '"$id" is in both requires and optional.',
  ];

  /// Worth fixing, but not blocking.
  List<String> warnings() => [
    for (final r in [...requires, ...optional])
      if (r.feature == null)
        'feature "${r.id}" is unknown to this version of litehost; phones '
            'without it will hide the app if it is required.',
    if (summary.isEmpty) 'summary is empty: the store shows it under the name.',
  ];

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'summary': summary,
    'developer': developer,
    'category': category,
    'requires': [for (final r in requires) '$r'],
    'optional': [for (final r in optional) '$r'],
    'minBridgeVersion': minBridgeVersion,
  };
}
