import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/money/money.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/money_input.dart';
import '../../ui/widgets/amount_text.dart';
import '../../ui/widgets/page_header.dart';
import '../agent/llm/llm_client.dart';
import '../agent/llm/llm_errors.dart';
import '../agent/llm/openai_compatible_client.dart';
import '../agent/settings/agent_settings.dart';

final _keyLabelProvider = FutureProvider.autoDispose
    .family<String, AgentSettings>((ref, settings) async {
      final key = await ref
          .watch(agentSettingsRepositoryProvider)
          .apiKey(settings.provider);
      if (key == null || key.isEmpty) return 'Add key';
      return key.length < 8 ? '••••' : '••••${key.substring(key.length - 4)}';
    });

class AssistantSettingsScreen extends ConsumerStatefulWidget {
  const AssistantSettingsScreen({super.key});

  @override
  ConsumerState<AssistantSettingsScreen> createState() =>
      _AssistantSettingsScreenState();
}

class _AssistantSettingsScreenState
    extends ConsumerState<AssistantSettingsScreen> {
  String? _error;
  bool _testing = false;
  String? _testFeedback;
  AgentSettings? _testedSettings;

  Future<void> _testConnection(AgentSettings settings) async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _testFeedback = null;
    });
    String feedback;
    try {
      final client = ref.read(llmClientProvider);
      await client.complete(
        messages: const [UserMessage('Reply with OK.')],
        tools: const [],
      );
      feedback = 'Connected to ${settings.model}';
    } on LlmException catch (error) {
      feedback = llmErrorText(error.kind);
    } on Object {
      feedback = llmErrorText(LlmErrorKind.badResponse);
    }
    if (!mounted) return;
    setState(() {
      _testFeedback = feedback;
      _testedSettings = settings;
      _testing = false;
    });
  }

  Future<void> _pickProvider(AgentSettings settings) async {
    final repository = ref.read(agentSettingsRepositoryProvider);
    final provider = await _showSheet<AgentProvider>(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Provider', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final option in AgentProvider.values)
            Builder(
              builder: (sheet) => _AssistantRow(
                label: option.label,
                selected: option == settings.provider,
                onTap: () => Navigator.pop(sheet, option),
              ),
            ),
        ],
      ),
    );
    if (provider == null || provider == settings.provider || !mounted) return;
    setState(() => _error = null);
    try {
      await repository.selectProvider(provider);
    } on Exception {
      if (mounted) setState(() => _error = 'Could not change the provider.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(agentSettingsProvider);
    final settings = value.value;
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return Scaffold(
      appBar: PageHeader(
        title: const Text('Assistant settings'),
        onBack: () => Navigator.pop(context),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
          children: [
            if (settings != null)
              IgnorePointer(
                ignoring: _testing,
                child: Column(children: _rows(settings)),
              ),
            if (_error != null || value.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error ?? 'Could not load assistant settings.',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: colors.warning,
                  ),
                ),
              ),
            if (settings != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.brass,
                  foregroundColor: colors.onBrass,
                ),
                onPressed: _testing ? null : () => _testConnection(settings),
                child: Text(_testing ? 'Testing…' : 'Test connection'),
              ),
              if (_testFeedback case final message?
                  when identical(settings, _testedSettings))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: colors.muted,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _rows(AgentSettings settings) {
    final repository = ref.read(agentSettingsRepositoryProvider);
    final keyLabel = settings.hasApiKey
        ? ref.watch(_keyLabelProvider(settings)).value ?? '••••'
        : 'Add key';
    final threshold = settings.largeAmountThreshold;
    return [
      _AssistantRow(
        label: 'Provider',
        value: settings.provider.label,
        onTap: () => _pickProvider(settings),
      ),
      _AssistantRow(
        label: 'API key',
        value: keyLabel,
        onTap: () => _showSheet<void>(
          context,
          _AssistantEditor(
            title: 'API key',
            inputKey: const Key('assistant-api-key'),
            secret: true,
            save: (text, _) => repository.setApiKey(settings.provider, text),
            remove: settings.hasApiKey
                ? () => repository.clearApiKey(settings.provider)
                : null,
          ),
        ),
      ),
      _AssistantRow(
        label: 'Model',
        value: settings.model.isEmpty ? 'Set model' : settings.model,
        onTap: () => _showSheet<void>(
          context,
          _AssistantEditor(
            title: 'Model',
            inputKey: const Key('assistant-model'),
            initial: settings.model,
            save: (text, _) => repository.save(settings.copyWith(model: text)),
          ),
        ),
      ),
      _AssistantRow(
        label: 'Base URL',
        value: settings.baseUrl.isEmpty ? 'Set URL' : settings.baseUrl,
        onTap: settings.provider != AgentProvider.custom
            ? null
            : () => _showSheet<void>(
                context,
                _AssistantEditor(
                  title: 'Base URL',
                  inputKey: const Key('assistant-base-url'),
                  initial: settings.baseUrl,
                  keyboardType: TextInputType.url,
                  save: (text, _) => repository.saveCustomBaseUrl(text),
                ),
              ),
      ),
      _AssistantRow(
        label: 'Large amounts need confirmation from',
        value:
            '${formatMoney(threshold, withSymbol: false)} ${threshold.currency}',
        isMoney: true,
        onTap: () => _showSheet<void>(
          context,
          _AssistantEditor(
            title: 'Large amounts need confirmation from',
            inputKey: const Key('assistant-threshold'),
            initial: formatMoney(threshold, withSymbol: false),
            currency: threshold.currency,
            save: (text, code) =>
                repository.saveLargeAmountThreshold(Money.parse(text, code!)),
          ),
        ),
      ),
    ];
  }
}

Future<T?> _showSheet<T>(BuildContext context, Widget child) {
  final colors = Theme.of(context).extension<AppColors>()!;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: colors.surface,
    barrierColor: colors.onBrass.withValues(alpha: .5),
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: child,
        ),
      ),
    ),
  );
}

class _AssistantRow extends StatelessWidget {
  const _AssistantRow({
    required this.label,
    this.value,
    this.selected = false,
    this.isMoney = false,
    this.onTap,
  });

  final String label;
  final String? value;
  final bool selected, isMoney;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.rule, width: .7)),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            if (value != null)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    value!,
                    textAlign: TextAlign.end,
                    style: isMoney
                        ? amountNumberStyle(colors.muted, 14)
                        : theme.textTheme.bodyMedium!.copyWith(
                            color: colors.muted,
                          ),
                  ),
                ),
              ),
            if (selected || (value != null && onTap != null))
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: PhosphorIcon(
                  selected
                      ? PhosphorIconsRegular.check
                      : PhosphorIconsRegular.caretRight,
                  color: colors.muted,
                  size: 14,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AssistantEditor extends StatefulWidget {
  const _AssistantEditor({
    required this.title,
    required this.inputKey,
    required this.save,
    this.initial = '',
    this.secret = false,
    this.currency,
    this.keyboardType,
    this.remove,
  });

  final String title, initial;
  final Key inputKey;
  final bool secret;
  final String? currency;
  final TextInputType? keyboardType;
  final Future<void> Function(String, String?) save;
  final Future<void> Function()? remove;

  @override
  State<_AssistantEditor> createState() => _AssistantEditorState();
}

class _AssistantEditorState extends State<_AssistantEditor> {
  late final _controller = TextEditingController(text: widget.initial);
  late String? _currency = widget.currency;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Could not update assistant settings.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text != null && mounted && !_busy) _controller.text = text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final currency = _currency;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: currency != null
                    ? MoneyInput(
                        inputKey: widget.inputKey,
                        controller: _controller,
                        currency: currency,
                        enabled: !_busy,
                        selectOnFocus: true,
                        style: amountNumberStyle(colors.ink, 16),
                      )
                    : TextField(
                        key: widget.inputKey,
                        controller: _controller,
                        enabled: !_busy,
                        obscureText: widget.secret,
                        autocorrect: false,
                        enableSuggestions: false,
                        enableIMEPersonalizedLearning: false,
                        keyboardType: widget.secret
                            ? TextInputType.visiblePassword
                            : widget.keyboardType,
                        decoration: InputDecoration.collapsed(
                          hintText: widget.title,
                          hintStyle: theme.textTheme.bodyMedium!.copyWith(
                            color: colors.muted,
                          ),
                        ),
                      ),
              ),
              if (widget.secret)
                IconButton(
                  tooltip: 'Paste',
                  onPressed: _busy ? null : _paste,
                  icon: PhosphorIcon(
                    PhosphorIconsRegular.clipboard,
                    color: colors.muted,
                  ),
                ),
              if (currency != null)
                DropdownButton<String>(
                  value: currency,
                  dropdownColor: colors.surface,
                  underline: const SizedBox.shrink(),
                  icon: PhosphorIcon(
                    PhosphorIconsRegular.caretRight,
                    color: colors.muted,
                    size: 14,
                  ),
                  items: [
                    for (final code in ['CNY', 'PKR', 'USD'])
                      DropdownMenuItem(value: code, child: Text(code)),
                  ],
                  onChanged: _busy
                      ? null
                      : (code) => setState(() => _currency = code),
                ),
            ],
          ),
        ),
        Divider(height: .7, thickness: .7, color: colors.rule),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              style: theme.textTheme.bodySmall!.copyWith(color: colors.warning),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.brass,
            foregroundColor: colors.onBrass,
          ),
          onPressed: _busy
              ? null
              : () => _submit(() {
                  final text = _controller.text.trim();
                  if (text.isEmpty) {
                    final message = switch (widget.title) {
                      'Base URL' => 'Enter an HTTPS URL.',
                      'API key' => 'Enter an API key.',
                      'Model' => 'Enter a model name.',
                      _ => 'Enter an amount.',
                    };
                    throw FormatException(message);
                  }
                  return widget.save(text, currency);
                }),
          child: const Text('Save'),
        ),
        if (widget.remove != null)
          TextButton(
            onPressed: _busy ? null : () => _submit(widget.remove!),
            child: const Text('Remove'),
          ),
      ],
    );
  }
}
