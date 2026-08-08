import 'package:flutter/material.dart';

/// A bordered card wrapping a column of rows (typically [ListTile]s or
/// [SwitchListTile]s) with hairline dividers between them — groups a
/// settings-style section visually instead of leaving each row floating
/// on the flat scaffold background under just a text header.
class GroupedCard extends StatelessWidget {
  final List<Widget> children;

  const GroupedCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).colorScheme.outlineVariant;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) Divider(height: 1, indent: 16, color: border),
          ],
        ],
      ),
    );
  }
}
