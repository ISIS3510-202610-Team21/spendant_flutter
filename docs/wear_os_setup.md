# Wear OS setup

## Run the watch build

Use the Wear flavor plus the dedicated entrypoint:

```bash
flutter run -d <wear-device-id> --flavor wear --target lib/main_wear.dart
```

## Build an APK for Wear

```bash
flutter build apk --release --flavor wear --target lib/main_wear.dart
```

## Run the mobile build

The phone app keeps its normal flavor:

```bash
flutter run -d <phone-device-id> --flavor mobile --target lib/main.dart
```

## What is configured

- `mobile` flavor for the existing phone app.
- `wear` flavor with `applicationId` `com.example.spendant_flutter.wear`.
- Watch-only manifest overlay with `android.hardware.type.watch`.
- Standalone Wear metadata.
- Dedicated Flutter entrypoint in `lib/main_wear.dart`.
- Wear Data Layer bridge for syncing recent expenses.

## Current sync path

The Data Layer publishes the last 5 expenses on:

`/spendant/expenses/recent`

## Next recommended step

Split the launcher icons and notification behavior for Wear, then test on:

- Pixel Watch emulator
- physical Pixel Watch
