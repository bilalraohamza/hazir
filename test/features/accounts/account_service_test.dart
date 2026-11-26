import 'package:budget_app/core/money/money.dart';
import 'package:budget_app/data/db/app_database.dart';
import 'package:budget_app/features/accounts/account_service.dart';
import 'package:budget_app/features/ledger/ledger_errors.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AccountService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedIfEmpty();
    service = AccountService(db);
  });

  Future<Account> account(int id) =>
      (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingle();

  Matcher failure(String code) =>
      throwsA(isA<LedgerException>().having((e) => e.code, 'code', code));

  test(
    'create appends a trimmed account with opening balance and credit flag',
    () async {
      final id = await service.createAccount(
        name: ' Huabei ',
        currency: 'CNY',
        openingMinor: -120,
        isCredit: true,
      );
      final row = await account(id);
      expect(
        [row.name, row.currency, row.openingMinor, row.isCredit, row.sortOrder],
        ['Huabei', 'CNY', -120, true, 9],
      );
    },
  );

  test(
    'create rejects duplicate active names and unknown currencies',
    () async {
      await expectLater(
        service.createAccount(name: ' weCHAT ', currency: 'PKR'),
        failure('duplicate_name'),
      );
      await expectLater(
        service.createAccount(name: 'New', currency: 'EUR'),
        failure('unknown_currency'),
      );
      final writes = await Future.wait([
        for (var i = 0; i < 2; i++)
          service
              .createAccount(name: 'New', currency: 'USD')
              .then(
                (_) => 'saved',
                onError: (Object e) => (e as LedgerException).code,
              ),
      ]);
      expect(writes, unorderedEquals(['saved', 'duplicate_name']));
    },
  );

  test(
    'rename permits changing case and rejects another active name',
    () async {
      await service.renameAccount(1, 'wechat');
      expect((await account(1)).name, 'wechat');
      await expectLater(
        service.renameAccount(1, 'ALIPAY'),
        failure('duplicate_name'),
      );
      expect((await account(1)).name, 'wechat');
    },
  );

  test(
    'opening balance accepts matching money and rejects a different currency',
    () async {
      await service.setOpeningBalance(1, const Money(-123, 'CNY'));
      await expectLater(
        service.setOpeningBalance(1, const Money(5, 'PKR')),
        failure('currency_mismatch'),
      );
      expect((await account(1)).openingMinor, -123);
    },
  );

  test(
    'archive frees the name and unarchive requires an available name',
    () async {
      await service.archiveAccount(1);
      expect((await account(1)).archived, isTrue);
      final other = await service.createAccount(
        name: 'WECHAT',
        currency: 'PKR',
      );
      await expectLater(service.unarchiveAccount(1), failure('duplicate_name'));
      expect((await account(1)).archived, isTrue);
      await service.archiveAccount(other);
      await service.unarchiveAccount(1);
      expect((await account(1)).archived, isFalse);
    },
  );

  test('account mutations reject unknown ids', () async {
    await expectLater(
      service.renameAccount(-1, 'A'),
      failure('unknown_account'),
    );
    await expectLater(
      service.setOpeningBalance(-1, const Money(0, 'USD')),
      failure('unknown_account'),
    );
    await expectLater(service.archiveAccount(-1), failure('unknown_account'));
    await expectLater(service.unarchiveAccount(-1), failure('unknown_account'));
  });
}
