import 'package:flutter/material.dart';

/// The app's one standard thin separator between rows in a compact list —
/// originated with Recent transactions' compact rows, now reused everywhere
/// a list of single-line rows appears (By card/account, By merchant, By
/// spend category, Investments' By AMC) so switching between them doesn't
/// read as switching apps.
Widget buildRowDivider(BuildContext context) => Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
    );

/// Interspersed with [buildRowDivider] between each pair of [children] (none
/// before the first or after the last) — the same pattern Recent
/// transactions' hand-written `for` loop already used, factored out so every
/// other compact list can just call this instead of re-deriving it.
List<Widget> withRowDividers(BuildContext context, List<Widget> children) => [
      for (var i = 0; i < children.length; i++) ...[
        children[i],
        if (i != children.length - 1) buildRowDivider(context),
      ],
    ];
