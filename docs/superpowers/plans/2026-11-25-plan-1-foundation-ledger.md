# Plan 1: Foundation and Ledger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working Android budget app without the AI agent: exact multi-currency money math, a local database, daily exchange rates, the visual design system, manual entry of expenses, income and transfers, and the Wealth and Spending screens.

**Architecture:** Flutter app organised by feature folders. Pure Dart code (money, ledger, fx, account and category services) sits under `lib/core` and `lib/features/<feature>/`, using exactly the paths in each task, and is tested without widgets. Drift (SQLite) is the single source of truth; Riverpod providers expose services and streams to screens. Later plans add the agent, limits, upcoming items, goals, debts and backups as new feature folders on top of the same services.

**Tech Stack:** Flutter (stable), Dart, drift + drift_flutter, flutter_riverpod, go_router, fl_chart, dio, decimal, intl, phosphor_flutter.

**Spec:** `docs/superpowers/specs/2026-11-25-budget-app-design.md` (also in the claude.ai project as `claude/budget-app-design.md`)

**Later plans (not in this one):** 2 Agent and Chat; 3 Limits, Upcoming and reminders; 4 Goals, Debts and Credit; 5 Lock, Backups, Roman Urdu and polish.

## Global Constraints

- Amounts are integers in the currency's minor unit. No `double` anywhere in money logic. Exchange rates are `Decimal`.
- Minor-unit digits: CNY 2, PKR 2, USD 2. Any ISO currency can be added later.
- Every account has exactly one currency; every transaction is stored in its account's currency and never rewritten.
- Main currency defaults to CNY and only changes display.
- Rates come from `https://open.er-api.com/v6/latest/USD`, stored as one snapshot per day; if a fetch fails, the last snapshot is used and marked stale. The app must show the attribution "Rates by ExchangeRate-API".
- Transfers are never counted as spending or income.
- Starter expense categories: Food, Groceries, Transport, Rent, Bills, Shopping, Education, Health, Entertainment, Gifts, Sending home, Other.
- Starter income categories: Scholarship/Stipend, From family, Part-time work, Gift, Refund, Other.
- Starter accounts: WeChat, Alipay, Bank card, Cash (CNY); Pakistani bank, Cash, JazzCash, Easypaisa (PKR); USD account (USD). All with opening balance 0.
- Fonts Bricolage Grotesque and Instrument Sans are bundled as assets. Never use runtime Google Fonts download (blocked in China).
- Icons: Phosphor duotone.
- Color tokens and rules exactly as spec section 12. Brass `#E8B83A` is identical in both themes and only ever a fill with ink `#15201B` on top.
- UI copy: sentence case, no all-caps labels, no middle-dot separators.
- Month boundaries use the phone's local time zone.
- App display name is "Hazir" (Android label and MaterialApp title); the Flutter project name stays `budget_app`.
- The repository root is the existing git repository (on Rao's machine `D:\Study\Project\hazir-app`). There is no `budget-app/` subfolder and no new `git init`.

## Review Focus

1. Cross-currency rounding on small amounts (for example 1 PKR to CNY): conversion must round half-up to the target minor unit, never truncate, never produce floats.
2. First launch with no internet: no rate snapshot exists. Combined totals must show only main-currency accounts plus a clear "rates unavailable" state, never a wrong total.
3. Editing or deleting a transaction must update balances and spending immediately on every screen.
4. A transfer to the same account, or with zero or negative amounts, must be rejected.
5. An entry at 23:59 local time on the last day of a month belongs to that month in Spending.

---

## File structure

```
pubspec.yaml
assets/fonts/BricolageGrotesque-Variable.ttf
assets/fonts/InstrumentSans-Variable.ttf
lib/main.dart
lib/app/app.dart                     MaterialApp.router, themes
lib/app/router.dart                  go_router config, tab shell
lib/app/providers.dart               database, services, settings providers
lib/core/money/currency.dart         Currency registry
lib/core/money/money.dart            Money value type, formatting
lib/core/money/convert.dart          Decimal-rate conversion
lib/data/db/tables.dart              Drift table definitions
lib/data/db/app_database.dart        AppDatabase, migrations
lib/data/db/seed.dart                starter accounts and categories
lib/features/fx/rates_api.dart       RatesApi interface + Dio implementation
lib/features/fx/fx_service.dart      snapshots, rateOn(), refresh
lib/features/ledger/ledger_errors.dart
lib/features/ledger/ledger_service.dart   writes + queries
lib/features/entry/entry_form_screen.dart
lib/features/wealth/wealth_screen.dart
lib/features/wealth/account_edit_sheet.dart
lib/features/spending/spending_screen.dart
lib/features/spending/category_entries_screen.dart
lib/features/accounts/account_service.dart
lib/features/categories/category_service.dart
lib/features/settings/settings_screen.dart
lib/ui/theme/app_colors.dart         AppColors ThemeExtension
lib/ui/theme/app_theme.dart          light/dark ThemeData
lib/ui/widgets/amount_text.dart      big numerals widget
lib/ui/widgets/placeholder_tab.dart
test/...                             mirrors lib/
```

---

### Task 1: Project setup

**Files:**
- Create: Flutter project in the existing repository root, `pubspec.yaml`, `assets/fonts/*`, `lib/main.dart`, `test/smoke_test.dart`

**Interfaces:**
- Produces: a building Android app with all dependencies resolved and fonts registered as families `Bricolage` and `Instrument`.

- [x] **Step 1:** In the existing repository root (already a git repo with `docs/` and `AGENTS.md`; do not run `git init`), run `flutter create --org com.rao --project-name budget_app --platforms android,ios .` Then set the display name: `android:label="Hazir"` in `android/app/src/main/AndroidManifest.xml`, `CFBundleDisplayName` = `Hazir` in `ios/Runner/Info.plist`, and `title: 'Hazir'` on the MaterialApp.
- [x] **Step 2:** Add dependencies: `flutter pub add flutter_riverpod go_router drift drift_flutter fl_chart dio decimal intl phosphor_flutter path_provider` and `flutter pub add --dev drift_dev build_runner`.
- [x] **Step 3:** Download the two variable fonts (OFL) from their official GitHub releases or Google Fonts website into `assets/fonts/`, add their `OFL.txt` files next to them, and register them in `pubspec.yaml` under `flutter: fonts:` as families `Bricolage` and `Instrument`.
- [x] **Step 4: Write smoke test** `test/smoke_test.dart`: pump `const ProviderScope(child: BudgetApp())` and `expect(find.byType(MaterialApp), findsOneWidget)`. (`BudgetApp` can be a bare `MaterialApp` for now in `lib/app/app.dart`.)
- [x] **Step 5:** Run `flutter test test/smoke_test.dart` → PASS. Run `flutter build apk --debug` → succeeds.
- [x] **Step 6: Commit** `chore: create flutter project with dependencies and fonts`

### Task 2: Money core

**Files:**
- Create: `lib/core/money/currency.dart`, `lib/core/money/money.dart`, `lib/core/money/convert.dart`
- Test: `test/core/money/money_test.dart`, `test/core/money/convert_test.dart`

**Interfaces:**
- Produces:
  - `class Currency { final String code; final int minorDigits; final String symbol; }` and `Currency currencyOf(String code)` (throws `ArgumentError` for unknown). Registry: CNY ¥ 2, PKR ₨ 2, USD $ 2.
  - `class Money { final int minor; final String currency; }` with `==`, `+` and `-` (throw `ArgumentError` on currency mismatch), `bool get isNegative`, `static Money parse(String text, String currency)` (accepts "28", "28.5", "1,200.00"; rejects more decimals than minorDigits).
  - `String formatMoney(Money m, {bool withSymbol = true, bool signed = false})` producing e.g. `¥8,420.50`, `−28.00` (minus sign U+2212 when `signed`).
  - `Money convert(Money m, Decimal rate, String toCurrency)`: multiply major amount by rate, round half-up to the target's minor unit.
  - `Decimal crossRate(Decimal fromPerUsd, Decimal toPerUsd)` = `toPerUsd / fromPerUsd`, computed with at least 12 decimal places of precision.

- [x] **Step 1: Write failing tests**

```dart
test('parse and format', () {
  expect(Money.parse('1,200.5', 'CNY').minor, 120050);
  expect(() => Money.parse('1.234', 'CNY'), throwsFormatException);
  expect(formatMoney(Money(842050, 'CNY')), '¥8,420.50');
  expect(formatMoney(Money(-2800, 'CNY'), withSymbol: false, signed: true), '−28.00');
});
test('add rejects mixed currency', () {
  expect(() => Money(1, 'CNY') + Money(1, 'PKR'), throwsArgumentError);
});
test('convert rounds half up, no truncation', () {
  final cnyPerPkr = crossRate(Decimal.parse('281.5'), Decimal.parse('7.1'));
  expect(convert(Money(100, 'PKR'), cnyPerPkr, 'CNY').minor, 3);      // 1 PKR ≈ 0.0252 CNY → 0.03
  expect(convert(Money(500000, 'PKR'), cnyPerPkr, 'CNY').minor, 12611); // 5000 PKR → 126.11
});
```

- [x] **Step 2:** Run `flutter test test/core/money` → FAIL (undefined).
- [x] **Step 3:** Implement the signatures above. Use `Decimal` for all intermediate math; `Decimal.round` is not half-up for negatives, so implement half-up on absolute value and reapply sign.
- [x] **Step 4:** Run `flutter test test/core/money` → PASS.
- [x] **Step 5: Commit** `feat: money value type, parsing, formatting and conversion`

### Task 3: Database schema and seed

**Files:**
- Create: `lib/data/db/tables.dart`, `lib/data/db/app_database.dart`, `lib/data/db/seed.dart`
- Test: `test/data/db/seed_test.dart`

**Interfaces:**
- Produces Drift tables (all ids `int` autoincrement; dates stored as `DateTime`):
  - `Accounts`: id, name (text, unique among non-archived), currency (text), openingMinor (int, default 0), isCredit (bool, default false), archived (bool, default false), sortOrder (int).
  - `Categories`: id, name, kind (text: `expense` | `income`), iconKey (text), archived (bool, default false).
  - `Transactions`: id, kind (text: `expense` | `income` | `transfer`), accountId, amountMinor (int, always positive), currency, categoryId (nullable), toAccountId (nullable), toAmountMinor (nullable), toCurrency (nullable), note (nullable), occurredAt, createdAt, fxDay (text `yyyy-MM-dd`, nullable): the rate snapshot day frozen for this entry (see Task 5).
  - `FxSnapshots`: day (text `yyyy-MM-dd`, primary key part), currency (text, part of key), perUsd (text, Decimal string), fetchedAt.
  - `Settings`: key (text primary key), value (text). Keys used now: `mainCurrency` (default `CNY`).
- `class AppDatabase extends _$AppDatabase` with `AppDatabase(QueryExecutor e)`, `schemaVersion => 1`, and `Future<void> seedIfEmpty()` from `seed.dart` inserting starter accounts and categories from Global Constraints.

- [x] **Step 1: Write failing test** using `AppDatabase(NativeDatabase.memory())`: after `seedIfEmpty()` twice, `accounts` has 9 rows (4 CNY, 4 PKR, 1 USD), expense categories = 12, income categories = 6, and `Settings` `mainCurrency` = `CNY`.
- [x] **Step 2:** Run → FAIL.
- [x] **Step 3:** Implement tables and seed; run `dart run build_runner build --delete-conflicting-outputs`.
- [x] **Step 4:** Run `flutter test test/data/db` → PASS.
- [x] **Step 5: Commit** `feat: drift schema and starter data`

### Task 4: Exchange rates

**Files:**
- Create: `lib/features/fx/rates_api.dart`, `lib/features/fx/fx_service.dart`
- Test: `test/features/fx/fx_service_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `crossRate` (Task 2).
- Produces:
  - `abstract class RatesApi { Future<Map<String, Decimal>> latestPerUsd(); }` and `class ErApiRatesApi implements RatesApi` (Dio GET, reads `rates`, requires `result == "success"`, parses each value with `Decimal.parse(value.toString())`).
  - `class FxService { FxService(AppDatabase db, RatesApi api, {DateTime Function()? clock}); Future<void> refreshIfNeeded(); Future<Decimal?> rate(String from, String to, {DateTime? on}); Future<bool> isStale(); }`
  - `rate` uses the snapshot for `on` (default today); if that day has none, the latest earlier snapshot; returns `Decimal.one` when `from == to`; returns `null` when no snapshot exists at all.
  - `refreshIfNeeded` fetches only if today has no snapshot; on failure it swallows the error (stale state is reported by `isStale`). After a successful fetch it calls `backfillFxDays()`.
  - `Future<String?> snapshotDayFor(DateTime date)`: the latest snapshot day on or before `date`, else null.
  - `Future<Decimal?> rateForDay(String from, String to, String day)`: rate from that exact snapshot day.
  - `Future<void> backfillFxDays()`: for transactions with `fxDay == null`, set `fxDay` to the earliest snapshot day on or after their date (once set, never changed).

- [ ] **Step 1: Write failing tests** with a `FakeRatesApi` and fixed clock:
  - after refresh, `rate('PKR','CNY')` equals `crossRate(281.5, 7.1)`;
  - second refresh on same day does not call the API (count calls);
  - API throwing → `rate` falls back to yesterday's snapshot and `isStale()` is true;
  - empty database and API throwing → `rate('PKR','CNY')` is null, `rate('CNY','CNY')` is 1;
  - a transaction saved with no snapshots gets `fxDay` filled by `backfillFxDays()` after the first successful refresh, and a later refresh does not change it.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test test/features/fx` → PASS.
- [ ] **Step 5: Commit** `feat: daily exchange rate snapshots with fallback`

### Task 5: Ledger service

**Files:**
- Create: `lib/features/ledger/ledger_errors.dart`, `lib/features/ledger/ledger_service.dart`
- Test: `test/features/ledger/ledger_service_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `FxService`, `Money`, `convert`.
- Produces:
  - `class LedgerException implements Exception { final String code; final String message; }` with codes `unknown_account`, `archived_account`, `unknown_category`, `wrong_category_kind`, `non_positive_amount`, `currency_mismatch`, `same_account`, `missing_to_amount`.
  - `class LedgerService`:
    - `Future<int> addExpense({required int accountId, required Money amount, required int categoryId, String? note, DateTime? at})`
    - `Future<int> addIncome({...same})`
    - `Future<int> addTransfer({required int fromAccountId, required int toAccountId, required Money amount, Money? received, Decimal? customRate, String? note, DateTime? at})`: if currencies differ, `received` wins, else `customRate`, else `FxService.rate` on that date; if none available, throw `missing_to_amount`.
    - Every write sets `fxDay` = `FxService.snapshotDayFor(entry date)` at save time (null if none; filled later by `backfillFxDays`). Converting an entry to the main currency always uses its own `fxDay` snapshot, so past spending never shifts when rates move or the main currency changes.
    - `class TransactionDraft { final String kind; final int accountId; final Money amount; final int? categoryId; final int? toAccountId; final Money? received; final Decimal? customRate; final String? note; final DateTime at; }`
    - `Future<void> replaceTransaction(int id, TransactionDraft draft)`: full replacement with the same validation as the add methods (works for all three kinds, including changing a transfer's destination, received amount or rate). `note == null` means no note. `Future<void> deleteTransaction(int id)`.
    - `Stream<List<AccountBalance>> watchBalances()` where `AccountBalance { Account account; Money balance; }`, balance = opening + income - expense - transfers out + transfers in.
    - `Stream<WorthSummary> watchWorth()` where `WorthSummary { Money? total; Map<String, Money> byCurrency; bool ratesMissing; bool ratesStale; }`. `total` is null when any non-main currency has no rate.
    - `Stream<List<CategorySpend>> watchSpending(DateTime month)` where `CategorySpend { Category category; Money total; int count; }`, expenses only, converted to main currency with each entry's own-day rate, sorted by total descending.
    - `Stream<List<Transaction>> watchEntries({int? categoryId, DateTime? month})`.

- [ ] **Step 1: Write failing tests** (in-memory db, seeded, fake fx):
  - expense 28.00 from WeChat → WeChat balance −28.00, Food spend 28.00;
  - validation: amount 0 → `non_positive_amount`; PKR money on CNY account → `currency_mismatch`; income category on expense → `wrong_category_kind`; transfer to same account → `same_account`;
  - transfer 5000 PKR from Pakistani bank to Alipay with `received` 122.00 CNY → balances −5000 PKR and +122 CNY, spending for the month is empty;
  - transfer with `customRate` 0.0245 → received 122.50 CNY;
  - replace expense with 30.00 then delete → balance back to 0 and Food spend absent (Review Focus 3);
  - replace a transfer's destination from Alipay to WeChat → Alipay back to 0, WeChat increased;
  - a PKR expense's converted spend stays identical after a new day's snapshot with a different rate is added;
  - expense at 23:59 on 30 Nov local time counts in November, not December (Review Focus 5);
  - `watchWorth` with no snapshots and a PKR balance → `total == null`, `ratesMissing == true`, `byCurrency['CNY']` correct (Review Focus 2).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement. Compute balances and sums with SQL aggregates per account and currency, then do currency conversion in Dart with `convert`; never sum across currencies in SQL.
- [ ] **Step 4:** Run `flutter test test/features/ledger` → PASS.
- [ ] **Step 5: Commit** `feat: ledger service with validation, balances, worth and spending`

### Task 6: Design system

**Files:**
- Create: `lib/ui/theme/app_colors.dart`, `lib/ui/theme/app_theme.dart`, `lib/ui/widgets/amount_text.dart`
- Test: `test/ui/theme/app_theme_test.dart`

**Interfaces:**
- Produces:
  - `class AppColors extends ThemeExtension<AppColors>` with fields `ground, surface, ink, muted, rule, brass, onBrass, yuan, rupee, dollar, gain, warning` and `static AppColors light`, `static AppColors dark` using spec section 12 values (`onBrass` = `#15201B` in both; `warning` light `#A32D2D`, dark `#F09595`; `gain` light `#2F7A4F`, dark `#7FD1A0`).
  - `Color currencyColor(AppColors c, String code)` (CNY yuan, PKR rupee, USD dollar, others muted).
  - `ThemeData buildTheme(Brightness b)`: Material 3, `scaffoldBackgroundColor` ground, text theme in `Instrument`, extension `AppColors`.
  - `AmountText(Money m, {double size = 44, bool showDecimals = true, bool signed = false})`: `Bricolage` font, `FontFeature.tabularFigures()`, width axis 80 (`FontVariation('wdth', 80)`), symbol at half size raised, decimals in muted color at half size.

- [ ] **Step 1: Write failing tests:** `AppColors.light.brass == AppColors.dark.brass`; contrast ratio (write a small `contrast(Color a, Color b)` helper in the test) of ink and muted on ground and surface ≥ 4.5 in both themes; `buildTheme(Brightness.dark).extension<AppColors>()!.ground == Color(0xFF0E1613)`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement. If any muted pair fails 4.5, darken (light) or lighten (dark) that muted value minimally and note the new hex in the commit message.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** `feat: design tokens, themes and amount text`

### Task 7: App shell and navigation

**Files:**
- Create: `lib/app/router.dart`, `lib/app/providers.dart`, `lib/ui/widgets/placeholder_tab.dart`, plus minimal placeholder files `lib/features/wealth/wealth_screen.dart`, `lib/features/spending/spending_screen.dart`, `lib/features/settings/settings_screen.dart`, `lib/features/entry/entry_form_screen.dart` (each a widget with the final class name showing `PlaceholderTab(title)`; Tasks 8 to 11 replace their bodies); Modify: `lib/app/app.dart`, `lib/main.dart`
- Test: `test/app/shell_test.dart`

**Interfaces:**
- Consumes: Tasks 3 to 6.
- Produces:
  - Providers: `databaseProvider` (drift_flutter `driftDatabase(name: 'budget')`, overridable in tests), `fxServiceProvider`, `ledgerServiceProvider`, `mainCurrencyProvider` (StreamProvider<String> from Settings).
  - Routes: `/chat`, `/wealth`, `/spending`, `/goals`, `/upcoming` inside a `StatefulShellRoute` with a bottom bar; `/settings`; `/entry` (full-screen, optional `?kind=expense|income|transfer`).
  - Bottom bar labels and Phosphor duotone icons: Chat `chatCircleText`, Wealth `wallet`, Spending `chartPieSlice`, Goals `flagBanner`, Upcoming `calendarDots`. Active item sits on a brass pill with `onBrass` icon color.
  - Chat, Goals and Upcoming show `PlaceholderTab(title)` with one line "Coming in the next update" and a "+" button to `/entry` on Chat.
  - Initial route in plan 1 is `/wealth`, because Chat is still a placeholder. Plan 2 changes the initial route to `/chat`. Tab order stays Chat, Wealth, Spending, Goals, Upcoming.
  - On start: `seedIfEmpty()` then `fxService.refreshIfNeeded()` (not awaited before first frame).
- [ ] **Step 1: Write failing widget test:** with an in-memory db override, the app opens on Wealth, tapping "Spending" shows the Spending screen (its placeholder for now, found by type `SpendingScreen`), and both light and dark themes build without exceptions.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** `feat: app shell with five tabs and theming`

### Task 8: Manual entry form

**Files:**
- Create: `lib/features/entry/entry_form_screen.dart`
- Test: `test/features/entry/entry_form_test.dart`

**Interfaces:**
- Consumes: `LedgerService` add methods and `replaceTransaction`, providers.
- Produces: `EntryFormScreen({String initialKind = 'expense', int? editTransactionId})`. Segmented control Expense / Income / Transfer. Fields: amount, account (currency shown), category (filtered by kind), date (default now), note; for transfer: to account, and when currencies differ a "Received" amount field plus an optional "Rate" field (filling one computes the other via `convert`, user may override). Save button label "Save" (brass fill). On `LedgerException` show the message under the related field; never close the screen on error. When editing, a "Delete" text action asks for confirmation.
- [ ] **Step 1: Write failing widget tests:** saving "28" Food WeChat creates one expense; amount "0" shows an error and nothing is saved; transfer PKR→CNY with Received "122" saves 122.00 CNY; editing an existing entry and deleting it removes it after confirming.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** `feat: manual entry form for expense, income and transfer`

### Task 9: Wealth screen

**Files:**
- Create: `lib/features/accounts/account_service.dart`, `lib/features/wealth/account_edit_sheet.dart`; Replace placeholder: `lib/features/wealth/wealth_screen.dart`
- Test: `test/features/accounts/account_service_test.dart`
- Test: `test/features/wealth/wealth_screen_test.dart`

**Interfaces:**
- Consumes: `watchBalances`, `watchWorth`, `mainCurrencyProvider`, `currencyColor`, `AmountText`.
- Produces:
  - `class AccountService { AccountService(AppDatabase db); Future<int> createAccount({required String name, required String currency, int openingMinor = 0, bool isCredit = false}); Future<void> renameAccount(int id, String name); Future<void> setOpeningBalance(int id, Money opening); Future<void> archiveAccount(int id); Future<void> unarchiveAccount(int id); }` throwing `LedgerException` codes `duplicate_name` (case-insensitive among non-archived), `unknown_currency`, `unknown_account`, `currency_mismatch` (opening balance currency). Provider `accountServiceProvider`. Unit tests for each method and error first, then the screen.
  - Header: label "Everything you have, in <currency name>" and total via `AmountText`. If `total == null`: show the main-currency subtotal with the line "Exchange rates aren't available yet. Connect to the internet to see your full total." If stale: small muted line "Rates from <date>".
  - Toggle Combined / By currency (local state). Combined: share bar by currency (currency colors) and groups. By currency: one total per currency, no conversion.
  - Groups per currency (name "Yuan", "Rupees", "Dollars", else code) with subtotal; accounts listed with balance; non-main groups show the converted subtotal in muted text.
  - Attribution line at the bottom: "Rates by ExchangeRate-API".
  - Tap an account → `AccountEditSheet` (rename, archive, opening balance). "Add account" action: name, currency (CNY, PKR, USD), opening balance. Archived accounts are hidden from the groups and listed under a collapsed "Archived" section; their balances still count in totals.
  - Worth history chart and exchange-rate effect are NOT in this plan (need snapshots over time; plan 5 polish).
- [ ] **Step 1: Write failing widget tests:** seeded data with a WeChat expense shows "Yuan" group and the right WeChat balance; with no snapshots and a PKR balance the "aren't available yet" line appears and no combined total is shown; adding an account "Huabei" CNY makes it appear in the Yuan group.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** `feat: wealth screen with currency groups and account management`

### Task 10: Spending screen

**Files:**
- Create: `lib/features/spending/spending_screen.dart`, `lib/features/spending/category_entries_screen.dart`
- Test: `test/features/spending/spending_screen_test.dart`

**Interfaces:**
- Consumes: `watchSpending(month)`, `watchEntries`, `EntryFormScreen` for edit.
- Produces: month picker (previous / next arrows, label "November 2026"), total spent this month via `AmountText`, a donut chart (`fl_chart` PieChart) of the top 6 categories with the rest grouped as "Other categories", then the category list (icon, name, count, total). Tap a category → `CategoryEntriesScreen` listing entries (date, note or account, amount signed); tap an entry → edit form. Empty month: "No spending recorded in <month>." with a "+ Add expense" button.
- [ ] **Step 1: Write failing widget tests:** two Food and one Transport expense in November show Food first with count 2; switching to December shows the empty message; editing a Food entry amount in the entries list updates the category total on return.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** `feat: spending screen with monthly categories and entries`

### Task 11: Settings (minimum) and device check

**Files:**
- Create: `lib/features/categories/category_service.dart`; Replace placeholder: `lib/features/settings/settings_screen.dart`
- Test: `test/features/categories/category_service_test.dart`, `test/features/settings/settings_test.dart`

**Interfaces:**
- Produces: `class CategoryService { CategoryService(AppDatabase db); Future<int> createCategory({required String name, required String kind, String iconKey = 'tag'}); Future<void> renameCategory(int id, String name); Future<void> archiveCategory(int id); }` throwing `LedgerException` `duplicate_name` (within the same kind), `unknown_category`. Archived categories disappear from pickers but stay on old entries. Provider `categoryServiceProvider`.
- Settings screen reachable from a gear icon in the Wealth and Spending headers, with main currency picker (CNY, PKR, USD) writing `Settings.mainCurrency`, and category management (add, rename, archive) for both kinds. Other settings arrive in later plans.
- [ ] **Step 1: Write failing test:** switching main currency to PKR makes the Wealth header show "in rupees" and the total in PKR; renaming the expense category "Other" to "Misc" shows in the expense picker of the entry form while the income "Other" is unchanged.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5:** Run the full suite `flutter test` → all PASS, then `flutter build apk --release` and install on Rao's Android phone; check by hand: light and dark mode (switch phone theme), fonts render (not the default font), rates load on Wi-Fi in China, airplane mode shows the "aren't available yet" line on a fresh install.
- [ ] **Step 6: Commit** `feat: settings for main currency and categories`
