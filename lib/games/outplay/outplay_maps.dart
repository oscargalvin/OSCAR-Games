import 'dart:math';
import 'dart:ui';

/// What makes a map special.
enum MapHazard { none, lava, cars }

/// A map drawn as rows of characters:
///   `#` stone wall, `R` red brick, `B` blue panel, `C` crate, `K` dark rock
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

  const OutplayMap({
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
      c == '#' || c == 'R' || c == 'B' || c == 'C' || c == 'K';

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
];

OutplayMap mapById(String id) =>
    kArenaMaps.firstWhere((m) => m.id == id, orElse: () => kArenaMaps.first);
