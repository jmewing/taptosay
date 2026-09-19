import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'provision_screen.dart';
import 'sync.dart';
import 'tile_face.dart';
import 'vocab.dart';

/// TapToSay — category-based tap-to-speak AAC app (Android-first).
/// Landscape-only. Home = category grid (People / Food / I Feel / I Want /
/// I Need / Play / Activities / ABC / Colors / Shapes / Numbers / My Day).
///
/// Vocabulary comes from the server (`/api/config/sync`) on launch, with an
/// on-device offline cache and built-in fallback. First run prompts for the
/// four remote credentials (school ID, student ID, auth password, server URL).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape-only (also enforced in AndroidManifest).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // Hide the status bar (Wi-Fi / clock / battery) so the header sits flush
  // at the top and every pixel goes to the buttons.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Load cached config (categories + PINs) before first frame.
  await ConfigStore.instance.load();
  runApp(const TapToSayApp());
}

class TapToSayApp extends StatelessWidget {
  const TapToSayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TapToSay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00838F)),
        scaffoldBackgroundColor: const Color(0xFFEFF6F8),
      ),
      home: const CategoryHome(),
    );
  }
}

/* ------------------------------------------------------------------ */
/*  Screens                                                           */
/* ------------------------------------------------------------------ */

class CategoryHome extends StatefulWidget {
  const CategoryHome({super.key});

  @override
  State<CategoryHome> createState() => _CategoryHomeState();
}

class _CategoryHomeState extends State<CategoryHome> {
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initTts();
    _syncOnLaunch();
  }

  /// On launch, fetch config from the server (if provisioned). Silently
  /// falls back to the offline cache / built-ins on any failure.
  Future<void> _syncOnLaunch() async {
    try {
      await ConfigStore.instance.load();
      if (!ConfigStore.instance.isProvisioned) return;
      await ConfigStore.instance.sync();
      if (mounted) setState(() {});
    } catch (_) {
      // offline or credentials changed — keep the cache / built-ins
    }
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.45); // slow & clear for a young AAC user
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (_) {
      // engine not ready yet; tiles still work, speak() no-ops
    }
  }

  Future<void> _speak(String word) async {
    try {
      await HapticFeedback.lightImpact();
      await _tts.stop();
      await _tts.speak(word);
    } catch (_) {
      // ignore — nothing to do if TTS hiccups mid-tap
    }
  }

  /// Numeric PIN gate. Shows a number-pad dialog and resolves true only if
  /// the entered digits match [pin]. Used to protect Settings and Exit.
  Future<bool> _promptPin(String pin) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Enter code'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              counterText: '',
              hintText: '••••',
            ),
            onSubmitted: (_) => Navigator.of(ctx).pop(true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    if (ok != true) return false;
    return controller.text == pin;
  }

  /// Unlock kiosk mode and drop to the normal launcher.
  Future<void> _exitKiosk() async {
    const channel = MethodChannel('com.jmewing.taptosay/kiosk');
    try {
      await channel.invokeMethod('stopLockTask');
    } catch (_) {
      // ignore — still try to go home below
    }
    try {
      await channel.invokeMethod('goHome');
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ConfigStore.instance.categories;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        centerTitle: true,
        title: const Text(
          'Tap To Say',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF00838F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, size: 22),
            tooltip: 'Sync config',
            onPressed: () async {
              try {
                await ConfigStore.instance.sync();
                if (!mounted) return;
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ Synced')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Sync failed: $e')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings, size: 22),
            tooltip: 'Connect / settings',
            onPressed: () async {
              final pin = ConfigStore.instance.settingsPin;
              if (pin.isEmpty) {
                // Not synced yet; allow setup once so the tablet can connect
                // for the very first time without a PIN. After sync it will be
                // protected.
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const ProvisionScreen()),
                );
                if (mounted) setState(() {});
                return;
              }
              final ok = await _promptPin(pin);
              if (!mounted) return;
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Wrong code')),
                );
                return;
              }
              await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const ProvisionScreen()),
              );
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app, size: 22),
            tooltip: 'Exit',
            onPressed: () async {
              final pin = ConfigStore.instance.exitPin;
              if (pin.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Exit PIN not configured yet — sync with the server first')),
                );
                return;
              }
              final ok = await _promptPin(pin);
              if (!mounted) return;
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Wrong code')),
                );
                return;
              }
              await _exitKiosk();
            },
          ),
        ],
      ),
      body: ConfigStore.instance.isProvisioned
          ? _categoryGrid(context, categories)
          : _unprovisioned(context),
    );
  }

  Widget _unprovisioned(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This tablet is not connected yet.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final done = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const ProvisionScreen()),
                );
                if (done == true && mounted) setState(() {});
              },
              child: const Text('Set up tablet'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryGrid(BuildContext context, List<Category> categories) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const cols = 4;
        const spacing = 6.0;
        const pad = 8.0;
        final rows = (categories.length / cols).ceil();
        final tileW = (constraints.maxWidth - pad * 2 - spacing * (cols - 1)) / cols;
        final tileH = (constraints.maxHeight - pad * 2 - spacing * (rows - 1)) / rows;
        return GridView.builder(
          padding: const EdgeInsets.all(pad),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: tileW / tileH,
          ),
          itemCount: categories.length,
          itemBuilder: (context, i) {
            final cat = categories[i];
            return _CategoryTile(
              category: cat,
              onTap: () {
                _speak(cat.name); // speak the category name out loud
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WordGridScreen(
                      title: cat.name,
                      emoji: cat.emoji,
                      color: cat.color,
                      sayings: cat.sayings,
                      category: cat.name,
                      speak: _speak,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final Category category;
  final VoidCallback onTap;

  const _CategoryTile({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: category.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.black26, width: 2),
      ),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: TileFace(
            category: category.name,
            label: category.name,
            emoji: category.emoji,
            color: category.color,
            labelFontSize: 20,
            badgeSize: 96,
          ),
        ),
      ),
    );
  }
}

/// Generic word/drill-down grid screen.
class WordGridScreen extends StatelessWidget {
  final String title;
  final String emoji;
  final Color color;
  final List<Saying> sayings;
  final String category; // category name for the on-device photo store
  final Future<void> Function(String) speak;

  const WordGridScreen({
    super.key,
    required this.title,
    required this.emoji,
    required this.color,
    required this.sayings,
    required this.category,
    required this.speak,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          emoji.isEmpty ? title : '$emoji $title',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          const cols = 5;
          const spacing = 10.0;
          const pad = 10.0;
          final rows = (sayings.length / cols).ceil();
          final tileW = (constraints.maxWidth - pad * 2 - spacing * (cols - 1)) / cols;
          final tileH = (constraints.maxHeight - pad * 2 - spacing * (rows - 1)) / rows;
          return GridView.builder(
            padding: const EdgeInsets.all(pad),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: tileW / tileH,
            ),
            itemCount: sayings.length,
            itemBuilder: (context, i) {
              final s = sayings[i];
              return _WordTile(
                saying: s,
                category: category,
                speak: speak,
                onDecadeTap: (Saying d) {
                  speak(d.label);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WordGridScreen(
                        title: d.subTitle ?? d.label,
                        emoji: '', // no duplicate emoji/number on drill-down title
                        color: d.color,
                        sayings: d.sub!,
                        category: category,
                        speak: speak,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _WordTile extends StatelessWidget {
  final Saying saying;
  final String category;
  final Future<void> Function(String) speak;
  final void Function(Saying) onDecadeTap;

  const _WordTile({
    required this.saying,
    required this.category,
    required this.speak,
    required this.onDecadeTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasSub = saying.sub != null && saying.sub!.isNotEmpty;
    return Material(
      color: saying.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.black26, width: 2),
      ),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => hasSub ? onDecadeTap(saying) : speak(saying.label),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: TileFace(
            category: category,
            label: saying.label,
            emoji: saying.emoji,
            color: saying.color,
            labelFontSize: 22,
            badgeSize: 96,
          ),
        ),
      ),
    );
  }
}
