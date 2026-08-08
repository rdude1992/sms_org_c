import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../providers/sms_provider.dart';
import '../utils/formatters.dart';
import '../widgets/ui/empty_state.dart';
import 'thread_screen.dart';

/// Every saved draft reply across every thread — ThreadScreen loads the
/// matching draft's text into its reply box when opened for a thread that
/// has one (see _ThreadScreenState._loadDraftIfNeeded).
class DraftsScreen extends StatelessWidget {
  const DraftsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SmsProvider>(
      builder: (context, provider, _) {
        final drafts = provider.drafts;
        final scheme = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(title: const Text('Drafts')),
          body: drafts.isEmpty
              ? const EmptyState(
                  icon: Icons.drafts_outlined,
                  title: 'No drafts',
                  message: 'Unsent replies you leave typed in a chat are saved here.',
                )
              : ListView.builder(
                  itemCount: drafts.length,
                  itemBuilder: (context, index) {
                    final d = drafts[index];
                    return Slidable(
                      key: ValueKey(d.id),
                      endActionPane: ActionPane(
                        motion: const DrawerMotion(),
                        extentRatio: 0.28,
                        children: [
                          SlidableAction(
                            onPressed: (_) => provider.deleteMessage(d.id),
                            backgroundColor: scheme.error,
                            foregroundColor: Colors.white,
                            icon: Icons.delete_outline,
                            label: 'Delete',
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: CircleAvatar(
                          backgroundColor: scheme.secondaryContainer,
                          child: Icon(Icons.edit_outlined, color: scheme.onSecondaryContainer, size: 18),
                        ),
                        title: Text(
                          provider.displayNameFor(d.address),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            d.body.isEmpty ? '(empty draft)' : d.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                          ),
                        ),
                        trailing: Text(
                          Formatters.relativeOrTime(d.date),
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ThreadScreen(threadId: d.threadId)),
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
