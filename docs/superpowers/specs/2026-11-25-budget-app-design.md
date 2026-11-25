# Hazir (personal budget app): Design

Date: 2026-11-25
Owner: Rao
Status: Approved by Rao on 2026-11-25

## 1. Intent and why

App name: **Hazir** (display name). Internal Flutter project name stays `budget_app`.


Rao is a student living in Wuhan with money in three currencies (CNY, PKR, USD) across several accounts (WeChat, Alipay, bank cards, cash, a Pakistani bank, mobile wallets). He wants one personal app where he tells an AI agent, in plain language, what he spent, earned or moved, and the app keeps an exact record. Screens show where his money is, where it went, what is coming up and how his savings goals are going.

Version one is budgeting only. Later the same app and agent will grow into a personal assistant (todos, plans and more), so the core must be built to extend without a rewrite.

Rao wants it built properly, not as a throwaway: real database, clean architecture, distinctive design.

## 2. Goals, non-goals, anti-goals

Goals (version one)
- Log expenses, income and transfers by chatting, in English, Chinese or Roman Urdu.
- Ask the agent questions about his money and get exact answers ("how much on food this month?", "can I afford a 600 yuan jacket?").
- See balances per account and in total, spending by category and month, savings goals, upcoming expenses and income, monthly category limits, and debts (credit accounts, money he owes, money owed to him).
- Do almost anything in the app through the agent, not only logging.
- Work fully without the agent: every action is also possible by hand.
- Cost nothing to run.

Non-goals (version one)
- Todos, plans, any non-money features.
- Cloud sync, accounts, multiple users.
- Reading payment notifications or bank statements automatically. Rao explicitly does not want notification reading.
- iPhone build (the stack keeps it possible later).
- Investments, stocks, crypto.

Anti-goals (failure even if it technically works)
- A wrong number. Any balance, total or answer that is off is a failure. The AI never computes money.
- Silent changes. Nothing changes a balance without being shown to Rao.
- Generic "AI-made" look (default fonts, purple accents, everything in identical cards).
- App useless when offline or when the free AI model is down.
- Data loss with no way to recover.

## 3. Constraints

- Platform: Android phone now. Must stay portable to iPhone.
- Location: mainland China. Google services (including Google Fonts downloads) and OpenAI/Anthropic APIs are not reachable. Everything the app needs at runtime must work from China without a VPN.
- Budget: free. Free AI model, free exchange-rate API, no server.
- Privacy: all financial data stays on the phone. Only the minimum needed for each agent turn is sent to the AI provider.
- Single user, single device.

## 4. Approaches considered

Framework
- Kotlin + Jetpack Compose: best Android integration, but Android only; its main advantage (reading payment notifications) is not wanted. Rejected.
- Flutter: one codebase for Android now and iPhone later, strong UI control. Chosen.
- React Native (Expo): workable, weaker for polished custom UI and performance. Rejected.

AI provider
- Zhipu GLM Flash models directly: free with no daily cap, reachable in China, supports tool calling, one request at a time. Chosen as default.
- OpenRouter free models: newer models, but 50 requests per day on a free account (1,000 after a one-time 10 USD credit purchase), free models can disappear, access from China is uncertain. Kept as an option in Settings.
- Alibaba Qwen free quota: expires after 90 days. Not used as default.

Agent framework
- LangChain-style framework: adds weight, little benefit for a single tool-calling loop. Rejected.
- Hand-written agent loop with a tool registry. Chosen.

## 5. The stack (decided)

| Layer | Choice |
|---|---|
| App framework | Flutter (Dart) |
| Database | Drift (SQLite), with versioned migrations |
| State management | Riverpod |
| Navigation | go_router |
| Charts | fl_chart |
| HTTP | Dio, calling any OpenAI-compatible chat completions API |
| AI default | Zhipu, newest free GLM Flash model that supports tool calling (verify the current model id at build time) |
| AI optional | OpenRouter or any OpenAI-compatible provider, set in Settings (base URL, key, model id) |
| Exchange rates | open.er-api.com, no key, updated daily, attribution shown in the app |
| Secrets | flutter_secure_storage for API keys |
| Biometric lock | local_auth |
| Local notifications | flutter_local_notifications |
| Fonts | Bricolage Grotesque and Instrument Sans, bundled as asset files (do not use runtime Google Fonts download) |
| Icons | Phosphor (Flutter package), duotone weight |

## 6. Screens

Bottom navigation, five tabs, in this order: Chat, Wealth, Spending, Goals, Upcoming. Settings is reached from a header icon. A "+" action for manual entry is available from Chat and from list screens.

Chat
- Header: today's date, total balance in the main currency (large numerals), and one line "You can spend X until <end of month>" (see section 9).
- Message stream: Rao's messages as plain right-aligned text; agent results as receipt cards; agent text as plain sentences.
- Receipt card for a saved or proposed entry: category icon tinted by currency color, title, category and account, amount; for expenses with a category limit, a progress line "Food in November: 1,050 of 1,200"; actions Undo and Edit (saved) or Confirm and Edit (needs confirmation).
- Input: one text field ("What did you spend or earn?") and a send button.
- History is stored on the phone only.

Wealth (accounts are part of this tab)
- Total worth in the main currency, change this month, and the part of that change caused by exchange rates, shown separately from spending.
- Toggle: Combined (everything converted to the main currency) or By currency (separate totals per currency, no conversion).
- Currency share bar, then accounts grouped by currency with a subtotal per group. Non-main-currency amounts also show their main-currency equivalent in secondary text.
- History line chart of total worth over 3, 6 or 12 months.
- Debts section: total owed to Rao, total Rao owes, and each person with amount left and due date.
- Account management: add, rename, archive, mark as credit, set currency and opening balance.

Spending
- By category and by month, with charts; month picker.
- Each category with a limit shows a progress bar and the current warning state.
- Tapping a category lists its entries; entries can be edited or deleted.

Goals
- Each goal: name, target amount and currency, target date, amount reserved so far and from which accounts, progress, and the amount per month still needed to reach it on time.
- Actions: put money toward a goal, release money, edit, delete.

Upcoming
- Recurring and one-time future items (expenses and income), sorted by due date, with amount, account and how it repeats.

Settings
- Main currency, interface language, theme (follows system), AI provider, large-amount threshold, warning thresholds, categories (add, rename, merge), app lock, backups and export.

Layouts of Spending, Goals and Upcoming are left to the builder within the design system in section 12; Rao reviews them during the build.

## 7. Money rules

- Amounts are stored as integers in the currency's minor unit (fen, paisa, cent). No floating point anywhere in money logic.
- Every account has exactly one currency. Every transaction is stored in its account's original currency and is never rewritten when rates change.
- Conversion happens only for display and for combined totals, using the cached daily rate.
- Main currency is CNY by default and can be changed in Settings; changing it only changes display.
- Rate history (builder's call): the free rate API has no history, so the app saves one rate snapshot per day from install onward in a rates table. Each transaction stores the rate snapshot day it uses (frozen once set), so it can be converted to any main currency consistently. Category limits and monthly spending use each entry's stored rate, so they never shift when rates move. The Wealth history chart and the exchange-rate effect use the daily snapshots; dates before install show no history. If a day's fetch fails, the last saved rate is used and marked as such.
- Starting currencies: CNY, PKR, USD. Any ISO currency can be added.
- Starting accounts (all editable) are WeChat, Alipay, Bank card and Cash (CNY) in CNY, Pakistani bank, Cash (PKR), JazzCash and Easypaisa in PKR, and USD account in USD.

Transactions have three kinds (lending, borrowing and repayments, described under Debts below, are recorded as money moving in or out of an account linked to a debt record, never as spending or income):
- Expense: from one account, one category, optional note.
- Income: into one account, one income category, optional note.
- Transfer: from one account to another. Not counted as spending or income. If currencies differ, both amounts are stored, plus the rate actually used. Rao can give the received amount or a custom rate; the app computes the other. If he gives neither, the day's API rate is used and the agent says so.

Categories
- Expense starter list: Food, Groceries, Transport, Rent, Bills, Shopping, Education, Health, Entertainment, Gifts, Sending home, Other.
- Income starter list: Scholarship/Stipend, From family, Part-time work, Gift, Refund, Other.
- The agent must use an existing category if one fits. If none fits, it asks Rao before creating a new one. Categories can be added, renamed and merged in Settings.

Budget limits
- Optional monthly limit per expense category, set in any currency and compared in the main currency.
- Warning thresholds default to 80% and 100%, adjustable in Settings, and shown next to each limit.
- When an entry crosses a threshold, the agent's reply says so, and the Spending tab shows it.

Recurring and upcoming items
- An item has amount, currency, account, category, kind (expense or income), due date and repeat rule (none, weekly, monthly on a day, yearly).
- All items appear in Upcoming. Expense items due before the end of the month reduce "can I afford it" and "You can spend"; income items never add to them until received (section 9).
- On the due date a local notification offers Paid, Change amount, Skip. Nothing touches a balance until Rao confirms.

Goals (contributions model, decided by Rao)
- Name, target amount and currency, target date.
- Rao puts money toward a goal ("put 500 toward laptop from Alipay"). The money stays in its real account but is marked as reserved for that goal. Reserved money still counts in balances and total worth, but not in "You can spend".
- Money can be released from a goal back to free money. When a goal is reached or deleted, its reserved money is released.
- Progress = reserved amount / target. Monthly amount needed = (target - reserved) / months left. Both calculated by the app.
- An account cannot have more reserved than its balance; the app rejects it.

Debts and credit (decided by Rao)
- Credit accounts: an account can be marked as credit (for example Huabei or a credit card). Its balance can go negative. Spending with it is a normal expense; paying it off from another account is a transfer, not spending.
- Personal debts with people, two directions: "I owe" and "owed to me". Each has the person's name (as Rao types it), amount, currency, optional due date and optional note.
- Lending money moves it out of an account and creates an "owed to me" record. It is not spending. Borrowing moves money into an account and creates an "I owe" record. It is not income.
- Repayments can be partial; the record tracks what is left and closes when it reaches zero.
- Due dates of debts appear in Upcoming with the same Paid / Change amount / Skip reminder.
- Wealth shows a Debts section: total owed to Rao, total Rao owes, and each person. Total worth = account balances + owed to me - I owe (credit account balances are already negative).

## 8. The agent

Behavior
- Understands English, Chinese and Roman Urdu, including mixed messages. Always replies in English.
- Never does arithmetic. Every number it states comes from a tool result calculated by the app.
- Asks a follow-up question when something needed is missing or ambiguous (for example which account, which currency, which category), instead of guessing.
- Save policy (mixed): a clear entry below the large-amount threshold (default 500 CNY equivalent, adjustable) is saved immediately and shown with Undo and Edit. Entries at or above the threshold, all transfers, and anything where the agent had to infer a value are shown as a proposal and saved only when Rao taps Confirm.
- Every write is validated by the app before saving (account exists, amount positive, currency matches account, category exists). Invalid tool calls are rejected with an error the agent can act on.

Scope: full parity (decided by Rao)
- The agent can do almost everything the app can do by hand. Every feature exposes tools.
- Excluded from the agent for safety: app lock, API keys and provider settings, backup password, restore from backup. These stay manual in Settings.
- Destructive actions (deleting anything, archiving an account, merging categories, closing a debt early) always need Confirm, regardless of amount.

Tools (version one; each is a function the app exposes to the model)
- Transactions: add_expense, add_income, add_transfer, update_transaction, delete_transaction.
- Accounts: create_account, update_account (rename, mark credit), archive_account.
- Categories: create_category (only after Rao agrees), rename_category, merge_categories.
- Limits: set_budget_limit, remove_budget_limit.
- Upcoming: add_upcoming_item, update_upcoming_item, delete_upcoming_item, mark_upcoming_paid, skip_upcoming.
- Goals: create_goal, update_goal, delete_goal, contribute_to_goal, release_from_goal.
- Debts: lend_money, borrow_money, record_repayment, update_debt, delete_debt.
- Settings the agent may change: main currency, large-amount threshold, warning thresholds.
- Read: get_balances, get_spending (by category, period, account), get_transactions (filtered search), get_budget_status, get_upcoming, get_goals, get_debts, get_affordability (amount, currency), get_exchange_rate, get_worth_history.
- Context helpers: list_accounts, list_categories.

Tool-count risk (builder's call): about 40 tools is a lot for a free model and can lower its accuracy. The builder should measure tool-call accuracy on the test message set; if it drops, group tools by area and send only the relevant group per turn (chosen by a cheap first step), without changing what the agent can do.

Context sent per turn
- System prompt, tool definitions, list of accounts and categories (names, ids, currencies), today's date and main currency, and the last few chat messages. Never the full transaction history.

Provider handling
- OpenAI-compatible client with base URL, model id and key from Settings; default points to Zhipu.
- If the provider fails or there is no internet, the chat shows a clear message and offers the manual entry form with the text Rao typed kept.

Extensibility
- Tools are registered per module. Todos and plans later add their own tables and tools without changing the agent loop.

## 9. Derived numbers (calculated by the app)

- Balance of an account: opening balance plus all its transactions.
- Total worth: sum of account balances (credit accounts negative) plus money owed to Rao minus money Rao owes, converted to the main currency.
- Exchange-rate effect for a period: change in total worth caused only by rate changes on non-main-currency balances, shown separately from spending.
- Affordability and "You can spend X until end of month": total balance of non-archived, non-credit accounts in the main currency, minus money reserved for goals, minus unpaid upcoming expenses and debt payments due before the end of the month. Expected income is never counted until it arrives (decided by Rao). Money owed to Rao is not counted until repaid.

## 10. Security, privacy, backup

- Optional fingerprint or phone-PIN lock when the app opens (on by default, can be turned off).
- API keys stored with secure storage, never in source code.
- No account numbers stored. Names of people appear only where Rao types them for debts.
- Automatic encrypted backup to phone storage weekly, keeping the last several copies.
- Monthly reminder to copy a backup off the phone.
- Backups are encrypted with a backup password Rao sets once (decided by Rao), so they can be restored on a new phone. The app warns clearly that a forgotten password means backups cannot be opened.
- Manual export of an encrypted backup file and restore from it.
- CSV export of transactions.

## 11. Languages

- Interface: English and Roman Urdu, switchable in Settings. Roman Urdu labels use one consistent spelling style; Rao can correct wording.
- Strings are kept in localization files so more languages can be added.

## 12. Visual design system

One design for light and dark. Layout, type, accent and icons are identical; only ground, surface and ink colors flip, through theme tokens.

Color tokens
| Token | Light | Dark |
|---|---|---|
| Ground | #EEF1EC | #0E1613 |
| Surface | #FFFFFF | #17221D |
| Ink (text) | #15201B | #E6ECE7 |
| Muted text | #5E6B64 | #8C9A92 |
| Rule (hairlines, tracks) | #D5DCD6 | #28352F |
| Brass (accent) | #E8B83A | #E8B83A |
| Yuan | #C8463A | #E0705F |
| Rupee | #2F8F5B | #5DBE88 |
| Dollar | #5F8696 | #8FB3C2 |

Color rules
- Brass is the only accent and is used only as a fill (send button, Confirm, active tab highlight, limit bars below 100%), always with dark ink (#15201B) on top. Never as text color, because brass text on the light ground fails contrast.
- Undo and Edit are brass-outlined buttons with ink text.
- Currency colors appear only to show which currency something is in (icon tint, currency groups, share bar).
- Expenses are shown in ink with a minus sign, not in red. Green only for gains, warning color only for limits over 100%.
- All text meets 4.5:1 contrast in both modes.

Type
- Bricolage Grotesque (condensed width, tabular figures) for balances, amounts and large numbers. This is the one bold element of the design.
- Instrument Sans for all other text.
- Both bundled as font assets (OFL licence).
- No all-caps labels, no middle-dot separated metadata.

Icons
- Phosphor duotone. On the active tab, the icon sits on the brass highlight.

Patterns
- Receipt cards for entries; plain-language summaries ("You can spend ¥1,310 until 30 Nov") instead of dashboard labels; accounts grouped by currency.

## 13. Testing priorities

- Unit tests for all money math: minor units, conversion, transfers with custom rates, balances, budget status, affordability, exchange-rate effect.
- Unit tests for agent tool validation (rejecting bad calls).
- A small test set of real example messages in English, Chinese and Roman Urdu to check the agent's tool calls with the chosen model.

## 14. Left to the builder

- Exact screen layouts of Spending, Goals, Upcoming and Settings, within section 12.
- Icon choice per category.
- Launcher icon design (app name is decided: Hazir, Urdu for "present, at your service").
- Animation details, kept minimal.
- Code structure inside the layers.
