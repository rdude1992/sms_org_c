# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SmartSMS: a Flutter + native-Android SMS app. Conversational and flat-list
inbox views, five-way SMS categorisation (personal / promotional /
transactional / OTP / updates), transaction & investment insights parsed
from bank/card/mutual-fund SMS, default-SMS-app support, contact name
resolution, category-aware local notifications, backup/export/restore, and
dark mode.

**Android-only by necessity, not by choice.** Default-SMS-app registration,
full inbox read/write, and programmatic send/receive are Android-specific
OS capabilities with no iOS equivalent. The Flutter UI layer is reusable if
cross-platform ever matters, but the SMS layer
(`sms_organizer/android/app/src/main/kotlin/...`) would need an iOS-side
rethink of scope.

## Commands

The Flutter project root is `sms_organizer/`, not the repo root — `cd` there first.

- `flutter pub get` — install dependencies; also regenerates `gradlew`,
  `gradlew.bat`, and `gradle-wrapper.jar`, which aren't checked in.
- `flutter analyze` — static analysis (`flutter_lints`).
- `flutter test` — unit/widget tests. No `test/` directory exists yet.
- `flutter run` — run on a connected device or emulator. Test on a real
  device or an emulator with working SIM/SMS simulation — SMS behavior
  doesn't work meaningfully on most bare emulators (Android Studio
  emulators support simulated SMS between two instances via
  `adb emu sms send`).
- `flutter build apk` — debug/release APK build.

Before any of the above, `android/local.properties` (git-ignored, not
checked in) needs `sdk.dir`/`flutter.sdk` set for your machine.

**This sandboxed environment does not have a Flutter/Dart SDK installed.**
If these commands aren't available, say so rather than guessing at
results — verify changes by tracing the diff by hand (types, imports,
exhaustive `switch`/enum coverage) instead of fabricating a build/analyze
result.

**Testing the default-SMS-app flow is destructive to your daily driver**:
setting an app as the default SMS handler means your existing SMS app
stops receiving messages until you switch back (Settings → Apps → Default
apps → SMS app). Use a spare device or emulator first.

## Architecture

Flutter UI (`sms_organizer/lib/`) plus a native Android layer
(`sms_organizer/android/app/src/main/kotlin/com/smsorganizer/app/`) that
exists specifically so incoming-SMS notifications work even when Android
has fully killed the Dart/Flutter process — plain Kotlin receivers
categorize, check mute state, resolve the contact name, and post the
notification with **zero dependency on a running Flutter engine**. (Note
the Kotlin package is `com.smsorganizer.app`, despite the Android
`applicationId` being `com.smartsms.app` — historical naming, not a typo
to "fix".)

**`lib/` layers**: `models/` (`SmsMessage`, `Transaction`,
`InvestmentEvent`, `SmsCategory`, `SpendCategory`, `InstrumentType`,
`EntityType`, ...) → `services/` (parsing, categorisation, caching,
backup) → `providers/` (`SmsProvider` is the one large app-state
provider; `ThemeProvider`, `NotificationSettingsProvider`,
`SecuritySettingsProvider` are narrower, single-purpose ones) →
`screens/` + `widgets/` (Provider-consumed UI).

**Categorisation/parsing is a direct port of a TypeScript SMS parser.**
`lib/utils/sms_extractors.dart` mirrors the source function-for-function
(same names, same order, same regexes); `categorization_service.dart`
mirrors its `categorizeMessage`. `Categorizer.kt` on the native side is a
*second*, hand-mirrored copy of the same classifier, used only to decide
which notification channel to fire on — the Dart and Kotlin classifiers
share no code and can drift. If you tune one, update the other and bump
`CategorizationService.version` (see caching below).

**Two independent classification axes on a `Transaction` — easy to
conflate:**
- `SpendCategory` — user-facing "what was this for" (Food, Shopping,
  Investment, ...). Auto-tagged conservatively by
  `spend_category_detector.dart`, always user-overridable, and
  **debit-only in every Insights aggregate**:
  `InsightsService.groupBySpendCategory` skips credits/reversals before
  bucketing, by design — a credit auto-tagged "Income" never appears in
  the spend breakdown. Credits/reversals left uncategorised only surface
  via Settings → "Review uncategorised transactions", not via Insights.
- `InstrumentType` / `EntityType` — what physical instrument or
  sender-type the *SMS itself* implies (bank account, card, UPI, an
  investment sub-account like PPF/SSY/NPS, wallet, broker...), inferred
  by `TransactionParserService._instrumentType` / `extractEntityType`.
  `Transaction.instrumentGroupKey` merges a debit card with its linked
  bank account when they share issuer + last-4, but deliberately keeps
  other instrument types (investment, credit card) split out even if a
  last-4 happens to coincide.

**Caching model**: raw SMS content is never duplicated into a local
database — `content://sms` (via the platform channel) stays the single
source of truth for message bodies/addresses/dates/read-status, fetched
fresh on every `SmsProvider.refresh()`. Only *derived* data (categories,
parsed transactions/investments) is cached, in sqflite
(`DatabaseService`), and is only actually reused as a cache once a
message id is already present — messages new since the last sync are the
only ones re-classified, making `refresh()` incremental rather than
rescanning the whole inbox every time. Cached entries are never
auto-re-evaluated just because the regex changed; bump
`CategorizationService.version` (checked against a value stored in the
database on every app start) to force a one-time automatic cache wipe, or
the user can trigger one manually via Settings → "Recalculate
categorisation".

**Notification pipeline is entirely native**, not
`flutter_local_notifications` — see `IncomingSmsNotifier.kt`. Muted-category
state lives in a native `SharedPreferences` file (not the Dart
`shared_preferences` plugin's storage format, which plain Kotlin can't
safely decode), so the background Kotlin receiver and the Dart Settings
screen read/write the same file and can't drift out of sync.

See `sms_organizer/README.md` for the full architecture file map, the
contact-name-resolution flow, notification cold-start/warm-tap handling,
and the "Known limitations" section (MMS not parsed, native/Dart
categorizer drift risk, one notification per thread not per message,
backup is app-data-only, no release signing configured).
