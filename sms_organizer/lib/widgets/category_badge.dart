import 'package:flutter/material.dart';
import '../models/category.dart';

class CategoryBadge extends StatelessWidget {
  final SmsCategory category;
  final bool compact;

  /// Whether to show the category's text label alongside its icon. Off by
  /// default in dense message list rows, where the tag name next to every
  /// row reads as noise once you know what the color/icon means — a
  /// tooltip still surfaces it on demand.
  final bool showLabel;

  const CategoryBadge({
    super.key,
    required this.category,
    this.compact = false,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = category.color;
    final badge = Container(
      padding: showLabel
          ? EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 4)
          : EdgeInsets.all(compact ? 4 : 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        shape: showLabel ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: showLabel ? BorderRadius.circular(999) : null,
        border: showLabel ? Border.all(color: color.withOpacity(0.24)) : null,
      ),
      child: showLabel
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(category.icon, size: compact ? 12 : 14, color: color),
                const SizedBox(width: 4),
                Text(
                  category.label,
                  style: TextStyle(
                    color: color,
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : Icon(category.icon, size: compact ? 12 : 14, color: color),
    );
    return showLabel ? badge : Tooltip(message: category.label, child: badge);
  }
}
