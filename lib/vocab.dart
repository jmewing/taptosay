import 'package:flutter/material.dart';

/// Data model for the TapToSay vocabulary: `Category` (home tile + word grid)
/// and `Saying` (one phrase/word). Both carry a `fromJson` factory so the
/// tablet can build them from the server's `/api/config/sync` payload.

/// Parse a `#RRGGBB` hex string into a Flutter [Color]. Falls back to grey.
Color colorFromHex(String? hex) {
  if (hex == null) return const Color(0xFF90A4AE);
  var s = hex.replaceFirst('#', '').trim();
  if (s.length == 6) s = 'FF$s'; // add opaque alpha
  final v = int.tryParse(s, radix: 16);
  return v == null ? const Color(0xFF90A4AE) : Color(v);
}

/// One phrase/word with a big display glyph. The unit of speech.
class Saying {
  final String label; // spoken text
  final String emoji; // shown on the white badge (emoji, letter, or number) — fallback
  final String? symbol; // Mulberry AAC symbol key (served as PNG) — overrides emoji
  final int? mediaId; // uploaded custom photo id — overrides emoji
  final Color color;
  final List<Saying>? sub; // drill-down tiles (e.g. decade 20 -> 20..29)
  final String? subTitle; // label for the drill-down screen
  const Saying(this.label, this.emoji, this.color,
      {this.symbol, this.mediaId, this.sub, this.subTitle});

  factory Saying.fromJson(Map<String, dynamic> j) {
    return Saying(
      j['label'] as String? ?? '',
      j['emoji'] as String? ?? '',
      colorFromHex(j['color'] as String?), 
      symbol: j['symbol'] as String?,
      mediaId: _intOrNull(j['media_id']),
      sub: (j['sub'] as List?)
          ?.map((e) => Saying.fromJson(e as Map<String, dynamic>))
          .toList(),
      subTitle: j['subTitle'] as String?,
    );
  }
}

/// A category: title on the home screen + its word grid.
class Category {
  final String name;
  final String emoji;
  final String? symbol;
  final int? mediaId;
  final Color color;
  final List<Saying> sayings;
  const Category(this.name, this.emoji, this.color, this.sayings,
      {this.symbol, this.mediaId});

  factory Category.fromJson(Map<String, dynamic> j) {
    return Category(
      j['name'] as String? ?? '',
      j['emoji'] as String? ?? '',
      colorFromHex(j['color'] as String?),
      (j['sayings'] as List?)
              ?.map((e) => Saying.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      symbol: j['symbol'] as String?,
      mediaId: _intOrNull(j['media_id']),
    );
  }
}

int? _intOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  return s.isEmpty ? null : int.tryParse(s.replaceAll(RegExp(r'\D'), ''));
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
/*  Built-in fallback vocabulary (used when the tablet is offline     */
/*  and has no cached config). Mirrors db/default-vocab.json.          */
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

/// Built-in fallback vocabulary.
final List<Category> builtInCategories = <Category>[
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
