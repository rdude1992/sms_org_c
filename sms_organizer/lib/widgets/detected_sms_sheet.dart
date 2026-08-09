import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/formatters.dart';

/// Bottom sheet shared by transaction and investment tiles: shows the
/// parsed/detected fields side by side with the original SMS text, so a
/// user can sanity-check how an amount/merchant/instrument was extracted —
/// or just confirm what the underlying message actually said. [onEdit], when
/// given, shows a pencil next to the title that jumps straight into editing
/// (closing this sheet first) — so a correction doesn't require backing out
/// and long-pressing the tile instead.
void showDetectedSmsSheet(
  BuildContext context, {
  required String title,
  required DateTime date,
  required String rawBody,
  required List<MapEntry<String, String>> details,
  VoidCallback? onEdit,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          Formatters.full(date),
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit',
                      onPressed: () {
                        Navigator.pop(context);
                        onEdit();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              for (final entry in details)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          entry.key,
                          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Original message',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          )),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    tooltip: 'Copy',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: rawBody));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied message'), duration: Duration(seconds: 1)),
                        );
                      }
                    },
                  ),
                ],
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  rawBody.isEmpty ? '(no message text captured)' : rawBody,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
