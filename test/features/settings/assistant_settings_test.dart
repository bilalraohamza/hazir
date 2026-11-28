import 'package:budget_app/features/settings/assistant_settings_screen.dart';
import 'package:budget_app/ui/theme/app_colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../agent/settings/fake_agent_key_store.dart';
import '../../app/shell_fixture.dart';

void main() {
  late ShellFixture fixture;
  late FakeAgentKeyStore keys;

  setUp(() {
    fixture = ShellFixture();
    keys = FakeAgentKeyStore();
    addTearDown(fixture.db.close);
  });

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> openAssistant(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(fixture.build(agentKeyStore: keys));
    await tester.pumpAndSettle();
    await tap(tester, find.byTooltip('Settings'));
    expect(find.text('Assistant'), findsOneWidget);
    expect(find.text('Not set up'), findsOneWidget);
    await tap(tester, find.text('AI assistant'));
    expect(find.text('Test connection'), findsNothing);
  }

  testWidgets('API key is masked after Save and Remove clears it', (
    tester,
  ) async {
    await openAssistant(tester);
    for (final (key, masked) in [
      ('example-key-4321', '••••4321'),
      ('short', '••••'),
    ]) {
      await tap(tester, find.text('Add key'));
      final field = find.byKey(const Key('assistant-api-key'));
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      expect(find.byTooltip('Paste'), findsOneWidget);
      await tester.enterText(field, key);
      await tap(tester, find.text('Save'));
      expect(find.text(masked), findsOneWidget);
      expect(find.text(key), findsNothing);
      await tap(tester, find.text(masked));
      await tap(tester, find.text('Remove'));
      expect(find.text('Add key'), findsOneWidget);
      expect(keys.keys, isEmpty);
    }
  });

  testWidgets(
    'provider picker applies presets and rejects a non-HTTPS Custom URL inline',
    (tester) async {
      await openAssistant(tester);
      await tap(tester, find.text('Provider'));
      await tap(tester, find.text('OpenRouter'));
      expect(find.text('z-ai/glm-5.3-flash:free'), findsOneWidget);
      expect(find.text('https://openrouter.ai/api/v1'), findsOneWidget);
      await tap(tester, find.text('Provider'));
      await tap(tester, find.text('Custom'));
      await tap(tester, find.text('Base URL'));
      await tester.enterText(
        find.byKey(const Key('assistant-base-url')),
        'http://example.invalid/v1',
      );
      await tap(tester, find.text('Save'));
      expect(find.textContaining('HTTPS'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('assistant-base-url')),
        'https://example.invalid/v1',
      );
      await tap(tester, find.text('Save'));
      expect(find.text('https://example.invalid/v1'), findsOneWidget);
    },
  );

  testWidgets('threshold editor saves the amount in the selected currency', (
    tester,
  ) async {
    await openAssistant(tester);
    expect(find.text('500.00 CNY'), findsOneWidget);
    await tap(tester, find.text('Large amounts need confirmation from'));
    await tap(tester, find.text('CNY'));
    await tap(tester, find.text('PKR').last);
    await tester.enterText(
      find.byKey(const Key('assistant-threshold')),
      '750.50',
    );
    await tap(tester, find.text('Save'));
    expect(find.text('750.50 PKR'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('Assistant settings builds in ${brightness.name} mode', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await openAssistant(tester);
      final theme = Theme.of(
        tester.element(find.byType(AssistantSettingsScreen)),
      );
      expect(
        theme.extension<AppColors>(),
        brightness == Brightness.dark ? AppColors.dark : AppColors.light,
      );
      expect(find.text('Large amounts need confirmation from'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
