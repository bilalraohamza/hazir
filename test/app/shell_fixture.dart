import 'dart:async';

import 'package:budget_app/app/app.dart';
import 'package:budget_app/app/providers.dart';
import 'package:budget_app/data/db/app_database.dart';
import 'package:budget_app/features/fx/fx_service.dart';
import 'package:budget_app/features/fx/rates_api.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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

  Widget build({Widget child = const BudgetApp()}) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      fxServiceProvider.overrideWithValue(FxService(db, api, clock: () => now)),
    ],
    child: child,
  );
}
