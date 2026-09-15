import 'dart:io';

import 'package:flutter/material.dart';

import 'photos.dart';

/// The face of a tile. If the user has set a personal photo for this
/// tile (category|label), show the photo full-bleed with the label in a
/// dark gradient bar. Otherwise show the classic white-circle emoji badge
/// with the label underneath. Re-renders automatically when the photo
/// store changes (revision notifier).
class TileFace extends StatelessWidget {
  final String category; // store key: category name
  final String label; // store key: tile label + spoken text
  final String emoji; // fallback glyph (badge)
  final Color color; // fallback tile/tint color
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
    return ValueListenableBuilder<int>(
      valueListenable: PhotoStore.instance.revision,
      builder: (context, _, __) {
        return FutureBuilder<String?>(
          future: PhotoStore.instance.pathFor(category, label),
          builder: (context, snap) {
            final path = snap.data;
            if (path != null && path.isNotEmpty) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: color,
                        child: Center(child: _Badge(emoji: emoji, size: badgeSize)),
                      ),
                    ),
                  ),
                  // dark gradient so the label stays readable
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xB3000000)],
                        stops: [0.55, 1.0],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
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
                              Shadow(color: Colors.black87, blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
            // No photo: classic badge layout.
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
          },
        );
      },
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
