import 'package:budget_app/core/money/money.dart';
import 'package:budget_app/data/db/app_database.dart';
import 'package:budget_app/features/agent/settings/agent_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_agent_key_store.dart';

void main() {
  late AppDatabase db;
  late FakeAgentKeyStore keys;
  late AgentSettingsRepository repository;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedIfEmpty();
    keys = FakeAgentKeyStore();
    repository = AgentSettingsRepository(db, keys);
  });

  test(
    'defaults and saved settings reload with an independent threshold currency',
    () async {
      final defaults = await repository.watch().first;
      expect(defaults.provider, AgentProvider.zhipu);
      expect(defaults.model, 'glm-4.7-flash');
      expect(defaults.baseUrl, 'https://open.bigmodel.cn/api/paas/v4');
      expect(defaults.hasApiKey, isFalse);
      expect(defaults.largeAmountThreshold, const Money(50000, 'CNY'));
      await repository.save(defaults);
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(key: 'mainCurrency', value: 'PKR'),
          );
      final rows = await db.select(db.settings).get();
      expect(
        rows.singleWhere((row) => row.key == 'largeAmountThreshold').value,
        '50000:CNY',
      );
      expect(
        (await AgentSettingsRepository(
          db,
          keys,
        ).watch().first).largeAmountThreshold,
        const Money(50000, 'CNY'),
      );

      await repository.save(
        defaults.copyWith(
          model: 'another-model',
          largeAmountThreshold: const Money(12345, 'USD'),
        ),
      );
      final reloaded = await AgentSettingsRepository(db, keys).watch().first;
      expect(reloaded.model, 'another-model');
      expect(reloaded.largeAmountThreshold, const Money(12345, 'USD'));
    },
  );

  test('an invalid stored threshold falls back to 500 CNY', () async {
    for (final value in ['12.3:CNY', '-1:CNY', '50000:EUR', 'invalid']) {
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(key: 'largeAmountThreshold', value: value),
          );
      expect(
        (await repository.watch().first).largeAmountThreshold,
        const Money(50000, 'CNY'),
      );
    }
  });

  test(
    'keys are isolated by provider and no key or suffix reaches Settings',
    () async {
      const zhipu = 'example-zhipu-9284';
      const openRouter = 'example-openrouter-7519';
      final present = repository.watch().firstWhere((value) => value.hasApiKey);
      await repository.setApiKey(AgentProvider.zhipu, zhipu);
      expect((await present).hasApiKey, isTrue);
      await repository.setApiKey(AgentProvider.openRouter, openRouter);
      expect(keys.keys, {
        'apiKey.zhipu': zhipu,
        'apiKey.openRouter': openRouter,
      });
      expect(await repository.apiKey(AgentProvider.zhipu), zhipu);
      expect(await repository.apiKey(AgentProvider.openRouter), openRouter);
      final values = (await db.select(db.settings).get())
          .map((row) => '${row.key}:${row.value}')
          .join(' ');
      for (final secret in [zhipu, openRouter, '9284', '7519', 'apiKey']) {
        expect(values, isNot(contains(secret)));
      }
      final removed = repository.watch().firstWhere(
        (value) => !value.hasApiKey,
      );
      await repository.clearApiKey(AgentProvider.zhipu);
      expect((await removed).hasApiKey, isFalse);
      expect(await repository.apiKey(AgentProvider.openRouter), openRouter);
    },
  );

  test(
    'switching providers restores Custom and reapplies the other presets',
    () async {
      final defaults = await repository.watch().first;
      await repository.save(defaults.copyWith(provider: AgentProvider.custom));
      final custom = await repository.watch().first;
      await repository.save(
        custom.copyWith(
          baseUrl: 'https://example.invalid/v1',
          model: 'custom-model',
        ),
      );
      await repository.setApiKey(AgentProvider.custom, 'example-custom-9021');
      final savedCustom = await repository.watch().first;
      await repository.save(
        savedCustom.copyWith(provider: AgentProvider.openRouter),
      );
      final router = await repository.watch().first;
      expect(router.baseUrl, 'https://openrouter.ai/api/v1');
      expect(router.model, 'z-ai/glm-5.3-flash:free');
      await repository.save(router.copyWith(model: 'temporary-model'));
      await repository.save(router.copyWith(provider: AgentProvider.custom));
      final restored = await repository.watch().first;
      expect(restored.baseUrl, 'https://example.invalid/v1');
      expect(restored.model, 'custom-model');
      expect(restored.hasApiKey, isTrue);
      await repository.save(
        restored.copyWith(provider: AgentProvider.openRouter),
      );
      expect((await repository.watch().first).model, 'z-ai/glm-5.3-flash:free');
    },
  );

  test(
    'the first Custom URL keeps its key and a subsequent host change clears it',
    () async {
      await repository.selectProvider(AgentProvider.custom);
      await repository.setApiKey(AgentProvider.custom, 'example-first-key');
      final custom = await repository.watch().first;
      await repository.save(
        custom.copyWith(
          baseUrl: 'https://example.invalid/v1',
          model: 'custom-model',
        ),
      );
      expect(
        await repository.apiKey(AgentProvider.custom),
        'example-first-key',
      );
      final configured = await repository.watch().first;
      await repository.save(
        configured.copyWith(baseUrl: 'https://other.invalid/v1'),
      );
      expect(await repository.apiKey(AgentProvider.custom), isNull);
    },
  );

  test('save rejects a blank model for every provider', () async {
    for (final provider in AgentProvider.values) {
      await repository.selectProvider(provider);
      final current = await repository.watch().first;
      await expectLater(
        repository.save(current.copyWith(model: '  ')),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Enter a model name.',
          ),
        ),
      );
    }
  });

  test('non-HTTPS Custom URLs are rejected and only a new host clears the Custom key', () async {
    final defaults = await repository.watch().first;
    await repository.save(defaults.copyWith(provider: AgentProvider.custom));
    final custom = await repository.watch().first;
    await repository.save(
      custom.copyWith(
        baseUrl: 'https://example.invalid/v1',
        model: 'custom-model',
      ),
    );
    await repository.setApiKey(AgentProvider.custom, 'example-custom-4528');
    await repository.setApiKey(AgentProvider.zhipu, 'example-zhipu-7328');
    final configured = await repository.watch().first;
    await expectLater(
      repository.save(configured.copyWith(baseUrl: 'http://other.invalid/v1')),
      throwsFormatException,
    );
    expect((await repository.watch().first).baseUrl, configured.baseUrl);
    await repository.save(
      configured.copyWith(baseUrl: 'https://example.invalid/v2'),
    );
    expect(
      await repository.apiKey(AgentProvider.custom),
      'example-custom-4528',
    );
    await repository.save(
      configured.copyWith(baseUrl: 'https://other.invalid/v1'),
    );
    expect((await repository.watch().first).hasApiKey, isFalse);
    expect(await repository.apiKey(AgentProvider.zhipu), 'example-zhipu-7328');
  });
}
