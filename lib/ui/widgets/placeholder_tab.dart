import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'add_entry_button.dart';
import 'page_header.dart';

class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab(this.title, {super.key, this.showAdd = false});

  final String title;
  final bool showAdd;

  @override
  Widget build(BuildContext context) {
    final header = PageHeader(title: Text(title));
    const content = Center(child: Text('Coming in the next update'));
    if (showAdd) {
      return AddEntryScaffold(
        appBar: header,
        onAdd: () => context.push('/entry?kind=expense'),
        fillRemaining: content,
      );
    }
    return Scaffold(appBar: header, body: content);
  }
}
