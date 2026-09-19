import 'package:flutter/material.dart';

/// The face of a tile: a white-circle emoji badge with the label underneath.
/// (On-device tile photo editing was removed — tiles are managed from the
/// portal, so a tile always renders its glyph badge.)
class TileFace extends StatelessWidget {
  final String category; // category name (kept for call-site symmetry)
  final String label; // tile label + spoken text
  final String emoji; // glyph shown in the badge
  final Color color; // tile/tint color
  final double labelFontSize;
  final double badgeSize;

  const TileFace({
    super.key,
    required this.category,
    required this.label,
    required this.emoji,
    required this.color,
    this.labelFontSize = 22,
    this.badgeSize = 96,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: FittedBox(
            fit: BoxFit.contain,
            child: _Badge(emoji: emoji, size: badgeSize),
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          flex: 2,
          child: FittedBox(
            fit: BoxFit.contain,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: labelFontSize,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: const [
                  Shadow(color: Colors.black45, blurRadius: 4),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// White circle badge so the glyph always stands out from the tile color.
class _Badge extends StatelessWidget {
  final String emoji;
  final double size;

  const _Badge({required this.emoji, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            emoji,
            style: const TextStyle(
              fontSize: 60,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
