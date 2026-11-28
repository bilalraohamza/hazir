# Plan 2: Agent and Chat Implementation Plan

> **For agentic workers:** Follow AGENTS.md. Work one task at a time; each task starts with failing tests and ends with a commit. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hazir's Chat tab becomes a working AI agent: Rao types in English, Chinese or Roman Urdu; the agent logs expenses, income and transfers, manages accounts and categories, and answers questions about his money, always through app tools that calculate every number.

**Architecture:** A provider-neutral OpenAI-compatible client talks to Zhipu (default) or OpenRouter (optional). A hand-written agent loop sends the user's message, a compact context and a tool list; the model calls tools; the app validates and runs them through the existing services (LedgerService, AccountService, CategoryService, DeletionService, FxService); a save policy decides whether a write is saved immediately or proposed for confirmation. Chat messages and their cards are stored locally in new Drift tables. The model never does arithmetic and never writes to the database directly.

**Tech Stack:** existing stack plus flutter_secure_storage (API key).

**Spec:** `docs/superpowers/specs/2026-11-25-budget-app-design.md`, sections 8, 9, 10 and 12. Plan 1 code is the base.

**Not in this plan:** budget limits, upcoming items, goals, debts and credit (plans 3 and 4 add their own tools to the same registry), app lock and backups (plan 5).

## Global Constraints

- The model never calculates money. Every amount the user sees in a card comes from the database or a tool result computed by the app. The agent's text may repeat tool-provided figures but cards are the source of truth.
- Tool arguments carry amounts as decimal STRINGS ("28.50") plus a currency code, parsed with Money.parse. Never JSON numbers for money.
- Accounts and categories are referenced by id in tool calls; the context gives the model the id list.
- Every write goes through the existing services and their validation. A rejected call returns a structured tool error (code + message) to the model, never an exception to the UI.
- Save policy (spec section 8): add_expense and add_income are saved immediately only when the amount converted to the main currency is below the large-amount threshold (default 500.00 CNY, adjustable), a rate is available for the conversion, and the model reports no assumed fields. Everything else (transfers, large or assumed entries, account and category changes, edits, deletes) is proposed and runs only after Rao taps Confirm. Deletes always show the existing delete warning text.
- Replies are always in English. Input may be English, Chinese or Roman Urdu, mixed.
- Only the last 8 chat messages, the account and category lists, today's local date and time, and the main currency are sent per turn. Never the transaction history (queries go through read tools).
- API keys live only in flutter_secure_storage. Never in the database, logs, crash text or source code.
- No network calls in tests: use FakeLlmClient everywhere except the opt-in eval script.
- UI rules from plan 1 stay: AppColors only, Bricolage numbers, Instrument text, Phosphor icons, sentence case, no middle dots, works in light and dark.

## Review Focus

1. Ambiguous messages ("lunch 28" with several CNY accounts): the agent must ask, not guess, or mark the field as assumed so the entry needs Confirm.
2. Large amount without an exchange rate (for example 50,000 PKR offline): treat as large, require Confirm.
3. Model returns malformed tool arguments or an unknown tool name: the loop returns a tool error to the model once, and after repeated failure shows a friendly message with "Add it manually" instead of crashing.
4. No API key, wrong key (401), rate limit (429), timeout or no internet: clear message in Chat, the typed text is kept, and the manual form is one tap away.
5. Undo on an auto-saved entry, then Edit on another: balances and cards stay consistent with the database.

---

## File structure

```
lib/features/agent/
  settings/agent_settings.dart        AgentSettings model + repository (DB + secure storage)
  llm/llm_client.dart                  LlmClient interface, messages, tool call types, errors
  llm/openai_compatible_client.dart    Dio implementation
  tools/tool_spec.dart                 ToolSpec, ToolKind, ToolResult, ToolError
  tools/tool_registry.dart             registry + JSON schema export
  tools/read_tools.dart                balances, spending, entries, worth, rate, affordability
  tools/entry_tools.dart               add/replace/delete transactions
  tools/account_tools.dart             create/rename/archive/delete accounts
  tools/category_tools.dart            create/rename/archive/delete categories
  tools/settings_tools.dart            main currency, large-amount threshold
  policy/save_policy.dart              auto-save vs propose
  agent/context_builder.dart           per-turn context
  agent/system_prompt.dart             versioned system prompt text
  agent/agent_loop.dart                the loop
  chat/chat_repository.dart            chat tables access
  chat/chat_screen.dart                Chat tab UI
  chat/chat_cards.dart                 receipt, proposal, answer, error cards
lib/data/db/tables.dart                + ChatMessages, ChatActions (schema v2)
lib/features/settings/assistant_settings_screen.dart
tool/agent_eval.dart                   opt-in live evaluation script
test/agent/...                         unit and widget tests
test/agent/eval/messages.json          evaluation cases
```

---

### Task 1: Agent settings and Assistant settings screen

**Files:** `pubspec.yaml`, `lib/features/agent/settings/agent_settings.dart`, `lib/features/settings/assistant_settings_screen.dart`, `lib/features/settings/settings_screen.dart`, tests in `test/agent/settings/`, `test/features/settings/`

**Interfaces:**
- Produces:
  - `enum AgentProvider { zhipu, openRouter, custom }`
  - `class AgentSettings { final AgentProvider provider; final String baseUrl; final String model; final bool hasApiKey; final Money largeAmountThreshold; }` with defaults: zhipu, `https://open.bigmodel.cn/api/paas/v4`, model `glm-4.7-flash`, threshold `Money(50000, 'CNY')`.
  - Provider presets: openRouter base `https://openrouter.ai/api/v1`, default model `z-ai/glm-5.3-flash:free`; custom has no preset.
  - `class AgentSettingsRepository { Stream<AgentSettings> watch(); Future<void> save(AgentSettings s); Future<void> setApiKey(AgentProvider p, String key); Future<String?> apiKey(AgentProvider p); Future<void> clearApiKey(AgentProvider p); }` storing non-secret values in the Settings table (keys `agentProvider`, `agentBaseUrl`, `agentModel`, `largeAmountThreshold` as "50000:CNY") and keys per provider in flutter_secure_storage (`apiKey.zhipu` etc.).
- [x] **Step 1:** add `flutter_secure_storage`. Write failing tests for the repository with an in-memory DB and a fake secure store: defaults, save and reload, keys stored per provider and never in the DB, threshold parsing.
- [x] **Step 2:** implement; run tests; pass.
- [x] **Step 3:** Settings gets an "Assistant" section (first section, above Appearance) with one row "AI assistant" whose value is the provider name and "Not set up" in muted when there is no key. It opens `AssistantSettingsScreen`: rows Provider (sheet: Zhipu, OpenRouter, Custom), API key (masked "••••1234" or "Add key"; sheet with a text field, paste button, Save and Remove), Model (text field, prefilled from preset), Base URL (only editable for Custom), "Large amounts need confirmation from" (money input in the main currency), and a brass "Test connection" button that sends a one-line request through the LlmClient (Task 2; until then, wire it at the end of Task 2) and shows "Connected to <model>" or the mapped error.
- [x] **Step 4:** widget tests: section and row appear, key saved is shown masked, Remove clears it, provider switch applies the preset.
- [x] **Step 5:** commit `feat: assistant settings and secure api key`.

### Task 2: OpenAI-compatible client

**Files:** `lib/features/agent/llm/llm_client.dart`, `openai_compatible_client.dart`, `test/agent/llm/`

**Interfaces:**
- Produces:
  - `sealed class LlmMessage` with `SystemMessage(text)`, `UserMessage(text)`, `AssistantMessage(text?, toolCalls)`, `ToolMessage(toolCallId, name, jsonContent)`.
  - `class ToolCall { final String id; final String name; final Map<String, Object?> arguments; final String rawArguments; }`
  - `class LlmResponse { final String? text; final List<ToolCall> toolCalls; }`
  - `abstract class LlmClient { Future<LlmResponse> complete({required List<LlmMessage> messages, required List<Map<String,Object?>> tools}); }`
  - `class LlmException implements Exception { final LlmErrorKind kind; final String message; }` with kinds `noApiKey, unauthorized, rateLimited, quotaExceeded, timeout, network, badResponse, server`.
  - `class OpenAiCompatibleClient implements LlmClient` taking `AgentSettingsRepository` and a `Dio`; POST `<baseUrl>/chat/completions` with `model`, `messages`, `tools` (type function), `tool_choice: "auto"`, `temperature: 0.2`; For compatible Zhipu models: `thinking: {"type": "disabled"}`. HTTP 402 and documented Zhipu balance or quota exhaustion codes map to `quotaExceeded`. Timeouts: connect 10 s, receive 45 s. Unparseable tool arguments keep `rawArguments` and an empty map (the loop handles it).
  - `class FakeLlmClient implements LlmClient` (in `test/agent/fakes.dart`) returning scripted responses and recording requests.
- [x] **Step 1:** failing tests with a Dio mock adapter: request body shape (messages, tools, model, auth header `Bearer`), parsing text-only and tool-call responses (including multiple calls), arguments as string JSON, error mapping (401 to unauthorized, 429 to rateLimited, timeout, socket error to network, 5xx to server, missing key to noApiKey without any request).
- [x] **Step 2:** implement; pass. Wire "Test connection" in Assistant settings to a minimal request.
- [x] **Step 3:** commit `feat: openai compatible llm client`.

### Task 3: Chat storage (schema v2)

**Files:** `drift_schemas/`, `lib/data/db/tables.dart`, `lib/data/db/app_database.dart` and its generated code, `lib/features/agent/chat/chat_repository.dart`, and `test/agent/chat/`.

**Interfaces:**
- Before changing the database, dump and commit the v1 schema and generate the v1 migration test fixture.
- `ChatMessages` has `id`, `role` (`user` or `assistant`), `text`, nullable integer `turnId`, and `createdAt`. User messages have a null `turnId`. Assistant messages reference the user message that started the turn.
- `ChatActions` has `id`, `turnId` referencing the user message, `kind` (`saved`, `proposed`, or `error`), nullable `toolName`, nullable `argumentsJson`, `status` (`saved`, `undone`, `pending`, `confirmed`, `cancelled`, or `failed`), nullable `transactionId`, nullable `resultJson`, and `createdAt`. The transaction ID has no foreign key so actions survive deletion of their entries.
- For proposals, `argumentsJson` holds the normalized preview for Confirm. For errors, `resultJson` holds `{"kind": "<LlmErrorKind name>"}` or a tool error code. Answers are assistant text.
- `schemaVersion => 2`. The migration only creates the two chat tables. Verify that a populated v1 database file created from the exported schema upgrades without changing its ledger rows.
- `class ChatTurn { final ChatMessage user; final List<ChatAction> actions; final List<ChatMessage> replies; }`. Actions and replies are ordered by `createdAt` then `id`.
- `Stream<List<ChatTurn>> watchTurns({int limit = 100})` returns the most recent turns with the newest last.
- `Future<int> addUser(String text)`, `Future<int> addAssistant(int turnId, String text)`, and `Future<int> addAction({required int turnId, required String kind, required String status, String? toolName, String? argumentsJson, int? transactionId, String? resultJson})`.
- `Future<void> setActionStatus(int id, String status, {int? transactionId, String? resultJson})`, `Future<ChatAction?> action(int id)`, and `Future<List<ChatAction>> actionsForTurn(int turnId)`.
- `Future<List<ChatMessage>> historyBefore(int turnId, int n)` returns the last `n` messages of either role with IDs below `turnId`, oldest first. Task 7 attaches the saved-action lines.
- Unknown role, kind, or status strings throw `ArgumentError`.
- [x] Steps. Write failing tests for inserts, turn grouping and order, an error before any reply, action updates, history cutoff, the turn limit, validation, and the v1 file migration. Implement, pass the full suite and analyzer, then commit `feat: chat storage`.

### Task 4: Tool framework and read tools

**Files:** `tools/tool_spec.dart`, `tool_registry.dart`, `tool_args.dart`, `read_tools.dart`, `test/agent/tools/`

**Interfaces:**
- `enum ToolKind { read, write, destructive }`
- `class ToolSpec { final String name; final String description; final Map<String,Object?> parameters; final ToolKind kind; }` with nullable callbacks `run`, `validate`, and `execute`, each of type `Future<ToolResult> Function(Map<String,Object?> args)`
- Read tools set only `run`. Write and destructive tools set both `validate` and `execute`. The constructor asserts the correct shape.
- `sealed class ToolResult` with `ToolOk(Map<String,Object?> data)` and `ToolError(String code, String message)`; `toJson()` for the tool message.
- `class ToolRegistry { void register(ToolSpec s); List<Map<String,Object?>> schemas(); ToolSpec? byName(String n); }`
- Argument helpers that return ToolError instead of throwing: `money(args, 'amount', 'currency')`, `intId(args, 'account_id')`, `optionalDate(args, 'at')` (ISO local "2026-11-28T12:41" or "2026-11-28"), `stringList(args, 'assumed')`.
- Read tools (all return computed values as both formatted strings and minor units):
  - `list_accounts` (id, name, currency, archived), `list_categories` (id, name, kind, archived),
  - `get_balances` (active account breakdown, totals including archived balances as on Wealth, combined total in main currency or `rates_missing` and the affected currencies),
  - `get_spending` (args: period `this_month` | `last_month` | `YYYY-MM`, optional category_id, account_id; returns total and per category with counts and unconverted count),
  - `get_entries` (args: optional category_id, account_id, kind, from, to, text contains in note, limit max 20),
  - `get_exchange_rate` (from, to; returns rate and day, or rates_missing),
  - `get_affordability` (amount, currency): available = combined balance of non-archived accounts in the main currency; returns available before and after, and a note that budget limits and upcoming expenses are not included yet (plan 3 extends this).
- [x] Steps: failing tests for each read tool against a seeded in-memory DB (including rates missing), argument helper errors (bad amount string "28,5.1", unknown id, bad date), implement, pass, commit `feat: tool registry and read tools`.

### Task 5: Write tools

**Files:** `entry_tools.dart`, `account_tools.dart`, `category_tools.dart`, `settings_tools.dart`, tests

**Interfaces:**
- Every write tool accepts an optional `assumed` array of field names the model filled in without the user saying them, and a short `summary` string (shown on proposal cards).
- Entry tools (ToolKind.write unless noted): `add_expense` (account_id, amount, currency, category_id, note?, at?), `add_income` (same), `add_transfer` (from_account_id, to_account_id, amount, currency, received_amount?, received_currency?, rate?, note?, at?), `edit_entry` (entry_id plus any fields; full replacement built from the stored entry), `delete_entry` (entry_id; destructive).
- Account tools: `create_account` (name, currency, opening_amount?), `rename_account`, `archive_account`, `delete_account` (destructive; result includes the counts used in the warning text).
- Category tools: `create_category` (name, kind, icon_key?; description tells the model to ask Rao first), `rename_category`, `archive_category`, `delete_category` (category_id, move_to_category_id?; destructive).
- Settings tools: `set_main_currency` (currency), `set_large_amount_threshold` (amount, currency).
- Each tool has two phases so the save policy can sit between them: `validate(args) -> ToolResult` (no writes, returns a normalized preview: account and category names, Money values, converted main-currency amount or null) and `execute(normalized) -> ToolResult` (performs the write via the existing services, returns transactionId or receipt id). LedgerException codes map to ToolError with the same code.
- [ ] Steps: failing tests per tool for validate and execute (happy path, each validation error, transfers with received vs rate vs none and rates missing, delete returns a DeletionReceipt usable for undo), implement, pass, commit `feat: agent write tools`.

### Task 6: Save policy

**Files:** `policy/save_policy.dart`, tests

**Interfaces:**
- `enum Decision { autoSave, propose }`
- `class SavePolicy { Decision decide({required String toolName, required ToolKind kind, required Map<String,Object?> preview, required List<String> assumed, required Money threshold}); }`
- Rules exactly as in Global Constraints. Converted main-currency amount missing counts as large.
- [ ] Steps: table-driven failing tests (small clear expense auto, 499.99 auto, 500.00 propose, PKR equivalent above threshold propose, PKR with no rate propose, assumed field propose, every transfer propose, every non-entry write propose, destructive propose), implement, pass, commit `feat: save policy`.

### Task 7: Context, system prompt and agent loop

**Files:** `agent/context_builder.dart`, `agent/system_prompt.dart`, `agent/agent_loop.dart`, tests

**Interfaces:**
- `class AgentContext { String toPromptBlock(); }` built from: local date, weekday and time with UTC offset, main currency, large-amount threshold, active accounts (id, name, currency), active categories (id, name, kind).
- `const systemPromptVersion = 1;` and `String systemPrompt(AgentContext c)`. Required content (write it as clear instructions, not as code):
  - You are Hazir, Rao's personal money assistant. Reply in short, plain English, whatever language Rao writes in. He may write English, Chinese, Roman Urdu or a mix (for example "aaj khana 50 ka khaya wechat se" means today he spent 50 on food from WeChat).
  - Never calculate, convert or total money yourself. Use the tools for every number and only repeat numbers the tools returned.
  - To log something, call the matching tool. If a required detail is missing and cannot be reasonably inferred, ask one short question instead of calling the tool. If you fill in a detail Rao did not say (account, category, date, currency), list it in `assumed`.
  - Use existing categories. If nothing fits, ask Rao whether to create one before calling create_category.
  - For questions, call read tools and answer in one or two sentences.
  - Lending, borrowing, budgets, upcoming bills and goals are not available yet: say so briefly and suggest logging it as a normal entry or waiting for the next update.
  - Do not invent accounts, categories or ids that are not in the context.
- `class AgentLoop { AgentLoop(LlmClient llm, ToolRegistry tools, SavePolicy policy, ChatRepository chat, AgentContextBuilder ctx, AgentSettingsRepository settings); Future<void> send(String userText); Future<void> confirm(int actionId); Future<void> cancel(int actionId); Future<void> undo(int actionId); }`
- Loop rules:
  1. Store the user message. Build messages: system prompt, last 8 chat messages (text only), the new user message.
  2. Call the LLM with all tool schemas. Up to 6 rounds per user message.
  3. For each tool call: unknown tool or unparseable arguments -> ToolError back to the model. Read tool -> run, return result. Write or destructive tool -> validate; on ToolError return it; on success ask SavePolicy: autoSave -> execute, store a `saved` action with transactionId, return the result to the model; propose -> store a `pending` action with the normalized preview, return `{"status":"waiting_for_confirmation"}` to the model.
  4. When the model returns text without tool calls, store it as the assistant message (actions link to it) and stop.
  5. After 6 rounds or two consecutive identical failing calls, stop and store an assistant message "I couldn't do that. You can add it manually." with an error action.
  6. LlmException -> store an error action with the mapped friendly text (see Task 8) and no assistant text; the user message stays.
  - `confirm` executes the stored normalized action exactly as previewed (re-validates first; if it now fails, mark failed and show the error). `cancel` marks cancelled. `undo` on a saved entry deletes it through DeletionService and marks undone.
- [ ] Steps: failing tests with FakeLlmClient scripts covering: small expense auto-saved and confirmed in text; large expense proposed then confirmed; transfer proposed; clarifying question (no tool call) stored as text; malformed arguments then corrected call; unknown tool; 6-round cap; LlmException kinds; confirm after the account was archived fails cleanly; undo removes the entry and updates balances; only 8 previous messages sent; context contains ids and no transaction history; system prompt contains the version and the key rules. Implement, pass, commit `feat: agent loop`.

### Task 8: Chat screen

**Files:** `chat/chat_screen.dart`, `chat/chat_cards.dart`, `lib/app/router.dart`, tests

**Layout (same visual language as plan 1, works in light and dark):**
- Shared page header: left "Chat", right the gear. Initial app route becomes `/chat`.
- Message list (newest at the bottom, auto-scroll on new items, bottom padding for the input bar):
  - User message: right-aligned plain text in ink on a soft surface pill (surface fill, hairline border, 14px radius), max 80% width.
  - Assistant text: left-aligned plain text, no bubble.
  - Saved card (`saved`): receipt card as in the approved mockup: category duotone icon tinted by currency color, title (note or category name), "<category>, <account>, <time>" in muted (comma separated, no middle dots), amount in Bricolage on the right with a real minus for expenses; actions Undo and Edit as brass-outlined pills with ink text. After Undo the card shows "Undone" in muted and no actions.
  - Proposal card (`pending`): same layout plus a muted line from `summary`, assumed fields shown in muted italic ("Account assumed: WeChat"), actions Confirm (brass fill, ink text), Edit (outlined), Cancel (plain). For destructive actions the card shows the same warning text as the delete sheets and the Confirm button is warning red with white text and the same label ("Delete account and 12 entries").
  - Answer data: no special card in this plan; the assistant text answers.
  - Error card: muted text line with an icon and actions: "Add manually" (opens the entry form; for logging intents prefilled with nothing, the typed text is copied into the note) and "Try again" (resends the last user message). Messages: no key "Set up the AI assistant in Settings to use chat." with "Open settings"; unauthorized "Your API key was rejected. Check it in Settings."; rate limited "The AI service is busy. Try again in a moment."; quota exceeded "Your AI account has run out of free quota. Check your provider's console."; network or timeout "Couldn't reach the AI service. Check your internet connection."; server or bad response "The AI service had a problem. Try again or add it manually.".
  - Thinking state: a muted "Thinking…" line with a small animated three-dot indicator (respect reduced motion) while a request runs; the input is disabled during it.
- Input bar pinned at the bottom above the tab bar: rounded field on surface with hairline border, placeholder "What did you spend or earn?", multiline up to 4 lines, send button as a brass circle with PhosphorIconsRegular.arrowUp in ink (disabled and muted when empty), and a small "+" icon button on the left that opens the manual entry form (replaces the floating add button on Chat only; Wealth and Spending keep theirs).
- Empty chat: muted centered text "Tell Hazir what you spent, earned or moved. For example: lunch 28 wechat, got 3000 stipend, sent 5000 rupees to Alipay and got 122." plus three tappable example chips that fill the input.
- Edit on a card opens the redesigned entry form in edit mode (saved) or prefilled from the proposal (pending; saving there marks the action confirmed with the new transaction id).
- [ ] Steps: widget tests with FakeLlmClient: sending shows the user message, thinking, then a saved card with the right amount from the DB; Undo; proposal Confirm saves; Cancel; destructive proposal shows the warning label; error card for noApiKey opens settings; Add manually opens the form; send disabled when empty; example chip fills input; light and dark build. Implement, pass, commit `feat: chat screen`.

### Task 9: Live evaluation and device check

**Files:** `test/agent/eval/messages.json`, `tool/agent_eval.dart`

- [ ] **Step 1:** write `messages.json` with at least 30 cases: each has `input`, and `expect` as either `{"tool": name, "args": {subset}}`, `{"ask": true}` (clarifying question expected), or `{"answer_with_tool": name}`. Cover: English, Chinese ("午饭 28 微信"), Roman Urdu ("kal 1500 ka khana cash se", "abbu ne 20000 bheje bank mein"), mixed; expenses, income, transfers with received amount and with rate; questions ("how much did I spend on food this month", "can I afford 600 yuan"); missing account; unknown category ("gym 200"); large amount; delete and rename requests; dates ("yesterday", "on monday").
- [ ] **Step 2:** `tool/agent_eval.dart` runs every case against the real API using the key from the environment variable `HAZIR_EVAL_KEY` and provider/model from `HAZIR_EVAL_PROVIDER` / `HAZIR_EVAL_MODEL`, with tools in a dry-run mode (validate only, nothing written, on a temporary seeded database). It prints per case pass or fail and the overall accuracy. It is not part of `flutter test`.
- [ ] **Step 3:** Rao runs it for the default model and for OpenRouter `z-ai/glm-5.3-flash:free` (if he has a key) and reports both accuracies. Target: at least 90% on logging cases and 100% "no wrong save" (a wrong account, amount or currency that would have been auto-saved counts as a critical failure). If the default model misses the target, switch the default to the better one or improve the prompt (bump `systemPromptVersion`) and rerun.
- [ ] **Step 4:** build the signed release split APK, install as an update on Rao's phone, and check by hand: set up the key, log a lunch by chat, a Roman Urdu income, a PKR to CNY transfer with received amount, ask a spending question, Undo one entry, turn off internet and see the error card with Add manually.
- [ ] **Step 5:** commit `test: agent evaluation set and script`.

## Decisions from the understanding check (2026-11-28)

These answers are part of the plan. Where they differ from a task above, these win.

### Settings (Task 1)

1. **Provider switching.** Zhipu and OpenRouter reapply their preset model and base URL each time Rao switches to them. Custom remembers its own last URL and model in the Settings keys `agentCustomBaseUrl` and `agentCustomModel`. Each provider keeps its own key (`apiKey.zhipu`, `apiKey.openRouter`, `apiKey.custom`). If the Custom URL's host changes, the Custom key is cleared and must be entered again. A Custom URL must use https; reject anything else with an inline error.
2. **Threshold currency.** The threshold is stored with its own currency ("50000:CNY") and is never rewritten when the main currency changes. Settings shows and edits it in its own currency (money input with a currency picker). The save policy converts the entry amount into the threshold's currency using the latest available rate (today's snapshot or the most recent fallback), not the entry's `fxDay`, because this is a safety check and not accounting. Same currency needs no rate. No rate available means the entry counts as large. This replaces "converted to the main currency" in Global Constraints and Task 6.
3. **Test connection and masking.** Task 1 does not show the Test connection button at all; Task 2 adds it. It tests the saved settings (every field saves when it is changed). The key row shows "••••" plus the last 4 characters, derived from secure storage when the screen opens and never stored anywhere else. Keys shorter than 8 characters show only "••••".
4. **Android backup.** Disable platform backup and device transfer for all Hazir data in Task 1: `android:allowBackup="false"`, plus `android:dataExtractionRules` (Android 12+) and `android:fullBackupContent` (older) files that exclude every domain. Hazir's own encrypted backup comes in plan 5. Until then, data does not move to a new phone automatically.

### Tools (Tasks 4 and 5)

5. **Read tool semantics.** All dates are local. `from` is inclusive from the start of that day and `to` is inclusive to the end of that day; months are local calendar months. `get_spending` never includes transfers; its account filter applies to the expense's account. `get_entries` with an account filter matches either side of a transfer. `get_affordability` uses non-archived accounts (there are no credit accounts until plan 4; keep a single filter function so plan 4 can extend it). If some balances cannot be converted, it returns the converted total plus `partial: true` and the list of accounts left out, and the system prompt tells the model to say the answer is partial. There is no `get_worth_history` in plan 2; `get_balances` is the only worth tool, so drop "worth" from the read tools file map.
6. **Write tool contract.** Task 4's `ToolSpec` has a `run` callback for read tools and `validate` and `execute` callbacks for write and destructive tools; exactly one of the two shapes is set (assert it). Task 5 may add pure, non-writing validation methods to the services, and the existing write paths must call the same validation so the rules exist in one place. Task 5's tool list is final. Opening-balance changes, unarchiving, account reordering and anything about credit stay manual in plan 2.
7. **Assumptions.**
   - Ask a short question when a required detail has no reasonable default: several accounts could fit, the currency cannot be told, or no category clearly fits.
   - If Rao names the account, its currency is implied and is not an assumption. If he names no account and exactly one active account fits the currency, use it and list `account_id` in `assumed`.
   - A clearly matching category is not an assumption.
   - An omitted date means now and is not an assumption. Relative dates ("yesterday", "on monday") are resolved from the context date and are not assumptions.
   - On Confirm, the loop validates again. If any shown value changed (names, money values, converted amount, or a destructive action's affected-entry counts), it does not execute: the old action becomes `failed` with reason `changed` in `resultJson`, and a new `pending` action with the fresh preview is added to the same turn for Rao to confirm.

### Chat storage and the loop (Tasks 3 and 7)

8. **Action ownership and retries.**
   - Rename `ChatActions.messageId` to `turnId`: it references the **user** message that started the turn. The assistant's text is its own `ChatMessages` row. Actions therefore exist even when there is no assistant text (errors), and saved actions appear in Chat as soon as they are stored.
   - "Try again" re-runs the same turn. It does not store a new user message.
   - Inside one turn, a write whose tool name and normalized arguments equal one already saved in that turn is not executed again; the loop returns the earlier result.
   - On a retry, the messages sent to the model include a note listing what this turn already saved, so the model does not repeat it.
   - History: the "last 8 messages" are the 8 before the new user message (they do not include it). When an assistant reply had saved or confirmed actions, its history text gets a short appended line such as `[saved: expense 28.00 CNY, Food, WeChat, entry 41]`. This lets "undo that" or "make it 30" work.

### Cards and the entry form (Task 8)

9. **Undo and card states.** Cards read their entry live from the database by `transactionId`, so an edit made elsewhere shows on the card. If the entry was deleted elsewhere, the card shows "Deleted" in muted text with no actions. Undo is available on `saved` and `confirmed` entry actions for as long as the entry exists, and it survives restart (it deletes through DeletionService and marks the action `undone`). Account, category and settings changes, and destructive actions, get no Undo: their card shows "Done" in muted text.
10. **Entry form and layouts.**
    - Task 8 may extend the entry form: add an optional `EntryDraft initial` (kind, account, amount, currency, category, note, date, and transfer fields), and make the route return the saved transaction id when it closes.
    - Manual fallback after an error: open the form as an expense with the typed text in the note. No guessing.
    - Transfer card: arrows-left-right icon, title "Transfer", muted line "<from> to <to>, <time>", sent amount on the right and the received amount under it in muted text.
    - Account, category and settings changes: a compact card with an icon and the summary text, and no amount.
    - There is no mockup file in the repo; the written layout in this plan controls. The balance and "You can spend" header waits for plan 3. Chat only has the shared page header.
11. **Existing UI and rollout.** Confirmed: Assistant goes first, above Appearance and Money; those sections, the theme setting and the Accounts and Categories pages stay as they are. Update the Wealth-first tests to Chat-first. Wealth and Spending keep the shared add button; Chat uses the input bar's "+". For Task 9, Codex builds the signed split APK; Rao installs it and does the phone check.

### Evaluation and prompt (Tasks 7 and 9)

12. **Scoring and deferred features.**
    - A case passes only if the expected call happens and no other write is attempted. Read calls are allowed.
    - Record the save policy decision for every write. A critical failure is any write that would have auto-saved with the wrong account, amount, currency or kind.
    - Rate-limited or failed requests retry up to 3 times with backoff. After that the case counts as skipped: it is reported, but left out of the accuracy. A run is invalid if more than 10% of cases are skipped.
    - Lending and borrowing: the assistant says debt tracking is coming in a later update and does not log it as income or spending. Budgets, upcoming bills and goals: it says they are not available yet. Replace the plan's "suggest logging it as a normal entry" line with this.

### Package and API notes

- **flutter_secure_storage:** use the latest stable version that resolves through the China mirror. Use the package's default Android options unless its current docs require a setting, and do not use deprecated options. It must build in both Hazir Dev and release. `minSdk` stays `flutter.minSdkVersion` (24).
- **Zhipu thinking:** do not send `thinking` blindly. Add a small function that decides the field from provider and model, based on Zhipu's current docs: disabled for models that accept it, omitted for models that require thinking or are unknown. Unit-test it.
- **Custom URL safety:** Dio must not follow redirects (`followRedirects: false`) and must treat a redirect as an error, so the key is never sent to another host. Never log request headers or bodies; no LogInterceptor.
- **Drift:** before bumping to schema 2 in Task 3, dump and commit the v1 schema with drift_dev, and use it in the migration test.
