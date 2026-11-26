import 'package:budget_app/data/db/app_database.dart';
import 'package:budget_app/features/categories/category_service.dart';
import 'package:budget_app/features/ledger/ledger_errors.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CategoryService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedIfEmpty();
    service = CategoryService(db);
  });

  Future<Category> read(int id) =>
      (db.select(db.categories)..where((row) => row.id.equals(id))).getSingle();

  Matcher failure(String code) => throwsA(
    isA<LedgerException>().having((error) => error.code, 'code', code),
  );

  test(
    'create trims names and persists the kind and chosen or default icon',
    () async {
      final expense = await service.createCategory(
        name: ' Cafeteria ',
        kind: 'expense',
        iconKey: 'coffee',
      );
      final income = await service.createCategory(
        name: 'Cafeteria',
        kind: 'income',
      );
      final first = await read(expense);
      final second = await read(income);
      expect(
        [first.name, first.kind, first.iconKey, first.archived],
        ['Cafeteria', 'expense', 'coffee', false],
      );
      expect(
        [second.name, second.kind, second.iconKey],
        ['Cafeteria', 'income', 'tag'],
      );
    },
  );

  test(
    'create rejects duplicate names within a kind and validates its inputs',
    () async {
      await expectLater(
        service.createCategory(name: ' fOOD ', kind: 'expense'),
        failure('duplicate_name'),
      );
      await expectLater(
        service.createCategory(name: 'X', kind: 'transfer'),
        failure('wrong_category_kind'),
      );
      await expectLater(
        service.createCategory(name: ' ', kind: 'income'),
        failure('empty_name'),
      );
      final results = await Future.wait([
        for (var i = 0; i < 2; i++)
          service
              .createCategory(name: 'New', kind: 'income')
              .then(
                (_) => 'saved',
                onError: (Object error) => (error as LedgerException).code,
              ),
      ]);
      expect(results, unorderedEquals(['saved', 'duplicate_name']));
    },
  );

  test(
    'rename changes expense Other while income Other stays unchanged',
    () async {
      await service.renameCategory(12, ' Misc ');
      expect((await read(12)).name, 'Misc');
      expect((await read(18)).name, 'Other');
      await service.renameCategory(12, 'mISC');
      expect((await read(12)).name, 'mISC');
      await expectLater(
        service.renameCategory(12, ' Food '),
        failure('duplicate_name'),
      );
      expect((await read(12)).name, 'mISC');
    },
  );

  test(
    'archive and unarchive preserve category identity and reserve the name',
    () async {
      await service.archiveCategory(1);
      expect((await read(1)).archived, isTrue);
      await expectLater(
        service.createCategory(name: 'food', kind: 'expense'),
        failure('duplicate_name'),
      );
      await service.unarchiveCategory(1);
      final restored = await read(1);
      expect(
        [restored.id, restored.name, restored.iconKey, restored.archived],
        [1, 'Food', 'forkKnife', false],
      );
    },
  );

  test('rename, archive, and unarchive reject unknown categories', () async {
    await expectLater(
      service.renameCategory(-1, 'X'),
      failure('unknown_category'),
    );
    await expectLater(service.archiveCategory(-1), failure('unknown_category'));
    await expectLater(
      service.unarchiveCategory(-1),
      failure('unknown_category'),
    );
  });
}
