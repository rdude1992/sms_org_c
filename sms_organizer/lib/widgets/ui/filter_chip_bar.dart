import 'package:flutter/material.dart';

/// Horizontally scrolling row of pill filter chips — shared by the inbox
/// category filter and the insights date-range filter, which previously
/// each had their own near-identical ListView-of-ChoiceChips.
class FilterChipBar<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onSelected;

  const FilterChipBar({
    super.key,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final value = values[index];
          return ChoiceChip(
            label: Text(labelBuilder(value)),
            selected: value == selected,
            onSelected: (_) => onSelected(value),
          );
        },
      ),
    );
  }
}
