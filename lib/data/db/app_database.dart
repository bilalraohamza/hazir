import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';
part 'seed.dart';

extension ChatMessageText on ChatMessage {
  String get text => messageText;
}

@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    Transactions,
    FxSnapshots,
    Settings,
    ChatMessages,
    ChatActions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await transaction(() async {
          await migrator.createTable(chatMessages);
          await migrator.createTable(chatActions);
        });
      }
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );

  Future<void> seedIfEmpty() => transaction(() async {
    await _seedIfEmpty(this);
    await (update(categories)..where(
          (row) => row.name.equals('Other') & row.iconKey.equals('dotsThree'),
        ))
        .write(const CategoriesCompanion(iconKey: Value('tag')));
  });
}
