import 'package:flutter/material.dart';

/// A muted, gently pulsing placeholder block — the building unit for
/// skeleton loading states below.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut).drive(Tween(begin: 0.5, end: 1.0));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: widget.borderRadius,
        ),
      ),
    );
  }
}

/// One placeholder row shaped like a conversation/message list tile —
/// avatar circle plus two lines of text.
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SkeletonBox(width: 44, height: 44, borderRadius: BorderRadius.all(Radius.circular(22))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: double.infinity, height: 13),
                SizedBox(height: 8),
                SkeletonBox(width: 160, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-screen stand-in for a list still loading — a handful of
/// [SkeletonListTile] rows instead of a bare spinner, so the shape of the
/// eventual content is visible immediately.
class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 74),
      itemBuilder: (_, __) => const SkeletonListTile(),
    );
  }
}
