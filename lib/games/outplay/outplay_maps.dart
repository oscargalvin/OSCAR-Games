import 'dart:math';
import 'dart:ui';

/// What makes a map special.
enum MapHazard { none, lava, cars, ghosts, bouncy, water, karts }

/// A map drawn as rows of characters:
///   `#` stone wall, `R` red brick, `B` blue panel, `C` crate, `K` dark rock,
///   `W` spooky wallpaper, `D` bookshelf, `X` croc rubber, `J` croc charm,
///   `A` arena crowd, `P` red corner post, `U` blue corner post, `N` white post
///   `G` hedge, `Y` tyre wall, `H` hay bale
///   `.` floor, `S` a place people can start
///   `Q` `F` `O` (Duel Zone only) the quick play, free-for-all and online pads
class OutplayMap {
  final String id;
  final String name;
  final String blurb;
  final List<String> rows;
  final MapHazard hazard;
  final Color skyTop;
  final Color skyBottom;
  final Color floorA;
  final Color floorB;

  /// How tall the walls are (1 is normal; a croc shoe towers over you).
  final double wallHeight;

  /// Where the croc's heel strap crosses the shoe, if it has one.
  final double? strapX;

  /// Where the two sides start in a 1v1 or team game, if the map says.
  final List<Offset>? cornerSpots;

  /// The boxing ring's corners (top-left and bottom-right posts), if any.
  Rect? get ring {
    Offset? a, b;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final c = rows[y][x];
        if (c != 'P' && c != 'U' && c != 'N') continue;
        final p = Offset(x + 0.5, y + 0.5);
        a = a == null ? p : Offset(min(a.dx, p.dx), min(a.dy, p.dy));
        b = b == null ? p : Offset(max(b.dx, p.dx), max(b.dy, p.dy));
      }
    }
    return a == null ? null : Rect.fromPoints(a, b!);
  }

  const OutplayMap({
    this.wallHeight = 1,
    this.strapX,
    this.cornerSpots,
    required this.id,
    required this.name,
    required this.blurb,
    required this.rows,
    this.hazard = MapHazard.none,
    required this.skyTop,
    required this.skyBottom,
    required this.floorA,
    required this.floorB,
  });

  int get width => rows.first.length;
  int get height => rows.length;

  String cell(int x, int y) {
    if (y < 0 || y >= height || x < 0 || x >= width) return '#';
    return rows[y][x];
  }

  bool solidAt(int x, int y) => isSolid(cell(x, y));

  static bool isSolid(String c) =>
      c == '#' ||
      c == 'R' ||
      c == 'B' ||
      c == 'C' ||
      c == 'K' ||
      c == 'W' ||
      c == 'D' ||
      c == 'X' ||
      c == 'J' ||
      c == 'A' ||
      c == 'P' ||
      c == 'U' ||
      c == 'N' ||
      c == 'G' ||
      c == 'Y' ||
      c == 'H';

  Offset get centre => Offset(width / 2, height / 2);

  List<Offset> spawnPoints() {
    final out = <Offset>[];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (rows[y][x] == 'S') out.add(Offset(x + 0.5, y + 0.5));
      }
    }
    return out;
  }

  Offset? padCentre(String pad) {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (rows[y][x] == pad) return Offset(x + 0.5, y + 0.5);
      }
    }
    return null;
  }

  /// Volcano lava creeps in from the edge, leaving the summit safe.
  double safeRadius(double time) => max(2.6, 10.5 - time * 0.09);

  bool isLava(Offset p, double time) =>
      hazard == MapHazard.lava && (p - centre).distance > safeRadius(time);

  /// The road on Runway runs left to right across these rows.
  static const double roadTop = 5;
  static const double roadBottom = 8;
  bool onRoad(Offset p) =>
      hazard == MapHazard.cars && p.dy >= roadTop && p.dy <= roadBottom;

  /// Lazy Lake: an oval lake in the middle of the map.
  static const double lakeRx = 6.6;
  static const double lakeRy = 4.6;

  /// How far out from the middle of the lake you are (under 1 is water).
  double lakeDistance(Offset p) {
    final dx = (p.dx - centre.dx) / lakeRx, dy = (p.dy - centre.dy) / lakeRy;
    return sqrt(dx * dx + dy * dy);
  }

  bool isWater(Offset p) => hazard == MapHazard.water && lakeDistance(p) < 1;

  /// Crazy Goat Cars: the go-karts race round a loop with rounded corners.
  /// Its middle line is a rounded box 2 squares in from the tyre wall.
  static const double trackHalfWidth = 2;
  static const double loopInset = 3;
  static const double loopCorner = 2.5;

  /// How far [p] is from the middle of the race track (negative = inside).
  double trackOffset(Offset p) {
    final hx = width / 2 - loopInset - loopCorner;
    final hy = height / 2 - loopInset - loopCorner;
    final qx = (p.dx - centre.dx).abs() - hx;
    final qy = (p.dy - centre.dy).abs() - hy;
    final outside = sqrt(pow(max(qx, 0.0), 2) + pow(max(qy, 0.0), 2));
    return outside + min(max(qx, qy), 0.0) - loopCorner;
  }

  bool onTrack(Offset p) =>
      hazard == MapHazard.karts && trackOffset(p).abs() < trackHalfWidth;

  /// Length of the race loop.
  double get loopLength {
    final w = width - 2 * loopInset - 2 * loopCorner;
    final h = height - 2 * loopInset - 2 * loopCorner;
    return 2 * (w + h) + 2 * pi * loopCorner;
  }

  /// The point [s] squares along the race loop (going clockwise).
  Offset loopPoint(double s) {
    final r = loopCorner;
    final l = loopInset + r, t = loopInset + r;
    final rgt = width - loopInset - r, btm = height - loopInset - r;
    final w = rgt - l, h = btm - t, arc = pi * r / 2;
    var d = s % loopLength;
    if (d < 0) d += loopLength;
    // Top straight, going right.
    if (d < w) return Offset(l + d, t - r);
    d -= w;
    if (d < arc) {
      return Offset(rgt, t) + Offset.fromDirection(-pi / 2 + d / r, r);
    }
    d -= arc;
    if (d < h) return Offset(rgt + r, t + d);
    d -= h;
    if (d < arc) return Offset(rgt, btm) + Offset.fromDirection(d / r, r);
    d -= arc;
    if (d < w) return Offset(rgt - d, btm + r);
    d -= w;
    if (d < arc) {
      return Offset(l, btm) + Offset.fromDirection(pi / 2 + d / r, r);
    }
    d -= arc;
    if (d < h) return Offset(l - r, btm - d);
    d -= h;
    return Offset(l, t) + Offset.fromDirection(pi + d / r, r);
  }
}

const OutplayMap kDuelZone = OutplayMap(
  id: 'duel_zone',
  name: 'Duel Zone',
  blurb: 'Walk onto a glowing pad to start a game.',
  rows: [
    'BBBBBBBBBBBBB',
    'B...........B',
    'B..Q.....F..B',
    'B...........B',
    'B...........B',
    'B.....O.....B',
    'B...........B',
    'B...........B',
    'B.....S.....B',
    'B...........B',
    'BBBBBBBBBBBBB',
  ],
  skyTop: Color(0xFF1A1440),
  skyBottom: Color(0xFF5B3FA8),
  floorA: Color(0xFF2E2A5C),
  floorB: Color(0xFF39346E),
);

const List<OutplayMap> kArenaMaps = [
  OutplayMap(
    id: 'warehouse',
    name: 'Warehouse',
    blurb: 'Crates to hide behind.',
    rows: [
      '################',
      '#S......S......#',
      '#..CC......CC..#',
      '#..C........C..#',
      '#......CC......#',
      '#S..........S..#',
      '#....C....C....#',
      '#....C....C....#',
      '#..............#',
      '#S.....CC.....S#',
      '#..C........C..#',
      '#..CC......CC..#',
      '#S......S......#',
      '################',
    ],
    skyTop: Color(0xFF263238),
    skyBottom: Color(0xFF546E7A),
    floorA: Color(0xFF4E5560),
    floorB: Color(0xFF59616D),
  ),
  OutplayMap(
    id: 'volcano',
    name: 'Volcano',
    blurb: 'Lava rises! Climb to the top to stay safe.',
    hazard: MapHazard.lava,
    rows: [
      'KKKKKKKKKKKKKKKKKKKKKKK',
      'KKKKKKKKK.....KKKKKKKKK',
      'KKKKKK.....S.....KKKKKK',
      'KKKKK...S.........KKKKK',
      'KKKK...............KKKK',
      'KKK..S...........S..KKK',
      'KK...................KK',
      'KK.....K.......K.....KK',
      'KK.................S.KK',
      'K..........K..........K',
      'K.....................K',
      'K.S......K...K......S.K',
      'K.....................K',
      'K..........K..........K',
      'KK.S.................KK',
      'KK.....K.......K.....KK',
      'KK...................KK',
      'KKK..S...........S..KKK',
      'KKKK...............KKKK',
      'KKKKK.........S...KKKKK',
      'KKKKKK.....S.....KKKKKK',
      'KKKKKKKKK.....KKKKKKKKK',
      'KKKKKKKKKKKKKKKKKKKKKKK',
    ],
    skyTop: Color(0xFF3E0E0E),
    skyBottom: Color(0xFFFF7043),
    floorA: Color(0xFF3E2C28),
    floorB: Color(0xFF4A3530),
  ),
  OutplayMap(
    id: 'runway',
    name: 'Runway',
    blurb: 'Cars zoom down the road. Jump over them!',
    hazard: MapHazard.cars,
    rows: [
      '################################',
      '#S......S.......S.......S......#',
      '#....CC.......CC.......CC......#',
      '#..............................#',
      '#..S.......S.......S.......S...#',
      '#..............................#',
      '#..............................#',
      '#..............................#',
      '#..S.......S.......S.......S...#',
      '#..............................#',
      '#....CC.......CC.......CC......#',
      '#S......S.......S.......S......#',
      '################################',
    ],
    skyTop: Color(0xFF1E88E5),
    skyBottom: Color(0xFFBBDEFB),
    floorA: Color(0xFF66BB6A),
    floorB: Color(0xFF5CAE60),
  ),
  OutplayMap(
    id: 'courtyard',
    name: 'Courtyard',
    blurb: 'Brick walls and long hallways.',
    rows: [
      'RRRRRRRRRRRRRRRR',
      'R.S....RR....S.R',
      'R..............R',
      'R..RR......RR..R',
      'R..R...S....R..R',
      'R......RR......R',
      'RS....RRRR....SR',
      'RS....RRRR....SR',
      'R......RR......R',
      'R..R....S...R..R',
      'R..RR......RR..R',
      'R..............R',
      'R.S....RR....S.R',
      'RRRRRRRRRRRRRRRR',
    ],
    skyTop: Color(0xFF0D47A1),
    skyBottom: Color(0xFF90CAF9),
    floorA: Color(0xFF8D8270),
    floorB: Color(0xFF9A8F7C),
  ),
  OutplayMap(
    id: 'mansion',
    name: 'Haunted Mansion',
    blurb: 'Spooky rooms and ghosts. Don\'t touch the ghosts!',
    hazard: MapHazard.ghosts,
    rows: [
      'WWWWWWWWWWWWWWWWWWWW',
      'WS.....W.....W....SW',
      'W......W.....W.....W',
      'W..DD......S....DD.W',
      'W..................W',
      'WWW..WWWW..WWWW..WWW',
      'W..................W',
      'W.S..D........D..S.W',
      'W....D...WW...D....W',
      'W........WW........W',
      'WWW..WWWW..WWWW..WWW',
      'W..................W',
      'W..DD.....S.....DD.W',
      'W......W.....W.....W',
      'WS.....W.....W....SW',
      'WWWWWWWWWWWWWWWWWWWW',
    ],
    skyTop: Color(0xFF0D0221),
    skyBottom: Color(0xFF3A1C5C),
    floorA: Color(0xFF3E2723),
    floorB: Color(0xFF4E342E),
  ),
  OutplayMap(
    id: 'crocs',
    name: 'Crazy Crocs',
    blurb:
        'You\'re tiny, inside a giant croc shoe! The squishy footbed makes '
        'you jump higher.',
    hazard: MapHazard.bouncy,
    wallHeight: 2.4,
    strapX: 27.5,
    rows: [
      'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
      'XXXXXXX.......XXXXXXXXXXXXXXXXXXXXXX',
      'XXXXX....................XXXXXXXXXXX',
      'XXXX..S.......S................XXXXX',
      'XXX......J.............J....S...XXXX',
      'XXX..............................XXX',
      'XX..................S.............XX',
      'XX................................XX',
      'XX.S.............J..............S.XX',
      'XX................................XX',
      'XX..................S.............XX',
      'XXX..............................XXX',
      'XXX......J.............J....S...XXXX',
      'XXXX..S.......S................XXXXX',
      'XXXXX....................XXXXXXXXXXX',
      'XXXXXXX.......XXXXXXXXXXXXXXXXXXXXXX',
      'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
    ],
    skyTop: Color(0xFF1E88E5),
    skyBottom: Color(0xFFB3E5FC),
    floorA: Color(0xFF9CCC65),
    floorB: Color(0xFF97C760),
  ),
  OutplayMap(
    id: 'arena',
    name: 'Arena',
    blurb: 'A boxing ring with a cheering crowd. Red corner vs blue corner!',
    cornerSpots: [Offset(7.6, 7.6), Offset(14.4, 14.4)],
    wallHeight: 1.6,
    rows: [
      'AAAAAAAAAAAAAAAAAAAAAA',
      'A....................A',
      'A.........S..........A',
      'A..S..............S..A',
      'A....................A',
      'A....................A',
      'A.....P........N.....A',
      'A....................A',
      'A....................A',
      'A........S..S........A',
      'A.S..................A',
      'A..................S.A',
      'A........S..S........A',
      'A....................A',
      'A....................A',
      'A.....N........U.....A',
      'A....................A',
      'A....................A',
      'A..S..............S..A',
      'A..........S.........A',
      'A....................A',
      'AAAAAAAAAAAAAAAAAAAAAA',
    ],
    skyTop: Color(0xFF05070F),
    skyBottom: Color(0xFF1C2541),
    floorA: Color(0xFF2B2D42),
    floorB: Color(0xFF32344D),
  ),
  OutplayMap(
    id: 'lake',
    name: 'Lazy Lake',
    blurb:
        'A sunny lake. Swim to heal for 3 seconds, but stay in longer than '
        '5 and you drown!',
    hazard: MapHazard.water,
    rows: [
      'GGGGGGGGGGGGGGGGGGGGGGGGGG',
      'G.S.....S.......S......S.G',
      'G........................G',
      'G..G..........S.......G..G',
      'G........................G',
      'G.S....................S.G',
      'G........................G',
      'GS......................SG',
      'G........................G',
      'GG......................GG',
      'G........................G',
      'G........................G',
      'G.S....................S.G',
      'G........................G',
      'G..G.......S..........G..G',
      'G........................G',
      'G.S.....S.......S......S.G',
      'GGGGGGGGGGGGGGGGGGGGGGGGGG',
    ],
    skyTop: Color(0xFF29B6F6),
    skyBottom: Color(0xFFE1F5FE),
    floorA: Color(0xFF7CB342),
    floorB: Color(0xFF76AC3E),
  ),
  OutplayMap(
    id: 'leaf_maze',
    name: 'Leaf Maze',
    blurb: 'A twisty maze of leafy hedges. Sneak round corners and ambush!',
    rows: [
      'GGGGGGGGGGGGGGGGGGGGGGGGG',
      'GS..........S..........SG',
      'GGG.G.GGG.GGG.GGGGGGGGG.G',
      'G...G.........G.........G',
      'G.GGG.G.GGGGGGG.G.GGGGG.G',
      'G.G...G.G.......G...G.G.G',
      'G.G.GGG.GGG.GGGGG.G.G.G.G',
      'G.G.............G.G.....G',
      'G.G.GGGGG.......G.G.GGG.G',
      'GSG.....G...S.....G...GSG',
      'G.GGG.G.G.......GGG.G.G.G',
      'G.....G.G...........G...G',
      'GGG.G.G.G.G.G.GGGGG.G.GGG',
      'G.......G.G.G...........G',
      'G.GGGGGGG.G.GGG.G.GGGGG.G',
      'G.G.............G.......G',
      'G.G.GGGGGGG.G.G.G.G.G.G.G',
      'GS..G.......S.....G...GSG',
      'GGGGGGGGGGGGGGGGGGGGGGGGG',
    ],
    skyTop: Color(0xFF4FC3F7),
    skyBottom: Color(0xFFDCEDC8),
    floorA: Color(0xFF8D6E63),
    floorB: Color(0xFF7CB342),
  ),
  OutplayMap(
    id: 'goat_karts',
    name: 'Crazy Goat Cars',
    blurb:
        'A race track full of go-karts driven by goats. Get hit and you go '
        'flying!',
    hazard: MapHazard.karts,
    rows: [
      'YYYYYYYYYYYYYYYYYYYYYYYYYYYYYY',
      'Y............................Y',
      'Y............................Y',
      'Y............................Y',
      'Y............................Y',
      'Y..................S.........Y',
      'Y.............H..............Y',
      'Y......S..............S......Y',
      'Y........HH..................Y',
      'Y................S...........Y',
      'Y...........S................Y',
      'Y..................HH........Y',
      'Y......S..............S......Y',
      'Y..............H.............Y',
      'Y.........S..................Y',
      'Y............................Y',
      'Y............................Y',
      'Y............................Y',
      'Y............................Y',
      'YYYYYYYYYYYYYYYYYYYYYYYYYYYYYY',
    ],
    skyTop: Color(0xFF1E88E5),
    skyBottom: Color(0xFFFFE0B2),
    floorA: Color(0xFF8BC34A),
    floorB: Color(0xFF85BC45),
  ),
];

OutplayMap mapById(String id) =>
    kArenaMaps.firstWhere((m) => m.id == id, orElse: () => kArenaMaps.first);
