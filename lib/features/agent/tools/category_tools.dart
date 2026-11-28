import '../../../data/db/app_database.dart';
import '../../categories/category_service.dart';
import '../../ledger/deletion_service.dart';
import '../../ledger/deletion_texts.dart';
import 'tool_registry.dart';
import 'tool_spec.dart';
import 'write_tool.dart';

void registerCategoryTools(ToolRegistry registry, AppDatabase db) {
  final service = CategoryService(db);
  final deletions = DeletionService(db);
  const categoryId = {'category_id': 'Category ID.'};

  registerWriteTool(
    registry,
    db,
    'create_category',
    'Ask Rao first before proposing a new category.',
    {
      'name': 'Name of the new category.',
      'kind': 'Category kind: expense or income.',
      'icon_key': 'Optional category icon key. Defaults to tag.',
    },
    (args) async {
      final kind = args.text('kind');
      final name = await service.validateNewCategory(
        name: args.text('name'),
        kind: kind,
      );
      final icon = args.optionalText('icon_key') ?? 'tag';
      return WriteAction(
        'Create $name',
        {'category_name': name, 'kind': kind, 'icon_key': icon},
        () async {
          final id = await service.createCategory(
            name: name,
            kind: kind,
            iconKey: icon,
          );
          return ToolOk({'category_id': id});
        },
      );
    },
    required: ['name', 'kind'],
  );

  registerWriteTool(
    registry,
    db,
    'rename_category',
    'Rename an existing category.',
    {...categoryId, 'name': 'New category name.'},
    (args) async {
      final id = args.id('category_id');
      final category = await service.validateCategory(id);
      final name = await service.validateRename(id, args.text('name'));
      return WriteAction(
        'Rename ${category.name} to $name',
        {'category_id': id, 'category_name': category.name, 'new_name': name},
        () async {
          await service.renameCategory(id, name);
          return ToolOk({'category_id': id});
        },
      );
    },
    required: ['category_id', 'name'],
  );

  registerWriteTool(
    registry,
    db,
    'archive_category',
    'Archive a category and retain its entries.',
    categoryId,
    (args) async {
      final id = args.id('category_id');
      final category = await service.validateCategory(id);
      return WriteAction(
        'Archive ${category.name}',
        {
          'category_id': id,
          'category_name': category.name,
          'archived': category.archived,
        },
        () async {
          await service.archiveCategory(id);
          return ToolOk({'category_id': id});
        },
      );
    },
    required: ['category_id'],
  );

  registerWriteTool(
    registry,
    db,
    'delete_category',
    'Delete a category after confirmation and move its entries when needed.',
    {
      ...categoryId,
      'move_to_category_id': 'Required when the category has entries. Choose an active category of the same kind.',
    },
    (args) async {
      final id = args.id('category_id');
      final details = await deletions.categoryDeletionDetails(id);
      final destinationId = args.has('move_to_category_id')
          ? args.id('move_to_category_id')
          : null;
      final target = details.entryCount > 0 || destinationId != null
          ? await deletions.validateCategoryMove(
              details.category,
              destinationId,
            )
          : null;
      final copy = categoryDeletionText(
        details.category.name,
        details.entryCount,
      );
      final data = <String, Object?>{
        'category_id': id,
        'entry_count': details.entryCount,
      };
      return WriteAction(
        'Delete ${details.category.name}',
        {
          ...data,
          'category_name': details.category.name,
          'move_to_category_id': target?.id,
          'move_to_category_name': target?.name,
          'warning': copy.warning,
          'confirm_label': copy.confirmLabel,
        },
        () async => ToolOk(
          data,
          deletionReceipt: await deletions.deleteCategory(
            id,
            moveToCategoryId: target?.id,
          ),
        ),
      );
    },
    required: ['category_id'],
    kind: ToolKind.destructive,
  );
}
