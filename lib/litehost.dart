/// Use SetLiteWeb's features from a LiteStore mini app.
///
/// Start with [LiteHost]. While developing in a normal browser, use a
/// [MockHost]: `if (!LiteHost.isAvailable) LiteHost.useMock(MockHost());`
library;

export 'src/api.dart';
export 'src/errors.dart';
export 'src/feature.dart' show Feature;
export 'src/mock_host.dart';
export 'src/models.dart';
export 'src/transport.dart';
