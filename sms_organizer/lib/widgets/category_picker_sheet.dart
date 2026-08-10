import 'package:flutter/material.dart';
import '../models/category.dart';
import '../models/sms_message.dart';
import '../providers/sms_provider.dart';

/// Bottom sheet letting the user manually correct [message]'s category when
/// CategorizationService got it wrong — see SmsProvider.setMessageCategory.
Future<void> showCategoryPickerSheet(
  BuildContext context,
  SmsProvider provider,
  SmsMessage message,
) {
  return showModalBottomSheet(
    context: context,
    // Scroll-controlled + a Flexible/ListView list (rather than a plain
    // Column) so this stays reachable in full if SmsCategory ever grows, or
    // on a shorter/landscape screen — a fixed-height, non-scrolling sheet
    // would otherwise silently clip whatever doesn't fit (see the near-miss
    // this caused for the 14-option SpendCategory pickers).
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set category',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: scheme.onSurface),
                  ),
                  const SizedBox(height: 6),
                  // Which message this actually applies to isn't always
                  // obvious from context alone (e.g. reached via a
                  // transaction's "Not a transaction?" action) — a short
                  // preview means never having to guess or back out to check.
                  Text(
                    message.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final category in SmsCategory.values)
                    ListTile(
                      leading: Icon(category.icon, color: category.color),
                      title: Text(category.label),
                      trailing:
                          message.category == category ? Icon(Icons.check, color: scheme.primary) : null,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        provider.setMessageCategory(message, category);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Bulk variant of [showCategoryPickerSheet] for a multi-select "Set
/// category" action. Doesn't show a current-value checkmark since
/// [selectedCount] items can span several different categories at once.
/// [onSelect] fires with the tapped category and does the actual
/// persisting — the Inbox's multi-select routes it to
/// SmsProvider.setSelectedCategory (which operates on the shared
/// [SmsProvider.selectedIds]); TransactionListScreen's "Not a transaction?"
/// bulk action routes it to SmsProvider.setCategoryForTransactions instead,
/// since that screen deliberately keeps its own local selection rather than
/// sharing the Inbox's.
Future<void> showBulkCategoryPickerSheet(
  BuildContext context, {
  required int selectedCount,
  required String itemLabel,
  required ValueChanged<SmsCategory> onSelect,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Set category for $selectedCount $itemLabel${selectedCount == 1 ? '' : 's'}',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: scheme.onSurface),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final category in SmsCategory.values)
                    ListTile(
                      leading: Icon(category.icon, color: category.color),
                      title: Text(category.label),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        onSelect(category);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
