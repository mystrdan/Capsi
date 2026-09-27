# Capsi Flutter client

This directory is the new shared Flutter UI foundation for Capsi.

## Direction

- Flutter owns the cross-platform application interface.
- Rust remains the source of truth for Capsi networking, identity, discovery,
  encryption, storage, messaging and file-transfer behavior.
- `native/` is the first native ABI boundary between Flutter and the existing
  `capsi-core` crate.
- The existing Tauri application remains intact during the migration so the
  current release path is not broken while the Flutter client is brought up.

## Local development

From this directory:

```bash
flutter pub get
flutter run -d windows
```

The Android, macOS and iOS platform directories can be generated with Flutter's
standard project tooling when those targets are enabled.

## Migration rule

Do not reimplement Capsi networking in Dart. New product operations should be
implemented in `capsi-core` first, then exposed through the native boundary to
Flutter.
