import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'main.dart'; // Category, Saying, allCategories helpers
import 'photos.dart';
import 'tile_face.dart';

/// Settings: pick a category, then a tile, then snap/choose/remove the
/// tile's photo. Photos stay in the app's private storage — never the repo.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('⚙️ Settings — Tile Photos'),
        backgroundColor: const Color(0xFF37474F),
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final cols = 4;
          const spacing = 6.0;
          const pad = 8.0;
          final rows = (allCategories.length / cols).ceil();
          final tileW =
              (constraints.maxWidth - pad * 2 - spacing * (cols - 1)) / cols;
          final tileH =
              (constraints.maxHeight - pad * 2 - spacing * (rows - 1)) / rows;
          return GridView.builder(
            padding: const EdgeInsets.all(pad),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: tileW / tileH,
            ),
            itemCount: allCategories.length,
            itemBuilder: (context, i) {
              final cat = allCategories[i];
              return Material(
                color: cat.color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Colors.black26, width: 2),
                ),
                elevation: 3,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CategoryPhotoEditor(category: cat),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 3,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: _SettingsBadge(emoji: cat.emoji),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Expanded(
                          flex: 2,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Text(
                              cat.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(color: Colors.black45, blurRadius: 4),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SettingsBadge extends StatelessWidget {
  final String emoji;
  const _SettingsBadge({required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
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

/// One category's tiles, each editable (tap to add/change/remove photo).
class CategoryPhotoEditor extends StatefulWidget {
  final Category category;
  const CategoryPhotoEditor({super.key, required this.category});

  @override
  State<CategoryPhotoEditor> createState() => _CategoryPhotoEditorState();
}

class _CategoryPhotoEditorState extends State<CategoryPhotoEditor> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickAndApply(Saying saying, ImageSource source) async {
    // Persist the target BEFORE opening the picker: if the system picker
    // kills our activity (seen on this 2GB kiosk tablet), the photo is
    // recovered on next launch via retrieveLostData + takePending.
    await PhotoStore.instance.markPending(widget.category.name, saying.label);
    try {
      // Lift kiosk lock briefly so the system camera/gallery can open.
      await KioskBridge.lift();
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1200,
        imageQuality: 85,
      );
      await KioskBridge.restore();
      if (picked == null) {
        await PhotoStore.instance.takePending(); // cancelled — clear marker
        return;
      }
      await PhotoStore.instance.setPhoto(
        widget.category.name,
        saying.label,
        picked.path,
      );
      await PhotoStore.instance.takePending(); // success — clear marker
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📸 ${saying.label} photo set')),
        );
      }
    } catch (e) {
      await KioskBridge.restore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not take/use photo: $e')),
        );
      }
    }
  }

  Future<void> _removePhoto(Saying saying) async {
    await PhotoStore.instance.removePhoto(widget.category.name, saying.label);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🗑️ ${saying.label} photo removed')),
      );
    }
  }

  Future<void> _onTileTap(Saying saying) async {
    final has = await PhotoStore.instance.hasPhoto(
      widget.category.name,
      saying.label,
    );
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Snap photo'),
              onTap: () => Navigator.of(context).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop('gallery'),
            ),
            if (has)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () => Navigator.of(context).pop('remove'),
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'camera':
        await _pickAndApply(saying, ImageSource.camera);
      case 'gallery':
        await _pickAndApply(saying, ImageSource.gallery);
      case 'remove':
        await _removePhoto(saying);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('Edit ${widget.category.name}'),
        backgroundColor: widget.category.color,
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final cols = 5;
          const spacing = 10.0;
          const pad = 10.0;
          final rows = (widget.category.sayings.length / cols).ceil();
          final tileW =
              (constraints.maxWidth - pad * 2 - spacing * (cols - 1)) / cols;
          final tileH =
              (constraints.maxHeight - pad * 2 - spacing * (rows - 1)) / rows;
          return GridView.builder(
            padding: const EdgeInsets.all(pad),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: tileW / tileH,
            ),
            itemCount: widget.category.sayings.length,
            itemBuilder: (context, i) {
              final s = widget.category.sayings[i];
              return _EditableTile(
                category: widget.category.name,
                saying: s,
                onTap: () => _onTileTap(s),
              );
            },
          );
        },
      ),
    );
  }
}

/// A tile in the editor. Shows its current photo (or badge) plus a small
/// camera chip so it's obvious this tile is tappable-to-edit.
class _EditableTile extends StatelessWidget {
  final String category;
  final Saying saying;
  final VoidCallback onTap;

  const _EditableTile({
    required this.category,
    required this.saying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: saying.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.black26, width: 2),
      ),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: TileFace(
                category: category,
                label: saying.label,
                emoji: saying.emoji,
                color: saying.color,
                labelFontSize: 20,
                badgeSize: 72,
              ),
            ),
            // camera chip: signals "tap to edit"
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.photo_camera,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
