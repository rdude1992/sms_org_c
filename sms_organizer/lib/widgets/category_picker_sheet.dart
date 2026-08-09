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
                  'Set category',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: scheme.onSurface),
                ),
              ),
            ),
            const SizedBox(height: 4),
            for (final category in SmsCategory.values)
              ListTile(
                leading: Icon(category.icon, color: category.color),
                title: Text(category.label),
                trailing: message.category == category ? Icon(Icons.check, color: scheme.primary) : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  provider.setMessageCategory(message, category);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Bulk variant of [showCategoryPickerSheet] for the Inbox's multi-select
/// "Set category" action — see SmsProvider.setSelectedCategory. Doesn't
/// show a current-value checkmark since [selectedCount] messages can span
/// several different categories at once.
Future<void> showBulkCategoryPickerSheet(
  BuildContext context,
  SmsProvider provider,
  int selectedCount,
) {
  return showModalBottomSheet(
    context: context,
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
                  'Set category for $selectedCount message${selectedCount == 1 ? '' : 's'}',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: scheme.onSurface),
                ),
              ),
            ),
            const SizedBox(height: 4),
            for (final category in SmsCategory.values)
              ListTile(
                leading: Icon(category.icon, color: category.color),
                title: Text(category.label),
                onTap: () {
                  Navigator.pop(sheetContext);
                  provider.setSelectedCategory(category);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
