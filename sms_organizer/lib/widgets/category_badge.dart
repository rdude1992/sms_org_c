import 'package:flutter/material.dart';
import '../models/category.dart';

class CategoryBadge extends StatelessWidget {
  final SmsCategory category;
  final bool compact;

  const CategoryBadge({super.key, required this.category, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final color = category.color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
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
      ),
    );
  }
}
