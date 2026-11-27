import 'package:drift/drift.dart' show Variable;
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../ui/widgets/amount_text.dart';
import '../../ui/widgets/category_icons.dart';
import '../../ui/widgets/money_input.dart';
import '../../ui/widgets/deletion_feedback.dart';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/money/convert.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../data/db/app_database.dart';
import '../../ui/theme/app_colors.dart';
import '../ledger/ledger_errors.dart';
import '../categories/category_edit_sheet.dart';
import '../ledger/ledger_service.dart';

class EntryFormScreen extends ConsumerStatefulWidget {
  const EntryFormScreen({
    super.key,
    this.initialKind = 'expense',
    this.editTransactionId,
    this.initialDate,
  });
  final String initialKind;
  final int? editTransactionId;
  final DateTime? initialDate;
  @override
  ConsumerState<EntryFormScreen> createState() => _EntryFormState();
}

class _EntryFormState extends ConsumerState<EntryFormScreen> {
  final amount = _AmountController(),
      received = TextEditingController(),
      rate = TextEditingController(),
      note = TextEditingController();
  late final Future<void> loading;
  late String kind;
  List<Account> accounts = [];
  List<Category> categories = [];
  final usage = <int, int>{};
  late Future<Decimal?> quote;
  (String, String, DateTime)? quoteKey;
  final rateFocus = FocusNode();
  bool editingRate = false;
  int? source, destination, category;
  late DateTime date = widget.initialDate ?? DateTime.now();
  bool busy = false, rateEdited = false;
  String? originalNote;
  final errors = <String, String>{};
  AppColors get colors => Theme.of(context).extension<AppColors>()!;
  bool get transfer => kind == 'transfer';
  Account? account(int? id) => accounts.where((a) => a.id == id).firstOrNull;
  bool get cross =>
      transfer &&
      account(source) != null &&
      account(destination) != null &&
      account(source)!.currency != account(destination)!.currency;
  Iterable<Category> get choices => categories.where((c) => c.kind == kind);
  @override
  void initState() {
    super.initState();
    kind = widget.initialKind;
    rateFocus.addListener(() {
      if (!rateFocus.hasFocus && mounted) setState(() => editingRate = false);
    });
    loading = load();
  }

  Future<void> load() async {
    final db = ref.read(databaseProvider);
    accounts = await (db.select(
      db.accounts,
    )..where((a) => a.archived.equals(false))).get();
    accounts.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    categories = await (db.select(
      db.categories,
    )..where((c) => c.archived.equals(false))).get();
    if (!mounted) return;
    final now = DateTime.now();
    final counts = await db
        .customSelect(
          'SELECT category_id, COUNT(*) AS uses FROM transactions WHERE category_id IS NOT NULL AND occurred_at BETWEEN ? AND ? GROUP BY category_id',
          variables: [
            Variable.withDateTime(now.subtract(const Duration(days: 90))),
            Variable.withDateTime(now),
          ],
        )
        .get();
    if (!mounted) return;
    for (final row in counts) {
      usage[row.read<int>('category_id')] = row.read<int>('uses');
    }
    source = accounts.firstOrNull?.id;
    destination = accounts.where((a) => a.id != source).firstOrNull?.id;
    category = choices.firstOrNull?.id;
    final id = widget.editTransactionId;
    if (id == null) return;
    final row = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(id))).getSingle();
    if (!mounted) return;
    kind = row.kind;
    source = account(row.accountId)?.id;
    destination = account(row.toAccountId)?.id;
    category = choices.where((c) => c.id == row.categoryId).firstOrNull?.id;
    amount.text = formatMoney(
      Money(row.amountMinor, row.currency),
      withSymbol: false,
    );
    originalNote = row.note;
    note.text = row.note ?? '';
    date = row.occurredAt;
    if (cross) {
      received.text = formatMoney(
        Money(row.toAmountMinor!, row.toCurrency!),
        withSymbol: false,
      );
      syncConversion();
    }
  }

  @override
  void dispose() {
    for (final c in [amount, received, rate, note]) {
      c.dispose();
    }
    rateFocus.dispose();
    super.dispose();
  }

  void syncConversion() {
    if (!cross) return;
    final target = rateEdited ? received : rate;
    try {
      final from = account(source)!.currency,
          to = account(destination)!.currency;
      final money = Money.parse(amount.text, from);
      if (rateEdited) {
        target.text = formatMoney(
          convert(money, Decimal.parse(rate.text), to),
          withSymbol: false,
        );
      } else {
        final other = Money.parse(received.text, to);
        Decimal major(Money value) =>
            Decimal.fromInt(value.minor)
                .shift(-currencyOf(value.currency).minorDigits);
        target.text = money.minor > 0
            ? crossRate(major(money), major(other)).toString()
            : '';
      }
    } on FormatException {
      target.clear();
    } on RangeError {
      target.clear();
    }
  }

  void resetConversion() {
    received.clear();
    rate.clear();
    rateEdited = false;
  }

  void change(VoidCallback action) => setState(() {
    errors.clear();
    action();
  });
  void finish() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/wealth');
    }
  }

  Future<void> save() async {
    if (busy) return;
    setState(() {
      errors.clear();
      busy = true;
    });
    String field = 'Account';
    try {
      final a = account(source);
      if (a == null) throw const FormatException('Choose an active account.');
      field = 'Amount';
      final value = Money.parse(amount.text, a.currency);
      Money? incoming;
      Decimal? customRate;
      if (cross && received.text.trim().isNotEmpty) {
        field = 'Received';
        incoming = Money.parse(received.text, account(destination)!.currency);
      } else if (cross && rate.text.trim().isNotEmpty) {
        field = 'Rate';
        customRate = Decimal.parse(rate.text.trim());
      }
      final draft = TransactionDraft(
        kind: kind,
        accountId: a.id,
        amount: value,
        categoryId: transfer ? null : category,
        toAccountId: transfer ? destination : null,
        received: incoming,
        customRate: customRate,
        note: note.text.trim().isEmpty ? null : note.text.trim(),
        at: date,
      );
      final ledger = ref.read(ledgerServiceProvider);
      if (!transfer && category == null) {
        throw const LedgerException(
          'unknown_category',
          'Choose an active category.',
        );
      }
      if (transfer && destination == null) {
        field = 'To account';
        throw const FormatException('Choose a destination account.');
      }
      if (widget.editTransactionId != null) {
        await ledger.replaceTransaction(widget.editTransactionId!, draft);
      } else if (transfer) {
        await ledger.addTransfer(
          fromAccountId: a.id,
          toAccountId: destination!,
          amount: value,
          received: incoming,
          customRate: customRate,
          note: draft.note,
          at: date,
        );
      } else {
        final add = kind == 'income' ? ledger.addIncome : ledger.addExpense;
        await add(
          accountId: a.id,
          amount: value,
          categoryId: category!,
          note: draft.note,
          at: date,
        );
      }
      if (mounted) finish();
    } on LedgerException catch (e) {
      field = switch (e.code) {
        'non_positive_amount' || 'currency_mismatch' => 'Amount',
        'unknown_category' || 'wrong_category_kind' => 'Category',
        'missing_to_amount' => 'Received',
        'same_account' => 'To account',
        'archived_account' || 'unknown_account' => 'Account',
        _ => 'Save',
      };
      errors[field] = e.message;
    } on FormatException catch (e) {
      errors[field] = e.message;
    } on RangeError {
      errors[field] = 'Amount exceeds the minor-unit range.';
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> remove() async {
    final confirmed = await confirmEntryDeletion(context);
    if (!confirmed || !mounted || busy) return;
    final undo = deletionUndoFor(context);
    setState(() => busy = true);
    try {
      final receipt = await ref
          .read(deletionServiceProvider)
          .deleteTransaction(widget.editTransactionId!);
      undo(deletedEntryMessage(originalNote), receipt);
      if (mounted) finish();
    } on LedgerException catch (error) {
      if (mounted) setState(() => errors['Save'] = error.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      builder: pickerTheme,
      initialDate: date,
      firstDate: DateTime(1),
      lastDate: DateTime(9999),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(date),
      builder: pickerTheme,
    );
    if (time != null && mounted) {
      setState(
        () => date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Widget pickerTheme(BuildContext context, Widget? child) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: colors.ink,
          onPrimary: colors.ground,
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          border: InputBorder.none,
        ),
        timePickerTheme: const TimePickerThemeData(
          inputDecorationTheme: InputDecorationThemeData(
            border: InputBorder.none,
          ),
        ),
      ),
      child: child!,
    );
  }

  String get when {
    final today = DateUtils.dateOnly(DateTime.now());
    final day = DateUtils.dateOnly(date);
    final label = day == today
        ? 'Today'
        : day == DateTime(today.year, today.month, today.day - 1)
        ? 'Yesterday'
        : DateFormat('EEE d MMM').format(date);
    return '$label, ${DateFormat('HH:mm').format(date)}';
  }

  TextStyle get muted =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(color: colors.muted);
  TextStyle get valueStyle =>
      Theme.of(context).textTheme.titleSmall!.copyWith(color: colors.ink);
  Widget error(String key) => errors[key] == null
      ? const SizedBox.shrink()
      : Text(errors[key]!, style: muted.copyWith(color: colors.warning));
  Widget icon(IconData data, Color color, [double size = 22]) => PhosphorIcon(
    data,
    color: color,
    size: size,
    duotoneSecondaryColor: color,
    duotoneSecondaryOpacity: .25,
  );
  InputDecoration plain(String hint) =>
      InputDecoration.collapsed(hintText: hint, hintStyle: muted);

  Future<int?> choose(
    String title,
    Map<int, String> items,
    int? selected, {
    bool allowNewCategory = false,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: colors.surface,
      barrierColor: colors.onBrass.withValues(alpha: .5),
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: valueStyle),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in items.entries)
                    ListTile(
                      title: Text(e.value, style: valueStyle),
                      trailing: selected == e.key
                          ? icon(PhosphorIconsDuotone.check, colors.ink)
                          : null,
                      onTap: () => Navigator.pop(sheet, e.key),
                    ),
                  if (allowNewCategory)
                    ListTile(
                      leading: icon(PhosphorIconsRegular.plus, colors.muted),
                      title: const Text('New category'),
                      onTap: () => Navigator.pop(sheet, 0),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget row(String label, Widget value, {VoidCallback? tap}) => InkWell(
    onTap: tap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 46),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.rule, width: .7)),
      ),
      child: Row(
        children: [
          Text(label, style: muted),
          const SizedBox(width: 12),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: value),
          ),
          if (tap != null)
            icon(PhosphorIconsRegular.caretRight, colors.muted, 16),
        ],
      ),
    ),
  );
  Widget accountRow(bool to) {
    final label = to || kind == 'income' ? 'To' : 'From';
    final current = account(to ? destination : source);
    return row(
      label,
      Text.rich(
        TextSpan(
          text: current?.name ?? 'Choose account',
          children: [
            TextSpan(text: ' ${current?.currency ?? ''}', style: muted),
          ],
        ),
        style: valueStyle,
      ),
      tap: () async {
        final id = await choose(label, {
          for (final a in accounts) a.id: '${a.name}, ${a.currency}',
        }, current?.id);
        if (id != null && mounted) {
          change(() {
            if (to) {
              destination = id;
            } else {
              source = id;
            }
            resetConversion();
          });
        }
      },
    );
  }

  Widget segments() => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Color.alphaBlend(colors.rule.withValues(alpha: .4), colors.ground),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        for (final label in ['Expense', 'Income', 'Transfer'])
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: kind == label.toLowerCase()
                    ? colors.brass
                    : null,
                foregroundColor: kind == label.toLowerCase()
                    ? colors.onBrass
                    : colors.muted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => change(() {
                if (kind != label.toLowerCase()) {
                  kind = label.toLowerCase();
                  category = choices.firstOrNull?.id;
                  resetConversion();
                }
              }),
              child: Text(label),
            ),
          ),
      ],
    ),
  );
  Widget hero() {
    final style = amountNumberStyle(colors.ink, 60);
    final currency = currencyOf(account(source)?.currency ?? 'CNY');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  currency.symbol,
                  style: style.copyWith(fontSize: 26),
                ),
              ),
              IntrinsicWidth(
                child: MoneyInput(
                  inputKey: const Key('Amount'),
                  currency: currency.code,
                  controller: amount,
                  autofocus: true,
                  cursorHeight: 52,
                  style: style,
                  onChanged: (_) => change(syncConversion),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> createCategory() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final db = ref.read(databaseProvider);
    final id = await CategoryEditSheet.show(context, kind: kind);
    if (id == null || !mounted) return;
    final fresh = await (db.select(
      db.categories,
    )..where((row) => row.archived.equals(false))).get();
    if (!mounted) return;
    change(() {
      categories = fresh;
      category = id;
    });
  }

  Future<void> moreCategories() async {
    final id = await choose(
      'Categories',
      {for (final c in choices) c.id: c.name},
      category,
      allowNewCategory: true,
    );
    if (!mounted || id == null) return;
    if (id == 0) {
      await createCategory();
    } else {
      change(() => category = id);
    }
  }

  Widget grid() {
    final sorted = choices.toList()
      ..sort((a, b) {
        final cmp = (usage[b.id] ?? 0).compareTo(usage[a.id] ?? 0);
        return cmp == 0 ? a.id.compareTo(b.id) : cmp;
      });
    final needsMore = sorted.length > 8;
    final visible = needsMore ? sorted.take(7).toList() : sorted;
    final selected = choices.where((c) => c.id == category).firstOrNull;
    if (selected != null && !visible.contains(selected)) visible[6] = selected;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      mainAxisExtent: 72,
      children: [
        for (final c in visible)
          tile(
            c.name,
            categoryIcon(c.iconKey),
            c.id == category,
            () => change(() => category = c.id),
          ),
        if (needsMore)
          tile('More', PhosphorIconsDuotone.dotsThree, false, moreCategories)
        else if (visible.length < 8)
          tile(
            'New',
            PhosphorIconsRegular.plus,
            false,
            createCategory,
            dashed: true,
          ),
      ],
    );
  }

  Widget tile(
    String label,
    IconData glyph,
    bool active,
    VoidCallback tap, {
    bool dashed = false,
  }) {
    final ink = dashed
        ? colors.muted
        : active
        ? colors.onBrass
        : colors.ink;
    return CustomPaint(
      foregroundPainter: dashed ? _DashedTileBorder(colors.muted) : null,
      child: Material(
        color: dashed
            ? colors.ground
            : active
            ? colors.brass
            : colors.surface,
        shape: RoundedRectangleBorder(
          side: dashed
              ? BorderSide.none
              : BorderSide(
                  color: active ? colors.brass : colors.rule,
                  width: .7,
                ),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon(glyph, ink),
              const SizedBox(height: 3),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall!
                        .copyWith(color: ink),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get displayRate {
    final d = Decimal.tryParse(rate.text);
    return d == null ? rate.text : d.round(scale: 6).toString();
  }

  String? preview(Decimal? fx, String from, String to) {
    if (fx == null) return null;
    try {
      return formatMoney(convert(Money.parse(amount.text, from), fx, to));
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  Widget card() {
    final from = account(source)!.currency, to = account(destination)!;
    final key = (from, to.currency, DateUtils.dateOnly(date));
    if (quoteKey != key) {
      quoteKey = key;
      quote = ref.read(fxServiceProvider).rate(from, to.currency, on: date);
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.rule, width: .7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${to.name} receives', style: muted),
          Row(
            children: [
              Text(
                currencyOf(to.currency).symbol,
                style: amountNumberStyle(colors.ink, 28),
              ),
              Expanded(
                child: MoneyInput(
                  inputKey: const Key('Received'),
                  currency: to.currency,
                  controller: received,
                  style: amountNumberStyle(colors.ink, 28),
                  onChanged: (_) => change(() {
                    rateEdited = false;
                    syncConversion();
                  }),
                ),
              ),
              Text('at ', style: muted),
              if (editingRate)
                SizedBox(
                  width: 100,
                  child: MoneyInput(
                    inputKey: const Key('Rate'),
                    selectOnFocus: true,
                    focusNode: rateFocus,
                    autofocus: true,
                    controller: rate,
                    textAlign: TextAlign.end,
                    style: amountNumberStyle(colors.ink, 18),
                    onChanged: (_) => change(() {
                      rateEdited = true;
                      syncConversion();
                    }),
                  ),
                )
              else
                Tooltip(
                  message: 'Rate',
                  child: InkWell(
                    onTap: () => setState(() => editingRate = true),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            displayRate.isEmpty ? '0.00' : displayRate,
                            style: amountNumberStyle(
                              displayRate.isEmpty ? colors.muted : colors.ink,
                              18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          FutureBuilder<Decimal?>(
            key: ValueKey(key),
            future: quote,
            builder: (_, snapshot) {
              final result = preview(snapshot.data, from, to.currency);
              const hint = 'Tap either number to change it.';
              return Text(
                result == null
                    ? hint
                    : "$hint Today's rate would give $result.",
                style: Theme.of(context).textTheme.bodySmall!
                    .copyWith(color: colors.muted),
              );
            },
          ),
          error('Received'),
          error('Rate'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      centerTitle: true,
      leading: IconButton(
        tooltip: 'Close',
        onPressed: busy ? null : finish,
        icon: icon(PhosphorIconsRegular.x, colors.ink),
      ),
      title: Text(
        widget.editTransactionId == null ? 'New entry' : 'Edit entry',
        style: muted,
      ),
      actions: [
        if (widget.editTransactionId != null)
          TextButton(
            onPressed: busy ? null : remove,
            child: const Text('Delete'),
          ),
      ],
    ),
    body: FutureBuilder<void>(
      future: loading,
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load the entry.'));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: AbsorbPointer(
                    absorbing: busy,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          segments(),
                          hero(),
                          error('Amount'),
                          accountRow(false),
                          error('Account'),
                          if (transfer) ...[
                            accountRow(true),
                            error('To account'),
                          ],
                          if (!transfer) ...[
                            const SizedBox(height: 12),
                            grid(),
                            error('Category'),
                          ],
                          if (cross) ...[const SizedBox(height: 12), card()],
                          const SizedBox(height: 6),
                          row(
                            'When',
                            Text(when, style: valueStyle),
                            tap: pickDate,
                          ),
                          row(
                            'Note',
                            TextField(
                              controller: note,
                              textAlign: TextAlign.end,
                              decoration: plain('Add a note'),
                              style: valueStyle,
                            ),
                          ),
                          const SizedBox(height: 12),
                          error('Save'),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.brass,
                    foregroundColor: colors.onBrass,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  onPressed: busy ? null : save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _AmountController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final decimalPoint = text.indexOf('.');
    if (style == null ||
        decimalPoint < 0 ||
        (withComposing &&
            value.isComposingRangeValid &&
            !value.composing.isCollapsed)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final muted = Theme.of(context).extension<AppColors>()!.muted;
    return TextSpan(
      style: style,
      text: text.substring(0, decimalPoint),
      children: [
        TextSpan(
          text: text.substring(decimalPoint),
          style: style.copyWith(fontSize: style.fontSize! / 2, color: muted),
        ),
      ],
    );
  }
}

class _DashedTileBorder extends CustomPainter {
  const _DashedTileBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(.5),
          const Radius.circular(10),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7;
    final outline = path.computeMetrics().single;
    for (double start = 0; start < outline.length; start += 6) {
      canvas.drawPath(
        outline.extractPath(start, (start + 3).clamp(0, outline.length)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedTileBorder oldDelegate) =>
      color != oldDelegate.color;
}
