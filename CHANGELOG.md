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
