import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../theme/app_colors.dart';

class MoneyInput extends StatefulWidget {
  const MoneyInput({
    super.key,
    required this.inputKey,
    required this.controller,
    this.currency,
    this.focusNode,
    this.allowNegative = false,
    this.autofocus = false,
    this.selectOnFocus = false,
    this.enabled = true,
    this.style,
    this.textAlign = TextAlign.start,
    this.cursorHeight,
    this.onChanged,
  });

  final Key inputKey;
  final TextEditingController controller;
  // A rate has no currency-specific precision, so it keeps every entered digit.
  final String? currency;
  final FocusNode? focusNode;
  final bool allowNegative, autofocus, selectOnFocus, enabled;
  final TextStyle? style;
  final TextAlign textAlign;
  final double? cursorHeight;
  final ValueChanged<String>? onChanged;

  @override
  State<MoneyInput> createState() => _MoneyInputState();
}

class _MoneyInputState extends State<MoneyInput> {
  late final focus = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    focus.addListener(focusChanged);
  }

  @override
  void dispose() {
    focus.removeListener(focusChanged);
    if (widget.focusNode == null) focus.dispose();
    super.dispose();
  }

  void selectAll() {
    final controller = widget.controller;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  void focusChanged() {
    final controller = widget.controller;
    if (focus.hasFocus) {
      final plain = controller.text.replaceAll(',', '');
      if (plain != controller.text) {
        controller.value = TextEditingValue(
          text: plain,
          selection: TextSelection(baseOffset: 0, extentOffset: plain.length),
        );
      }
      if (widget.selectOnFocus) selectAll();
      return;
    }
    final currency = widget.currency;
    if (currency == null || controller.text.isEmpty) return;
    try {
      final value = Money.parse(controller.text, currency);
      controller.text = formatMoney(value, withSymbol: false);
    } on FormatException {
      // Keep incomplete input for the form to validate on save.
    }
  }

  TextEditingValue accept(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final sign = widget.allowNegative ? '[-−]?' : '';
    final places = widget.currency == null
        ? ''
        : '{0,${currencyOf(widget.currency!).minorDigits}}';
    final fraction = places.isEmpty ? r'\d*' : '\\d$places';
    final pattern = RegExp('^$sign\\d*(?:\\.$fraction)?\$');
    if (!pattern.hasMatch(text)) return oldValue;
    final decimal = text.indexOf('.');
    if (decimal != 0 &&
        !(decimal == 1 && (text.startsWith('-') || text.startsWith('−')))) {
      return newValue;
    }
    return TextEditingValue(
      text: text.replaceRange(decimal, decimal, '0'),
      selection: TextSelection.collapsed(
        offset: newValue.selection.extentOffset + 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return TextField(
      key: widget.inputKey,
      controller: widget.controller,
      focusNode: focus,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      style: widget.style,
      textAlign: widget.textAlign,
      cursorHeight: widget.cursorHeight,
      decoration: InputDecoration.collapsed(
        hintText: '0.00',
        hintStyle:
            widget.style?.copyWith(color: colors.muted) ??
            TextStyle(color: colors.muted),
      ),
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: widget.allowNegative,
      ),
      inputFormatters: [TextInputFormatter.withFunction(accept)],
      onTap: selectAll,
      onChanged: widget.onChanged,
    );
  }
}
