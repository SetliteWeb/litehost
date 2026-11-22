import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Opens the camera or microphone for a moment and closes it again: the
/// real test that the WebView passes the permission through.
Future<String> openStream({required bool video}) async {
  final stream = await web.window.navigator.mediaDevices
      .getUserMedia(web.MediaStreamConstraints(video: video.toJS, audio: (!video).toJS))
      .toDart;
  final tracks = stream.getTracks().toDart;
  final parts = <String>[];
  for (final t in tracks) {
    final s = t.getSettings();
    parts.add(video ? '${t.label.isEmpty ? 'camera' : t.label} ${s.width}×${s.height}' : (t.label.isEmpty ? 'microphone' : t.label));
    t.stop();
  }
  return parts.isEmpty ? 'stream opened, no tracks' : 'stream opened: ${parts.join(', ')}';
}
