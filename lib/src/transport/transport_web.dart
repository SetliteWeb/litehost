import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../errors.dart';
import '../transport.dart';
import 'transport_stub.dart' show NoHost;

/// The object SetLiteWeb injects into every mini app page.
@JS('LiteHost')
external _JsLiteHost? get _jsHost;

extension type _JsLiteHost._(JSObject _) implements JSObject {
  @JS('call')
  external JSPromise<JSAny?> invoke(String method, JSAny? params);
  external JSFunction on(String name, JSFunction listener);
  external void ready();
  external void close();
  external JSNumber? get bridgeVersion;
}

HostTransport defaultTransport() => const WebHost();

class WebHost implements HostTransport {
  const WebHost();

  @override
  bool get isAvailable => _jsHost != null;

  @override
  int get bridgeVersion => _jsHost?.bridgeVersion?.toDartInt ?? 0;

  @override
  Future<Object?> invoke(String method, Map<String, Object?> params) async {
    final host = _jsHost;
    if (host == null) return const NoHost().invoke(method, params);
    try {
      final result = await host.invoke(method, params.jsify()).toDart;
      return result.dartify();
    } catch (e) {
      throw _toException(e, method);
    }
  }

  static LiteHostException _toException(Object e, String method) {
    if (e is LiteHostException) return e;
    String? code;
    var message = '$e';
    try {
      final o = e as JSObject;
      code = (o.getProperty('code'.toJS) as JSString?)?.toDart;
      message = (o.getProperty('message'.toJS) as JSString?)?.toDart ?? message;
    } catch (_) {
      // Not a JS error object: keep the text.
    }
    return LiteHostException(
      LiteHostError.fromCode(code),
      message,
      code: code,
      method: method,
    );
  }

  @override
  Stream<Object?> on(String event) {
    JSFunction? off;
    late final StreamController<Object?> out;
    out = StreamController<Object?>(
      onListen: () {
        final host = _jsHost;
        if (host == null) {
          out.close();
          return;
        }
        off = host.on(
          event,
          ((JSAny? data) {
            if (!out.isClosed) out.add(data.dartify());
          }).toJS,
        );
      },
      onCancel: () {
        off?.callAsFunction();
        off = null;
      },
    );
    return out.stream;
  }

  @override
  void ready() => _jsHost?.ready();

  @override
  void close() => _jsHost?.close();
}
