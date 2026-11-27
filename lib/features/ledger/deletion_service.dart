import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import 'ledger_errors.dart';

class DeletionReceipt {
  DeletionReceipt._(this._restore);
  final Future<void> Function() _restore;
  Future<void>? _result;

  Future<void> restore() => _result ??= _runRestore();

  Future<void> _runRestore() async {
    try {
      await _restore();
    } catch (_) {
      _result = null;
      rethrow;
    }
  }
}

typedef AccountDeletionDetails = ({
  Account account,
  int entryCount,
  int transferCount,
  List<String> counterpartNames,
});

typedef CategoryDeletionDetails = ({
  Category category,
  int entryCount,
  List<Category> destinations,
});

class DeletionService {
  DeletionService(this._db);
  final AppDatabase _db;

  Future<AccountDeletionDetails> accountDeletionDetails(int id) =>
      _db.transaction(() async {
        final account = await _account(id);
        final entries =
            await (_db.select(_db.transactions)..where(
                  (row) =>
                      row.accountId.equals(id) | row.toAccountId.equals(id),
                ))
                .get();
        final transfers = entries.where((entry) => entry.kind == 'transfer');
        final counterparts = {
          for (final entry in transfers)
            if (entry.accountId == id) entry.toAccountId else entry.accountId,
        };
        final names = [
          for (final row in await _db.select(_db.accounts).get())
            if (counterparts.contains(row.id)) row.name,
        ]..sort();
        return (
          account: account,
          entryCount: entries.length,
          transferCount: transfers.length,
          counterpartNames: names,
        );
      });

  Future<CategoryDeletionDetails> categoryDeletionDetails(int id) =>
      _db.transaction(() async {
        final category = await _category(id);
        final count = await (_db.select(
          _db.transactions,
        )..where((row) => row.categoryId.equals(id))).get();
        final choices =
            await (_db.select(_db.categories)
                  ..where(
                    (row) =>
                        row.id.isNotValue(id) &
                        row.kind.equals(category.kind) &
                        row.archived.equals(false),
                  )
                  ..orderBy([(row) => OrderingTerm.asc(row.id)]))
                .get();
        return (
          category: category,
          entryCount: count.length,
          destinations: choices,
        );
      });

  Future<DeletionReceipt> deleteTransaction(int id) => _db.transaction(
    () async {
      final row = await (_db.select(
        _db.transactions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) {
        throw const LedgerException(
          'unknown_transaction',
          'This entry is no longer available.',
        );
      }
      await (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
      return DeletionReceipt._(
        () => _db.transaction(() async {
          await _db.into(_db.transactions).insert(row);
        }),
      );
    },
  );

  Future<DeletionReceipt> deleteAccount(int id) => _db.transaction(() async {
    final account = await _account(id);
    final transactions =
        await (_db.select(_db.transactions)..where(
              (row) => row.accountId.equals(id) | row.toAccountId.equals(id),
            ))
            .get();
    await (_db.delete(_db.transactions)..where(
          (row) => row.accountId.equals(id) | row.toAccountId.equals(id),
        ))
        .go();
    await (_db.delete(_db.accounts)..where((row) => row.id.equals(id))).go();
    return DeletionReceipt._(
      () => _db.transaction(() async {
        await _db.into(_db.accounts).insert(account);
        await _db.batch(
          (batch) => batch.insertAll(_db.transactions, transactions),
        );
      }),
    );
  });

  Future<DeletionReceipt> deleteCategory(
    int id, {
    int? moveToCategoryId,
  }) => _db.transaction(() async {
    final category = await _category(id);
    final idColumn = _db.transactions.id;
    final query = _db.selectOnly(_db.transactions)
      ..addColumns([idColumn])
      ..where(_db.transactions.categoryId.equals(id));
    final movedIds = (await query.get())
        .map((row) => row.read(idColumn)!)
        .toList();
    if (movedIds.isNotEmpty) {
      if (moveToCategoryId == null) {
        throw const LedgerException(
          'category_has_entries',
          'Choose where to move this category’s entries.',
        );
      }
      final target = await (_db.select(
        _db.categories,
      )..where((row) => row.id.equals(moveToCategoryId))).getSingleOrNull();
      if (moveToCategoryId == id ||
          target == null ||
          target.kind != category.kind ||
          target.archived) {
        throw const LedgerException(
          'wrong_category_kind',
          'Choose another active category of the same type.',
        );
      }
      await (_db.update(_db.transactions)
            ..where((t) => t.categoryId.equals(id)))
          .write(TransactionsCompanion(categoryId: Value(moveToCategoryId)));
    }
    await (_db.delete(_db.categories)..where((row) => row.id.equals(id))).go();
    return DeletionReceipt._(
      () => _db.transaction(() async {
        await _db.into(_db.categories).insert(category);
        if (movedIds.isEmpty) return;
        await _db.batch((batch) {
          for (final movedId in movedIds) {
            batch.update(
              _db.transactions,
              TransactionsCompanion(categoryId: Value(id)),
              where: (row) =>
                  row.id.equals(movedId) &
                  row.categoryId.equals(moveToCategoryId!),
            );
          }
        });
      }),
    );
  });

  Future<Account> _account(int id) async {
    final row = await (_db.select(
      _db.accounts,
    )..where((account) => account.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw const LedgerException(
        'unknown_account',
        'This account is no longer available.',
      );
    }
    return row;
  }

  Future<Category> _category(int id) async {
    final row = await (_db.select(
      _db.categories,
    )..where((category) => category.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw const LedgerException(
        'unknown_category',
        'This category is no longer available.',
      );
    }
    return row;
  }
}
