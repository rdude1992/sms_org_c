import 'package:flutter/material.dart';
import '../models/sim_info.dart';

/// Lets the user pick which active SIM to send an outgoing SMS from.
/// Callers should only mount this when there's more than one active SIM —
/// it doesn't hide itself for a single-SIM/no-permission device.
class SimPicker extends StatelessWidget {
  final List<SimInfo> sims;
  final int? selectedSubscriptionId;
  final ValueChanged<int?> onChanged;

  /// Compact renders as an icon button that opens a picker menu — for tight
  /// spaces like the chat reply bar. Non-compact (the default) renders a
  /// full-width labeled SegmentedButton, used in the compose screen.
  final bool compact;

  const SimPicker({
    super.key,
    required this.sims,
    required this.selectedSubscriptionId,
    required this.onChanged,
    this.compact = false,
  });

  String _labelFor(SimInfo sim) => sim.carrierName?.isNotEmpty == true ? sim.carrierName! : sim.label;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      final selected = sims.firstWhere(
        (s) => s.subscriptionId == selectedSubscriptionId,
        orElse: () => sims.first,
      );
      return PopupMenuButton<int>(
        tooltip: 'Send from ${_labelFor(selected)}',
        initialValue: selected.subscriptionId,
        onSelected: onChanged,
        itemBuilder: (context) => [
          for (final sim in sims)
            PopupMenuItem(value: sim.subscriptionId, child: Text(_labelFor(sim))),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sim_card_outlined, size: 16),
              const SizedBox(width: 4),
              Text(selected.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.sim_card_outlined, size: 18, color: mutedColor),
        const SizedBox(width: 8),
        Text('Send from', style: TextStyle(fontSize: 13, color: mutedColor)),
        const SizedBox(width: 12),
        Expanded(
          child: SegmentedButton<int>(
            segments: [
              for (final sim in sims)
                ButtonSegment(value: sim.subscriptionId, label: Text(_labelFor(sim))),
            ],
            selected: {selectedSubscriptionId ?? sims.first.subscriptionId},
            onSelectionChanged: (selection) => onChanged(selection.first),
            showSelectedIcon: false,
          ),
        ),
      ],
    );
  }
}
