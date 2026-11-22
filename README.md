# litehost

Use SetLiteWeb's phone features from a **LiteStore mini app**: location,
QR scanner, Bluetooth, profile, sign-in, storage and more, with typed Dart
APIs. Mini apps are web apps (Flutter web or any Dart web app) that
SetLiteWeb downloads, verifies and runs offline inside its own screen.

```dart
import 'package:litehost/litehost.dart';

void main() {
  // Outside SetLiteWeb (e.g. `flutter run -d chrome`): pretend answers.
  if (!LiteHost.isAvailable) LiteHost.useMock(MockHost());
  runApp(const MyApp());
}

Future<void> findShops() async {
  try {
    final pos = await LiteHost.location.get(reason: 'To find shops near you');
    // ...
  } on LiteHostException catch (e) {
    if (e.error == LiteHostError.denied) showManualAddress();
  }
}
```

## How it works

- Every feature that touches the user (location, camera, profile…) shows
  SetLiteWeb's consent sheet the first time; the answer is remembered per
  app. Pass `reason` to explain why you need it.
- Your app can only use features it declares in `litestore.yaml`. Phones
  that lack a **required** feature never see your app in the store.
- Call `LiteHost.capabilities()` to hide options the phone doesn't offer.

## litestore.yaml

```yaml
id: com.example.duka        # also your link path: /a/com.example.duka/...
name: Duka
version: 1.0.0
summary: Order from shops near you.
developer: Example Ltd
category: shopping
requires: [location]        # app is hidden where these are missing
optional: [scanner, profile.name, storage]
```

## Apps written in JavaScript

The host injects the same API as `window.LiteHost` into every page, so a
plain HTML/JS mini app can call it directly; keep its page in `web/` and
`litehost:check` reads it too:

```js
if (window.LiteHost) {
  const s = await LiteHost.wifi.signal();   // { connected, rssi, linkMbps, band }
  LiteHost.haptics({ style: 'light' });
  LiteHost.on('app.pause', saveDraft);
  LiteHost.ready();                         // hide the splash
}
```

```sh
dart run litehost:build --dir web           # package it with the listing
```

## Tools

```sh
dart run litehost:check     # code uses only declared features?
dart run litehost:build     # flutter build web + zip + SHA-256 + listing
dart run litehost:build --dir dist   # package any already built site
dart run litehost:build --target lib/main_prod.dart   # another entry point
```

The output in `build/litestore/` is what you upload to LiteStore.

## Features

| API | Feature id | Asks user |
|---|---|---|
| `LiteHost.location.get()` | `location` | yes |
| `LiteHost.camera.request()` / `microphone.request()` | `camera` / `microphone` | yes |
| `LiteHost.bluetooth.scan()/connect()/read()/write()/notifications()` | `bluetooth` | yes |
| `LiteHost.wifi.get()` | `wifi` | yes |
| `LiteHost.wifi.signal()` | `wifi.signal` | no (signal strength only; Android, SetLiteWeb 1.6.4+) |
| `LiteHost.wifi.enable()` | `wifi.enable` | no (the user turns it on in Android's Wi-Fi panel; 1.6.6+) |
| `LiteHost.bluetooth.enable()` | `bluetooth` | yes (with Bluetooth; Android's own dialog; 1.6.6+) |
| `LiteHost.torch.set()` / `isOn()` | `torch` | no (off when the app leaves; 1.6.6+) |
| `LiteHost.nfc.read()` | `nfc` | no (host screen; never bank card data; 1.6.6+) |
| `LiteHost.sensors.list()` / `watch()` | `sensors` | no (up to 50 Hz, 4 at once; 1.6.6+) |
| `LiteHost.gestures.watch()` | `gestures` | no (shake, flip, tilt, wave; 1.6.6+) |
| `LiteHost.device.battery()` | `device.info` | no (1.6.6+) |
| `LiteHost.location.track()` | `location.background` | yes (notification while it runs; uploads to your server; 1.6.7+) |
| `LiteHost.phone.call()` | `phone.call` | no (SetLiteWeb confirms each call; 1.6.7+) |
| `LiteHost.sms.otp()` | `sms.otp` | no (Google's own prompt per SMS; 1.6.7+) |
| `LiteHost.screen.capture()` | `screen.capture` | no (your app's screen only; 1.6.7+) |
| `LiteHost.pip.enter()` / `auto()` | `pip` | no (1.6.7+) |
| `LiteHost.clipboard.read()` / `write()` | `clipboard.read` / `clipboard.write` | read only |
| `LiteHost.profile.get({...})` | `profile.name` / `.phone` / `.email` / `.photo` | yes, per field |
| `LiteHost.auth.token()` | `auth.token` | yes |
| `LiteHost.auth.browser(url)` | `auth.browser` | no (browser sign-in) |
| `LiteHost.scanner.scan()` | `scanner` | no (host screen) |
| `LiteHost.image.pick()` | `image.pick` | no (host screen) |
| `LiteHost.share()` / `openUrl()` | `share` / `open.url` | no |
| `LiteHost.haptics()` / `keepScreenOn()` | `haptics` / `screen.keepOn` | no |
| `LiteHost.storage.*` | `storage` | no |
| `LiteHost.device.info()` | `device.info` | no |
| `LiteHost.links.create(path)` | `links` | no |
| `LiteHost.notifications.show()/schedule()/cancel()` | `notifications` | yes |
| `LiteHost.biometric.confirm(reason)` | `biometric` | no (phone's own prompt) |
| `LiteHost.contacts.pick()` | `contacts.pick` | no (user picks one) |

Events: `LiteHost.onPause`, `onResume`, `onLink`.

Plain web features (audio/video playback, IndexedDB, `navigator.onLine`,
device motion, speech synthesis…) work as in any browser and don't need
this package.
