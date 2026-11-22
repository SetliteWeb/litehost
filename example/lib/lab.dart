/// Runs one feature test and keeps what happened: ok or the host's error
/// code, a short result, and how long it took. No Flutter widgets here, so
/// it can be tested against litehost's MockHost.
library;

import 'package:litehost/litehost.dart';

enum Status { idle, running, ok, failed }

class Outcome {
  const Outcome(this.status, this.text, {this.code, this.ms});
  const Outcome.idle() : this(Status.idle, '');

  final Status status;
  final String text;

  /// The host's error code (`denied`, `unsupported`, …) when it failed.
  final String? code;
  final int? ms;
}

/// Calls [body] and turns its answer, or the host's error, into an Outcome.
Future<Outcome> attempt(Future<String> Function() body) async {
  final sw = Stopwatch()..start();
  try {
    final text = await body();
    return Outcome(Status.ok, text, ms: sw.elapsedMilliseconds);
  } on LiteHostException catch (e) {
    return Outcome(Status.failed, e.message, code: e.code ?? e.error.name, ms: sw.elapsedMilliseconds);
  } catch (e) {
    return Outcome(Status.failed, '$e', code: 'error', ms: sw.elapsedMilliseconds);
  }
}

/// What a code means for the person testing.
String explain(String? code) => switch (code) {
      'denied' => 'You (or an earlier answer) said no. Change it in LiteStore › Mini app permissions.',
      'unsupported' => "This phone or SetLiteWeb version doesn't offer it.",
      'undeclared' => "Not in the app's litestore.yaml / store listing.",
      'cancelled' => 'You backed out of the screen.',
      'blocked' => "Blocked for SetLiteWeb in the phone's settings.",
      'disabled' => 'Turned off on the phone (e.g. Bluetooth or location services).',
      'unavailable' => "The phone couldn't provide it right now.",
      'notInHost' => 'Not running inside SetLiteWeb.',
      'signedOut' => 'Sign in to SetLiteWeb first.',
      'quota' => "The app's storage is full.",
      'invalid' => 'The test sent bad parameters (a bug in Feature Lab).',
      _ => '',
    };

/// The tests that never show a prompt or open another screen.
const quietTests = {'capabilities', 'device', 'wifi.signal', 'clipboard.write', 'storage', 'links', 'haptics', 'keepOn', 'sensors', 'battery'};

/// Storage round trip: set, get, keys, remove, clear.
Future<String> storageRoundTrip() async {
  final stamp = DateTime.now().toIso8601String();
  await LiteHost.storage.set('lab.a', stamp);
  await LiteHost.storage.setJson('lab.b', {'n': 1, 'ok': true});
  final a = await LiteHost.storage.get('lab.a');
  final b = await LiteHost.storage.getJson('lab.b');
  final keys = await LiteHost.storage.keys();
  await LiteHost.storage.remove('lab.a');
  final afterRemove = await LiteHost.storage.get('lab.a');
  await LiteHost.storage.clear();
  final afterClear = await LiteHost.storage.keys();
  final ok = a == stamp && b is Map && b['ok'] == true && keys.contains('lab.a') && afterRemove == null && afterClear.isEmpty;
  if (!ok) throw StateError('round trip mismatch: a=$a b=$b keys=$keys afterRemove=$afterRemove afterClear=$afterClear');
  return 'set, get, JSON, keys (${keys.length}), remove and clear all worked';
}
