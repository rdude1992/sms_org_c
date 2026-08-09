import 'package:flutter/material.dart';

/// A bordered card wrapping a column of rows (typically [ListTile]s or
/// [SwitchListTile]s) — groups a settings-style section visually instead
/// of leaving each row floating on the flat scaffold background under
/// just a text header.
class GroupedCard extends StatelessWidget {
  final List<Widget> children;

  const GroupedCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(children: children),
    );
  }
}
