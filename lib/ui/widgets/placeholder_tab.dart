import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'add_entry_button.dart';
import 'page_header.dart';

class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab(this.title, {super.key, this.showAdd = false});

  final String title;
  final bool showAdd;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PageHeader(title: Text(title)),
    body: const Center(child: Text('Coming in the next update')),
    floatingActionButton: showAdd
        ? AddEntryButton(onPressed: () => context.push('/entry?kind=expense'))
        : null,
  );
}
