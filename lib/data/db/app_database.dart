import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';
part 'seed.dart';

@DriftDatabase(
  tables: [Accounts, Categories, Transactions, FxSnapshots, Settings],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );

  Future<void> seedIfEmpty() => transaction(() => _seedIfEmpty(this));
}
