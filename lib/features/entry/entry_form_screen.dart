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
import '../ledger/ledger_service.dart';

class EntryFormScreen extends ConsumerStatefulWidget {
  const EntryFormScreen({
    super.key,
    this.initialKind = 'expense',
    this.editTransactionId,
  });
  final String initialKind;
  final int? editTransactionId;
  @override
  ConsumerState<EntryFormScreen> createState() => _EntryFormState();
}

class _EntryFormState extends ConsumerState<EntryFormScreen> {
  final amount = TextEditingController(),
      received = TextEditingController(),
      rate = TextEditingController(),
      note = TextEditingController();
  late final Future<void> loading;
  late String kind;
  List<Account> accounts = [];
  List<Category> categories = [];
  int? source, destination, category;
  DateTime date = DateTime.now();
  bool busy = false, rateEdited = false;
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
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: colors.onBrass.withValues(alpha: .5),
      builder: (dialog) => AlertDialog(
        backgroundColor: colors.surface,
        surfaceTintColor: colors.surface,
        shadowColor: colors.onBrass,
        title: const Text('Delete this entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || busy) return;
    setState(() => busy = true);
    try {
      await ref
          .read(ledgerServiceProvider)
          .deleteTransaction(widget.editTransactionId!);
      if (mounted) finish();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: colors.ink,
              onPrimary: colors.ground,
            ),
          ),
          child: child!,
        );
      },
      initialDate: date,
      firstDate: DateTime(1),
      lastDate: DateTime(9999),
    );
    if (picked != null && mounted) {
      setState(
        () => date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          date.hour,
          date.minute,
          date.second,
        ),
      );
    }
  }

  InputDecoration decoration(String label, {String? suffix}) => InputDecoration(
    labelText: label,
    suffixText: suffix,
    errorText: errors[label],
    border: const OutlineInputBorder(),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: colors.ink),
    ),
  );
  Widget number(
    String label,
    TextEditingController controller,
    String? suffix,
  ) => TextField(
    key: Key(label),
    controller: controller,
    decoration: decoration(label, suffix: suffix),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (_) => change(() {
      if (label != 'Amount') rateEdited = label == 'Rate';
      syncConversion();
    }),
  );
  Widget picker(
    String label,
    int? value,
    Map<int, String> items,
    ValueChanged<int?> select,
  ) => DropdownButtonFormField<int>(
    key: ValueKey((label, value)),
    initialValue: value,
    isExpanded: true,
    decoration: decoration(label),
    items: [
      for (final e in items.entries)
        DropdownMenuItem(value: e.key, child: Text(e.value)),
    ],
    onChanged: (v) => change(() => select(v)),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.editTransactionId == null ? 'Add entry' : 'Edit entry',
      ),
    ),
    body: FutureBuilder<void>(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load the entry.'));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final names = {
          for (final a in accounts) a.id: '${a.name}, ${a.currency}',
        };
        final fields = <Widget>[
          SegmentedButton<String>(
            segments: [
              for (final k in ['Expense', 'Income', 'Transfer'])
                ButtonSegment(value: k.toLowerCase(), label: Text(k)),
            ],
            selected: {kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => change(() {
              kind = s.single;
              category = choices.firstOrNull?.id;
              resetConversion();
            }),
          ),
          number('Amount', amount, account(source)?.currency),
          picker('Account', source, names, (id) {
            source = id;
            resetConversion();
          }),
          if (transfer)
            picker('To account', destination, names, (id) {
              destination = id;
              resetConversion();
            })
          else
            picker('Category', category, {
              for (final c in choices) c.id: c.name,
            }, (id) => category = id),
          if (cross) ...[
            number('Received', received, account(destination)!.currency),
            number('Rate', rate, null),
          ],
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colors.muted),
            ),
            onPressed: pickDate,
            child: Text(
              'Date   ${MaterialLocalizations.of(context).formatMediumDate(date)}',
            ),
          ),
          TextField(controller: note, decoration: decoration('Note')),
          if (errors['Save'] != null) Text(errors['Save']!),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.brass,
              foregroundColor: colors.onBrass,
            ),
            onPressed: busy ? null : save,
            child: const Text('Save'),
          ),
          if (widget.editTransactionId != null)
            TextButton(
              onPressed: busy ? null : remove,
              child: const Text('Delete'),
            ),
        ];
        return SafeArea(
          child: AbsorbPointer(
            absorbing: busy,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final field in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: field,
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
