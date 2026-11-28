import 'package:budget_app/core/money/money.dart';
import 'package:budget_app/data/db/app_database.dart';
import 'package:budget_app/features/agent/tools/read_tools.dart';
import 'package:budget_app/features/agent/tools/tool_args.dart';
import 'package:budget_app/features/agent/tools/tool_registry.dart';
import 'package:budget_app/features/agent/tools/tool_spec.dart';
import 'package:budget_app/features/fx/fx_service.dart';
import 'package:budget_app/features/fx/rates_api.dart';
import 'package:budget_app/features/ledger/ledger_service.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _Rates implements RatesApi {
  @override
  Future<Map<String, Decimal>> latestPerUsd() async => {
    'CNY': Decimal.fromInt(7),
    'PKR': Decimal.fromInt(280),
  };
}

void main() {
  group('Tool arguments and registry', () {
    Matcher code(String code) =>
        isA<ToolError>().having((e) => e.code, 'code', code);

    test('money requires a positive decimal string and a known currency', () {
      Object parse(Object value, [String currency = 'CNY']) =>
          money({'amount': value, 'currency': currency}, 'amount', 'currency');
      expect(parse('28.50'), const Money(2850, 'CNY'));
      expect(parse(28.5), code('amount_must_be_string'));
      expect(parse('28,5.1'), code('invalid_amount'));
      expect(parse('-5'), code('invalid_amount'));
      expect(parse('28', 'ZZZ'), code('unknown_currency'));
      expect(
        money({}, 'amount', 'currency'),
        isA<ToolError>().having(
          (e) => e.message,
          'message',
          contains('amount'),
        ),
      );
    });

    test('ids accept digit strings and reject other types', () {
      expect(intId({'id': '12'}, 'id'), 12);
      expect(intId({'id': 12.0}, 'id'), code('invalid_id'));
      expect(intId({}, 'id'), code('missing_argument'));
    });

    test(
      'dates use strict local ISO syntax and string lists check each item',
      () {
        expect(
          optionalDate({'at': '2026-11-28T12:41'}, 'at'),
          DateTime(2026, 11, 28, 12, 41),
        );
        expect(
          optionalDate({'at': '2026-11-28'}, 'at'),
          DateTime(2026, 11, 28),
        );
        expect(optionalDate({}, 'at'), isNull);
        expect(optionalDate({'at': '2026-02-30'}, 'at'), code('invalid_date'));
        expect(
          optionalDate({'at': '2026-11-28T12:41Z'}, 'at'),
          code('invalid_date'),
        );
        expect(
          stringList({
            'items': ['note'],
          }, 'items'),
          ['note'],
        );
        expect(
          stringList({
            'items': ['note', 1],
          }, 'items'),
          code('invalid_list'),
        );
      },
    );

    test(
      'registry exports OpenAI function schemas and rejects duplicate names',
      () {
        final registry = ToolRegistry();
        final tool = ToolSpec(
          name: 'sample',
          description: 'Sample',
          parameters: {'type': 'object'},
          kind: ToolKind.read,
          run: (_) async => const ToolOk({}),
        );
        registry.register(tool);
        expect(registry.byName('sample'), same(tool));
        expect(registry.schemas(), [
          {
            'type': 'function',
            'function': {
              'name': 'sample',
              'description': 'Sample',
              'parameters': {'type': 'object'},
            },
          },
        ]);
        expect(() => registry.register(tool), throwsArgumentError);
      },
    );

    test('read tools cannot use validate and execute', () {
      Future<ToolResult> callback(Map<String, Object?> _) async =>
          const ToolOk({});
      expect(
        () => ToolSpec(
          name: 'wrong',
          description: 'Wrong',
          parameters: {},
          kind: ToolKind.read,
          validate: callback,
          execute: callback,
        ),
        throwsAssertionError,
      );
    });
  });

  group('Seeded read tools', () {
    late AppDatabase db;
    late FxService fx;
    late LedgerService ledger;
    late ToolRegistry registry;
    late int wechat, bank, food;
    final now = DateTime(2026, 11, 28, 12, 41);

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.seedIfEmpty();
      fx = FxService(db, _Rates(), clock: () => now);
      ledger = LedgerService(db, fx, clock: () => now);
      registry = ToolRegistry();
      registerReadTools(registry, db, ledger, fx, clock: () => now);
      final accounts = await db.select(db.accounts).get();
      wechat = accounts.singleWhere((a) => a.name == 'WeChat').id;
      bank = accounts.singleWhere((a) => a.name == 'Pakistani bank').id;
      food = (await db.select(db.categories).get())
          .singleWhere((c) => c.name == 'Food')
          .id;
    });

    Future<ToolResult> run(
      String name, [
      Map<String, Object?> args = const {},
    ]) => registry.byName(name)!.run!(args);
    Future<Map<String, Object?>> read(
      String name, [
      Map<String, Object?> args = const {},
    ]) async => (await run(name, args) as ToolOk).data;
    Map<String, Object?> json(Money m) => {
      'minor': m.minor,
      'currency': m.currency,
      'formatted': formatMoney(m),
    };

    test('lists expose account and category archive flags', () async {
      await (db.update(db.accounts)..where((a) => a.id.equals(bank))).write(
        const AccountsCompanion(archived: Value(true)),
      );
      await (db.update(db.categories)..where((c) => c.id.equals(food))).write(
        const CategoriesCompanion(archived: Value(true)),
      );
      final accounts = (await read('list_accounts'))['accounts'] as List;
      expect(accounts, hasLength(9));
      expect(accounts.singleWhere((a) => (a as Map)['id'] == bank), {
        'id': bank,
        'name': 'Pakistani bank',
        'currency': 'PKR',
        'archived': true,
      });
      final categories = (await read('list_categories'))['categories'] as List;
      expect(categories, hasLength(18));
      expect(categories.singleWhere((c) => (c as Map)['id'] == food), {
        'id': food,
        'name': 'Food',
        'kind': 'expense',
        'archived': true,
      });
    });

    test('balance totals match Wealth and include archived balances', () async {
      await (db.update(db.accounts)..where((a) => a.id.equals(bank))).write(
        const AccountsCompanion(
          openingMinor: Value(10000),
          archived: Value(true),
        ),
      );
      await fx.refreshIfNeeded();
      final worth = await ledger.watchWorth().first;
      final result = await read('get_balances');
      expect(result['total'], json(worth.total!));
      expect(worth.total, const Money(250, 'CNY'));
      expect(
        result['by_currency'],
        worth.byCurrency.map((code, amount) => MapEntry(code, json(amount))),
      );
      expect(
        (result['accounts'] as List).any((a) => (a as Map)['id'] == bank),
        isFalse,
      );
    });

    test('spending totals match Spending and support string account and category filters', () async {
      await fx.refreshIfNeeded();
      await ledger.addExpense(
        accountId: wechat,
        amount: const Money(2850, 'CNY'),
        categoryId: food,
      );
      await ledger.addExpense(
        accountId: bank,
        amount: const Money(10000, 'PKR'),
        categoryId: food,
      );
      final spend = (await ledger.watchSpending(now).first).single;
      final result = await read('get_spending', {'period': 'this_month'});
      expect(result['total'], json(spend.total));
      expect(result['categories'], [
        {'name': 'Food', 'amount': json(spend.total), 'count': 2},
      ]);
      expect(result['unconverted_count'], 0);
      expect(
        (await read('get_spending', {
          'period': '2026-11',
          'account_id': '$wechat',
          'category_id': '$food',
        }))['total'],
        json(const Money(2850, 'CNY')),
      );
      expect(
        (await read('get_spending', {'period': 'last_month'}))['total'],
        json(const Money(0, 'CNY')),
      );
    });

    test(
      'entries match either transfer account and spending excludes transfers',
      () async {
        final id = await ledger.addTransfer(
          fromAccountId: bank,
          toAccountId: wechat,
          amount: const Money(500000, 'PKR'),
          received: const Money(12200, 'CNY'),
        );
        for (final account in [bank, wechat]) {
          final result = await read('get_entries', {'account_id': account});
          final entry = (result['entries'] as List).single as Map;
          expect(entry['id'], id);
          expect(entry['account'], 'Pakistani bank');
          expect(entry['to_account'], 'WeChat');
          expect(entry['amount'], json(const Money(500000, 'PKR')));
        }
        expect(
          (await read('get_spending', {'period': 'this_month'}))['categories'],
          isEmpty,
        );
      },
    );

    test(
      'entry date bounds include both local days and notes match without case',
      () async {
        for (final at in [
          DateTime(2026, 11, 27, 23, 59),
          DateTime(2026, 11, 28),
          DateTime(2026, 11, 29, 23, 59, 59),
          DateTime(2026, 11, 30),
        ]) {
          await ledger.addExpense(
            accountId: wechat,
            amount: const Money(100, 'CNY'),
            categoryId: food,
            at: at,
            note: 'Cafe',
          );
        }
        final result = await read('get_entries', {
          'from': '2026-11-28T12:41',
          'to': '2026-11-29',
          'note_contains': 'CAFE',
        });
        expect((result['entries'] as List).map((e) => (e as Map)['at']), [
          '2026-11-29T23:59:59.000',
          '2026-11-28T00:00:00.000',
        ]);
        expect(
          (await read('get_entries', {'limit': 1}))['entries'],
          hasLength(1),
        );
      },
    );

    test('unknown ids and invalid dates return tool errors', () async {
      expect(
        await run('get_spending', {'period': 'this_month', 'category_id': 999}),
        isA<ToolError>().having((e) => e.code, 'code', 'not_found'),
      );
      expect(
        await run('get_entries', {'account_id': '999'}),
        isA<ToolError>().having((e) => e.code, 'code', 'not_found'),
      );
      expect(
        await run('get_entries', {'from': 'yesterday'}),
        isA<ToolError>().having((e) => e.code, 'code', 'invalid_date'),
      );
    });

    test(
      'exchange rate includes its snapshot day and reports missing rates',
      () async {
        expect(await read('get_exchange_rate', {'from': 'PKR', 'to': 'CNY'}), {
          'rates_missing': true,
        });
        await fx.refreshIfNeeded();
        expect(await read('get_exchange_rate', {'from': 'PKR', 'to': 'CNY'}), {
          'rate': '0.025',
          'day': '2026-11-28',
        });
      },
    );

    test('affordability excludes archived accounts and subtracts the converted purchase', () async {
      await fx.refreshIfNeeded();
      await (db.update(db.accounts)..where((a) => a.id.equals(wechat))).write(
        const AccountsCompanion(openingMinor: Value(5000)),
      );
      await (db.update(db.accounts)..where((a) => a.id.equals(bank))).write(
        const AccountsCompanion(
          openingMinor: Value(10000),
          archived: Value(true),
        ),
      );
      final result = await read('get_affordability', {
        'amount': '100',
        'currency': 'PKR',
      });
      expect(result['available'], json(const Money(5000, 'CNY')));
      expect(result['available_after'], json(const Money(4750, 'CNY')));
      expect(result['note'], contains('upcoming expenses'));
      expect(
        await run('get_affordability', {'amount': 28.5, 'currency': 'CNY'}),
        isA<ToolError>().having((e) => e.code, 'code', 'amount_must_be_string'),
      );
    });

    test(
      'missing rates report affected currencies, accounts and spending entries',
      () async {
        await ledger.addExpense(
          accountId: bank,
          amount: const Money(100, 'PKR'),
          categoryId: food,
        );
        final worth = await read('get_balances');
        expect(worth['total'], isNull);
        expect(worth['rates_missing'], true);
        expect(worth['missing_currencies'], ['PKR']);
        final result = await read('get_affordability', {
          'amount': '1',
          'currency': 'CNY',
        });
        expect(result['available_after'], json(const Money(-100, 'CNY')));
        expect(
          (result['available_after'] as Map)['formatted'],
          '\u2212\u00a51.00',
        );
        expect(result['partial'], true);
        expect(result['excluded_accounts'], [containsPair('id', bank)]);
        expect(
          (await read('get_spending', {
            'period': 'this_month',
          }))['unconverted_count'],
          1,
        );
      },
    );

    test('entry limit defaults to 10 and caps at 20', () async {
      for (var i = 0; i < 21; i++) {
        await ledger.addExpense(
          accountId: wechat,
          amount: const Money(100, 'CNY'),
          categoryId: food,
        );
      }
      final rows = (await read('get_entries'))['entries'] as List;
      expect(rows, hasLength(10));
      expect((rows.first as Map)['id'], 21);
      expect(
        (await read('get_entries', {'limit': 100}))['entries'],
        hasLength(20),
      );
    });

    test('affordability flags offsetting foreign accounts and a missing purchase rate', () async {
      await (db.update(db.accounts)..where((a) => a.id.equals(bank))).write(
        const AccountsCompanion(openingMinor: Value(100)),
      );
      final wallet = (await (db.select(
        db.accounts,
      )..where((a) => a.name.equals('JazzCash'))).getSingle()).id;
      await ledger.addExpense(
        accountId: wallet,
        amount: const Money(100, 'PKR'),
        categoryId: food,
      );
      expect((await read('get_balances'))['rates_missing'], false);
      final result = await read('get_affordability', {
        'amount': '1',
        'currency': 'PKR',
      });
      expect(result['partial'], true);
      expect(result['available_after'], isNull);
      expect(result['purchase_rate_missing'], true);
      expect(
        result['excluded_accounts'],
        unorderedEquals([containsPair('id', bank), containsPair('id', wallet)]),
      );
    });
  });
}
