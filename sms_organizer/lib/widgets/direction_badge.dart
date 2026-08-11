import 'package:flutter/material.dart';

/// Small badge showing whether a message was received (down-left arrow) or
/// sent (up-right arrow) — used to disambiguate direction in flat list views
/// where messages aren't laid out as left/right chat bubbles.
class DirectionBadge extends StatelessWidget {
  final bool isIncoming;

  /// Icon glyph size — padding/border scale to match, so a caller using
  /// this as a standalone tap target (see inbox_screen.dart's flat message
  /// list, where it doubles as the avatar-tap-to-expand affordance) can
  /// size it up without reimplementing the badge's look.
  final double iconSize;

  const DirectionBadge({super.key, required this.isIncoming, this.iconSize = 10});

  static const incomingColor = Color(0xFF10B981); // emerald
  static const outgoingColor = Color(0xFF3B82F6); // blue

  @override
  Widget build(BuildContext context) {
    final color = isIncoming ? incomingColor : outgoingColor;
    final padding = iconSize / 5; // matches the original 10-icon/2-padding ratio
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
      ),
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
        child: Icon(
          isIncoming ? Icons.south_west : Icons.north_east,
          size: iconSize,
          color: color,
        ),
      ),
    );
  }
}
