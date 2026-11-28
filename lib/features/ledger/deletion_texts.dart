import 'deletion_service.dart';

typedef DeletionText = ({String warning, String confirmLabel});

String entryCountLabel(int count) =>
    '$count ${count == 1 ? 'entry' : 'entries'}';

const entryDeletionText = (
  warning: 'Delete this entry?',
  confirmLabel: 'Delete',
);

const accountDeletionFootnote =
    "This can't be undone after a few seconds. To keep the history, archive it instead.";

DeletionText accountDeletionText(AccountDeletionDetails details) {
  final transfers = details.transferCount;
  final names = details.counterpartNames;
  final counterparts = names.length < 2
      ? names.join()
      : '${names.take(names.length - 1).join(', ')} and ${names.last}';
  final countLabel = entryCountLabel(details.entryCount);
  final description = StringBuffer('This permanently deletes the account');
  if (details.entryCount > 0) description.write(' and its $countLabel');
  if (transfers > 0) {
    description.write(
      ', including $transfers ${transfers == 1 ? 'transfer' : 'transfers'}',
    );
    if (counterparts.isNotEmpty) description.write(' with $counterparts');
  }
  description.write('.');
  if (transfers > 0) description.write(' Their balances will change.');
  return (
    warning: description.toString(),
    confirmLabel: details.entryCount == 0
        ? 'Delete account'
        : 'Delete account and $countLabel',
  );
}

DeletionText categoryDeletionText(String name, int count) {
  if (count == 0) {
    return (warning: 'Delete $name?', confirmLabel: 'Delete category');
  }
  final subject = count == 1
      ? 'uses this category. Choose where it goes'
      : 'use this category. Choose where they go';
  final countLabel = entryCountLabel(count);
  return (
    warning: '$countLabel $subject, so your spending history stays correct.',
    confirmLabel: 'Move $countLabel and delete',
  );
}
