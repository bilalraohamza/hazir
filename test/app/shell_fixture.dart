import 'dart:async';

import 'package:budget_app/app/app.dart';
import 'package:budget_app/app/providers.dart';
import 'package:budget_app/data/db/app_database.dart';
import 'package:budget_app/features/agent/llm/llm_client.dart';
import 'package:budget_app/features/agent/llm/openai_compatible_client.dart';
import 'package:budget_app/features/fx/fx_service.dart';
import 'package:budget_app/features/agent/settings/agent_settings.dart';
import 'package:budget_app/features/fx/rates_api.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../agent/settings/fake_agent_key_store.dart';

class PendingRatesApi implements RatesApi {
  int calls = 0;
  final response = Completer<Map<String, Decimal>>();
  @override
  Future<Map<String, Decimal>> latestPerUsd() {
    calls++;
    return response.future;
  }
}

class ShellFixture {
  final db = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  final api = PendingRatesApi();
  DateTime now = DateTime(2026, 11, 26);

  Widget build({
    Widget child = const BudgetApp(),
    AgentKeyStore? agentKeyStore,
    LlmClient? llmClient,
  }) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      if (llmClient != null) llmClientProvider.overrideWithValue(llmClient),
      agentSettingsRepositoryProvider.overrideWithValue(
        AgentSettingsRepository(db, agentKeyStore ?? FakeAgentKeyStore()),
      ),
      fxServiceProvider.overrideWithValue(FxService(db, api, clock: () => now)),
    ],
    child: child,
  );
}
