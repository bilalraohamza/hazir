import 'dart:io';

import 'package:budget_app/data/db/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schema/schema.dart';

void main() {
  test(
    'upgrades a populated v1 database file without changing its ledger rows',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hazir-chat-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}chat.db');
      final old = GeneratedHelper().databaseForVersion(NativeDatabase(file), 1);
      try {
        await old.customStatement(
          "INSERT INTO accounts (id, name, currency, opening_minor, sort_order) VALUES (17, 'Wallet', 'PKR', 50000, 2)",
        );
        await old.customStatement(
          "INSERT INTO categories (id, name, kind, icon_key) VALUES (23, 'Groceries', 'expense', 'shoppingCart')",
        );
        await old.customStatement(
          "INSERT INTO transactions (id, kind, account_id, amount_minor, currency, category_id, note, occurred_at, created_at, fx_day) VALUES (31, 'expense', 17, 1234, 'PKR', 23, 'original note', 1795881600, 1795881601, '2026-11-28')",
        );
        final version = await old
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 1);
      } finally {
        await old.close();
      }

      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);
      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 2);
      final account = await upgraded.select(upgraded.accounts).getSingle();
      expect(account.toJson(), containsPair('name', 'Wallet'));
      expect(
        (account.id, account.currency, account.openingMinor, account.sortOrder),
        (17, 'PKR', 50000, 2),
      );
      final category = await upgraded.select(upgraded.categories).getSingle();
      expect(
        (category.id, category.name, category.kind, category.iconKey),
        (23, 'Groceries', 'expense', 'shoppingCart'),
      );
      final transaction = await upgraded
          .select(upgraded.transactions)
          .getSingle();
      expect(
        (
          transaction.id,
          transaction.accountId,
          transaction.categoryId,
          transaction.amountMinor,
          transaction.currency,
          transaction.note,
          transaction.fxDay,
        ),
        (31, 17, 23, 1234, 'PKR', 'original note', '2026-11-28'),
      );
      expect(transaction.occurredAt.millisecondsSinceEpoch, 1795881600000);
      expect(transaction.createdAt.millisecondsSinceEpoch, 1795881601000);
      expect(await upgraded.select(upgraded.chatMessages).get(), isEmpty);
      expect(await upgraded.select(upgraded.chatActions).get(), isEmpty);
      expect(
        await upgraded.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}
