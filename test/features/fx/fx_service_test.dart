import 'package:budget_app/core/money/convert.dart';
import 'package:budget_app/data/db/app_database.dart';
import 'package:budget_app/features/fx/fx_service.dart';
import 'package:budget_app/features/fx/rates_api.dart';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRatesApi implements RatesApi {
  int calls = 0;
  bool offline = false;
  final rates = {
    'CNY': Decimal.parse('7.1'),
    'PKR': Decimal.parse('281.5'),
    'USD': Decimal.one,
  };

  @override
  Future<Map<String, Decimal>> latestPerUsd() async {
    calls++;
    if (offline) throw StateError('offline');
    return Map.of(rates);
  }
}

void main() {
  late AppDatabase db;
  late FakeRatesApi api;
  late FxService fx;
  late DateTime now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    api = FakeRatesApi();
    now = DateTime(2026, 11, 25, 0, 5);
    fx = FxService(db, api, clock: () => now.toUtc());
  });

  test('refresh stores positive rates on the local day', () async {
    api.rates.addAll({'BAD': Decimal.zero, 'NEG': -Decimal.one});
    await fx.refreshIfNeeded();
    final rows = await db.select(db.fxSnapshots).get();
    expect(rows.map((r) => r.currency), unorderedEquals(['PKR', 'CNY', 'USD']));
    expect(rows.map((r) => r.day).toSet(), {'2026-11-25'});
    expect(
      await fx.rate('PKR', 'CNY'),
      crossRate(api.rates['PKR']!, api.rates['CNY']!),
    );
    expect(await fx.isStale(), isFalse);
  });

  test('same-day refreshes share one API call', () async {
    await Future.wait([fx.refreshIfNeeded(), fx.refreshIfNeeded()]);
    await fx.refreshIfNeeded();
    expect(api.calls, 1);
  });

  test('failed refresh falls back to yesterday and reports stale', () async {
    await fx.refreshIfNeeded();
    now = DateTime(2026, 11, 26);
    api.offline = true;
    await fx.refreshIfNeeded();
    expect(await fx.rate('USD', 'CNY'), Decimal.parse('7.1'));
    expect(await fx.snapshotDayFor(now), '2026-11-25');
    expect(await fx.isStale(), isTrue);
    expect(await fx.rateForDay('USD', 'CNY', '2026-11-26'), isNull);
    expect(await fx.rate('USD', 'CNY', on: DateTime(2026, 11, 24)), isNull);
  });

  test('empty offline database supports only identity conversion', () async {
    api.offline = true;
    await fx.refreshIfNeeded();
    expect(await fx.rate('PKR', 'CNY'), isNull);
    expect(await fx.rate('CNY', 'CNY'), Decimal.one);
    expect(await fx.isStale(), isTrue);
  });

  test('missing currency returns null in either direction', () async {
    await fx.refreshIfNeeded();
    expect(await fx.rate('EUR', 'CNY'), isNull);
    expect(await fx.rate('CNY', 'EUR'), isNull);
  });

  test(
    'backfill freezes the earliest eligible snapshot for each entry',
    () async {
      await db.seedIfEmpty();
      final account = (await db.select(db.accounts).get()).first;
      Future<int> entry(DateTime at) => db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              kind: 'income',
              accountId: account.id,
              amountMinor: 1,
              currency: account.currency,
              occurredAt: at,
              createdAt: now,
            ),
          );
      Future<String?> day(int id) async => (await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(id))).getSingle()).fxDay;
      final old = await entry(DateTime(2026, 11, 20));
      final future = await entry(DateTime(2026, 11, 26, 0, 1));
      await fx.refreshIfNeeded();
      expect(await day(old), '2026-11-25');
      expect(await day(future), isNull);
      now = DateTime(2026, 11, 27);
      api.rates['CNY'] = Decimal.fromInt(8);
      await fx.refreshIfNeeded();
      expect(await day(old), '2026-11-25');
      expect(await day(future), '2026-11-27');
      final lateEntry = await entry(DateTime(2026, 11, 24));
      await fx.backfillFxDays();
      expect(await day(lateEntry), '2026-11-25');
      expect(
        await fx.rateForDay('USD', 'CNY', '2026-11-25'),
        Decimal.parse('7.1'),
      );
      expect(await fx.rate('USD', 'CNY'), Decimal.fromInt(8));
    },
  );

  test(
    'API accepts exponent rates and skips malformed or nonpositive values',
    () async {
      final dio = Dio();
      addTearDown(dio.close);
      var result = 'success';
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(
              options.uri.toString(),
              'https://open.er-api.com/v6/latest/USD',
            );
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'result': result,
                  'rates': {
                    'BAD': 'oops',
                    'ZERO': 0,
                    'NEG': -1,
                    'NIL': null,
                    'TINY': 1.2e-7,
                    'USD': 1,
                  },
                },
              ),
            );
          },
        ),
      );
      final source = ErApiRatesApi(dio);
      expect(await source.latestPerUsd(), {
        'TINY': Decimal.parse('0.00000012'),
        'USD': Decimal.one,
      });
      result = 'error';
      await expectLater(source.latestPerUsd(), throwsA(isA<FormatException>()));
    },
  );
}
