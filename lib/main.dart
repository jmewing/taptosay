import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// TapToSay — tap a tile, it says the word.
/// Android-first AAC app (v1: single tap-to-speak grid).
void main() {
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
      home: const HomeGrid(),
    );
  }
}

class SpeakButton {
  final String label;
  final String emoji;
  final Color color;
  const SpeakButton(this.label, this.emoji, this.color);
}

/// v1 word set — big, common, kid-friendly. Category grids come next.
const _tiles = <SpeakButton>[
  SpeakButton('Mom', '👩', Color(0xFFEC407A)),
  SpeakButton('Dad', '👨', Color(0xFF42A5F5)),
  SpeakButton('Eat', '🍎', Color(0xFFFFA726)),
  SpeakButton('Drink', '🥤', Color(0xFF26C6DA)),
  SpeakButton('Play', '🧸', Color(0xFFAB47BC)),
  SpeakButton('More', '➕', Color(0xFF66BB6A)),
  SpeakButton('Stop', '✋', Color(0xFFEF5350)),
  SpeakButton('Help', '❓', Color(0xFFFF7043)),
  SpeakButton('Yes', '✅', Color(0xFF4CAF50)),
  SpeakButton('No', '❌', Color(0xFFF44336)),
  SpeakButton('Happy', '😊', Color(0xFFFFCA28)),
  SpeakButton('Sad', '😢', Color(0xFF7E57C2)),
  SpeakButton('Hurt', '🤕', Color(0xFF8D6E63)),
  SpeakButton('Bath', '🛁', Color(0xFF29B6F6)),
  SpeakButton('Sleep', '😴', Color(0xFF5C6BC0)),
  SpeakButton('All Done', '🏁', Color(0xFF78909C)),
];

class HomeGrid extends StatefulWidget {
  const HomeGrid({super.key});

  @override
  State<HomeGrid> createState() => _HomeGridState();
}

class _HomeGridState extends State<HomeGrid> {
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.45); // slow & clear for a young AAC user
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (_) {
      // Engine not ready yet; tiles still work, speak() will no-op.
    }
  }

  Future<void> _speak(String word) async {
    HapticFeedback.lightImpact();
    try {
      await _tts.stop();
      await _tts.speak(word);
    } catch (_) {
      // ignore — nothing to do if TTS hiccups mid-tap
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'TapToSay 🌻',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF00838F),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.85,
          children: [
            for (final tile in _tiles)
              _SpeakTile(
                tile: tile,
                onTap: () => _speak(tile.label),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpeakTile extends StatelessWidget {
  final SpeakButton tile;
  final VoidCallback onTap;

  const _SpeakTile({required this.tile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tile.color,
      borderRadius: BorderRadius.circular(18),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(tile.emoji, style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 6),
            Text(
              tile.label,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
