import 'dart:convert';

import 'package:budget_app/data/db/app_database.dart';
import 'package:budget_app/features/agent/settings/agent_settings.dart';
import 'package:budget_app/features/agent/tools/account_tools.dart';
import 'package:budget_app/features/agent/tools/category_tools.dart';
import 'package:budget_app/features/agent/tools/entry_tools.dart';
import 'package:budget_app/features/agent/tools/read_tools.dart';
import 'package:budget_app/features/agent/tools/settings_tools.dart';
import 'package:budget_app/features/agent/tools/tool_registry.dart';
import 'package:budget_app/features/agent/tools/tool_spec.dart';
import 'package:budget_app/features/agent/tools/write_tool.dart';
import 'package:budget_app/features/fx/fx_service.dart';
import 'package:budget_app/features/fx/rates_api.dart';
import 'package:budget_app/features/ledger/ledger_service.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _Rates implements RatesApi {
  @override
  Future<Map<String, Decimal>> latestPerUsd() async => {
    'CNY': Decimal.fromInt(7),
    'PKR': Decimal.fromInt(280),
  };
}

class _KeyStore implements AgentKeyStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('Unexpected key write');
  @override
  Future<void> delete(String key) async =>
      throw StateError('Unexpected key deletion');
}

void main() {
  late AppDatabase db;
  late FxService fx;
  late ToolRegistry registry;
  late int source, destination, food, income;
  final now = DateTime(2026, 11, 28, 12, 41);
  Map<String, Object?> expense() => {
    'account_id': source,
    'amount': '100',
    'currency': 'PKR',
    'category_id': food,
    'note': 'Lunch',
  };
  Map<String, Object?> transfer() => {
    'from_account_id': source,
    'to_account_id': destination,
    'amount': '100',
    'currency': 'PKR',
  };
  Future<String> state() async => [
    await db.select(db.accounts).get(),
    await db.select(db.categories).get(),
    await db.select(db.transactions).get(),
    await db.select(db.settings).get(),
  ].toString();
  Future<ToolResult> validate(String tool, Map<String, Object?> args) async {
    final before = await state();
    final result = await registry.byName(tool)!.validate!(args);
    expect(await state(), before, reason: '$tool validation must not write');
    return result;
  }

  Future<Map<String, Object?>> preview(
    String tool,
    Map<String, Object?> args,
  ) async {
    final result = await validate(tool, args);
    expect(result, isA<ToolOk>(), reason: result.toJson().toString());
    return (result as ToolOk).data;
  }

  Future<ToolOk> run(String tool, Map<String, Object?> args) async {
    final normalized = await preview(tool, args);
    final result = await registry.byName(tool)!.execute!(
      Map<String, Object?>.from(jsonDecode(jsonEncode(normalized)) as Map),
    );
    expect(result, isA<ToolOk>(), reason: result.toJson().toString());
    return result as ToolOk;
  }

  Matcher error(String code) =>
      isA<ToolError>().having((e) => e.code, 'code', code);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    source = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Pakistani bank',
            currency: 'PKR',
            sortOrder: 0,
          ),
        );
    destination = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Alipay',
            currency: 'CNY',
            sortOrder: 1,
          ),
        );
    food = await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            name: 'Food',
            kind: 'expense',
            iconKey: 'tag',
          ),
        );
    income = await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            name: 'Salary',
            kind: 'income',
            iconKey: 'tag',
          ),
        );
    fx = FxService(db, _Rates(), clock: () => now);
    registry = ToolRegistry();
    final settings = AgentSettingsRepository(db, _KeyStore());
    registerReadTools(registry, db, LedgerService(db, fx), fx);
    registerEntryTools(
      registry,
      db,
      LedgerService(db, fx, clock: () => now),
      fx,
      settings,
      clock: () => now,
    );
    registerAccountTools(registry, db);
    registerCategoryTools(registry, db);
    registerSettingsTools(registry, db, settings);
  });

  test('add_expense normalizes dates and uses the threshold currency at the latest rate', () async {
    expect((await preview('add_expense', expense()))['policy_amount'], isNull);
    await fx.refreshIfNeeded();
    final p = await preview('add_expense', {...expense(), 'at': '2026-10-01'});
    expect(p['policy_amount'], containsPair('minor', 250));
    expect(p['policy_amount'], containsPair('currency', 'CNY'));
    expect(p['at'], DateTime(2026, 10).toIso8601String());
    await run('add_expense', expense());
    expect(await db.select(db.transactions).get(), hasLength(1));
  });

  test('add_income and edit_entry preserve omitted fields and show old and new values', () async {
    final added = await run('add_income', {
      ...expense(),
      'category_id': income,
    });
    final args = {'entry_id': added.data['transaction_id'], 'amount': '200'};
    final p = await preview('edit_entry', args);
    expect(p['old'], isA<Map>());
    expect(p['new'], isA<Map>());
    await run('edit_entry', args);
    final row = await db.select(db.transactions).getSingle();
    expect(
      (row.amountMinor, row.note, row.categoryId, row.kind),
      (20000, 'Lunch', income, 'income'),
    );
  });

  test(
    'add_transfer supports received, custom, latest and missing rates',
    () async {
      expect(await validate('add_transfer', transfer()), error('rate_needed'));
      for (final (extra, received) in <(Map<String, Object?>, int)>[
        (
          {'received_amount': '9', 'received_currency': 'CNY', 'rate': '0.03'},
          900,
        ),
        ({'rate': '0.03'}, 300),
      ]) {
        expect(
          (await preview('add_transfer', {
            ...transfer(),
            ...extra,
          }))['received'],
          containsPair('minor', received),
        );
        await run('add_transfer', {...transfer(), ...extra});
      }
      await fx.refreshIfNeeded();
      expect(
        (await preview('add_transfer', transfer()))['received'],
        containsPair('minor', 250),
      );
      await run('add_transfer', transfer());
      expect(
        (await db.select(db.transactions).get()).map(
          (row) => row.toAmountMinor,
        ),
        [900, 300, 250],
      );
    },
  );

  test(
    'entry writes reject archived accounts and categories with ledger codes',
    () async {
      await run('archive_category', {'category_id': food});
      expect(
        await validate('add_expense', expense()),
        error('unknown_category'),
      );
      await run('archive_account', {'account_id': source});
      expect(
        await validate('add_expense', expense()),
        error('archived_account'),
      );
    },
  );

  test('account tools create, rename, archive and delete with undo', () async {
    final created = await run('create_account', {
      'name': ' Extra ',
      'currency': 'CNY',
      'opening_amount': '-2',
    });
    final id = created.data['account_id'];
    expect((await db.select(db.accounts).get()).last.openingMinor, -200);
    await run('rename_account', {'account_id': id, 'name': 'Renamed'});
    await run('archive_account', {'account_id': id});
    final args = {'account_id': id};
    expect(
      (await preview('delete_account', args))['confirm_label'],
      'Delete account',
    );
    final removed = await run('delete_account', args);
    expect(await db.select(db.accounts).get(), hasLength(2));
    await removed.deletionReceipt!.restore();
    expect((await db.select(db.accounts).get()).last.name, 'Renamed');
  });

  test(
    'category tools create, rename, archive and move entries before deleting',
    () async {
      final created = await run('create_category', {
        'name': 'Other food',
        'kind': 'expense',
      });
      final destination = created.data['category_id'];
      await run('rename_category', {
        'category_id': destination,
        'name': 'Meals',
      });
      await run('add_expense', expense());
      await run('archive_category', {'category_id': food});
      final args = {'category_id': food, 'move_to_category_id': destination};
      final p = await preview('delete_category', args);
      expect(p['confirm_label'], 'Move 1 entry and delete');
      expect(p['entry_count'], 1);
      final result = await run('delete_category', args);
      expect(
        (await db.select(db.transactions).getSingle()).categoryId,
        destination,
      );
      await result.deletionReceipt!.restore();
      expect((await db.select(db.transactions).getSingle()).categoryId, food);
    },
  );

  test('delete_entry returns an undo receipt outside the model JSON', () async {
    final added = await run('add_expense', expense());
    final deleted = await run('delete_entry', {
      'entry_id': added.data['transaction_id'],
    });
    expect(await db.select(db.transactions).get(), isEmpty);
    expect(jsonDecode(jsonEncode(deleted.toJson())), {
      'transaction_id': added.data['transaction_id'],
    });
    await deleted.deletionReceipt!.restore();
    expect(await db.select(db.transactions).get(), hasLength(1));
  });

  test('settings tools use the regular settings values and retain threshold currency', () async {
    await run('set_large_amount_threshold', {
      'amount': '100.01',
      'currency': 'USD',
    });
    await run('set_main_currency', {'currency': 'PKR'});
    expect({
      for (final row in await db.select(db.settings).get()) row.key: row.value,
    }, containsPair('mainCurrency', 'PKR'));
    expect({
      for (final row in await db.select(db.settings).get()) row.key: row.value,
    }, containsPair('largeAmountThreshold', '10001:USD'));
  });

  test('all money-taking tools reject JSON numbers', () async {
    final entry = await run('add_expense', expense());
    final inputs = {
      'add_expense': {...expense(), 'amount': 28.5},
      'add_income': {...expense(), 'amount': 28.5, 'category_id': income},
      'add_transfer': {
        ...transfer(),
        'received_amount': 28.5,
        'received_currency': 'CNY',
      },
      'edit_entry': {'entry_id': entry.data['transaction_id'], 'amount': 28.5},
      'create_account': {
        'name': 'New',
        'currency': 'CNY',
        'opening_amount': 28.5,
      },
      'set_large_amount_threshold': {'amount': 28.5, 'currency': 'CNY'},
    };
    for (final input in inputs.entries) {
      expect(
        await validate(input.key, input.value),
        error('amount_must_be_string'),
        reason: input.key,
      );
    }
  });

  test(
    'previewChanged compares names, money, dates and delete counts by value',
    () {
      final original = <String, Object?>{
        'account_name': 'Bank',
        'account_id': 1,
        'kind': 'expense',
        'at': '2026-11-28T12:41:00',
        'amount': {'minor': 100, 'currency': 'PKR'},
        'policy_amount': {'minor': 2, 'currency': 'CNY'},
        'entry_count': 1,
      };
      expect(
        previewChanged(original, jsonDecode(jsonEncode(original)) as Map),
        isFalse,
      );
      for (final change in <String, Object?>{
        'account_name': 'New',
        'amount': {'minor': 101, 'currency': 'PKR'},
        'at': '2026-11-29T12:41:00',
        'entry_count': 2,
      }.entries) {
        expect(
          previewChanged(original, {...original, change.key: change.value}),
          isTrue,
          reason: change.key,
        );
      }
    },
  );

  test('previewChanged ignores threshold conversion changes', () {
    final original = {
      'amount': {'minor': 100, 'currency': 'PKR'},
      'policy_amount': {'minor': 2, 'currency': 'CNY'},
    };
    expect(
      previewChanged(original, {
        ...original,
        'policy_amount': {'minor': 3, 'currency': 'CNY'},
      }),
      isFalse,
    );
  });

  test('registry schemas declare IDs as integers and have no union types', () {
    void checkSchema(Object? value) {
      if (value is Map) {
        expect(value['type'], isNot(isA<List>()));
        for (final entry in value.entries) {
          if (entry.key is String && (entry.key as String).endsWith('_id')) {
            expect(entry.value, containsPair('type', 'integer'));
          }
          checkSchema(entry.value);
        }
      } else if (value is List) {
        value.forEach(checkSchema);
      }
    }

    checkSchema(registry.schemas());
  });

  test(
    'execute rejects raw arguments and changes to a validated preview',
    () async {
      final tool = registry.byName('add_expense')!;
      expect(await tool.execute!(expense()), error('invalid_preview'));
      final p = await preview('add_expense', expense());
      await run('rename_account', {'account_id': source, 'name': 'Renamed'});
      expect(await tool.execute!(p), error('changed'));
      expect(await db.select(db.transactions).get(), isEmpty);
    },
  );
  test('invalid operations return actionable codes without writes', () async {
    final cases = <(String, Map<String, Object?>, String)>[
      ('add_expense', {...expense(), 'amount': '0'}, 'non_positive_amount'),
      ('add_expense', {...expense(), 'currency': 'CNY'}, 'currency_mismatch'),
      (
        'add_expense',
        {...expense(), 'category_id': income},
        'wrong_category_kind',
      ),
      ('add_expense', {...expense(), 'at': '2026-11-31'}, 'invalid_date'),
      (
        'add_expense',
        {
          ...expense(),
          'assumed': [12],
        },
        'invalid_list',
      ),
      ('add_income', {'account_id': source}, 'missing_argument'),
      (
        'add_transfer',
        {...transfer(), 'to_account_id': source},
        'same_account',
      ),
      ('add_transfer', {...transfer(), 'rate': '-0.5'}, 'non_positive_amount'),
      ('add_transfer', {...transfer(), 'rate': 'bad'}, 'invalid_rate'),
      ('edit_entry', {'entry_id': 999}, 'unknown_transaction'),
      ('delete_entry', {'entry_id': 999}, 'unknown_transaction'),
      (
        'create_account',
        {'name': 'Alipay', 'currency': 'USD'},
        'duplicate_name',
      ),
      ('create_account', {'name': '  ', 'currency': 'CNY'}, 'empty_name'),
      (
        'rename_account',
        {'account_id': destination, 'name': 'Pakistani bank'},
        'duplicate_name',
      ),
      ('archive_account', {'account_id': 999}, 'unknown_account'),
      ('delete_account', {'account_id': 999}, 'unknown_account'),
      (
        'create_category',
        {'name': 'X', 'kind': 'transfer'},
        'wrong_category_kind',
      ),
      ('rename_category', {'category_id': food, 'name': ' '}, 'empty_name'),
      ('archive_category', {'category_id': 999}, 'unknown_category'),
      ('delete_category', {'category_id': 999}, 'unknown_category'),
      ('set_main_currency', {'currency': 'EUR'}, 'unknown_currency'),
      (
        'set_large_amount_threshold',
        {'currency': 'CNY', 'amount': '-1'},
        'invalid_amount',
      ),
    ];
    for (final (name, args, code) in cases) {
      expect(await validate(name, args), error(code), reason: name);
    }
  });

  test(
    'same-currency transfer uses the source amount without a rate',
    () async {
      final created = await run('create_account', {
        'name': 'Other bank',
        'currency': 'PKR',
      });
      final args = {...transfer(), 'to_account_id': created.data['account_id']};
      final p = await preview('add_transfer', args);
      expect(p['received'], p['amount']);
      await run('add_transfer', args);
      expect(
        (await db.select(db.transactions).getSingle()).toAmountMinor,
        10000,
      );
    },
  );

  test('account and category delete previews use sheet copy and reject changed counts', () async {
    await run('add_transfer', {...transfer(), 'received_amount': '9'});
    final account = await preview('delete_account', {
      'account_id': destination,
    });
    expect(
      account['warning'],
      'This permanently deletes the account and its 1 entry, including 1 transfer with Pakistani bank. Their balances will change.',
    );
    expect(account['confirm_label'], 'Delete account and 1 entry');
    await run('add_expense', expense());
    expect(
      await validate('delete_category', {'category_id': food}),
      error('category_has_entries'),
    );
    expect(
      await validate('delete_category', {
        'category_id': food,
        'move_to_category_id': income,
      }),
      error('wrong_category_kind'),
    );
    final removed = await run('create_category', {
      'name': 'Other food',
      'kind': 'expense',
    });
    final category = await preview('delete_category', {
      'category_id': food,
      'move_to_category_id': removed.data['category_id'],
    });
    expect(
      category['warning'],
      '1 entry uses this category. Choose where it goes, so your spending history stays correct.',
    );
    await run('add_expense', expense());
    expect(
      await registry.byName('delete_category')!.execute!(category),
      error('changed'),
    );
    expect(await db.select(db.transactions).get(), hasLength(3));
  });
}
