## 1.6.0

For SetLiteWeb 1.6.16+:

- `LiteHost.scanner.scan(formats: ...)` reads barcodes too: pass
  `CodeFormat.products` for book and shop barcodes (ISBN/EAN-13, EAN-8,
  UPC-A, UPC-E), or any mix of `CodeFormat` values. The default is still
  QR only. Older SetLiteWeb versions read QR whatever you ask for.
- `MockHost` answers a barcode-only scan with an ISBN (9780141439518).

## 1.5.0

For SetLiteWeb 1.6.13+:

- Feature `account` (no question): put `requires: [account]` in
  litestore.yaml for apps only logged-in people may use. Opened signed out,
  SetLiteWeb shows its login (or sign-up) and then opens the app, at the
  shared page if any. Older SetLiteWeb versions don't list such apps.
  Profile details still come from `LiteHost.profile.get`.
- `litehost:check` knows `account` and never calls it unused.

## 1.4.0

For SetLiteWeb 1.6.11+:

- `ProfileField.photo` / feature `profile.photo` (asks): the user's
  profile photo as `Profile.photoUrl`, an https URL of a square JPEG.
- `MockHost(profilePhoto: ...)` and `litehost:check` know it.

## 1.3.1

- Example (Feature Lab) covers every 1.3.0 feature. No API changes.

## 1.3.0

For SetLiteWeb 1.6.7+ (Android):

- `LiteHost.location.track()` (feature `location.background`, asks): fixes
  keep coming in the background in a foreground service with a
  notification; each also goes to your https server (`uploadUrl`, with
  Authorization/X- headers), queued while offline. Cancel to stop.
- `LiteHost.phone.call()` (feature `phone.call`): SetLiteWeb confirms each
  call, then calls or opens the dialer.
- `LiteHost.sms.otp()` (feature `sms.otp`): the next code SMS, after
  Google's consent prompt; no SMS permission.
- `LiteHost.screen.capture()` (feature `screen.capture`): your app's
  screen as PNG.
- `LiteHost.pip.enter()` / `auto()` (feature `pip`): picture-in-picture.

## 1.2.0

For SetLiteWeb 1.6.6+ (Android):

- `LiteHost.bluetooth.enable()`: Android's "turn on Bluetooth?" dialog.
- `LiteHost.wifi.enable()` (feature `wifi.enable`): the Wi-Fi panel for
  the user to switch Wi-Fi on (Android 10+), directly on older phones.
- `LiteHost.torch.set()` / `isOn()` (feature `torch`): off by itself when
  the app leaves the screen.
- `LiteHost.nfc.read()` (feature `nfc`): the host's "hold a tag" sheet; tag
  id, techs and NDEF records (text, links, contact cards). No commands go
  to cards, so bank cards give only a random id.
- `LiteHost.sensors.list()` / `watch()` (feature `sensors`): motion,
  compass, light, pressure, proximity, temperature, humidity, steps; up
  to 50 Hz, 4 at once.
- `LiteHost.gestures.watch()` (feature `gestures`): shake, face down/up,
  tilt left/right, wave.
- `LiteHost.device.battery()`: level, charging and battery temperature.
- MockHost answers all of them; `litehost:check` knows them.

## 1.1.2

- The example is now Feature Lab: one card per feature (every litehost API,
  including wifi.signal, notifications, biometric, contacts, browser
  sign-in, camera and microphone streams), with results, error codes
  explained, timings, an event log and "Run safe tests". No API changes.

## 1.1.1

- Works with `archive` 3 as well as 4 (only the build tool uses it), so
  mini apps on Flame's tiled maps, still on archive 3, can depend on
  litehost.

## 1.1.0

- `LiteHost.wifi.signal()` (feature `wifi.signal`, SetLiteWeb 1.6.4+,
  Android): signal strength in dBm, Wi-Fi link speed and band, with
  `percent` and `quality` helpers. No network name, so no consent sheet.
  `MockHost` drifts it like a walk, or fixes it with `mockRssi`.
- `litehost:check` also reads JavaScript and HTML in `web/`, for mini apps
  that call `window.LiteHost` directly, and tells `wifi.get` from
  `wifi.signal`.
- `litehost:build`: `--target <file>` for apps whose entry point isn't
  lib/main.dart; no offline service worker (SetLiteWeb keeps the bundle);
  leaves out Flutter engine files a WebView never loads (skwasm, other
  renderers, `.symbols`, version.json), several MB per app. `--no-trim`
  keeps them; `--wasm` builds keep them too.

## 1.0.0

- First release, for SetLiteWeb bridge version 1: location, camera,
  microphone, Bluetooth LE, Wi-Fi, clipboard, profile, sign-in (SetLiteWeb
  token and browser OAuth), QR scanner, photo picker, share, open links,
  haptics, keep screen on, per-app storage, device info, shareable links,
  notifications (now or scheduled, opening the app on tap), biometric
  confirm, contact picker, and pause/resume/link events.
- `MockHost` for development in a normal browser and for tests.
- `litestore.yaml` manifest, `dart run litehost:check` and
  `dart run litehost:build`.
