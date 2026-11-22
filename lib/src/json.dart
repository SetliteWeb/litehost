// Values from the host arrive as JSON-like data; numbers may be doubles
// even when whole (dart2wasm), so read them leniently.

Map<String, Object?>? asMap(Object? v) =>
    v is Map ? {for (final e in v.entries) '${e.key}': e.value} : null;

List<Object?> asList(Object? v) => v is List ? v : const [];

String asString(Object? v, [String fallback = '']) =>
    v == null ? fallback : '$v';

String? asNullableString(Object? v) =>
    v == null || (v is String && v.isEmpty) ? null : '$v';

int asInt(Object? v, [int fallback = 0]) => switch (v) {
  int i => i,
  num n => n.toInt(),
  String s => int.tryParse(s) ?? fallback,
  _ => fallback,
};

double asDouble(Object? v, [double fallback = 0]) => switch (v) {
  num n => n.toDouble(),
  String s => double.tryParse(s) ?? fallback,
  _ => fallback,
};

bool asBool(Object? v) => v == true || v == 'true' || v == 1;
