# Net Worth Tracker (nwt-app)

A modern, secure Flutter application designed to track net worth using a strict double-entry ledger architecture.

## Architecture & Features

- **Double-Entry Bookkeeping**: Transactions require a minimum of two offsetting ledger entries (debits and credits). The database transaction will fail and roll back unless the sum of entry amounts in base currency is exactly zero.
- **State Management**: Built with Riverpod for robust and testable dependency injection and state management.
- **Local SQLite Database**: Powered by Drift. Includes macro categories, custom category mapping, and automatic database updates.
- **Biometric Security**: Built-in support for passcode lock and biometric authentication (FaceID/Fingerprint) via local_auth.
- **Responsive Theme**: Sleek Material 3 light and dark modes customized with custom Outlined text typography (Outfit) and glassmorphism design elements.

## Tech Stack

- **Framework**: Flutter (Channel Stable)
- **State Management**: `flutter_riverpod`
- **Local Storage / DB**: `drift` & `drift_sqflite`
- **Secure Storage**: `flutter_secure_storage`
- **Local Authentication**: `local_auth`
- **Charts**: `fl_chart`
- **Fonts**: `google_fonts`

## Getting Started

### Local Setup & Environment
Ensure you have Flutter installed. The local Flutter SDK path on this workspace context is located at:
`/Users/antoniofulvio/SDKs/flutter`

To run commands, use:

```bash
# Run static analysis
/Users/antoniofulvio/SDKs/flutter/bin/flutter analyze

# Run tests
/Users/antoniofulvio/SDKs/flutter/bin/flutter test

# Run code generator (Drift models)
/Users/antoniofulvio/SDKs/flutter/bin/flutter pub run build_runner build --delete-conflicting-outputs
```

## Maintenance & Resolved Issues

The project has been refactored to conform to Flutter v3.33+ best practices and clean up all deprecation warnings:
1. **Super Parameters**: Replaced manual super delegation constructors with super parameter syntax (`AppDatabase.executor(super.e)`).
2. **Material 3 Scheme Deprecations**: Removed deprecated `background` and `onBackground` color fields from color scheme builders, utilizing `surface` and `onSurface` correctly.
3. **Color Opacity Modernization**: Replaced deprecated `withOpacity()` usages with modern `.withValues(alpha: ...)` API.
4. **Form Fields**: Updated `DropdownButtonFormField` value setters from deprecated `value` property to `initialValue`.
