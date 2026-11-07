import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

// Sky Tower: a block slides back and forth over the top of your tower. Tap
// to drop it. Whatever hangs over the edge is chopped off and falls, so the
// blocks get smaller unless you drop them right on top.

const double kBlockH = 0.5; // how tall each block is
const double kStartSize = 3; // the first block is 3 x 3
const double kSlideRange = 4.2; // how far a block slides out each way
const double kPerfectGap = 0.12; // closer than this snaps on perfectly
const int kGrowAfter = 3; // perfects in a row before blocks grow back
const double kGrowBy = 0.2;

/// One block in the tower. x and z are the middle; w runs along x and d
/// along z.
class Slab {
  double x, z, w, d;
  final int floor;
  Slab(this.x, this.z, this.w, this.d, this.floor);
}

/// A chopped-off piece tumbling down.
class Chunk {
  double x, y, z;
  final double w, d;
  final int floor;
  double vy = 0;
  final double vx, vz;
  double spin = 0;
  Chunk(this.x, this.y, this.z, this.w, this.d, this.floor, this.vx, this.vz);
}

enum TowerEvent { drop, perfect, grow, miss, newSky }

class TowerGame {
  final List<Slab> stack = [Slab(0, 0, kStartSize, kStartSize, 0)];
  final List<Chunk> chunks = [];
  final List<TowerEvent> events = [];

  /// The block sliding over the top, or null once the game is over.
  Slab? moving;
  bool alongX = true;
  double _t = 0;
  int perfects = 0; // in a row
  int perfectTotal = 0;
  bool over = false;
  double clock = 0;

  TowerGame() {
    _next();
  }

  int get floors => stack.length - 1;
  Slab get top => stack.last;

  /// How fast the block slides: it speeds up as the tower grows.
  double get speed => min(5.5, 2.4 + floors * 0.06);

  /// Coins for this game: one per floor and two more per perfect drop.
  int get coins => floors + perfectTotal * 2;

  void _next() {
    alongX = !alongX;
    final t = top;
    // Start at the far end so the first pass slides in towards the tower.
    _t = 0;
    moving = Slab(
      alongX ? t.x - kSlideRange : t.x,
      alongX ? t.z : t.z - kSlideRange,
      t.w,
      t.d,
      stack.length,
    );
  }

  void step(double dt) {
    clock += dt;
    final m = moving;
    if (m != null && !over) {
      _t += dt * speed;
      // Bounce back and forth: 0..2R..0 along the path.
      final p = _t % (kSlideRange * 4);
      final off = p < kSlideRange * 2 ? p : kSlideRange * 4 - p;
      if (alongX) {
        m.x = top.x - kSlideRange + off;
      } else {
        m.z = top.z - kSlideRange + off;
      }
    }
    for (final c in chunks) {
      c.vy -= 18 * dt;
      c.y += c.vy * dt;
      c.x += c.vx * dt;
      c.z += c.vz * dt;
      c.spin += dt * 2.5;
    }
    chunks.removeWhere((c) => c.y < top.floor * kBlockH - 25);
  }

  /// Tap! Drops the sliding block onto the tower.
  void drop() {
    final m = moving;
    if (m == null || over) return;
    final t = top;
    final gap = alongX ? m.x - t.x : m.z - t.z;
    final size = alongX ? t.w : t.d;
    final y = m.floor * kBlockH;
    if (gap.abs() >= size) {
      // Missed the tower completely.
      chunks.add(Chunk(m.x, y, m.z, m.w, m.d, m.floor, 0, 0));
      moving = null;
      over = true;
      events.add(TowerEvent.miss);
      return;
    }
    if (gap.abs() < kPerfectGap) {
      // Spot on: it snaps right on top.
      m
        ..x = t.x
        ..z = t.z;
      perfects++;
      perfectTotal++;
      events.add(TowerEvent.perfect);
      if (perfects >= kGrowAfter) {
        // A run of perfects grows the blocks back a bit, on the side
        // that's been chopped the most.
        if (m.w < kStartSize || m.d < kStartSize) {
          if (m.w <= m.d) {
            m.w = min(kStartSize, m.w + kGrowBy);
          } else {
            m.d = min(kStartSize, m.d + kGrowBy);
          }
          events.add(TowerEvent.grow);
        }
      }
    } else {
      perfects = 0;
      final keep = size - gap.abs();
      final side = gap.sign;
      if (alongX) {
        final cut = m.w - keep;
        final keptX = t.x + gap / 2;
        chunks.add(
          Chunk(
            keptX + side * (keep / 2 + cut / 2),
            y,
            m.z,
            cut,
            m.d,
            m.floor,
            side * 1.2,
            0,
          ),
        );
        m
          ..x = keptX
          ..w = keep;
      } else {
        final cut = m.d - keep;
        final keptZ = t.z + gap / 2;
        chunks.add(
          Chunk(
            m.x,
            y,
            keptZ + side * (keep / 2 + cut / 2),
            m.w,
            cut,
            m.floor,
            0,
            side * 1.2,
          ),
        );
        m
          ..z = keptZ
          ..d = keep;
      }
      events.add(TowerEvent.drop);
    }
    stack.add(m);
    if (floors % 25 == 0) events.add(TowerEvent.newSky);
    _next();
  }
}

/// How high you are, as a name for the sky.
String skyName(int floors) {
  if (floors >= 100) return 'Deep Space';
  if (floors >= 75) return 'The Moon';
  if (floors >= 50) return 'Space';
  if (floors >= 25) return 'The Clouds';
  return 'The City';
}

/// Colours for the blocks. Each theme is bought with coins.
class TowerTheme {
  final String id;
  final String name;
  final int price;
  final String blurb;
  const TowerTheme(this.id, this.name, this.price, this.blurb);
}

const List<TowerTheme> kThemes = [
  TowerTheme('rainbow', 'Rainbow', 0, 'Every colour, floor by floor.'),
  TowerTheme('candy', 'Candy', 100, 'Pink and minty sweets.'),
  TowerTheme('ice', 'Ice', 250, 'Cool blue ice blocks.'),
  TowerTheme('lava', 'Lava', 500, 'Hot glowing rock.'),
  TowerTheme('gold', 'Gold', 1000, 'A tower of solid gold!'),
];

TowerTheme themeById(String id) =>
    kThemes.firstWhere((t) => t.id == id, orElse: () => kThemes.first);

class TowerSave {
  TowerSave._();
  static final TowerSave instance = TowerSave._();
  SharedPreferences? _prefs;

  int coins = 0;
  int best = 0;
  int games = 0;
  Set<String> themes = {'rainbow'};
  String theme = 'rainbow';

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString('sky_tower_save');
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      coins = m['coins'] as int? ?? 0;
      best = m['best'] as int? ?? 0;
      games = m['games'] as int? ?? 0;
      themes = {...(m['themes'] as List? ?? []).cast<String>(), 'rainbow'};
      theme = m['theme'] as String? ?? 'rainbow';
      if (!themes.contains(theme)) theme = 'rainbow';
    } catch (_) {
      // A broken save starts fresh.
    }
  }

  Future<void> save() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
      'sky_tower_save',
      jsonEncode({
        'coins': coins,
        'best': best,
        'games': games,
        'themes': themes.toList(),
        'theme': theme,
      }),
    );
    await _prefs!.setInt('highscore_sky_tower', best);
  }
}
