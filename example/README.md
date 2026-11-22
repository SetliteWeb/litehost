# Feature Lab (litehost example)

A LiteStore mini app that tests every SetLiteWeb feature the litehost SDK
offers, one card each: what the phone offers, device info, location,
Wi-Fi name and signal, Bluetooth (scan, connect, services), camera and
microphone (permission, then a real stream), photo picker, QR scanner,
profile, Sign in with SetLiteWeb, browser sign-in, biometric confirm,
contact picker, share, open links, shareable links, copy and paste,
vibration, keep screen on, storage, notifications (now, scheduled, cancel)
and closing the app. Pause, resume and link events go to a log.

Each card shows OK or the host's error code (`denied`, `unsupported`,
`cancelled`…) explained, and how long the call took. "Run safe tests" runs
the ones that never show a prompt.

```sh
flutter run -d chrome            # uses MockHost outside SetLiteWeb
dart run litehost:check          # every declared feature is used
dart run litehost:build          # build/litestore/<id>-<version>.zip + listing
```

Upload the zip and its listing to LiteStore (Admin › Mini apps). It is
also published in SetLiteWeb's store as "Feature Lab".
