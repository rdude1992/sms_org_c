import 'package:flutter/material.dart';

/// Small badge showing whether a message was received (down-left arrow) or
/// sent (up-right arrow) — used to disambiguate direction in flat list views
/// where messages aren't laid out as left/right chat bubbles.
class DirectionBadge extends StatelessWidget {
  final bool isIncoming;

  const DirectionBadge({super.key, required this.isIncoming});

  static const _incomingColor = Color(0xFF10B981); // emerald
  static const _outgoingColor = Color(0xFF3B82F6); // blue

  @override
  Widget build(BuildContext context) {
    final color = isIncoming ? _incomingColor : _outgoingColor;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
        child: Icon(
          isIncoming ? Icons.south_west : Icons.north_east,
          size: 10,
          color: color,
        ),
      ),
    );
  }
}
