import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// TapToSay — category-based tap-to-speak AAC app (Android-first).
/// Landscape-only. Home = category grid (People / Food / I Feel / I Want /
/// I Need / Play / Activities / ABC / Colors / Shapes / Numbers / My Day).
/// Tap a category -> it says the category name + word grid opens.
/// Tap a word (or decade in Numbers) -> it speaks.
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

/// One phrase/word with a big display glyph. The unit of speech.
class Saying {
  final String label; // spoken text
  final String emoji; // shown on the white badge (emoji, letter, or number)
  final Color color;
  final List<Saying>? sub; // drill-down tiles (e.g. decade 20 -> 20..29)
  final String? subTitle; // label for the drill-down screen
  const Saying(this.label, this.emoji, this.color, {this.sub, this.subTitle});
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
/*  Shared color palette for generated tiles                          */
/* ------------------------------------------------------------------ */

const _palette = <Color>[
  Color(0xFFEF5350), // red
  Color(0xFF42A5F5), // blue
  Color(0xFF66BB6A), // green
  Color(0xFFFFCA28), // yellow
  Color(0xFFAB47BC), // purple
  Color(0xFF26C6DA), // cyan
  Color(0xFFFF7043), // orange
  Color(0xFF7E57C2), // violet
  Color(0xFF26A69A), // teal
  Color(0xFF8D6E63), // brown
];

/* ------------------------------------------------------------------ */
/*  Number word helper (0-100)                                        */
/* ------------------------------------------------------------------ */

const _ones = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine'];
const _teens = ['ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
const _tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

String _numWord(int n) {
  if (n < 10) return _ones[n];
  if (n < 20) return _teens[n - 10];
  if (n < 100) {
    final t = n ~/ 10;
    final o = n % 10;
    return o == 0 ? _tens[t] : '${_tens[t]}-${_ones[o]}';
  }
  return 'one hundred';
}

/// A decade drill-down: base 10 -> 10..19, base 20 -> 20..29, etc.
List<Saying> _decade(int base) => [
      for (var i = 0; i < 10; i++)
        Saying(_numWord(base + i), '${base + i}', _palette[i % _palette.length]),
    ];

/* ------------------------------------------------------------------ */
/*  Word sets — from the morning spec + Jeremy's 17:07 refinements    */
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

/// Full A-Z, every letter, spoken by letter name.
final _abc = Category('ABC', '🔤', const Color(0xFFEC407A), [
  for (var i = 0; i < 26; i++)
    Saying(
      String.fromCharCode(65 + i),
      String.fromCharCode(65 + i),
      _palette[i % _palette.length],
    ),
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

/// 0-9 direct tiles, decade drill-downs to 100.
final _numbers = Category('Numbers', '🔢', const Color(0xFFFFA726), [
  Saying('zero', '0', _palette[0]),
  for (var i = 1; i <= 9; i++)
    Saying(_numWord(i), '$i', _palette[i % _palette.length]),
  for (var b = 10; b <= 90; b += 10)
    Saying(
      _numWord(b),
      '$b',
      _palette[(b ~/ 10) % _palette.length],
      sub: _decade(b),
      subTitle: '$b to ${b + 9}',
    ),
  Saying('one hundred', '100', _palette[9]),
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

final _categories = <Category>[
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
    try {
      await HapticFeedback.lightImpact();
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          const cols = 4;
          const spacing = 6.0;
          const pad = 8.0;
          final rows = (_categories.length / cols).ceil();
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
            itemCount: _categories.length,
            itemBuilder: (context, i) {
              final cat = _categories[i];
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
                        speak: _speak,
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: _EmojiBadge(display: category.emoji),
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Text(
                    category.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                    ),
                  ),
                ),
              ),
            ],
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
  final Future<void> Function(String) speak;

  const WordGridScreen({
    super.key,
    required this.title,
    required this.emoji,
    required this.color,
    required this.sayings,
    required this.speak,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          '$emoji $title',
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
                speak: speak,
                onDecadeTap: (Saying d) {
                  speak(d.label);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WordGridScreen(
                        title: d.subTitle ?? d.label,
                        emoji: d.emoji,
                        color: d.color,
                        sayings: d.sub!,
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
  final Future<void> Function(String) speak;
  final void Function(Saying) onDecadeTap;

  const _WordTile({
    required this.saying,
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: _EmojiBadge(display: saying.emoji),
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Text(
                    saying.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// White circle badge so the glyph always stands out from the tile color.
class _EmojiBadge extends StatelessWidget {
  final String display;

  const _EmojiBadge({required this.display});

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
            display,
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
