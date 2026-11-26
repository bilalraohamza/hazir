import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../features/accounts/account_service.dart';
import '../features/categories/category_service.dart';
import '../features/fx/fx_service.dart';
import '../features/fx/rates_api.dart';
import '../features/ledger/ledger_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(driftDatabase(name: 'budget'));
  ref.onDispose(db.close);
  return db;
});

final fxServiceProvider = Provider<FxService>(
  (ref) => FxService(ref.watch(databaseProvider), ErApiRatesApi()),
);

final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(ref.watch(databaseProvider)),
);

final categoryServiceProvider = Provider<CategoryService>(
  (ref) => CategoryService(ref.watch(databaseProvider)),
);

final ledgerServiceProvider = Provider<LedgerService>(
  (ref) =>
      LedgerService(ref.watch(databaseProvider), ref.watch(fxServiceProvider)),
);

final mainCurrencyProvider = StreamProvider<String>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.settings)..where((s) => s.key.equals('mainCurrency')))
      .watchSingle()
      .map((setting) => setting.value);
});
