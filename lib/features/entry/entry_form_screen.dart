import 'package:material_ui/material_ui.dart';

import '../../ui/widgets/placeholder_tab.dart';

class EntryFormScreen extends StatelessWidget {
  const EntryFormScreen({super.key, this.initialKind = 'expense'});
  final String initialKind;

  @override
  Widget build(BuildContext context) => const PlaceholderTab('Add entry');
}
