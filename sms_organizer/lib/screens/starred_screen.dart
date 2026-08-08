import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/category.dart';
import '../providers/sms_provider.dart';
import '../utils/formatters.dart';
import '../widgets/category_badge.dart';
import '../widgets/ui/empty_state.dart';
import 'thread_screen.dart';

/// Every starred message across every thread, newest first, in one place —
/// the counterpart to per-message starring in the thread view (see
/// MessageBubble / ThreadScreen's message action sheet).
class StarredScreen extends StatelessWidget {
  const StarredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SmsProvider>(
      builder: (context, provider, _) {
        final starred = provider.starredMessages;
        final scheme = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(title: const Text('Starred messages')),
          body: starred.isEmpty
              ? const EmptyState(
                  icon: Icons.star_outline,
                  title: 'No starred messages',
                  message: 'Long-press a message in a chat and tap "Star" to save it here.',
                )
              : ListView.builder(
                  itemCount: starred.length,
                  itemBuilder: (context, index) {
                    final m = starred[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: CircleAvatar(
                        backgroundColor: m.category.color.withOpacity(0.15),
                        child: Icon(m.category.icon, color: m.category.color, size: 18),
                      ),
                      title: Text(
                        provider.displayNameFor(m.address),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          m.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Formatters.relativeOrTime(m.date),
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CategoryBadge(category: m.category, compact: true, showLabel: false),
                              const SizedBox(width: 4),
                              InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: () => provider.toggleStarred(m.id),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(Icons.star, size: 16, color: Colors.amber.shade700),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ThreadScreen(threadId: m.threadId, highlightMessageId: m.id),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
