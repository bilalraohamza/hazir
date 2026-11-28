import '../../../data/db/app_database.dart';
import '../../settings/main_currency_setting.dart';
import '../settings/agent_settings.dart';
import 'tool_args.dart';
import 'tool_registry.dart';
import 'tool_spec.dart';
import 'write_tool.dart';

void registerSettingsTools(
  ToolRegistry registry,
  AppDatabase db,
  AgentSettingsRepository settings,
) {
  registerWriteTool(
    registry,
    db,
    'set_main_currency',
    'Set the main currency used on Wealth and Spending.',
    {'currency': 'Main currency code (CNY, PKR or USD).'},
    (args) async {
      final currency = args.currency();
      return WriteAction(
        'Set main currency to $currency',
        {'currency': currency, 'setting_id': mainCurrencySettingKey},
        () async {
          await saveMainCurrency(db, currency);
          return const ToolOk({'setting_id': mainCurrencySettingKey});
        },
      );
    },
    required: ['currency'],
  );
  registerWriteTool(
    registry,
    db,
    'set_large_amount_threshold',
    'Set the amount that requires confirmation for new entries.',
    {
      'amount': 'Threshold as a decimal string.',
      'currency': 'Currency of the threshold (CNY, PKR or USD).',
    },
    (args) async {
      final currency = args.currency();
      final amount = args.amount('amount', currency);
      if (amount.minor < 0) {
        throw const ToolError(
          'invalid_amount',
          'Threshold cannot be negative.',
        );
      }
      return WriteAction(
        'Set the large-amount threshold',
        {'amount': moneyJson(amount), 'setting_id': 'largeAmountThreshold'},
        () async {
          await settings.saveLargeAmountThreshold(amount);
          return const ToolOk({'setting_id': 'largeAmountThreshold'});
        },
      );
    },
    required: ['amount', 'currency'],
  );
}
