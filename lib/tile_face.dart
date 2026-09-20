import 'package:flutter/material.dart';

/// The face of a tile: a white-circle badge with the label underneath.
/// The badge shows a custom photo or a Mulberry AAC symbol when provided,
/// else falls back to an emoji glyph.
/// (On-device tile photo editing was removed — tiles are managed from the
/// portal, so a tile always renders its face from server-provided data.)
class TileFace extends StatelessWidget {
  final String category; // category name (kept for call-site symmetry)
  final String label; // tile label + spoken text
  final String emoji; // glyph shown in the badge (fallback)
  final String? symbolUrl; // Mulberry AAC PNG URL (overrides emoji when non-null)
  final String? mediaUrl; // uploaded custom photo URL (overrides emoji when non-null)
  final Color color; // tile/tint color
  final double labelFontSize;
  final double badgeSize;

  const TileFace({
    super.key,
    required this.category,
    required this.label,
    required this.emoji,
    required this.color,
    this.symbolUrl,
    this.mediaUrl,
    this.labelFontSize = 22,
    this.badgeSize = 96,
  });

  @override
  Widget build(BuildContext context) {
    final faceUrl = mediaUrl ?? symbolUrl; // custom photo wins over AAC symbol
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: FittedBox(
            fit: BoxFit.contain,
            child: _Badge(
              emoji: emoji,
              faceUrl: faceUrl,
              size: badgeSize,
            ),
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

/// White circle badge so the face always stands out from the tile color.
class _Badge extends StatelessWidget {
  final String emoji;
  final String? faceUrl; // non-null => render an image instead of the emoji
  final double size;

  const _Badge({required this.emoji, this.faceUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    Widget inner;
    final url = faceUrl;
    if (url != null && url.isNotEmpty) {
      inner = ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => _emojiInner(),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(child: SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ));
          },
        ),
      );
    } else {
      inner = _emojiInner();
    }

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
      clipBehavior: Clip.antiAlias,
      child: inner,
    );
  }

  Widget _emojiInner() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: FittedBox(
        fit: BoxFit.contain,
        child: Text(
          emoji,
          style: const TextStyle(
            fontSize: 60,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}
