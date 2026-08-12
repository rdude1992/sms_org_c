# SmartSMS (MVP)

A Flutter + native-Android smart SMS app: conversational and flat-list views,
auto-categorisation (personal / promotional / transactional / OTP),
transaction & investment insights parsed from bank/card/mutual-fund SMS,
default-SMS-app support, contact name resolution, category-aware local
notifications with per-category mute controls, multi-select actions,
backup/export/restore, and dark mode.

## ⚠️ Important: this was built without a Flutter SDK available

This project was generated in a sandbox with no internet access to Google's
Maven repo or Flutter's SDK distribution, so **none of this has been compiled
or run**. The code is complete and internally consistent as far as static
review can tell, but treat the first build like any fresh checkout — expect
to fix a handful of small things (dependency version bumps, a typo here or
there) once `flutter pub get` and Gradle actually run against it.

## Setup

1. Install Flutter (stable channel) and Android Studio / an Android SDK.
2. Create `android/local.properties` (git-ignored, not checked in) with
   `sdk.dir=<path to your Android SDK>` and `flutter.sdk=<path to your
   Flutter SDK>`.
3. Open the project in Android Studio once (or run `flutter pub get`) — this
   regenerates `gradlew`, `gradlew.bat`, and `gradle-wrapper.jar`, which
   couldn't be included here since they're binary/network-fetched files.
   `android/gradle/wrapper/gradle-wrapper.properties` already pins Gradle 8.6.
4. From the project root:
   ```bash
   flutter pub get
   flutter run
   ```
5. On first launch the app walks through:
   - SMS + contacts runtime permissions
   - Setting itself as the **default SMS app** (Android will show its
     standard role-picker dialog — this is required for send/receive/read
     to work fully; without it, Android only allows partial access)

Test on a **real device or an emulator with a working SIM/SMS simulation**,
since SMS behavior doesn't work meaningfully on most bare emulators without
extra setup (Android Studio emulators do support simulated SMS between two
emulator instances via the `adb emu sms send` command, if you want to test
without a physical device).

## Why this has to be Android-only

Default-SMS-app registration, full inbox read/write, and programmatic
send/receive are Android-specific OS capabilities. iOS does not expose
equivalent APIs to third-party apps — there is no "default SMS app" concept
on iOS at all. If cross-platform matters to you later, the Flutter UI layer
here is reusable, but the SMS layer (`android/app/src/main/kotlin/...`)
would need an iOS-side rethink of scope (e.g. dropping default-app/read/send
and keeping only manual paste-in categorisation).

## Architecture

```
android/app/src/main/kotlin/com/smsorganizer/app/
  MainActivity.kt          MethodChannel + EventChannel bridge, role request flow
  SmsRepository.kt         All content://sms reads/writes
  SmsDeliverReceiver.kt     Incoming SMS when app IS default
  SmsReceivedReceiver.kt    Incoming SMS when app is NOT default (read-only signal)
  MmsReceiver.kt            Minimal WAP-push receiver (see Limitations)
  HeadlessSmsSendService.kt "Respond via message" quick-reply
  ComposeSmsActivity.kt     Handles external sms:/smsto: links
  ContactsRepository.kt     Reads device contacts (name + number) for name resolution

lib/
  models/                  SmsMessage, SmsConversation, Transaction, InvestmentEvent,
                            SmsCategory, SpendCategory, InstrumentType, EntityType
  services/
    sms_platform_service.dart       Dart-side channel wrapper
    categorization_service.dart     Regex classifier → personal/promo/txn/otp/updates
    transaction_parser_service.dart Extracts amount/direction/instrument/issuer/balance
    spend_category_detector.dart    Best-effort auto-tagging of Transaction.spendCategory
    insights_service.dart           Aggregates into totals/trend/per-instrument/per-category summaries
    duplicate_detection_service.dart Flags the "shadow" half of a card-network +
                                      bank-account SMS pair reporting one purchase twice,
                                      so linked-account totals aren't doubled
    database_service.dart           sqflite cache of categories + parsed data
    backup_service.dart             JSON export/share + restore
    contact_service.dart            Phone-number-to-name lookup, built once from device contacts
    notification_preferences_service.dart  Persists muted categories (notifications
                                            themselves are fully native — see below)
    biometric_auth_service.dart     Fingerprint/face/PIN gate for the Insights/Accounts tabs
  providers/               SmsProvider (app state), ThemeProvider (dark mode),
                            NotificationSettingsProvider (per-category mute switches),
                            SecuritySettingsProvider (Insights/Accounts biometric lock)
  screens/                 Onboarding, Home (bottom nav: Inbox/Insights/Accounts/Settings),
                            Inbox (chat/list toggle), Thread, Compose, Insights (+
                            instrument/investment/merchant/transaction drilldowns,
                            uncategorised-transactions review), Accounts (the same
                            "Cards & Accounts" screen as Insights' drilldown, promoted
                            to a top-level tab), Settings, Starred, Drafts
  widgets/                 Conversation tile, message bubble, category badge, direction badge,
                            multi-select app bar, transaction tile (+ its edit/assign-account/
                            detected-SMS sheets), investment tile (+ its edit sheet),
                            category picker sheet
```

## Contact name resolution

`ContactsRepository.kt` reads the device's contacts once (name + number) via
`getContacts`. The Dart-side `ContactService` normalises numbers to their
last 10 digits (so "+91 98765 43210", "098765-43210", and "9876543210" all
match) and builds an in-memory lookup used everywhere a sender/recipient is
shown — conversation list, thread title, all-messages list, notifications.
Short alphanumeric sender IDs (e.g. bank/service senders like "HDFCBK")
simply won't match anything and fall back to showing the raw sender ID,
which is expected. If contacts permission is denied, this degrades
gracefully to showing raw addresses everywhere rather than failing to load.

## Notifications: fully native, works even if the app is killed

An earlier version of this posted notifications from Dart (via
`flutter_local_notifications`), which only works while a Flutter engine is
alive. If Android had fully killed the app process, the message still
landed correctly in `content://sms` but no notification fired — that gap is
now closed by moving the entire pipeline into plain Kotlin with **zero
dependency on a running Dart VM**:

- `Categorizer.kt` — a hand-mirrored copy of the Dart regex classifier
  (`lib/utils/regex_patterns.dart` / `categorization_service.dart`), used
  only to decide which channel to notify on. If you tune the regex on the
  Dart side, update this file too — there's no code sharing between the
  two, so they can drift if only one gets edited.
- `NotificationPrefsRepository.kt` — muted-category settings live in a
  **native** SharedPreferences file, not through the `shared_preferences`
  Flutter plugin (whose storage format isn't something plain Kotlin can
  safely decode). The Settings screen and the background receiver both
  read/write this same file via the MethodChannel, so they can't drift out
  of sync.
- `ContactsRepository.lookupDisplayName` — a targeted single-number
  `PhoneLookup` query (not the bulk `getAllContacts` the Dart-side
  `ContactService` uses), since this runs inside a BroadcastReceiver's
  short execution window.
- `IncomingSmsNotifier.kt` — ties it together: categorize → check mute →
  resolve contact name → build and post via `NotificationCompat` /
  `NotificationManagerCompat` directly.
- Both `SmsDeliverReceiver.kt` (app is default) and `SmsReceivedReceiver.kt`
  (app isn't default yet) call this after handling the incoming message,
  so notifications work either way.

**Tapping a notification** needs two separate paths, since a killed app
and a merely-backgrounded app behave differently at the OS level:
- **Cold start** (app was killed): the thread id rides along as an intent
  extra; `SmsPlatformService.getLaunchNotificationThreadId()` reads it
  once Dart is up (`HomeScreen.initState`).
- **Warm** (app already running): `MainActivity.onNewIntent` fires
  (`launchMode="singleTop"` makes this reliable) and pushes the thread id
  straight to Dart over the same MethodChannel —
  `SmsPlatformService.onNotificationThreadTapped`.

**Settings → Notifications** lets the user mute/unmute each category
independently (`NotificationSettingsProvider`). Since the mute list is read
fresh from native storage on every incoming message, a change in Settings
takes effect on the very next SMS without needing a restart.

One remaining cosmetic gap: the notification's small icon reuses the
launcher icon rather than a dedicated monochrome status-bar icon, so it'll
render as a solid silhouette rather than a clean glyph — flagged with a
`TODO` in `IncomingSmsNotifier.kt`.

## How categorisation & parsing work

Both the classifier and the extraction logic are a direct port of a
working TypeScript SMS parser (`smsParser.ts` in the source project) —
`lib/utils/sms_extractors.dart` mirrors that file function-for-function
(same names translated to camelCase, same order, same regexes), and
`categorization_service.dart` mirrors its `categorizeMessage`. See the
top-of-file comment in `sms_extractors.dart` for the JS→Dart translation
notes if you're porting further updates from the source later.

- **Categorisation** (`categorization_service.dart`) now has **five**
  buckets, not four: personal / promotional / transactional / OTP /
  **updates**. `updates` covers delivery notifications, booking
  confirmations, account statements, and bill/due-date reminders — things
  that aren't personal chat, aren't promotions, and aren't a transaction
  in themselves, even though they often come from the same bank senders
  that also send real transaction alerts. Checked in priority order:
  updates (several specific high-confidence patterns) → sender-suffix hint
  (many DLT-registered sender IDs end in `-P`/`-T`/`-S`/`-G`) → OTP →
  transactional (gated by several exclusions: promotional-sounding,
  "will be debited" future-tense, request/acknowledgement notifications,
  bill reminders that haven't been paid yet, mandate-registration
  notices) → updates keywords → promotional → personal (only plain
  10-digit senders) → default updates.

- **Transaction parsing** (`transaction_parser_service.dart`) runs on
  messages already tagged transactional and now extracts considerably
  more than before: amount, direction (credit / debit / **reversal** —
  reversed/declined/failed transactions are excluded from Insights totals
  rather than counted as a debit), instrument type, a masked account/card
  reference (`extractAccountNumber` — "XX1234", or "Pluxee Card" for cards
  that never surface a number), issuer, merchant, balance-after,
  **entity type** (bank / wallet / investment / card-service —
  `extractEntityType`), **wallet type** (e.g. "Fuel Wallet", "HDFC
  FASTag" — `extractWalletType`), bill due date, and FASTag-specific
  wallet id + vehicle number.

- **Investment parsing** now also extracts units, NAV, folio/PRAN, and
  AMC/scheme provider (`extractInvestmentDetails`) — including the
  "units credited to your folio" nuance, where money left the user's bank
  account even though the SMS says "credited" (to the fund, not the
  user's cash), and NPS Tier 1/2 naming.

- **Estimated fund value, NAV/units trend, and SIP detection**
  (`holdings_service.dart`) group investment events into per-fund
  *holdings* — same AMC + folio/account, or AMC + fund/scheme when no
  folio was detected (`InvestmentEvent.holdingGroupKey`) — a finer
  grouping than the "By AMC" tab's own `providerGroupKey` (AMC only),
  since two folios of the same fund — or two different funds under one
  AMC — have independent unit counts and NAV histories. Folio/account
  alone (not combined with fund name) is the identity key when present:
  the same physical holding can get a slightly different fund-name string
  depending on which message shape produced it (see the NPS case below),
  and requiring an exact match would silently split one holding into two.
  Each holding's units-held and net-invested are reconstructed
  event-by-event; "estimated current value" prefers units held × the most
  recent NAV any SMS mentioned, falls back to the most recent confirmed
  value statement (see below) plus contributions made since, and falls
  back again to cost basis if neither is available — never a live market
  quote. The Investments dashboard and the per-AMC drilldown
  (`AmcDetailScreen`) both chart this — invested vs. estimated value, NAV
  over time, units over time — and `detectSip` heuristically flags a
  recurring monthly contribution (same rounded amount recurring across ≥3
  distinct months) even when the SMS itself never used the word "SIP".

- **NPS/Protean gets two message shapes the holdings engine handles
  differently.** A contribution SMS ("Units for Voluntary contribution of
  Rs.X credited with NAV of DD/MM/YY") states neither units nor a NAV —
  "NAV of DD/MM/YY" is an *allotment date*, not a rupee value, and
  `extractInvestmentDetails`'s NAV regex has a lookahead specifically
  rejecting that date shape (it used to parse the date's leading digits as
  a bogus NAV, e.g. "NAV of 04/04/25" → 4.0, silently corrupting
  units-derivation and every NAV/value chart for that holding). Separately,
  a periodic statement ("Investment value in Tier II (PRANXXXX) as on
  DD.MM.YY is Rs X") states a value directly with no units/NAV at all —
  `extractInvestmentValueStatement` + `TransactionParserService.
  parseInvestmentValuation` record this as `InvestmentKind.valuationUpdate`
  (categorized `SmsCategory.updates`, not `transactional`, since no money
  moved — see `SmsProvider.refresh`'s `else if (category == updates)`
  branch), which `holdings_service.dart` treats as an authoritative
  checkpoint rather than a cash flow: every invested/redeemed total, the
  SIP detector, and provider/AMC bucketing all skip it via
  `InvestmentKind.isValuationOnly`.

- **PPF/SSY/NPS self-transfers** get their own `InstrumentType.investment`
  (`TransactionParserService._instrumentType`), separate from the generic
  `bankAccount` type, so a small-savings-scheme sub-account shows up as its
  own row in the Cards & Accounts "Investments" section instead of being
  lumped in with a regular bank account. The direction detector
  (`getTransactionType` in `sms_extractors.dart`) also special-cases
  "Rs.X transferred to your PPF/SSY A/c ..." as a debit — on its own that
  phrasing reads like an incoming transfer ("to your ... A/c"), even though
  it's really money leaving the linked bank account into a locked scheme.

- **OTP messages** now also extract the actual code (`extractOtp`) and
  surface a tap-to-copy button in the thread view (`MessageBubble`) —
  computed on demand per rendered message rather than cached, since it's
  a single cheap regex pass and only applies to a subset of messages.

- Insights groups by **wallet type** when present (so "Fuel Wallet" and
  "Meal Wallet" don't collapse into a generic bucket just because they're
  both wallet-entity transactions with no card number), falling back to
  instrument + issuer + masked reference otherwise.

- **`SpendCategory` (what a transaction was *for* — Food, Shopping,
  Investment, ...) is a separate axis from `InstrumentType`/`EntityType`
  above, and Insights' "By spend category" breakdown
  (`InsightsService.groupBySpendCategory`) is debit-only by design** — it
  skips credits and reversals before bucketing, so a credit auto-tagged
  "Income" (salary/interest/dividend keywords, `spend_category_detector.dart`)
  never appears there. Its "Uncategorised spend" row/slice only ever
  reflects untagged *debits* within the selected date range; every
  untagged transaction regardless of direction or range — the full
  tagging backlog — lives in Settings → "Review uncategorised
  transactions" instead. The two screens intentionally count different
  things; don't "fix" one to match the other without re-reading both.

- All of this is still **regex/keyword-based, not ML**. It'll work
  reasonably well on common Indian bank SMS formats out of the box, but
  real-world message formats vary a lot bank-to-bank. Tune
  `lib/utils/sms_extractors.dart` against your own actual SMS inbox —
  that file is deliberately centralised for exactly this, and structured
  to make re-porting future changes from the TS source straightforward.

- **`extractBillDueDate` is not a literal port.** The source relies on
  JS's lenient `new Date(str)`, which happily parses loosely-formatted
  strings like "18-Feb-25"; Dart's `DateTime.parse` is strict ISO-8601
  only. `tryParseFlexibleDate` in `sms_extractors.dart` is a small
  hand-written stand-in covering the two formats the source's own regex
  patterns actually produce (day-first, matching Indian SMS conventions).
  If you extend the due-date regex to match new formats, check this
  parser still covers them.

## Caching model: what's cached, what isn't, and how sync stays incremental

**Raw message content is never duplicated into our own database.**
`content://sms` stays the single source of truth for message bodies,
addresses, dates, thread ids, and read status — `SmsProvider.refresh()`
fetches it fresh from the platform channel every time. This is a
deliberate choice, not an oversight: duplicating SMS content into a second
local store adds a place for data to go stale and a redundant copy of
sensitive content for very little benefit, since the OS-backed provider is
already reasonably fast to query.

**Derived data (categories, parsed transactions, parsed investments) is
cached in sqflite** (`DatabaseService`) and — importantly — actually used
as a cache now, not just written and ignored:

- On every `refresh()`, each message's id is checked against the cached
  `message_categories` table first. If it's already there, the cached
  category is reused directly — **no regex runs on it again**. Only
  messages that aren't in the cache yet (i.e. arrived since the last sync)
  get classified and, if transactional, parsed.
- This makes `refresh()` incremental: the first sync after install pays
  the full cost of scanning your entire SMS history, but every sync after
  that — including the one triggered by every single incoming SMS — only
  does regex work proportional to *how many new messages arrived*, not
  proportional to your total inbox size.
- Cached entries are **never automatically re-evaluated** once written,
  even if you later tune the regex. That's what the Settings → Data & sync
  → "Recalculate categorisation" action is for — it clears the cache
  (`SmsProvider.recalculateAll()`) and forces a full re-scan on demand.
  There's also an **automatic** version of this: `CategorizationService.version`
  is checked against a value stored in the database's `meta` table on
  every app start (`SmsProvider._ensureCacheMatchesCurrentLogic`), and the
  cache is wiped once, automatically, whenever they don't match — e.g. this
  happened for existing installs when the classifier was replaced with the
  ported version, since old cached categories were stale by definition
  under the hood. Bump `CategorizationService.version` yourself if you
  tune the regex enough that old cached results should be considered
  invalid.
- Cache entries for messages that no longer exist on-device (deleted since
  the last sync) are pruned during `refresh()` so a stale transaction
  doesn't linger in Insights forever.

One thing this doesn't solve: the Insights/list screens still show a
loading state on the *very first* sync after install, since there's
nothing cached yet and no way to render transaction data before the first
full pass completes. That's expected — cache-first behavior only kicks in
from the second sync onward.



## Known limitations / scope cut for this MVP

- **MMS is not parsed.** `MmsReceiver.kt` exists only to satisfy Android's
  default-SMS-app eligibility requirement; it acknowledges receipt but
  doesn't extract or store MMS content/attachments.
- **Native and Dart categorisation can drift — more so now.** `Categorizer.kt`
  (native, used for the notification decision) is a hand-mirrored copy of
  `categorization_service.dart` (Dart, used for the displayed category),
  both ported from the same TS source. The Dart side additionally uses
  `extractAmount` for its "has amount" check where the native side uses a
  simpler inline regex — a deliberate simplification since the native
  path only needs a category, not full extraction, but it's a second
  place the two implementations differ even today. If you tune the
  classifier, update both, and bump `CategorizationService.version` so
  existing installs auto-reprocess (see the caching section above).
- **One notification per thread, not per message.** `IncomingSmsNotifier`
  reuses the thread id as both the notification id and the `PendingIntent`
  request code, so a second message in the same conversation before the
  first notification is dismissed replaces it rather than stacking. This
  matches how most SMS apps behave by default; a `MessagingStyle`
  multi-line notification would need the native side to track per-thread
  message history, which is a reasonable next step but wasn't needed to
  fix the actual reliability gap.
- **Notification small icon is a placeholder.** It reuses the launcher
  icon rather than a proper monochrome status-bar glyph — see the `TODO`
  in `IncomingSmsNotifier.kt`.
- **Merchant extraction is best-effort.** The regex looks for patterns like
  "at MERCHANT", "to MERCHANT" — it'll miss unusual phrasing.
- **Duplicate-alert detection is a heuristic, not exact.** For a linked
  debit-card + bank-account pair (see `Transaction.instrumentGroupKey`),
  `duplicate_detection_service.dart` collapses a card-network alert and a
  bank-account alert into one counted transaction when they're the same
  direction, amount, and within a 5-minute window of each other — it can't
  distinguish that from two genuinely separate purchases of the identical
  amount within 5 minutes of one another (rare, but possible). Both
  underlying SMS/transactions always stay visible in the inbox and
  transaction lists; only aggregate totals (Insights, Cards & Accounts,
  merchant breakdown) suppress the redundant one.
- **Backup/restore is app-data-only.** It exports/imports this app's view of
  your messages + parsed data as JSON. Restoring does **not** write messages
  back into the Android SMS provider (silently mass-inserting SMS into a
  user's inbox on restore would be a surprising thing for an app to do) —
  it repopulates the app's own cache/insights.
- **Placeholder app icon.** `res/mipmap-*/ic_launcher.png` are simple
  generated placeholders — swap in real branding before shipping.
- **"Estimated current value" is only ever as fresh as the last SMS that
  mentioned a NAV** — there's no live market data feed, so a fund you
  haven't gotten a purchase/redemption SMS for in months shows a stale NAV
  with no indication a newer one exists beyond the "as of &lt;date&gt;"
  label. SIP detection (`detectSip`) is a rounded-amount/≥3-months
  heuristic, not a flag read from the SMS — a SIP that changed amount
  partway through, or fewer than 3 installments so far, won't be
  recognised as recurring.
- **No release signing config.** `android/app/build.gradle` currently signs
  release builds with the debug key — set up a real `key.properties` /
  keystore before publishing anywhere.

## Testing the default-SMS-app flow safely

Setting an app as the default SMS handler on your own daily-driver phone
means your existing SMS app stops receiving messages until you switch back.
Test on a spare device or emulator first, and know how to switch back
(Settings → Apps → Default apps → SMS app) before you do this on your main
phone.
