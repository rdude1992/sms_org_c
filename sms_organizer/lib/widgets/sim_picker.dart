import 'package:flutter/material.dart';
import '../models/sim_info.dart';

/// Fixed accent per SIM slot, since Android exposes no colour of its own
/// per subscription — gives each SIM a consistent, at-a-glance identity
/// across the picker (both here and in the compose/reply bar) and the
/// per-message "SIM 2" tag in MessageBubble, the same way most dual-SIM
/// messaging apps colour-code which line a message went out on. Cycles
/// rather than assuming exactly two, for the rare 3+ active-subscription
/// case (multi-eSIM setups).
const _simPalette = [
  Color(0xFFC96442), // app accent — SIM 1
  Color(0xFF3B82F6), // blue — SIM 2
  Color(0xFF10B981), // emerald — SIM 3+
  Color(0xFFF59E0B),
];

Color simColor(int slotIndex) => _simPalette[slotIndex % _simPalette.length];

/// Lets the user pick which active SIM to send an outgoing SMS from.
/// Callers should only mount this when there's more than one active SIM —
/// it doesn't hide itself for a single-SIM/no-permission device.
class SimPicker extends StatelessWidget {
  final List<SimInfo> sims;
  final int? selectedSubscriptionId;
  final ValueChanged<int?> onChanged;

  /// Compact renders as a colour-coded pill that opens a picker menu — for
  /// tight spaces like the chat reply bar. Non-compact (the default)
  /// renders a full-width labeled SegmentedButton, used in the compose
  /// screen.
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
      final color = simColor(selected.slotIndex);
      final scheme = Theme.of(context).colorScheme;
      return PopupMenuButton<int>(
        tooltip: 'Send from ${_labelFor(selected)}',
        initialValue: selected.subscriptionId,
        onSelected: onChanged,
        itemBuilder: (context) => [
          for (final sim in sims)
            PopupMenuItem(
              value: sim.subscriptionId,
              child: Row(
                children: [
                  _SimDot(color: simColor(sim.slotIndex)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(sim.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        if (sim.carrierName?.isNotEmpty == true)
                          Text(
                            sim.carrierName!,
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  if (sim.subscriptionId == selectedSubscriptionId) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check, size: 16, color: scheme.primary),
                  ],
                ],
              ),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SimDot(color: color),
              const SizedBox(width: 6),
              Text(
                selected.label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
              ),
              Icon(Icons.arrow_drop_down, size: 16, color: color),
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
                ButtonSegment(
                  value: sim.subscriptionId,
                  label: Text(_labelFor(sim)),
                  icon: _SimDot(color: simColor(sim.slotIndex), size: 10),
                ),
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

class _SimDot extends StatelessWidget {
  final Color color;
  final double size;
  const _SimDot({required this.color, this.size = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
