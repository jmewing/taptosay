import 'dart:io';

import 'package:flutter/material.dart';

/// The face of a tile: a white-circle badge with the label underneath.
/// The badge shows a custom photo or a Mulberry AAC symbol when one is already
/// CACHED ON DISK, else it falls back to an emoji glyph.
/// (On-device tile photo editing was removed — tiles are managed from the
/// portal, so a tile always renders its face from server-provided data.)
///
/// PERFORMANCE CONTRACT (Jeremy, 2026-10-26): this widget never performs
/// network I/O. It takes a [facePath] — a local file path resolved by
/// [FaceCache.pathFor] — and renders it, or draws the emoji when the path is
/// null. Images are downloaded only during a config refresh.
class TileFace extends StatelessWidget {
  final String category; // category name (kept for call-site symmetry)
  final String label; // tile label + spoken text
  final String emoji; // glyph shown in the badge (fallback)
  final String? facePath; // LOCAL cached image path (overrides emoji when non-null)
  final Color color; // tile/tint color
  final double labelFontSize;
  final double badgeSize;

  const TileFace({
    super.key,
    required this.category,
    required this.label,
    required this.emoji,
    required this.color,
    this.facePath,
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
            child: _Badge(
              emoji: emoji,
              facePath: facePath,
              size: badgeSize,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: labelFontSize,
                fontWeight: FontWeight.w700,
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
  final String? facePath; // non-null => render the cached file instead
  final double size;

  const _Badge({required this.emoji, this.facePath, required this.size});

  @override
  Widget build(BuildContext context) {
    Widget inner;
    final path = facePath;
    if (path != null && path.isNotEmpty) {
      inner = ClipOval(
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Decode at the on-screen size instead of full resolution: these are
          // large Mulberry PNGs on a small badge.
          cacheWidth: (size * 3).round(),
          // A corrupt or since-deleted file must never blank the tile.
          errorBuilder: (context, error, stack) => _emojiInner(),
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
    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: Padding(
          padding: EdgeInsets.all(size * 0.12),
          child: Text(
            emoji,
            style: TextStyle(fontSize: size * 0.62, height: 1.0),
          ),
        ),
      ),
    );
  }
}
