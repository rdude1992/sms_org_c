import 'package:flutter/material.dart';

class MultiSelectAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int selectedCount;
  final VoidCallback onClear;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;
  final VoidCallback onDelete;

  /// Bulk "Set category" action — only offered where selection ids are
  /// individual messages (the Inbox's flat Messages list), not the Chats
  /// list, where a selected id stands in for a whole conversation and
  /// bulk-recategorising just its latest message would be misleading.
  final VoidCallback? onSetCategory;

  const MultiSelectAppBar({
    super.key,
    required this.selectedCount,
    required this.onClear,
    required this.onMarkRead,
    required this.onMarkUnread,
    required this.onDelete,
    this.onSetCategory,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), onPressed: onClear),
      title: Text('$selectedCount selected'),
      actions: [
        if (onSetCategory != null)
          IconButton(
            icon: const Icon(Icons.label_outline),
            tooltip: 'Set category',
            onPressed: onSetCategory,
          ),
        IconButton(
          icon: const Icon(Icons.mark_email_read_outlined),
          tooltip: 'Mark read',
          onPressed: onMarkRead,
        ),
        IconButton(
          icon: const Icon(Icons.mark_email_unread_outlined),
          tooltip: 'Mark unread',
          onPressed: onMarkUnread,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
          onPressed: () => _confirmDelete(context),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $selectedCount message${selectedCount == 1 ? '' : 's'}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}
