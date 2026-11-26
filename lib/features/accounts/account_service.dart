import 'package:drift/drift.dart';

import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../data/db/app_database.dart';
import '../ledger/ledger_errors.dart';

class AccountService {
  AccountService(this._db);
  final AppDatabase _db;

  Future<int> createAccount({
    required String name,
    required String currency,
    int openingMinor = 0,
    bool isCredit = false,
  }) async {
    try {
      currencyOf(currency);
    } on ArgumentError {
      throw const LedgerException(
        'unknown_currency',
        'Choose a supported currency.',
      );
    }
    final trimmed = name.trim();
    return _db.transaction(() async {
      await _checkName(trimmed);
      final last =
          await (_db.select(_db.accounts)
                ..orderBy([(a) => OrderingTerm.desc(a.sortOrder)])
                ..limit(1))
              .getSingleOrNull();
      return _db
          .into(_db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: trimmed,
              currency: currency,
              sortOrder: (last?.sortOrder ?? -1) + 1,
              openingMinor: Value(openingMinor),
              isCredit: Value(isCredit),
            ),
          );
    });
  }

  Future<void> renameAccount(int id, String name) => _db.transaction(() async {
    final account = await _account(id);
    final trimmed = name.trim();
    if (!account.archived) await _checkName(trimmed, except: id);
    await _update(id, AccountsCompanion(name: Value(trimmed)));
  });

  Future<void> setOpeningBalance(int id, Money opening) => _db.transaction(
    () async {
      final account = await _account(id);
      if (opening.currency != account.currency) {
        throw const LedgerException(
          'currency_mismatch',
          'Use the account currency for the opening balance.',
        );
      }
      await _update(id, AccountsCompanion(openingMinor: Value(opening.minor)));
    },
  );

  Future<void> archiveAccount(int id) => _db.transaction(() async {
    await _account(id);
    await _update(id, const AccountsCompanion(archived: Value(true)));
  });

  Future<void> unarchiveAccount(int id) => _db.transaction(() async {
    final account = await _account(id);
    await _checkName(account.name, except: id);
    await _update(id, const AccountsCompanion(archived: Value(false)));
  });

  Future<Account> _account(int id) async {
    final account = await (_db.select(
      _db.accounts,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
    if (account == null) {
      throw const LedgerException(
        'unknown_account',
        'This account is no longer available.',
      );
    }
    return account;
  }

  Future<void> _checkName(String name, {int? except}) async {
    final key = name.toLowerCase();
    final active = await (_db.select(
      _db.accounts,
    )..where((a) => a.archived.equals(false))).get();
    if (active.any(
      (a) => a.id != except && a.name.trim().toLowerCase() == key,
    )) {
      throw const LedgerException(
        'duplicate_name',
        'An active account already has this name.',
      );
    }
  }

  Future<void> _update(int id, AccountsCompanion values) async {
    await (_db.update(
      _db.accounts,
    )..where((a) => a.id.equals(id))).write(values);
  }
}
