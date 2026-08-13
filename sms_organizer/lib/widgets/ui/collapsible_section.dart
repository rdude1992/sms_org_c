import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/collapsible_sections_provider.dart';

/// A titled section that can be collapsed to just its header — shared by
/// Insights' "Recent transactions"/"By card / account"/"By merchant"/"By
/// spend category" sections and AmcDetailScreen's per-fund holding cards.
/// [trailing] — usually a "See all" button or an icon action — stays
/// outside the collapse/expand tap target and is always visible regardless
/// of state.
///
/// [prefKey] must be a stable, globally-unique string (e.g.
/// "insights.by_merchant", "amc_holding.<holding.key>") — collapsed state
/// persists across app restarts via [CollapsibleSectionsProvider], keyed on
/// this string rather than the section's position, so adding/reordering/
/// removing sections elsewhere never shuffles a saved state onto the wrong
/// one.
class CollapsibleSection extends StatelessWidget {
  final String prefKey;
  final Widget title;
  final Widget? trailing;
  final Widget child;

  const CollapsibleSection({
    super.key,
    required this.prefKey,
    required this.title,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Expanded by default (nothing looks hidden the first time a section is
    // ever seen) whenever [prefKey] hasn't been explicitly collapsed before.
    final collapsed = context.select<CollapsibleSectionsProvider, bool>((p) => p.isCollapsed(prefKey));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => context.read<CollapsibleSectionsProvider>().toggle(prefKey),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        collapsed ? Icons.chevron_right : Icons.expand_more,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Expanded(child: title),
                    ],
                  ),
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: collapsed
              ? const SizedBox(width: double.infinity)
              : Padding(padding: const EdgeInsets.only(top: 4), child: child),
        ),
      ],
    );
  }
}
