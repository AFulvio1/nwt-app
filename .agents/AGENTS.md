# Workspace Customization Rules

These instructions help Antigravity interact with and maintain the `nwt-app` workspace efficiently.

## Flutter / Dart Environment & Tools
* **Flutter SDK Path**: The local Flutter executable is located at `/Users/antoniofulvio/SDKs/flutter/bin/flutter`. Do not run bare `flutter` or `dart` commands since they may not be available in the default shell `PATH`.
* **Static Analysis**: Run static analysis using:
  ```bash
  /Users/antoniofulvio/SDKs/flutter/bin/flutter analyze
  ```
* **Testing**: Run the project tests using:
  ```bash
  /Users/antoniofulvio/SDKs/flutter/bin/flutter test
  ```
* **Code Generation (Drift / Build Runner)**: If database schema or classes marked with `@DriftDatabase` change, rebuild generated files (e.g. `database.g.dart`) using:
  ```bash
  /Users/antoniofulvio/SDKs/flutter/bin/flutter pub run build_runner build --delete-conflicting-outputs
  ```

## Architecture & Codebase Conventions
* **State Management**: The application uses **Riverpod** for state and service provider orchestration.
* **Database Layer**: Powered by **Drift** (SQLite). It uses an in-memory db during testing and `/Users/antoniofulvio/Library/Application Support/` (via `getApplicationDocumentsDirectory`) for persistence.
* **Ledger Validation**: The core database enforces a double-entry ledger rule. A transaction is invalid and will roll back unless the sum of `amountInBase` for all associated entries is exactly zero, and there are at least 2 entries. Refer to [database.dart](file:///Users/antoniofulvio/Projects/nwt-app/lib/core/database/database.dart).
* **Modern Flutter & Styling Rules**:
  * Avoid deprecated `withOpacity()` in colors. Use `.withValues(alpha: ...)` instead.
  * Avoid deprecated `background` and `onBackground` color parameters in `ColorScheme`. Use `surface` and `onSurface` instead.
  * Avoid deprecated `value` property in `DropdownButtonFormField`. Use `initialValue` instead.
  * **Localization Rule**:
    * The application UI, user-facing copy, code comments, and database schema documentation must always be written in English. Avoid any Italian labels or phrases in the user interface.

