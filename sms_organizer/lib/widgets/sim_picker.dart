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

  /// Compact renders as a small round tap-to-cycle toggle — sized and
  /// vertically centred to match the reply text field's single-line height
  /// rather than opening a separate picker menu, for tight spaces like the
  /// chat reply bar. Non-compact (the default) renders a full-width labeled
  /// SegmentedButton, used in the compose screen.
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
      final index = sims.indexWhere((s) => s.subscriptionId == selectedSubscriptionId);
      final selected = index == -1 ? sims.first : sims[index];
      final color = simColor(selected.slotIndex);
      return Tooltip(
        message: 'Sending from ${_labelFor(selected)} — tap to switch',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            final current = sims.indexOf(selected);
            onChanged(sims[(current + 1) % sims.length].subscriptionId);
          },
          child: Container(
            // Matches the reply TextField's single-line height (10 vertical
            // content padding + ~20 line height) so the two sit flush
            // instead of the toggle looking a size off next to it.
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.6)),
            ),
            child: Text(
              '${selected.slotIndex + 1}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color),
            ),
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
