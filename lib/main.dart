import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// TapToSay — category-based tap-to-speak AAC app (Android-first).
/// Landscape-only. Home = category grid (People / Food / I Feel / I Want /
/// I Need / Play / Activities / ABC / Colors / Shapes / Numbers / My Day).
/// Tap a category -> word grid -> tap a word -> it speaks.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape-only (also enforced in AndroidManifest).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
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

/// One phrase/word with a big emoji. The unit of speech.
class Saying {
  final String label; // spoken text + tile label
  final String emoji;
  final Color color;
  const Saying(this.label, this.emoji, this.color);
}

/// A category: title on the home screen + its word grid.
class Category {
  final String name;
  final String emoji;
  final Color color;
  final List<Saying> sayings;
  const Category(this.name, this.emoji, this.color, this.sayings);
}

/* ------------------------------------------------------------------ */
/*  Word sets — from this morning's spec                               */
/*  (People / Food / I FEEL / I WANT / I NEED / Play / Activities /    */
/*   ABC / Colors / Shapes / Numbers / My Day)                        */
/* ------------------------------------------------------------------ */

const _people = Category('People', '👨‍👩‍👧', Color(0xFF42A5F5), [
  Saying('Mom', '👩', Color(0xFFEC407A)),
  Saying('Dad', '👨', Color(0xFF42A5F5)),
  Saying('Baby', '👶', Color(0xFFFFCA28)),
  Saying('Teacher', '🧑‍🏫', Color(0xFF26A69A)),
  Saying('Friend', '🧒', Color(0xFF8D6E63)),
  Saying('Grandma', '👵', Color(0xFFAB47BC)),
  Saying('Grandpa', '👴', Color(0xFF7E57C2)),
  Saying('Me', '🙋', Color(0xFF66BB6A)),
]);

const _food = Category('Food', '🍎', Color(0xFFFFA726), [
  Saying('Apple', '🍎', Color(0xFFEF5350)),
  Saying('Banana', '🍌', Color(0xFFFFCA28)),
  Saying('Crackers', '🥨', Color(0xFFFFB74D)),
  Saying('Cereal', '🥣', Color(0xFFFFE082)),
  Saying('Water', '💧', Color(0xFF29B6F6)),
  Saying('Juice', '🧃', Color(0xFFFFA000)),
  Saying('Milk', '🥛', Color(0xFFE0E0E0)),
  Saying('Snack', '🍿', Color(0xFF8D6E63)),
  Saying('Pizza', '🍕', Color(0xFFF4511E)),
  Saying('Cookies', '🍪', Color(0xFFA1887F)),
]);

const _feel = Category('I Feel', '😊', Color(0xFFFF7043), [
  Saying('Happy', '😊', Color(0xFFFFCA28)),
  Saying('Sad', '😢', Color(0xFF7E57C2)),
  Saying('Mad', '😠', Color(0xFFEF5350)),
  Saying('Hurt', '🤕', Color(0xFF8D6E63)),
  Saying('Tired', '😴', Color(0xFF5C6BC0)),
  Saying('Scared', '😨', Color(0xFF26C6DA)),
  Saying('Silly', '🤪', Color(0xFFFF7043)),
  Saying('Calm', '😌', Color(0xFF66BB6A)),
]);

const _want = Category('I Want', '⭐', Color(0xFF26C6DA), [
  Saying('More', '➕', Color(0xFF66BB6A)),
  Saying('Stop', '✋', Color(0xFFEF5350)),
  Saying('Help', '🆘', Color(0xFFFF7043)),
  Saying('Play', '🧸', Color(0xFFAB47BC)),
  Saying('Bath', '🛁', Color(0xFF29B6F6)),
  Saying('Sleep', '🛏️', Color(0xFF5C6BC0)),
  Saying('Outside', '🌳', Color(0xFF66BB6A)),
  Saying('Music', '🎵', Color(0xFFEC407A)),
]);

const _need = Category('I Need', '🙏', Color(0xFF66BB6A), [
  Saying('Yes', '✅', Color(0xFF4CAF50)),
  Saying('No', '❌', Color(0xFFF44336)),
  Saying('This one', '👉', Color(0xFF42A5F5)),
  Saying('That one', '👈', Color(0xFF26A69A)),
  Saying('Break', '☕', Color(0xFF8D6E63)),
  Saying('Toilet', '🚻', Color(0xFF7E57C2)),
  Saying('Warm', '🔥', Color(0xFFFF7043)),
  Saying('Cold', '❄️', Color(0xFF29B6F6)),
]);

const _play = Category('Play', '🫧', Color(0xFFAB47BC), [
  Saying('Bubbles', '🫧', Color(0xFF29B6F6)),
  Saying('Trampoline', '🤸', Color(0xFFFFA726)),
  Saying('Pool', '🏊', Color(0xFF26C6DA)),
  Saying('The Cube', '🧊', Color(0xFF90A4AE)),
  Saying('Ball', '⚽', Color(0xFF66BB6A)),
  Saying('Swing', '🛝', Color(0xFF42A5F5)),
  Saying('Blocks', '🧱', Color(0xFF8D6E63)),
  Saying('Cars', '🚗', Color(0xFFEF5350)),
  Saying('Jump', '🦘', Color(0xFFAB47BC)),
  Saying('Spin', '🌀', Color(0xFF26C6DA)),
]);

const _activities = Category('Activities', '🧩', Color(0xFF7E57C2), [
  Saying('Read', '📖', Color(0xFF5C6BC0)),
  Saying('Draw', '🖍️', Color(0xFFFF7043)),
  Saying('Music', '🎵', Color(0xFFEC407A)),
  Saying('Dance', '💃', Color(0xFFAB47BC)),
  Saying('Run', '🏃', Color(0xFF66BB6A)),
  Saying('Jump', '🦘', Color(0xFFFFCA28)),
  Saying('Swim', '🏊', Color(0xFF26C6DA)),
  Saying('Walk', '🚶', Color(0xFF26A69A)),
]);

const _abc = Category('ABC', '🔤', Color(0xFFEC407A), [
  Saying('A', '🅰️', Color(0xFFEF5350)),
  Saying('B', '🅱️', Color(0xFF42A5F5)),
  Saying('C', '©️', Color(0xFFFFA726)),
  Saying('D', '🇩', Color(0xFF66BB6A)),
  Saying('E', '🇪', Color(0xFFAB47BC)),
  Saying('F', '🇫', Color(0xFF26C6DA)),
  Saying('G', '🇬', Color(0xFF7E57C2)),
  Saying('H', '🇭', Color(0xFFFF7043)),
]);

const _colors = Category('Colors', '🎨', Color(0xFF29B6F6), [
  Saying('Red', '🔴', Color(0xFFEF5350)),
  Saying('Blue', '🔵', Color(0xFF42A5F5)),
  Saying('Green', '🟢', Color(0xFF4CAF50)),
  Saying('Yellow', '🟡', Color(0xFFFFCA28)),
  Saying('Purple', '🟣', Color(0xFFAB47BC)),
  Saying('Orange', '🟠', Color(0xFFFF7043)),
  Saying('Pink', '🌸', Color(0xFFEC407A)),
  Saying('Black', '⚫', Color(0xFF37474F)),
]);

const _shapes = Category('Shapes', '🔷', Color(0xFF26A69A), [
  Saying('Circle', '⭕', Color(0xFF42A5F5)),
  Saying('Square', '🟦', Color(0xFF1E88E5)),
  Saying('Triangle', '🔺', Color(0xFFEF5350)),
  Saying('Star', '⭐', Color(0xFFFFCA28)),
  Saying('Heart', '❤️', Color(0xFFEC407A)),
  Saying('Diamond', '🔷', Color(0xFF26C6DA)),
]);

const _numbers = Category('Numbers', '🔢', Color(0xFFFFA726), [
  Saying('One', '1️⃣', Color(0xFFEF5350)),
  Saying('Two', '2️⃣', Color(0xFF42A5F5)),
  Saying('Three', '3️⃣', Color(0xFF66BB6A)),
  Saying('Four', '4️⃣', Color(0xFFFFCA28)),
  Saying('Five', '5️⃣', Color(0xFFAB47BC)),
  Saying('Six', '6️⃣', Color(0xFF26C6DA)),
  Saying('Seven', '7️⃣', Color(0xFFFF7043)),
  Saying('Eight', '8️⃣', Color(0xFF7E57C2)),
  Saying('Nine', '9️⃣', Color(0xFF26A69A)),
  Saying('Ten', '🔟', Color(0xFF8D6E63)),
]);

const _schedules = Category('My Day', '🗓️', Color(0xFF8D6E63), [
  Saying('Morning', '🌅', Color(0xFFFFCA28)),
  Saying('School', '🏫', Color(0xFF42A5F5)),
  Saying('Lunch', '🍱', Color(0xFFFFA726)),
  Saying('Home', '🏠', Color(0xFF66BB6A)),
  Saying('Bedtime', '🌙', Color(0xFF5C6BC0)),
  Saying('Now', '⏰', Color(0xFF26C6DA)),
  Saying('Later', '⏳', Color(0xFFAB47BC)),
  Saying('Today', '📅', Color(0xFF8D6E63)),
]);

const _categories = <Category>[
  _people,
  _food,
  _feel,
  _want,
  _need,
  _play,
  _activities,
  _abc,
  _colors,
  _shapes,
  _numbers,
  _schedules,
];

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
        padding: const EdgeInsets.all(8),
        child: GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.6,
          children: [
            for (final cat in _categories)
              _CategoryTile(
                category: cat,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CategoryGrid(
                      category: cat,
                      speak: _speak,
                    ),
                  ),
                ),
              ),
          ],
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
      borderRadius: BorderRadius.circular(18),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(category.emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(height: 4),
            Text(
              category.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
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

class CategoryGrid extends StatelessWidget {
  final Category category;
  final Future<void> Function(String) speak;

  const CategoryGrid({
    super.key,
    required this.category,
    required this.speak,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          '${category.emoji} ${category.name}',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        backgroundColor: category.color,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: GridView.count(
          crossAxisCount: 5,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.85,
          children: [
            for (final s in category.sayings)
              _WordTile(saying: s, onTap: () => speak(s.label)),
          ],
        ),
      ),
    );
  }
}

class _WordTile extends StatelessWidget {
  final Saying saying;
  final VoidCallback onTap;

  const _WordTile({required this.saying, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: saying.color,
      borderRadius: BorderRadius.circular(18),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(saying.emoji, style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 6),
            Text(
              saying.label,
              textAlign: TextAlign.center,
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
