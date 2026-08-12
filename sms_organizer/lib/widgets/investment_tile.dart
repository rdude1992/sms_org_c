import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../screens/thread_screen.dart';
import '../utils/formatters.dart';
import 'category_picker_sheet.dart';
import 'detected_sms_sheet.dart';
import 'investment_edit_sheet.dart';

/// Shared by the detail sheet's delete icon and the inline expanded panel's
/// options bar — deletes the underlying SMS (with confirmation), which also
/// drops this investment out of every list once [SmsProvider.deleteMessage]
/// refreshes. Mirrors _confirmDeleteTransactionSms in transaction_tile.dart.
Future<void> _confirmDeleteInvestmentSms(BuildContext context, SmsProvider provider, int smsId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete message?'),
      content: const Text(
        "Deletes the underlying SMS — this investment won't be tracked anymore either. "
        'This cannot be undone.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
        ),
      ],
    ),
  );
  if (confirmed == true) await provider.deleteMessage(smsId);
}

class InvestmentTile extends StatelessWidget {
  final InvestmentEvent investment;

  /// Multi-select support for InvestmentListScreen's bulk actions — mirrors
  /// TransactionTile's selected/selectionMode pattern. [onTap]/[onLongPress]
  /// override the tile's own detail-sheet/actions-menu behaviour while set,
  /// so a tap toggles selection instead of opening anything.
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// When set, adds a "Select" entry to the long-press actions sheet (only
  /// reachable while [onLongPress] is null, i.e. not already selecting) so
  /// multi-select is still one tap away without long-press itself having to
  /// mean "start selecting."
  final VoidCallback? onSelectStart;

  /// Shows [_ExpandedInvestmentPanel] inline below the row — every quick
  /// action (edit, thread, delete, ...) on top and the raw SMS body below —
  /// without needing a tap to open the detail sheet or a long-press into
  /// multi-select just to fix one row. True either because the list-level
  /// "expand all" toggle is on (see InvestmentListScreen) or because
  /// [onToggleExpand] was tapped for this row specifically.
  final bool expanded;

  /// Tapping the leading avatar toggles just this row's [expanded] state —
  /// kept separate from the row's own [onTap] (which opens the full detail
  /// sheet) so both stay reachable without one shadowing the other. Null in
  /// contexts that don't track per-row expansion, which also hides the
  /// avatar's arrow badge.
  final VoidCallback? onToggleExpand;

  /// Dense "bank statement" row — date, name, colored amount, thin divider,
  /// nothing else — used by InvestmentListScreen's compact view toggle in
  /// place of the full ListTile below. No avatar, no subtitle line, no
  /// inline expand panel; [expanded]/[onToggleExpand] are ignored while
  /// this is true.
  final bool compact;

  const InvestmentTile({
    super.key,
    required this.investment,
    this.selected = false,
    this.selectionMode = false,
    this.onTap,
    this.onLongPress,
    this.onSelectStart,
    this.expanded = false,
    this.onToggleExpand,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isRedemption = investment.kind.isRedemption;
    final color = isRedemption ? const Color(0xFFF59E0B) : Theme.of(context).colorScheme.primary;
    final sign = isRedemption ? '+' : '-';
    final icon = isRedemption ? Icons.call_received : Icons.trending_up;
    final scheme = Theme.of(context).colorScheme;

    if (compact) {
      final title = investment.fundOrScheme ?? investment.amc ?? investment.kind.label;
      return Material(
        color: selected ? scheme.primary.withOpacity(0.08) : Colors.transparent,
        child: InkWell(
          onTap: onTap ?? () => _showDetails(context),
          onLongPress: onLongPress ?? () => _showActions(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    Formatters.dayMonth(investment.date),
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: scheme.onSurface),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  Formatters.currency(investment.amount),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          minVerticalPadding: 10,
          selected: selected,
          selectedTileColor: scheme.primary.withOpacity(0.06),
          onTap: onTap ?? () => _showDetails(context),
          onLongPress: onLongPress ?? () => _showActions(context),
          leading: selectionMode
              ? Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? scheme.primary : scheme.outline,
                )
              : GestureDetector(
                  onTap: onToggleExpand,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: color.withOpacity(0.12),
                        child: Icon(icon, color: color, size: 18),
                      ),
                      if (onToggleExpand != null)
                        Positioned(
                          bottom: -3,
                          right: -3,
                          child: Container(
                            padding: const EdgeInsets.all(1),
                            decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                            child: Icon(
                              expanded ? Icons.expand_less : Icons.expand_more,
                              size: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
          title: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    investment.fundOrScheme ?? investment.amc ?? investment.kind.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (investment.isOverridden) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Manually edited',
                    child:
                        Icon(Icons.edit, size: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          subtitle: Text(
            [
              investment.kind.label,
              Formatters.relativeOrTime(investment.date),
              if (investment.folioOrAccount != null) 'Folio ${investment.folioOrAccount}',
            ].join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Text(
            '$sign${Formatters.currency(investment.amount)}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? _ExpandedInvestmentPanel(investment: investment)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  void _showDetails(BuildContext context) {
    final provider = context.read<SmsProvider>();
    final message = provider.messageById(investment.smsId);
    final i = investment;
    final details = <MapEntry<String, String>>[
      MapEntry('Amount', Formatters.currency(i.amount)),
      MapEntry('Type', i.kind.label),
      if (i.fundOrScheme != null) MapEntry('Fund / Scheme', i.fundOrScheme!),
      if (i.amc != null) MapEntry('AMC', i.amc!),
      if (i.folioOrAccount != null) MapEntry('Folio / Account', i.folioOrAccount!),
      if (i.units != null) MapEntry('Units', i.units!.toStringAsFixed(3)),
      if (i.nav != null) MapEntry('NAV', Formatters.currencyPrecise(i.nav!)),
    ];

    showDetectedSmsSheet(
      context,
      title: i.fundOrScheme ?? i.amc ?? i.kind.label,
      date: i.date,
      rawBody: i.rawBody,
      details: details,
      onEdit: () => showInvestmentEditSheet(context, provider, i),
      onViewThread: message == null
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ThreadScreen(threadId: message.threadId, highlightMessageId: message.id),
                ),
              ),
      onDelete: () => _confirmDeleteInvestmentSms(context, provider, i.smsId),
    );
  }

  /// Long-press menu: "Edit investment" for when it's correctly an
  /// investment but its type/fund/AMC/folio is wrong, or "Not an
  /// investment?" for when it shouldn't be here at all — the latter hands
  /// off to the same category picker the message list uses, so both
  /// corrections end up going through the same override machinery (see
  /// TransactionTile._showActions for the transaction-side equivalent).
  void _showActions(BuildContext context) {
    final provider = context.read<SmsProvider>();
    final message = provider.messageById(investment.smsId);
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit investment'),
                subtitle: const Text('Fix the type, fund/scheme, AMC, or folio'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showInvestmentEditSheet(context, provider, investment);
                },
              ),
              ListTile(
                leading: const Icon(Icons.label_outline),
                title: const Text('Not an investment?'),
                subtitle: Text(
                  message == null
                      ? 'Original message no longer available'
                      : 'Move it out of Investments entirely',
                ),
                enabled: message != null,
                onTap: message == null
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        showCategoryPickerSheet(context, provider, message);
                      },
              ),
              if (onSelectStart != null)
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Select'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onSelectStart!();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// Inline "peek at the SMS" panel an [InvestmentTile] expands to show —
/// either because the list's "expand all" toggle is on, or because this
/// row's avatar was tapped directly. Mirrors
/// transaction_tile.dart's _ExpandedTransactionPanel.
class _ExpandedInvestmentPanel extends StatelessWidget {
  final InvestmentEvent investment;
  const _ExpandedInvestmentPanel({required this.investment});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i = investment;
    final provider = context.read<SmsProvider>();
    final message = provider.messageById(i.smsId);

    Widget action({
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
      Color? color,
    }) {
      return IconButton(
        icon: Icon(icon, size: 18),
        tooltip: label,
        color: color,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 4,
            children: [
              action(
                icon: Icons.edit_outlined,
                label: 'Edit',
                onPressed: () => showInvestmentEditSheet(context, provider, i),
              ),
              if (message != null)
                action(
                  icon: Icons.forum_outlined,
                  label: 'Thread',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ThreadScreen(threadId: message.threadId, highlightMessageId: message.id),
                    ),
                  ),
                ),
              if (message != null)
                action(
                  icon: Icons.label_outline,
                  label: 'Not an investment',
                  onPressed: () => showCategoryPickerSheet(context, provider, message),
                ),
              action(
                icon: Icons.delete_outline,
                label: 'Delete',
                color: scheme.error,
                onPressed: () => _confirmDeleteInvestmentSms(context, provider, i.smsId),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Text(
                i.rawBody.isEmpty ? '(no message text)' : i.rawBody,
                style: TextStyle(fontSize: 13, height: 1.4, color: scheme.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
