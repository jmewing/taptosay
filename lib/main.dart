import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'provision_screen.dart';
import 'sync.dart';
import 'tile_face.dart';
import 'updater.dart';
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
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadVersion();
    _deviceSync();
    // Look for a newer build a moment after first paint (non-blocking).
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    // Safety net for a kiosk that never relaunches: a full device sync (config
    // + app update) every 6h, so the tablet stays current on both.
    _updateTimer = Timer.periodic(const Duration(hours: 6), (_) => _deviceSync());
  }

  Timer? _updateTimer;
  bool _updatePromptOpen = false;

  /// Show the running build in the very top-left of the app bar.
  Future<void> _loadVersion() async {
    final v = await Updater.currentVersionName();
    if (mounted && v.isNotEmpty) setState(() => _appVersion = v);
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _tts.stop();
    super.dispose();
  }

  /// Ask the server whether a newer build is published, and offer to install it.
  /// Runs on launch, after every sync, and every 6h. This is how a new APK on
  /// the website reaches every tablet without anyone flashing or re-installing
  /// by hand.
  Future<void> _checkForUpdate() async {
    if (_updatePromptOpen) return;
    try {
      final info = await Updater.check();
      if (info == null || !mounted) return;
      _updatePromptOpen = true;
      final go = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Update available'),
          content: Text('TapToSay ${info.versionName} is ready to install.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Later')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Install')),
          ],
        ),
      );
      _updatePromptOpen = false;
      if (go != true || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Downloading update…')),
      );
      final ok = await Updater.downloadAndInstall(info);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Update downloaded — confirm Install to finish.'
              : 'Update failed. Please try again later.'),
        ),
      );
    } catch (_) {
      _updatePromptOpen = false;
      // offline / no update — never block the app
    }
  }

  /// On launch, fetch config from the server (if provisioned). Silently
  /// falls back to the offline cache / built-ins on any failure.
  /// One "device sync": refresh configuration from the server (if provisioned)
  /// and then check for a newer app build. Runs on launch, on the manual Sync
  /// button, and every 6h.
  ///
  /// Background (auto) runs are QUIET: an offline/failed config sync shows only
  /// a brief message at the bottom of the screen — never a pop-up or dialog.
  /// Returns true when the config sync succeeded (or wasn't needed).
  Future<bool> _deviceSync({bool manual = false}) async {
    var cfgOk = true;
    try {
      await ConfigStore.instance.load();
      // If the tablet was provisioned via QR/NFC, the admin-extras bundle has
      // already been persisted natively; apply it so the app auto-connects
      // without the first-run hand-typing of credentials.
      if (!ConfigStore.instance.isProvisioned) {
        await _applyProvisioningExtras();
      }
      if (ConfigStore.instance.isProvisioned) {
        await ConfigStore.instance.sync();
        if (mounted) setState(() {});
      }
    } catch (_) {
      // offline or credentials changed — keep the cache / built-ins
      cfgOk = false;
    }
    // Quiet failure notice: a small bottom message only. Never a pop-up.
    if (!cfgOk && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync failed — offline'),
          duration: Duration(seconds: 3),
        ),
      );
    } else if (manual && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Synced'), duration: Duration(seconds: 2)),
      );
    }
    // Config sync done (or skipped) — now look for a newer app build.
    await _checkForUpdate();
    return cfgOk;
  }

  /// Read the device-owner provisioning extras from the native side and apply
  /// them (server_url, student_id, school_tea_id, auth_password).
  Future<void> _applyProvisioningExtras() async {
    const channel = MethodChannel('app.taptosay/kiosk');
    try {
      final extras = await channel.invokeMethod<Map<dynamic, dynamic>>('getProvisioningExtras');
      if (extras == null || extras.isEmpty) return;
      final map = extras.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      await ConfigStore.instance.applyProvisioningExtras(map);
      if (mounted) setState(() {});
    } catch (_) {
      // no extras — remain on the first-run provision screen
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
    const channel = MethodChannel('app.taptosay/kiosk');
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
    final store = ConfigStore.instance;
    final categories = store.categories;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        centerTitle: true,
        // The running app version sits at the very top-left (leading slot).
        leadingWidth: _appVersion.isEmpty ? 4 : 62,
        leading: _appVersion.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _appVersion,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white70),
                  ),
                ),
              ),
        // Roster mode: classroom dropdown to the LEFT of the title, student
        // dropdown to the RIGHT. Both are bounded to the leftover space
        // (Expanded) so a long name ellipsizes instead of widening the box and
        // shoving 'Tap To Say' off-centre (Jeremy, 2026-10-06).
        title: store.hasRoster
            ? Row(
                children: [
                  if (store.isTeacher)
                    Expanded(
                      child: _ClassroomDropdown(
                          onChanged: () => setState(() {})),
                    )
                  else
                    const Spacer(),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Tap To Say',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: _StudentDropdown(
                        onChanged: () => setState(() {})),
                  ),
                ],
              )
            : const Text(
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
              await _deviceSync(manual: true);
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings, size: 22),
            tooltip: 'Connect / settings',
            onPressed: () async {
              // Before the tablet has EVER connected, let setup through without a
              // code so a freshly-installed app can be configured (Jeremy,
              // 2026-10-05). Once provisioned, the server's settings PIN gates it.
              if (!ConfigStore.instance.isProvisioned) {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const ProvisionScreen()),
                );
                if (mounted) setState(() {});
                return;
              }
              final pin = ConfigStore.instance.settingsPin;
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
      // Always show the board. An unconnected, freshly-installed tablet runs on
      // the built-in default ACC board (the local vocab fallback); connecting to
      // the server then replaces it with the synced config. The app is usable
      // out of the box — no server connection required first.
      body: _categoryGrid(context, categories),
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

class _StudentDropdown extends StatelessWidget {
  final VoidCallback onChanged;
  const _StudentDropdown({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final store = ConfigStore.instance;
    final students = store.currentStudents;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: store.selectedStudentId,
          isExpanded: true,
          iconEnabledColor: Colors.white,
          dropdownColor: const Color(0xFF00695C),
          style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('--Select Student--',
                  style: TextStyle(color: Colors.white)),
            ),
            for (final s in students)
              DropdownMenuItem<String?>(
                value: s.studentId,
                child: Text(
                  s.label,
                  style: const TextStyle(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) {
            // Roster is already cached — switching is local, no network call.
            store.selectStudent(id);
            onChanged();
          },
        ),
      ),
    );
  }
}

class _ClassroomDropdown extends StatelessWidget {
  final VoidCallback onChanged;
  const _ClassroomDropdown({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final store = ConfigStore.instance;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: store.selectedClassroomId,
          isExpanded: true,
          iconEnabledColor: Colors.white,
          dropdownColor: const Color(0xFF00695C),
          style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('--Select Class--',
                  style: TextStyle(color: Colors.white)),
            ),
            for (final c in store.classrooms)
              DropdownMenuItem<String?>(
                value: c.classroomId,
                child: Text(
                  c.label,
                  style: const TextStyle(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) {
            // Switching classrooms resets the student and is purely local.
            store.selectClassroom(id);
            onChanged();
          },
        ),
      ),
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
            symbolUrl: ConfigStore.instance.symbolUrl(category.symbol),
            mediaUrl: ConfigStore.instance.mediaUrl(category.mediaId),
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
            symbolUrl: ConfigStore.instance.symbolUrl(saying.symbol),
            mediaUrl: ConfigStore.instance.mediaUrl(saying.mediaId),
            color: saying.color,
            labelFontSize: 22,
            badgeSize: 96,
          ),
        ),
      ),
    );
  }
}
