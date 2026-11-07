import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/save_service.dart';
import '../../services/sound_service.dart';
import '../../widgets/full_screen_game.dart';
import 'pie_splat_net.dart';
import '../boost_ball/boost_ball_3d.dart' show V3;
import '../outplay/outplay_3d.dart' show Scene3D, kUp;
import 'pie_splat_3d.dart';

const String kPieSplatId = 'pie_splat';
const double _gravity = 14;

enum PieMode { comedy, survival, cakeGrab, kingOfCake, hotPie, frenzy }

extension PieModeInfo on PieMode {
  String get title => switch (this) {
    PieMode.comedy => '😂 Comedy',
    PieMode.survival => '💀 Survival',
    PieMode.cakeGrab => '🥧 Pie Grab',
    PieMode.kingOfCake => '👑 King of the Pie',
    PieMode.hotPie => '💣 Hot Pie',
    PieMode.frenzy => '🌪 Pie Frenzy',
  };

  String get blurb => switch (this) {
    PieMode.comedy => 'Most points in 90s wins',
    PieMode.survival => '3 splats and you are out',
    PieMode.cakeGrab => 'Run and grab the most pies',
    PieMode.kingOfCake => 'Stand on the golden circle to score',
    PieMode.hotPie => 'Splat someone to pass the ticking pie!',
    PieMode.frenzy => 'Triple pies, super fast, 60 seconds',
  };

  String get howTo => switch (this) {
    PieMode.comedy => "Splat the show-offs. Dodge their pies. Don't splat the guests!",
    PieMode.survival => 'SURVIVAL: 3 splats and you are out! Last one standing wins.',
    PieMode.cakeGrab => 'Grab pies! Get splatted and you drop half of them.',
    PieMode.kingOfCake => 'Stand on the golden circle to score points. Splat anyone who tries to take it!',
    PieMode.hotPie => 'Got the HOT PIE? Splat someone to pass it on before it goes KABOOM!',
    PieMode.frenzy => 'PIE FRENZY! Triple pies all the time. Go go go!',
  };
}

/// How a party is set up: the mode, how hard the bots are, and who plays.
class PieSetup {
  const PieSetup({
    this.mode = PieMode.comedy,
    this.difficulty = 1,
    this.players = 4,
    this.teams = 0,
  });

  final PieMode mode;

  /// 0 easy, 1 medium, 2 hard.
  final int difficulty;

  /// Pie fighters in a free-for-all (when [teams] is 0).
  final int players;

  /// 0 = everyone for themselves, otherwise 2 to 5 teams.
  final int teams;

  /// 5 teams of 3 is 15 people; the other team games have 12.
  int get fighters => teams == 0 ? players : (teams == 5 ? 15 : 12);

  double get seconds => switch (mode) {
    PieMode.survival => 120,
    PieMode.hotPie => 180,
    PieMode.frenzy => 60,
    _ => 90,
  };

  /// The setup for an online party with [humans] real players: each player
  /// gets their own team (5 players = 15 people), or with 1 player it's
  /// everyone for themselves with 12 people.
  static PieSetup online(int humans, int mode, int difficulty) => PieSetup(
    mode: PieMode.values[mode.clamp(0, PieMode.values.length - 1)],
    difficulty: difficulty,
    players: 12,
    teams: humans >= 2 ? humans : 0,
  );
}

const List<String> kTeamNames = ['Red', 'Blue', 'Green', 'Yellow', 'Purple'];
const List<Color> kTeamColors = [
  Color(0xFFFF5252),
  Color(0xFF448AFF),
  Color(0xFF69F0AE),
  Color(0xFFFFD740),
  Color(0xFFE040FB),
];

/// Someone at the party: you, a pie-throwing goof, or an innocent stranger.
class Guy {
  Guy(this.kind, this.x, this.y, {this.player = false}) : tx = x, ty = y;
  final Kind kind;

  /// This is you, on this phone.
  bool player;

  /// A real person (you, or someone online), not a bot.
  bool human = false;
  String? name;
  double inX = 0, inY = 0; // their stick, online
  int cakes = 0;
  // Where the host says they are (online guests glide towards it).
  double nx = 0, ny = 0;
  double x, y;
  double angle = pi / 2;
  double walk = 0;
  double vx = 0, vy = 0;
  double throwT = 0;
  double splatAge = -1;
  double dizzy = 0;
  double dashT = 0, dashCd = 0;
  double dashX = 0, dashY = 0;
  double throwCd = 1.5;
  int score = 0, splats = 0, oops = 0;
  int triple = 0;
  int team = 0;
  int lives = 3;
  double zoneT = 0;
  bool out = false;
  double outAt = 0;

  /// Just been splatted: can't be splatted again for a moment.
  double safe = 0;
  String? line;
  double lineT = 0;
  double tx, ty;
  double think = 0;
  Guy? target;

  bool get bystander => kind.bystander;
  bool get protected => kind.protected;
  double get radius => kind == Kind.puppy ? 0.45 : 0.4 * kind.size + 0.08;

  void say(String text, [double time = 1.8]) {
    line = text;
    lineT = time;
  }
}

class _Pie {
  _Pie(this.x, this.y, this.z, this.vx, this.vy, this.vz, this.by);
  double x, y, z, vx, vy, vz;
  final Guy by;
  double spin = 0;
  bool dodgeChecked = false;
}

class _Float {
  _Float(this.text, this.pos, this.color, {this.size = 20, this.life = 1.1});
  final String text;
  final V3 pos;
  final Color color;
  final double size;
  final double life;
  double age = 0;
}

class _Blob {
  _Blob(this.x, this.y, this.r, this.seed);
  final double x, y, r, seed;
  double age = 0;
}

class TeamResult {
  TeamResult(this.team);
  final int team;
  final List<Guy> members = [];
  int get score => members.fold(0, (n, g) => n + g.score);
  int get cakes => members.fold(0, (n, g) => n + g.cakes);
  int get alive => members.where((g) => !g.out).length;
  int get lives => members.fold(0, (n, g) => n + (g.out ? 0 : g.lives));
  double get lastOut => members.fold(0.0, (n, g) => max(n, g.out ? g.outAt : 1e4));
}

class _Cushion {
  _Cushion(this.x, this.y);
  double x, y;
  double away = 0; // > 0 while it is waiting to come back
}

/// Pie Splat Party in 3D: a garden party pie fight.
class PieSplatGameScreen extends StatefulWidget {
  const PieSplatGameScreen({
    super.key,
    this.seed,
    this.setup = const PieSetup(),
    this.net,
    this.humans = const [],
  });

  /// For tests: makes the party play out the same every time.
  final int? seed;
  final PieSetup setup;

  /// Online: the room, and everyone's (id, name), room maker first.
  final PieNet? net;
  final List<(String, String)> humans;

  @override
  State<PieSplatGameScreen> createState() => PieSplatGameState();
}

class PieSplatGameState extends State<PieSplatGameScreen>
    with SingleTickerProviderStateMixin, FullScreenGame {
  late final Random _rnd = Random(widget.seed);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final FocusNode _focus = FocusNode();

  final List<Guy> guys = [];
  late Guy me;
  final List<_Pie> _pies = [];
  final List<_Float> _floats = [];
  final List<_Blob> _blobs = [];
  final List<_Cushion> _cushions = [];
  (double, double)? _golden; // the triple-pie pick-up
  double _goldenIn = 10;

  PieSetup get setup => widget.setup;
  bool get survival => setup.mode == PieMode.survival;
  bool get kingMode => setup.mode == PieMode.kingOfCake;
  bool get hotMode => setup.mode == PieMode.hotPie;
  bool get frenzy => setup.mode == PieMode.frenzy;

  /// Modes where you get knocked out and the last one standing wins.
  bool get elimination => survival || hotMode;
  Guy? hotHolder;
  double hotT = 0;
  static const double kingR = 2.4;
  bool get cakeMode => setup.mode == PieMode.cakeGrab;
  PieNet? get net => widget.net;
  bool get online => net != null;
  bool get guest => online && !net!.isHost;
  final List<(double, double)> _cakes = [];
  double _cakeIn = 1;
  double _sendIn = 0;
  final List<Object> _events = [];
  String? _netNote;
  bool get teamGame => setup.teams > 0;
  late final bool big = setup.fighters > 6;
  late final double halfW = big ? 16 : 11, halfH = big ? 12 : 8;
  late final List<Rect> tables = big
      ? [
          for (final (x, y) in [(-9.0, 5.0), (9.0, 5.0), if (!kingMode) (0.0, 0.0), (-9.0, -5.0), (9.0, -5.0)])
            Rect.fromCenter(center: Offset(x, y), width: 2.6, height: 1.4),
        ]
      : [
          Rect.fromCenter(center: const Offset(-5.5, 2.5), width: 2.6, height: 1.4),
          Rect.fromCenter(center: const Offset(5.5, 2.5), width: 2.6, height: 1.4),
          Rect.fromCenter(center: const Offset(0, -3), width: 2.2, height: 1.2),
        ];

  // How tough the bots are.
  double get _botThrowGap => const [3.0, 2.1, 1.45][setup.difficulty];
  double get _botMiss => const [1.6, 1.0, 0.5][setup.difficulty];
  double get _botDodge => const [0.05, 0.18, 0.4][setup.difficulty];
  double get _botSpeed => const [2.6, 3.1, 3.8][setup.difficulty];
  double get _botLead => const [0.1, 0.35, 0.7][setup.difficulty];

  double _countdown = 2.4;
  late double _timeLeft = setup.seconds;
  double clock = 0;
  bool _over = false;
  double _overT = 0;
  bool _newBest = false;
  double _faceSplat = 0;
  double _shake = 0;

  // Controls.
  int? _stickId;
  Offset? _stickFrom, _stickAt;
  final Set<LogicalKeyboardKey> _keys = {};

  // Camera (smoothed).
  double _camX = 0, _camY = -5.5;

  @override
  void initState() {
    super.initState();
    _setup();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    if (online && !guest && !_over) net!.send({'t': 'abort'});
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setup() {
    guys.clear();
    final n = setup.fighters;
    final teams = teamGame ? setup.teams : n;
    me = Guy(Kind.chef, 0, 0, player: true);
    final fighters = <Guy>[me];
    var k = _rnd.nextInt(kGoofs.length);
    for (var i = 1; i < n; i++) {
      fighters.add(Guy(kGoofs[k++ % kGoofs.length], 0, 0));
    }
    // Hand out teams (in a free-for-all everyone is their own team), then
    // put each team in its own corner of the garden. You start at the front.
    for (var i = 0; i < n; i++) {
      final g = fighters[i];
      g.team = teamGame ? i % teams : i;
      final a = -pi / 2 + g.team * pi * 2 / teams;
      final members = fighters.where((o) => o.team == g.team).toList();
      final slot = members.indexOf(g);
      final rad = Offset(cos(a) * (halfW - 3), sin(a) * (halfH - 2.5));
      final side = Offset(-sin(a), cos(a));
      final row = slot ~/ 3, col = slot % 3 - (min(3, members.length) - 1) / 2;
      final at = rad + side * (col * 1.4) - Offset(cos(a), sin(a)) * (row * 1.4);
      g
        ..x = at.dx
        ..y = at.dy
        ..tx = at.dx
        ..ty = at.dy
        ..angle = a + pi
        ..throwCd = 2.5 + _rnd.nextDouble() * 2;
      if (g.player) g.throwCd = 0;
    }
    // Online, the first fighters are the real players: one per team.
    final humans = widget.humans.isEmpty ? [('me', 'You')] : widget.humans;
    final mine = online ? max(0, humans.indexWhere((h) => h.$1 == net!.myId)) : 0;
    for (var i = 0; i < fighters.length; i++) {
      final g = fighters[i];
      g.player = i == mine;
      g.human = i < humans.length;
      g.name = g.human && online ? humans[i].$2 : null;
      if (g.human) g.throwCd = 0;
    }
    me = fighters[mine];
    guys.addAll(fighters);
    guys.add(Guy(Kind.granny, -3, 0.5));
    guys.add(Guy(Kind.waiter, 3.5, -0.8));
    guys.add(Guy(Kind.puppy, 1.5, -2.5));
    guys.add(Guy(Kind.stranger, -1, 3));
    guys.add(Guy(Kind.dad, 2, 4.5));
    if (big) {
      guys.add(Guy(Kind.granny, 6, 8));
      guys.add(Guy(Kind.stranger, -6, -8));
    }
    for (final g in guys) {
      g.lives = 3;
      g.out = false;
    }
    _cushions
      ..clear()
      ..add(_Cushion(-halfW * 0.6, -halfH * 0.45))
      ..add(_Cushion(halfW * 0.65, -halfH * 0.1));
    if (big) {
      _cushions
        ..add(_Cushion(-halfW * 0.4, halfH * 0.7))
        ..add(_Cushion(halfW * 0.3, halfH * 0.6));
    }
    _pies.clear();
    _floats.clear();
    _blobs.clear();
    _golden = null;
    _goldenIn = 10;
    _cakes.clear();
    _cakeIn = 1;
    hotHolder = null;
    hotT = 0;
    for (final g in guys) {
      g.nx = g.x;
      g.ny = g.y;
    }
    _camX = me.x * 0.75;
    _camY = me.y;
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    setState(() {
      if (online) _network(dt);
      _update(dt);
    });
  }

  void _addFloat(_Float f) {
    _floats.add(f);
    if (online && !guest) {
      _events.add(['f', f.text, _r(f.pos.x), _r(f.pos.y), _r(f.pos.z), f.color.toARGB32(), f.size, f.life]);
    }
  }

  void _addBlob(_Blob b) {
    _blobs.add(b);
    if (online && !guest) _events.add(['b', _r(b.x), _r(b.y), b.r, b.seed.round()]);
  }

  static double _r(double v) => (v * 100).roundToDouble() / 100;
  static double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

  // ---------------------------------------------------------------- online

  void _network(double dt) {
    final n = net!;
    for (final m in n.take()) {
      final t = m['t'];
      if (!guest) {
        final g = _humanById(m['id']);
        if (g == null || g.player) continue;
        if (t == 'in') {
          g.inX = _d(m['x']).clamp(-1.0, 1.0);
          g.inY = _d(m['y']).clamp(-1.0, 1.0);
        } else if (t == 'th') {
          _humanThrow(g);
        } else if (t == 'dg') {
          _humanDodge(g);
        } else if (t == 'bye') {
          // They left: a bot takes over.
          g
            ..human = false
            ..name = '${g.name} (bot)';
        }
      } else {
        if (t == 'st') _applySnapshot(m);
        if ((t == 'hostLeft' || t == 'abort') && !_over) {
          _netNote = 'The party host left the game.';
          _over = true;
          _overT = 1;
        }
      }
    }
    if (guest) {
      _sendIn -= dt;
      if (_sendIn <= 0) {
        _sendIn = 0.06;
        final (mx, my) = _stick;
        n.send({'t': 'in', 'id': n.myId, 'x': _r(mx), 'y': _r(my)});
      }
    } else {
      _sendIn -= dt;
      if (_sendIn <= 0) {
        _sendIn = 0.08;
        n.send(_snapshot());
        _events.clear();
      }
    }
  }

  Guy? _humanById(Object? id) {
    final i = widget.humans.indexWhere((h) => h.$1 == id);
    if (i < 0) return null;
    return fighters.elementAt(i);
  }

  Map<String, dynamic> _snapshot() => {
    't': 'st',
    'tl': _r(_timeLeft),
    'cd': _r(_countdown),
    'ov': _over ? 1 : 0,
    'g': [
      for (final g in guys)
        [
          _r(g.x), _r(g.y), _r(g.angle), _r(g.walk), _r(g.splatAge), _r(g.dizzy),
          _r(g.dashT), _r(g.throwT), g.score, g.lives, g.out ? 1 : 0, g.triple,
          g.lineT > 0 ? (g.line ?? '') : '', _r(g.lineT), g.cakes, g.splats, g.oops, _r(g.outAt),
        ],
    ],
    'p': [for (final p in _pies) [_r(p.x), _r(p.y), _r(p.z), _r(p.spin)]],
    'cu': [for (final c in _cushions) [_r(c.x), _r(c.y), _r(c.away)]],
    'go': _golden == null ? null : [_r(_golden!.$1), _r(_golden!.$2)],
    'ck': [for (final c in _cakes) [_r(c.$1), _r(c.$2)]],
    'hp': hotHolder == null ? -1 : guys.indexOf(hotHolder!),
    'ht': _r(hotT),
    'ev': [..._events],
  };

  void _applySnapshot(Map<String, dynamic> m) {
    _timeLeft = _d(m['tl']);
    _countdown = _d(m['cd']);
    final gs = m['g'] as List? ?? const [];
    for (var i = 0; i < min(gs.length, guys.length); i++) {
      final v = gs[i] as List;
      final g = guys[i];
      final wasSplat = g.splatAge;
      g
        ..nx = _d(v[0])
        ..ny = _d(v[1])
        ..angle = _d(v[2])
        ..walk = _d(v[3])
        ..splatAge = _d(v[4])
        ..dizzy = _d(v[5])
        ..dashT = _d(v[6])
        ..throwT = _d(v[7])
        ..score = (v[8] as num).toInt()
        ..lives = (v[9] as num).toInt()
        ..out = v[10] == 1
        ..triple = (v[11] as num).toInt()
        ..cakes = (v[14] as num).toInt()
        ..splats = (v[15] as num).toInt()
        ..oops = (v[16] as num).toInt()
        ..outAt = _d(v[17]);
      final line = v[12] as String;
      if (line.isNotEmpty) {
        g
          ..line = line
          ..lineT = _d(v[13]);
      }
      if (g.player && g.splatAge >= 0 && g.splatAge < 0.4 && (wasSplat < 0 || wasSplat > g.splatAge + 0.4)) {
        _faceSplat = big ? 1.1 : 1.5;
        _shake = 0.3;
      }
      if ((g.nx - g.x).abs() > 3 || (g.ny - g.y).abs() > 3) {
        g
          ..x = g.nx
          ..y = g.ny;
      }
    }
    _pies
      ..clear()
      ..addAll([
        for (final p in (m['p'] as List? ?? const []))
          _Pie(_d(p[0]), _d(p[1]), _d(p[2]), 0, 0, 0, me)..spin = _d(p[3]),
      ]);
    final cu = m['cu'] as List? ?? const [];
    for (var i = 0; i < min(cu.length, _cushions.length); i++) {
      _cushions[i]
        ..x = _d(cu[i][0])
        ..y = _d(cu[i][1])
        ..away = _d(cu[i][2]);
    }
    final hp = (m['hp'] as num?)?.toInt() ?? -1;
    hotHolder = hp >= 0 && hp < guys.length ? guys[hp] : null;
    hotT = _d(m['ht']);
    final go = m['go'];
    _golden = go is List ? (_d(go[0]), _d(go[1])) : null;
    _cakes
      ..clear()
      ..addAll([for (final c in (m['ck'] as List? ?? const [])) (_d(c[0]), _d(c[1]))]);
    for (final e in (m['ev'] as List? ?? const [])) {
      if (e is! List || e.isEmpty) continue;
      if (e[0] == 'f') {
        _floats.add(_Float('${e[1]}', V3(_d(e[2]), _d(e[3]), _d(e[4])), Color((e[5] as num).toInt()),
            size: _d(e[6]), life: _d(e[7])));
      } else if (e[0] == 'b') {
        _blobs.add(_Blob(_d(e[1]), _d(e[2]), _d(e[3]), _d(e[4])));
      }
    }
    if (m['ov'] == 1 && !_over) {
      _over = true;
      _overT = 0;
      _saveBest();
    }
  }

  Iterable<Guy> get fighters => guys.where((g) => !g.bystander);

  double _dist(Guy a, Guy b) => sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));

  Iterable<Guy> get alive => guys.where((g) => !g.out);

  bool enemies(Guy a, Guy b) => !a.bystander && !b.bystander && a.team != b.team;

  /// Who the camera follows: you, or a teammate once you're out.
  Guy get watched => me.out
      ? fighters.firstWhere((g) => !g.out && g.team == me.team, orElse: () => me)
      : me;

  // ------------------------------------------------------------------ update

  void _update(double dt) {
    clock += dt;
    _faceSplat = max(0, _faceSplat - dt);
    _shake = max(0, _shake - dt);
    for (final f in _floats) {
      f.age += dt;
    }
    _floats.removeWhere((f) => f.age > f.life);
    for (final b in _blobs) {
      b.age += dt;
    }
    _blobs.removeWhere((b) => b.age > 6);
    for (final g in guys) {
      if (g.lineT > 0) g.lineT -= dt;
      if (g.splatAge >= 0) {
        g.splatAge += dt;
        if (g.splatAge > 2.4) g.splatAge = -1;
      }
      g.throwT = max(0, g.throwT - dt * 3);
    }
    _moveCamera(dt);

    if (guest) {
      // The host runs the party; just glide everyone to where it says.
      final k = min(1.0, dt * 14);
      for (final g in guys) {
        g.x += (g.nx - g.x) * k;
        g.y += (g.ny - g.y) * k;
      }
      for (final p in _pies) {
        p.spin += dt * 9;
      }
      if (_over) _overT += dt;
      return;
    }

    if (_over) {
      _overT += dt;
      return;
    }
    if (_countdown > 0) {
      _countdown -= dt;
      return;
    }
    _timeLeft -= dt;

    final (mx, my) = _stick;
    _humanInput(me, mx, my, dt);
    for (final g in alive) {
      if (g.player) continue;
      if (g.human) {
        _humanInput(g, g.inX, g.inY, dt);
        continue;
      }
      g.bystander ? _strangerBrain(g, dt) : _botBrain(g, dt);
    }
    for (final g in alive) {
      _move(g, dt);
    }
    _updatePies(dt);
    _updateStuffOnGrass(dt);

    if (_timeLeft <= 0) _finish();
    if (kingMode) _updateKing(dt);
    if (hotMode) _updateHot(dt);
    if (elimination) {
      final teamsLeft = fighters.where((g) => !g.out).map((g) => g.team).toSet();
      final myTeamOut = !fighters.any((g) => !g.out && g.team == me.team);
      if (teamsLeft.length <= 1 || myTeamOut) _finish();
    }
  }

  bool inZone(Guy g) => g.x * g.x + g.y * g.y < kingR * kingR;

  void _updateKing(double dt) {
    for (final g in fighters) {
      if (g.out || g.dizzy > 0 || !inZone(g)) continue;
      g.zoneT += dt;
      if (g.zoneT >= 0.5) {
        g.zoneT -= 0.5;
        g.score += 1;
        if (g.player && g.score % 5 == 0) {
          _addFloat(_Float('+5', V3(g.x, g.y, 2.3), const Color(0xFFFFD54F), size: 18));
        }
      }
    }
  }

  void _updateHot(double dt) {
    final left = fighters.where((g) => !g.out).toList();
    if (left.map((g) => g.team).toSet().length <= 1) return;
    if (hotHolder == null || hotHolder!.out) {
      hotHolder = left[_rnd.nextInt(left.length)];
      hotT = max(7.0, 16 - (fighters.length - left.length) * 0.8) + _rnd.nextDouble() * 4;
      _addFloat(_Float(hotHolder!.player ? 'YOU HAVE THE HOT PIE!' : '${_nameOf(hotHolder!)} has the HOT PIE!',
          V3(hotHolder!.x, hotHolder!.y, 2.6), const Color(0xFFFF7043), size: hotHolder!.player ? 26 : 16, life: 1.6));
      return;
    }
    hotT -= dt;
    if (hotT <= 0) {
      final g = hotHolder!;
      g
        ..out = true
        ..outAt = clock
        ..splatAge = 0;
      _shake = 0.5;
      _addBlob(_Blob(g.x, g.y, 1.6, _rnd.nextDouble() * 1000));
      _addFloat(_Float('KABOOM!', V3(g.x, g.y, 2.2), const Color(0xFFFF7043), size: 38, life: 1.6));
      _addFloat(_Float(g.player ? 'YOU ARE OUT!' : '${_nameOf(g)} is OUT!', V3(g.x, g.y, 3.0),
          const Color(0xFFFF8A80), size: g.player ? 28 : 16, life: 1.6));
      for (final o in alive) {
        if (!identical(o, g) && _dist(o, g) < 3) {
          o.say(['WHOA!', 'I got custard in my EAR!', 'So sticky!', 'Ha! Not me!'][_rnd.nextInt(4)], 1.4);
        }
      }
      SoundService.instance.play(GameSound.gameOver);
      hotHolder = null;
    }
  }

  String _nameOf(Guy g) => g.player ? 'You' : (g.name ?? g.kind.short);

  void _moveCamera(double dt) {
    final k = min(1.0, dt * 4);
    final w = watched;
    _camX += (w.x * 0.75 - _camX) * k;
    _camY += (w.y - _camY) * k;
  }

  (double, double) get _stick {
    var mx = 0.0, my = 0.0;
    if (_stickFrom != null && _stickAt != null) {
      final d = _stickAt! - _stickFrom!;
      final l = d.distance;
      if (l > 6) {
        final m = min(1.0, l / 50);
        mx = d.dx / l * m;
        my = -d.dy / l * m;
      }
    }
    bool k(LogicalKeyboardKey a, LogicalKeyboardKey b) =>
        _keys.contains(a) || _keys.contains(b);
    if (k(LogicalKeyboardKey.keyA, LogicalKeyboardKey.arrowLeft)) mx -= 1;
    if (k(LogicalKeyboardKey.keyD, LogicalKeyboardKey.arrowRight)) mx += 1;
    if (k(LogicalKeyboardKey.keyW, LogicalKeyboardKey.arrowUp)) my += 1;
    if (k(LogicalKeyboardKey.keyS, LogicalKeyboardKey.arrowDown)) my -= 1;
    final l = sqrt(mx * mx + my * my);
    if (l > 1) return (mx / l, my / l);
    return (mx, my);
  }

  void _humanInput(Guy me, double mx, double my, double dt) {
    me.throwCd -= dt;
    me.dashCd -= dt;
    me.inX = mx;
    me.inY = my;
    if (me.dizzy > 0 || me.dashT > 0 || me.out) return;
    final l = sqrt(mx * mx + my * my);
    if (l > 0.1) {
      me.angle = atan2(my, mx);
      me.vx = mx * 5.4;
      me.vy = my * 5.4;
    } else {
      me.vx = 0;
      me.vy = 0;
    }
  }

  void _botBrain(Guy g, double dt) {
    g.throwCd -= dt;
    g.dashCd -= dt;
    g.think -= dt;
    if (g.dizzy > 0 || g.dashT > 0) return;
    if (g.think <= 0 || g.target == null) {
      g.think = 0.8 + _rnd.nextDouble() * 1.2;
      final foes = alive.where((o) => enemies(g, o)).toList();
      if (foes.isEmpty) return;
      foes.sort((a, b) => _dist(g, a).compareTo(_dist(g, b)));
      final roll = _rnd.nextDouble();
      final waiter = guys.where((o) => (o.kind == Kind.waiter || o.kind == Kind.dad) && !o.out).toList();
      if (roll < 0.06 && waiter.isNotEmpty && !survival) {
        g.target = waiter[_rnd.nextInt(waiter.length)]; // cheeky points
      } else if (roll < 0.06 + 0.6 / foes.length && foes.contains(me)) {
        // Don't let everybody gang up on you in the big games.
        g.target = me;
      } else if (roll < 0.75) {
        g.target = foes.first;
      } else {
        g.target = foes[_rnd.nextInt(foes.length)];
      }
      if (hotMode && hotHolder != null && !identical(hotHolder, g) && enemies(g, hotHolder!) && _dist(g, hotHolder!) < 8) {
        // Run away from the hot pie!
        final a = atan2(g.y - hotHolder!.y, g.x - hotHolder!.x) + (_rnd.nextDouble() - 0.5);
        g.tx = (g.x + cos(a) * 6).clamp(-halfW + 1, halfW - 1);
        g.ty = (g.y + sin(a) * 6).clamp(-halfH + 1, halfH - 1);
      } else if (hotMode && identical(hotHolder, g)) {
        // Chase the nearest enemy to pass it on.
        g.target = foes.first;
        g.tx = foes.first.x;
        g.ty = foes.first.y;
        g.think = 0.4;
      } else if (kingMode && _rnd.nextDouble() < 0.65) {
        final a = _rnd.nextDouble() * pi * 2, d = _rnd.nextDouble() * (kingR - 0.6);
        g.tx = cos(a) * d;
        g.ty = sin(a) * d;
      } else if (cakeMode && _cakes.isNotEmpty && _rnd.nextDouble() < 0.6) {
        // Run for the nearest pie.
        var best = _cakes.first;
        for (final c in _cakes) {
          if (pow(c.$1 - g.x, 2) + pow(c.$2 - g.y, 2) < pow(best.$1 - g.x, 2) + pow(best.$2 - g.y, 2)) {
            best = c;
          }
        }
        g.tx = best.$1;
        g.ty = best.$2;
      } else {
        // Find a spot a few steps away from the target to throw from.
        final a = _rnd.nextDouble() * pi * 2;
        final d = 4.5 + _rnd.nextDouble() * 3;
        g.tx = (g.target!.x + cos(a) * d).clamp(-halfW + 1, halfW - 1);
        g.ty = (g.target!.y + sin(a) * d).clamp(-halfH + 1, halfH - 1);
      }
    }
    final dx = g.tx - g.x, dy = g.ty - g.y;
    final d = sqrt(dx * dx + dy * dy);
    if (g.target!.out) g.target = null;
    if (g.target == null) return;
    final speed = _botSpeed * (g.kind == Kind.baby ? 1.15 : 1) * (identical(hotHolder, g) ? 1.2 : 1);
    if (d > 0.4) {
      g.vx = dx / d * speed;
      g.vy = dy / d * speed;
    } else {
      g.vx = 0;
      g.vy = 0;
    }
    final t = g.target!;
    g.angle = atan2(t.y - g.y, t.x - g.x);
    final td = sqrt(pow(t.x - g.x, 2) + pow(t.y - g.y, 2));
    if (g.throwCd <= 0 && td < 13) {
      g.throwCd = _botThrowGap * (0.8 + _rnd.nextDouble() * 0.6) *
          (frenzy ? 0.55 : 1) * (identical(hotHolder, g) ? 0.5 : 1);
      final flight = max(0.25, td / 13);
      final miss = _botMiss * (0.4 + _rnd.nextDouble() * 1.2);
      final ma = _rnd.nextDouble() * pi * 2;
      _throw(
        g,
        t.x + t.vx * flight * _botLead + cos(ma) * miss,
        t.y + t.vy * flight * _botLead + sin(ma) * miss,
        1.2 * t.kind.size,
      );
      if (_rnd.nextDouble() < 0.3) {
        final lines = g.kind.throwLines;
        g.say(lines[_rnd.nextInt(lines.length)], 1.2);
      }
    }
  }

  void _strangerBrain(Guy g, double dt) {
    g.think -= dt;
    if (g.dizzy > 0) return;
    if (g.think <= 0) {
      g.think = 2 + _rnd.nextDouble() * 3;
      if (g.kind == Kind.puppy && _rnd.nextDouble() < 0.5) {
        // Biscuit loves you and follows you about. Careful!
        g.tx = me.x + (_rnd.nextDouble() - 0.5) * 3;
        g.ty = me.y + (_rnd.nextDouble() - 0.5) * 3;
      } else {
        g.tx = (_rnd.nextDouble() * 2 - 1) * (halfW - 1.5);
        g.ty = (_rnd.nextDouble() * 2 - 1) * (halfH - 1.5);
      }
      if (_rnd.nextDouble() < 0.35) {
        final lines = g.kind.chatter;
        g.say(lines[_rnd.nextInt(lines.length)], 1.6);
      }
    }
    final dx = g.tx - g.x, dy = g.ty - g.y;
    final d = sqrt(dx * dx + dy * dy);
    final speed = g.kind == Kind.puppy ? 2.6 : 1.3;
    if (d > 0.3) {
      g.vx = dx / d * speed;
      g.vy = dy / d * speed;
      g.angle = atan2(dy, dx);
    } else {
      g.vx = 0;
      g.vy = 0;
    }
  }

  void _move(Guy g, double dt) {
    g.dizzy = max(0, g.dizzy - dt);
    g.safe = max(0, g.safe - dt);
    var vx = g.vx, vy = g.vy;
    if (g.dizzy > 0) {
      vx = 0;
      vy = 0;
    }
    if (g.dashT > 0) {
      g.dashT -= dt;
      vx = g.dashX * 13;
      vy = g.dashY * 13;
    }
    g.x += vx * dt;
    g.y += vy * dt;
    final moving = vx * vx + vy * vy > 0.1;
    g.walk = moving ? g.walk + dt * 11 : g.walk * 0.8;
    // Keep inside the garden fence and out of the tables.
    final r = g.radius;
    g.x = g.x.clamp(-halfW + r, halfW - r);
    g.y = g.y.clamp(-halfH + r, halfH - r);
    for (final t in tables) {
      final box = t.inflate(r);
      if (!box.contains(Offset(g.x, g.y))) continue;
      final pushes = [
        (g.x - box.left).abs(),
        (box.right - g.x).abs(),
        (g.y - box.top).abs(),
        (box.bottom - g.y).abs(),
      ];
      final m = pushes.reduce(min);
      if (m == pushes[0]) {
        g.x = box.left;
      } else if (m == pushes[1]) {
        g.x = box.right;
      } else if (m == pushes[2]) {
        g.y = box.top;
      } else {
        g.y = box.bottom;
      }
    }
    // Don't walk through each other.
    for (final o in alive) {
      if (identical(o, g)) continue;
      final dx = g.x - o.x, dy = g.y - o.y;
      final d = sqrt(dx * dx + dy * dy);
      final need = g.radius + o.radius;
      if (d > 0.001 && d < need) {
        g.x += dx / d * (need - d) * 0.5;
        g.y += dy / d * (need - d) * 0.5;
      }
    }
  }

  // ------------------------------------------------------------------ pies

  void _throw(Guy g, double tx, double ty, double tz) {
    final hz = 1.75 * g.kind.size;
    final sx = g.x + cos(g.angle) * 0.35, sy = g.y + sin(g.angle) * 0.35;
    var dx = tx - sx, dy = ty - sy;
    var d = sqrt(dx * dx + dy * dy);
    if (d > 16) {
      dx *= 16 / d;
      dy *= 16 / d;
      d = 16;
    }
    final t = max(0.22, d / 13);
    final vz = (tz - hz) / t + 0.5 * _gravity * t;
    _pies.add(_Pie(sx, sy, hz, dx / t, dy / t, vz, g));
    g.throwT = 1;
    if (g.player) SoundService.instance.play(GameSound.bowTwang);
  }

  /// The THROW button: aims at the nearest pie fighter you're facing.
  void throwPie() {
    if (guest) {
      if (!_over && _countdown <= 0) net!.send({'t': 'th', 'id': net!.myId});
      return;
    }
    _humanThrow(me);
  }

  void _humanThrow(Guy me) {
    if (_over || _countdown > 0 || me.dizzy > 0 || me.throwCd > 0 || me.out) return;
    me.throwCd = frenzy ? 0.25 : 0.42;
    Guy? best;
    var bestScore = 1e9;
    for (final g in alive) {
      if (!enemies(me, g) && g.kind != Kind.waiter && g.kind != Kind.dad) continue;
      final dx = g.x - me.x, dy = g.y - me.y;
      final d = sqrt(dx * dx + dy * dy);
      if (d > 15) continue;
      var off = (atan2(dy, dx) - me.angle).abs() % (pi * 2);
      if (off > pi) off = pi * 2 - off;
      if (off > 0.75) continue;
      final score = off * 6 + d * 0.3;
      if (score < bestScore) {
        bestScore = score;
        best = g;
      }
    }
    double tx, ty, tz;
    if (best != null) {
      final d = sqrt(pow(best.x - me.x, 2) + pow(best.y - me.y, 2));
      final flight = max(0.22, d / 13);
      tx = best.x + best.vx * flight * 0.7;
      ty = best.y + best.vy * flight * 0.7;
      tz = 1.2 * best.kind.size;
      me.angle = atan2(ty - me.y, tx - me.x);
    } else {
      tx = me.x + cos(me.angle) * 9;
      ty = me.y + sin(me.angle) * 9;
      tz = 0;
    }
    _throw(me, tx, ty, tz);
    if (me.triple > 0 || frenzy) {
      if (!frenzy) me.triple--;
      for (final s in [-0.3, 0.3]) {
        final a = atan2(ty - me.y, tx - me.x) + s;
        final d = sqrt(pow(tx - me.x, 2) + pow(ty - me.y, 2));
        _throw(me, me.x + cos(a) * d, me.y + sin(a) * d, tz);
      }
    }
  }

  /// The DODGE button: a quick dash you can't be splatted during.
  void dodge() {
    if (guest) {
      if (!_over && _countdown <= 0) net!.send({'t': 'dg', 'id': net!.myId});
      return;
    }
    _humanDodge(me);
  }

  void _humanDodge(Guy me) {
    if (_over || _countdown > 0 || me.dizzy > 0 || me.dashCd > 0 || me.out) return;
    final (mx, my) = (me.inX, me.inY);
    final l = sqrt(mx * mx + my * my);
    // Dash the way you're pushing, or sideways if you're standing still.
    final a = l > 0.1 ? atan2(my, mx) : me.angle + pi / 2;
    me.dashX = cos(a);
    me.dashY = sin(a);
    me.dashT = 0.24;
    me.dashCd = 0.9;
  }

  void _updatePies(double dt) {
    final gone = <_Pie>{};
    for (final p in _pies) {
      p.vz -= _gravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.z += p.vz * dt;
      p.spin += dt * 9;
      // Bots sometimes see a pie coming and jump out of the way.
      for (final g in alive) {
        if (g.human || g.bystander || !enemies(g, p.by) || p.dodgeChecked) continue;
        final d = sqrt(pow(g.x - p.x, 2) + pow(g.y - p.y, 2));
        if (d < 2.2) {
          p.dodgeChecked = true;
          if (g.dashCd <= 0 && g.dizzy <= 0 && _rnd.nextDouble() < _botDodge) {
            final a = atan2(p.vy, p.vx) + (_rnd.nextBool() ? pi / 2 : -pi / 2);
            g
              ..dashX = cos(a)
              ..dashY = sin(a)
              ..dashT = 0.24
              ..dashCd = 2.5;
          }
        }
      }
      Guy? hit;
      for (final g in alive) {
        // Pies fly straight past your own teammates.
        if (identical(g, p.by) || g.dashT > 0 || g.safe > 0) continue;
        if (!g.bystander && !enemies(g, p.by)) continue;
        final d = sqrt(pow(g.x - p.x, 2) + pow(g.y - p.y, 2));
        if (d < g.radius + 0.18 && p.z > 0 && p.z < g.kind.height + 0.1) {
          hit = g;
          break;
        }
      }
      if (hit != null) {
        _splat(hit, p.by);
        gone.add(p);
        continue;
      }
      var onTable = false;
      for (final t in tables) {
        if (t.contains(Offset(p.x, p.y)) && p.z < 0.95) onTable = true;
      }
      if (onTable || p.z <= 0 || p.x.abs() > halfW + 3 || p.y.abs() > halfH + 3) {
        if (!onTable && p.z <= 0) {
          _addBlob(_Blob(p.x, p.y, 0.45, _rnd.nextDouble() * 1000));
        }
        gone.add(p);
      }
    }
    _pies.removeWhere(gone.contains);
  }

  void _splat(Guy g, Guy by) {
    g.splatAge = 0;
    g.safe = elimination ? 1.6 : 0.8;
    g.dizzy = g.bystander ? 1.5 : 0.9;
    final lines = g.kind.splatLines;
    g.say(lines[_rnd.nextInt(lines.length)], 1.8);
    final head = V3(g.x, g.y, g.kind.height + 0.2);
    if (g.player) {
      _faceSplat = big ? 1.1 : 1.5;
      _shake = 0.3;
      SoundService.instance.play(GameSound.hit);
    }
    if (g.kind == Kind.waiter) {
      by.score += 5;
      _addBlob(_Blob(g.x + 0.5, g.y, 0.6, _rnd.nextDouble() * 1000));
      _addFloat(_Float(by.player ? '+5 Splat the waiter!' : '+5', head,
          const Color(0xFFFFEB3B), size: by.player ? 20 : 15));
      if (by.player) SoundService.instance.play(GameSound.hit);
      return;
    }
    if (g.kind == Kind.dad) {
      // Right on his shiny bald head!
      by.score += 10;
      _addBlob(_Blob(g.x - 0.4, g.y, 0.7, _rnd.nextDouble() * 1000));
      _addFloat(_Float(by.player ? "+10 BONK! Right on Dad's head!" : '+10 Dad!', head,
          const Color(0xFFFFEB3B), size: by.player ? 22 : 15, life: 1.4));
      if (by.player) SoundService.instance.play(GameSound.hit);
      return;
    }
    if (g.protected) {
      by.score -= 15;
      by.oops++;
      if (by.player) {
        _shake = 0.4;
        _addFloat(_Float('-15', head, const Color(0xFFFF5252), size: 26, life: 1.4));
        _addFloat(_Float(
          switch (g.kind) {
            Kind.granny => 'NOT GRANNY!',
            Kind.stranger => 'NOT THE STRANGER!',
            _ => 'NOT THE PUPPY!',
          },
          head + const V3(0, 0, 0.7),
          const Color(0xFFFF5252),
          size: 30,
          life: 1.5,
        ));
        SoundService.instance.play(GameSound.noMatch);
      } else {
        _addFloat(_Float('Oops! -15 ${by.kind.short}', head, const Color(0xFFFFAB91), size: 15));
        by.say(['Oops!', 'Sorry Granny!', 'Whoopsie!', 'It was HIM!'][_rnd.nextInt(4)], 1.4);
      }
      return;
    }
    if (!kingMode) by.score += 10;
    by.splats++;
    if (hotMode && identical(hotHolder, by) && !g.out) {
      // Pass the hot pie on!
      hotHolder = g;
      hotT = max(hotT, 3);
      _addFloat(_Float(g.player ? 'YOU HAVE THE HOT PIE!' : 'Passed to ${_nameOf(g)}!',
          V3(g.x, g.y, 2.6), const Color(0xFFFF7043), size: g.player ? 26 : 16, life: 1.4));
    }
    if (cakeMode && g.cakes > 0) {
      // Splatted: drop half your cakes on the grass!
      final drop = (g.cakes + 1) ~/ 2;
      g.cakes -= drop;
      for (var i = 0; i < drop; i++) {
        final a = _rnd.nextDouble() * pi * 2, d = 1 + _rnd.nextDouble() * 1.5;
        _cakes.add((
          (g.x + cos(a) * d).clamp(-halfW + 1, halfW - 1),
          (g.y + sin(a) * d).clamp(-halfH + 1, halfH - 1),
        ));
      }
      _addFloat(_Float('Dropped $drop pie${drop == 1 ? '' : 's'}!', head + const V3(0, 0, 0.5),
          const Color(0xFFFFAB91), size: g.player ? 24 : 15));
    }
    if (survival) {
      g.lives--;
      if (g.lives <= 0) {
        g.out = true;
        g.outAt = clock;
        _addFloat(_Float(
          g.player ? 'YOU ARE OUT!' : '${g.kind.short} is OUT!',
          head + const V3(0, 0, 0.5),
          const Color(0xFFFF8A80),
          size: g.player ? 30 : 18,
          life: 1.6,
        ));
        _addBlob(_Blob(g.x, g.y, 0.9, _rnd.nextDouble() * 1000));
      }
    }
    _addFloat(_Float(
      by.player && !kingMode && !cakeMode && !elimination ? '+10 SPLAT!' : 'SPLAT!',
      head,
      by.player ? const Color(0xFFFFEB3B) : Colors.white,
      size: by.player ? 24 : 17,
    ));
    if (by.player) {
      SoundService.instance.play(GameSound.hit);
    } else if (_rnd.nextDouble() < 0.4) {
      by.say(['Ha ha ha!', 'Got you!', 'Bullseye!', 'Delicious!'][_rnd.nextInt(4)], 1.3);
    }
  }

  void _updateStuffOnGrass(double dt) {
    if (cakeMode) {
      _cakeIn -= dt;
      if (_cakeIn <= 0 && _cakes.length < (big ? 7 : 4)) {
        _cakeIn = 1.2;
        var cx = 0.0, cy = 0.0;
        do {
          cx = (_rnd.nextDouble() * 2 - 1) * (halfW - 1.5);
          cy = (_rnd.nextDouble() * 2 - 1) * (halfH - 1.5);
        } while (tables.any((t) => t.inflate(0.8).contains(Offset(cx, cy))));
        _cakes.add((cx, cy));
      }
      for (final g in fighters) {
        if (g.out) continue;
        final i = _cakes.indexWhere((c) => pow(c.$1 - g.x, 2) + pow(c.$2 - g.y, 2) < 0.55);
        if (i < 0) continue;
        _cakes.removeAt(i);
        g.cakes++;
        _addFloat(_Float(g.player ? '+1 PIE!' : '+1', V3(g.x, g.y, 2.3),
            const Color(0xFFF48FB1), size: g.player ? 22 : 14));
        if (g.player) SoundService.instance.play(GameSound.eat);
      }
    }
    for (final c in _cushions) {
      if (c.away > 0) {
        c.away -= dt;
        if (c.away <= 0) {
          c.x = (_rnd.nextDouble() * 2 - 1) * (halfW - 2);
          c.y = (_rnd.nextDouble() * 2 - 1) * (halfH - 2);
          if (tables.any((t) => t.inflate(1).contains(Offset(c.x, c.y)))) c.away = 0.5;
        }
        continue;
      }
      for (final g in alive) {
        if (g.dashT > 0) continue;
        if (pow(g.x - c.x, 2) + pow(g.y - c.y, 2) < 0.5) {
          _whoopee(c, g);
          break;
        }
      }
    }
    if (_golden == null) {
      if (frenzy) return;
      _goldenIn -= dt;
      if (_goldenIn <= 0) {
        var gx = 0.0, gy = 0.0;
        do {
          gx = (_rnd.nextDouble() * 2 - 1) * (halfW - 2);
          gy = (_rnd.nextDouble() * 2 - 1) * (halfH - 2);
        } while (tables.any((t) => t.inflate(1).contains(Offset(gx, gy))));
        _golden = (gx, gy);
      }
    } else {
      final (gx, gy) = _golden!;
      for (final g in fighters) {
        if (g.out) continue;
        if (pow(g.x - gx, 2) + pow(g.y - gy, 2) < 0.6) {
          g.triple = 3;
          _golden = null;
          _goldenIn = 12;
          _addFloat(_Float(
            g.player ? 'TRIPLE PIES!' : '${g.kind.short} got TRIPLE PIES!',
            V3(g.x, g.y, 2.4),
            const Color(0xFFFFD54F),
            size: g.player ? 26 : 16,
            life: 1.5,
          ));
          if (g.player) SoundService.instance.play(GameSound.match);
          break;
        }
      }
    }
    // Bots with triple pies throw three at once.
    for (final g in fighters) {
      if (g.human || (g.triple <= 0 && !frenzy) || g.throwT < 0.99) continue;
      final mine = _pies.where((p) => identical(p.by, g));
      if (mine.isEmpty) continue;
      if (!frenzy) g.triple--;
      final p = mine.last;
      for (final s in [-0.3, 0.3]) {
        final sp = sqrt(p.vx * p.vx + p.vy * p.vy);
        final a = atan2(p.vy, p.vx) + s;
        _pies.add(_Pie(p.x, p.y, p.z, cos(a) * sp, sin(a) * sp, p.vz, g));
      }
    }
  }

  void _whoopee(_Cushion c, Guy g) {
    c.away = 7;
    g.dizzy = 0.8;
    _addFloat(_Float('PFFFFRRRRT!', V3(c.x, c.y, 1.2), const Color(0xFFFF80AB), size: 28, life: 1.5));
    g.say(
      g.kind == Kind.puppy
          ? '*sniffs it suspiciously*'
          : ['Pardon me!', 'It was NOT me!', 'Oh dear...', 'Excuse ME!'][_rnd.nextInt(4)],
      1.6,
    );
    SoundService.instance.play(GameSound.tooEarly);
    for (final o in alive) {
      if (identical(o, g)) continue;
      if (pow(o.x - c.x, 2) + pow(o.y - c.y, 2) < 36) {
        o.say(['Hee hee hee!', 'Ewww!', 'Who did THAT?!', 'HA HA HA!', 'Pardon YOU!'][_rnd.nextInt(5)], 1.4);
      }
    }
  }

  void _finish() {
    if (_over) return;
    _over = true;
    _overT = 0;
    _pies.clear();
    if (online) net!.send(_snapshot());
    _saveBest();
    SoundService.instance.play(place == 1 ? GameSound.win : GameSound.levelComplete);
  }

  void _saveBest() {
    final save = SaveService.instance;
    final s = max(0, cakeMode ? me.cakes * 10 : me.score);
    _newBest = s > save.getHighScore(kPieSplatId);
    save.saveHighScore(kPieSplatId, s);
  }

  /// Each team's standing, best first. In a free-for-all a team is one person.
  List<TeamResult> get standings {
    final byTeam = <int, TeamResult>{};
    for (final g in fighters) {
      (byTeam[g.team] ??= TeamResult(g.team)).members.add(g);
    }
    final list = byTeam.values.toList();
    int key(TeamResult t) => elimination
        ? t.alive * 100000 + (survival ? t.lives * 1000 : 0) + (t.lastOut * 10).round()
        : cakeMode
            ? t.cakes
            : t.score;
    list.sort((a, b) => key(b).compareTo(key(a)));
    return list;
  }

  int get place => standings.indexWhere((t) => t.team == me.team) + 1;

  void _restart() {
    setState(() {
      _setup();
      _countdown = 2.4;
      _timeLeft = setup.seconds;
      _over = false;
      _faceSplat = 0;
    });
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF7EC8F2),
      body: KeyboardListener(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (e) {
          if (e is KeyDownEvent) {
            _keys.add(e.logicalKey);
            if (e.logicalKey == LogicalKeyboardKey.space ||
                e.logicalKey == LogicalKeyboardKey.enter) {
              throwPie();
            }
            if (e.logicalKey == LogicalKeyboardKey.shiftLeft ||
                e.logicalKey == LogicalKeyboardKey.keyE) {
              dodge();
            }
          } else if (e is KeyUpEvent) {
            _keys.remove(e.logicalKey);
          }
        },
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final size = box.biggest;
              final btn = (size.shortestSide * 0.2).clamp(66.0, 96.0);
              return Stack(
                children: [
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) {
                        if (_stickId != null) return;
                        if (e.localPosition.dx < size.width * 0.6 && e.localPosition.dy > 60) {
                          _stickId = e.pointer;
                          _stickFrom = e.localPosition;
                          _stickAt = e.localPosition;
                        } else if (e.localPosition.dy > 60) {
                          throwPie();
                        }
                      },
                      onPointerMove: (e) {
                        if (e.pointer == _stickId) _stickAt = e.localPosition;
                      },
                      onPointerUp: (e) => _release(e.pointer),
                      onPointerCancel: (e) => _release(e.pointer),
                      child: CustomPaint(painter: _PartyPainter(this)),
                    ),
                  ),
                  Positioned(left: 0, right: 0, top: 0, child: _hud()),
                  if (!_over)
                    Positioned(
                      right: 14 + btn * 0.15,
                      bottom: 16,
                      child: _roundButton(
                        const Key('pie_throw'),
                        'THROW',
                        btn,
                        const Color(0xFFFF4081),
                        throwPie,
                      ),
                    ),
                  if (!_over)
                    Positioned(
                      right: 14 + btn * 1.25,
                      bottom: 12,
                      child: _roundButton(
                        const Key('pie_dodge'),
                        'DODGE',
                        btn * 0.72,
                        const Color(0xFF40C4FF),
                        dodge,
                      ),
                    ),
                  if (_over && _overT > 0.8) Positioned.fill(child: _results()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _release(int pointer) {
    if (pointer != _stickId) return;
    _stickId = null;
    _stickFrom = null;
    _stickAt = null;
  }

  Widget _roundButton(Key key, String label, double size, Color color, VoidCallback onPress) {
    return Listener(
      key: key,
      onPointerDown: (_) => onPress(),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: kInk3, width: 3),
          boxShadow: const [BoxShadow(color: kInk3, offset: Offset(0, 4))],
        ),
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hud() {
    Widget pill(Widget child, {Color color = Colors.white}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kInk3, width: 2.5),
      ),
      child: child,
    );
    final secs = max(0, _timeLeft.ceil());
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: pill(const Icon(Icons.arrow_back_rounded, color: kInk3, size: 22)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: pill(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (teamGame) ...[
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: kTeamColors[me.team],
                            shape: BoxShape.circle,
                            border: Border.all(color: kInk3, width: 2),
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      if (survival)
                        for (var i = 0; i < 3; i++)
                          Icon(
                            i < me.lives && !me.out ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: const Color(0xFFE53935),
                            size: 18,
                          ),
                      if (survival) const SizedBox(width: 5),
                      Text(
                        _hudText,
                        key: const Key('pie_score'),
                        style: const TextStyle(color: kInk3, fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  color: const Color(0xFFFFE082),
                ),
              ),
            ),
            const SizedBox(width: 6),
            pill(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_rounded, color: kInk3, size: 18),
                  const SizedBox(width: 3),
                  Text(
                    '$secs',
                    style: TextStyle(
                      color: secs <= 10 ? const Color(0xFFD32F2F) : kInk3,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String ordinal(int n) => switch (n) {
    1 => '1st',
    2 => '2nd',
    3 => '3rd',
    _ => '${n}th',
  };

  String get _hudText {
    if (me.out) return 'OUT! Watching your team';
    if (cakeMode) {
      final mine = teamGame ? standings.firstWhere((t) => t.team == me.team).cakes : me.cakes;
      return '$mine pies · ${ordinal(place)}';
    }
    if (elimination) {
      final left = fighters.where((g) => !g.out).length;
      if (hotMode && identical(hotHolder, me)) return 'HOT PIE! ${max(0, hotT).toStringAsFixed(1)}s';
      return '$left left';
    }
    return '${teamGame ? standings.firstWhere((t) => t.team == me.team).score : me.score} pts · ${ordinal(place)}';
  }

  static String rankFor(int place, int score) {
    if (place == 1) return 'Supreme Splat Wizard';
    if (score >= 100) return 'Captain Custard';
    if (score >= 40) return 'Splat Sergeant';
    if (score >= 0) return 'Custard Cadet';
    return 'Granny Splatter (oh dear)';
  }

  Widget _results() {
    final best = SaveService.instance.getHighScore(kPieSplatId);
    final rank = standings;
    final who = teamGame ? 'YOUR TEAM' : 'YOU';
    final headline = switch (place) {
      1 => '$who WON THE PIE PARTY!',
      2 => 'So close! ${ordinal(place)} place!',
      _ when place == rank.length => 'Last place... ${teamGame ? 'your team' : 'you'} got creamed!',
      _ => '${ordinal(place)} place! Not bad!',
    };
    String label(TeamResult t) => teamGame
        ? '${kTeamNames[t.team]} team${t.team == me.team ? ' (you)' : ''}'
        : t.members.first.player
            ? 'You'
            : (t.members.first.name ?? t.members.first.kind.short);
    String value(TeamResult t) => elimination
        ? (teamGame ? '${t.alive} left' : (t.alive > 0 ? (survival ? '${t.lives} ♥' : 'still in') : 'out'))
        : cakeMode
            ? '${t.cakes} pies'
            : '${t.score}';
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          width: 340,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: kCream3,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: kInk3, width: 3),
            boxShadow: const [BoxShadow(color: kInk3, offset: Offset(0, 6))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_netNote != null)
                Text(_netNote!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.w800)),
              Text(
                headline,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kInk3, fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < rank.length; i++)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: rank[i].team == me.team ? const Color(0xFFFFE082) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kInk3, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(i == 0 ? '👑' : '${i + 1}.',
                            style: const TextStyle(color: kInk3, fontWeight: FontWeight.w900)),
                      ),
                      if (teamGame) ...[
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: kTeamColors[rank[i].team],
                            shape: BoxShape.circle,
                            border: Border.all(color: kInk3, width: 1.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          label(rank[i]),
                          style: const TextStyle(color: kInk3, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        value(rank[i]),
                        style: const TextStyle(color: kInk3, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'You are a ${rankFor(place, me.score)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: kInk3, fontSize: 16, fontWeight: FontWeight.w800),
              ),
              Text(
                'Your splats: ${me.splats}   Guests splatted: ${me.oops}',
                style: TextStyle(color: kInk3.withValues(alpha: 0.75), fontSize: 13),
              ),
              Text(
                _newBest ? 'NEW BEST SCORE!' : 'Best: $best',
                style: TextStyle(
                  color: _newBest ? const Color(0xFF2E7D32) : kInk3.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (!online) _button('Play again', const Color(0xFFFF4081), _restart),
                  _button(online ? 'Back to room' : 'Menu', Colors.white, () => Navigator.of(context).pop()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kInk3, width: 2.5),
          boxShadow: const [BoxShadow(color: kInk3, offset: Offset(0, 4))],
        ),
        child: Text(
          label,
          style: const TextStyle(color: kInk3, fontSize: 17, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ drawing

class _PartyPainter extends CustomPainter {
  _PartyPainter(this.g);
  final PieSplatGameState g;

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5BB8F0), Color(0xFFCDEBFF)],
        ).createShader(Offset.zero & size),
    );
    c.save();
    if (g._shake > 0) {
      final s = g._shake * 12;
      c.translate(sin(g.clock * 70) * s, cos(g.clock * 53) * s);
    }
    final s = _scene(size);
    s.draw(c);
    _overlays(c, s, size);
    c.restore();

    // Pie in YOUR face.
    if (g._faceSplat > 0) {
      final k = (g.big ? 1.1 : 1.5) - g._faceSplat;
      final a = (g._faceSplat / 0.5).clamp(0.0, 1.0);
      final grow = Curves.easeOutBack.transform(min(1.0, k / 0.15));
      final cream = Paint()..color = kCream3.withValues(alpha: a);
      final rnd = Random(5);
      final centre = Offset(size.width / 2, size.height * 0.45 + k * 30);
      final r = size.shortestSide * 0.34 * grow;
      c.drawCircle(centre, r * 0.75, cream);
      for (var i = 0; i < 10; i++) {
        final an = i * pi / 5 + rnd.nextDouble() * 0.3;
        final d = r * (0.6 + rnd.nextDouble() * 0.35);
        c.drawCircle(centre + Offset(cos(an) * d, sin(an) * d), r * (0.15 + rnd.nextDouble() * 0.12), cream);
      }
      for (var i = 0; i < 5; i++) {
        final x = centre.dx + (i - 2) * r * 0.3;
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - 9, centre.dy, 18, r * (0.6 + 0.5 * ((i * 37) % 10) / 10) + k * 60),
            const Radius.circular(9),
          ),
          cream,
        );
      }
      c.drawCircle(centre + Offset(r * 0.1, -r * 0.3), r * 0.1, Paint()..color = const Color(0xFFD50000).withValues(alpha: a));
      _text(c, 'SPLAT!', centre, 44, Colors.white.withValues(alpha: a), maxWidth: size.width);
    }

    _stick(c);

    if (g._countdown > 0) {
      c.drawRect(Offset.zero & size, Paint()..color = const Color(0x55000000));
      final cd = g._countdown;
      final shown = cd > 1.8 ? '3' : cd > 1.2 ? '2' : cd > 0.6 ? '1' : 'PIE FIGHT!';
      final big = min(size.shortestSide * 0.25, 110.0);
      _text(c, shown, size.center(Offset.zero), shown.length > 1 ? big * 0.6 : big, Colors.white,
          maxWidth: size.width - 20);
      _text(
        c,
        g.setup.mode == PieMode.comedy && g.teamGame
            ? "Splat the other teams. Pies fly past your teammates. Don't splat the guests!"
            : g.setup.mode.howTo,
        size.center(Offset(0, big * 0.85)),
        16,
        Colors.white,
        maxWidth: min(size.width - 30, 420),
      );
    }
  }

  Scene3D _scene(Size size) {
    final hw = g.halfW, hh = g.halfH;
    final portrait = size.width < size.height;
    final back = portrait ? 6.5 : 7.0;
    final up = portrait ? 11.0 : 8.0;
    final camX = g._camX.clamp(-5.0, 5.0);
    final camY = g._camY.clamp(-hh + 4.0, hh - 4.0);
    final eye = V3(camX, camY - back, up);
    final look = V3(camX, camY + 1.0, 0);
    final focal = portrait ? size.width * 1.45 : min(size.width * 0.9, size.height * 1.7);
    final s = Scene3D(
      eye,
      look - eye,
      focal,
      Offset(size.width / 2, size.height * (portrait ? 0.6 : 0.5)),
      fog: const Color(0xFFCDEBFF),
      fogFar: 60,
      fogMax: 0.35,
    );

    // Grass outside, then the striped lawn.
    s.poly([
      const V3(-40, -30, -0.01),
      const V3(40, -30, -0.01),
      const V3(40, 40, -0.01),
      const V3(-40, 40, -0.01),
    ], const Color(0xFF558B2F), floor: true, lit: false);
    for (var i = 0; i < (hw).round(); i++) {
      final x0 = -hw + i * 2.0;
      s.poly([
        V3(x0, -hh, 0),
        V3(x0 + 2, -hh, 0),
        V3(x0 + 2, hh, 0),
        V3(x0, hh, 0),
      ], i.isEven ? const Color(0xFF7CB342) : const Color(0xFF8BC34A), floor: true, lit: false);
    }
    for (final b in g._blobs) {
      addFloorSplat(s, b.x, b.y, b.r * min(1.0, b.age * 8), b.seed);
    }
    // Shadows under people and pies help you see where things are.
    void shadow(double x, double y, double r) {
      s.poly([
        for (var i = 0; i < 8; i++) V3(x + cos(i * pi / 4) * r, y + sin(i * pi / 4) * r * 0.9, 0.02),
      ], const Color(0x55000000), floor: true, lit: false);
    }

    for (final p in g.alive) {
      shadow(p.x, p.y, p.radius * 0.9);
      if (g.teamGame && !p.bystander) {
        // A ring in your team's colour.
        final r = p.radius + 0.12;
        for (var i = 0; i < 12; i++) {
          final a0 = i * pi / 6, a1 = (i + 1) * pi / 6;
          s.poly([
            V3(p.x + cos(a0) * r, p.y + sin(a0) * r, 0.03),
            V3(p.x + cos(a1) * r, p.y + sin(a1) * r, 0.03),
            V3(p.x + cos(a1) * (r - 0.12), p.y + sin(a1) * (r - 0.12), 0.03),
            V3(p.x + cos(a0) * (r - 0.12), p.y + sin(a0) * (r - 0.12), 0.03),
          ], kTeamColors[p.team], floor: true, lit: false);
        }
      }
    }
    for (final p in g._pies) {
      shadow(p.x, p.y, 0.22);
    }

    // The fence.
    const fence = Color(0xFFFFFFFF);
    const ax = V3(1, 0, 0), ay = V3(0, 1, 0);
    for (var x = -hw; x <= hw + 0.01; x += 2) {
      for (final y in [-hh, hh]) {
        s.box(V3(x, y, 0.45), ax, ay, kUp, 0.08, 0.08, 0.45, fence);
      }
    }
    for (var y = -hh + 2; y < hh; y += 2) {
      for (final x in [-hw, hw]) {
        s.box(V3(x, y, 0.45), ax, ay, kUp, 0.08, 0.08, 0.45, fence);
      }
    }
    for (final y in [-hh, hh]) {
      s.box(V3(0, y, 0.6), ax, ay, kUp, hw, 0.04, 0.06, fence);
    }
    for (final x in [-hw, hw]) {
      s.box(V3(x, 0, 0.6), ax, ay, kUp, 0.04, hh, 0.06, fence);
    }
    // Balloons on the corners.
    const balloons = [Color(0xFFFF4081), Color(0xFFFFEB3B), Color(0xFF40C4FF), Color(0xFF69F0AE)];
    var bi = 0;
    for (final x in [-hw, hw]) {
      for (final y in [-hh, hh]) {
        final bob = sin(g.clock * 2 + bi) * 0.12;
        s.box(V3(x, y, 1.4), ax, ay, kUp, 0.015, 0.015, 0.6, Colors.white);
        s.box(V3(x, y, 2.3 + bob), ax, ay, kUp, 0.3, 0.3, 0.38, balloons[bi % 4]);
        bi++;
      }
    }
    // Party tables with cakes.
    for (final t in g.tables) {
      final c = V3(t.center.dx, t.center.dy, 0);
      s.group(() {
        s.box(c + kUp * 0.4, ax, ay, kUp, t.width / 2, t.height / 2, 0.4,
            const Color(0xFFF8BBD0), top: Colors.white);
        s.box(c + kUp * 0.98, ax, ay, kUp, 0.4, 0.4, 0.18, const Color(0xFF8D6E63), top: kCream3);
        s.box(c + kUp * 1.26, ax, ay, kUp, 0.28, 0.28, 0.1, const Color(0xFFF48FB1), top: kCream3);
        s.box(c + kUp * 1.45, ax, ay, kUp, 0.03, 0.03, 0.09, const Color(0xFF64B5F6));
        s.box(c + kUp * 1.57, ax, ay, kUp, 0.035, 0.035, 0.035, const Color(0xFFFFC107));
      });
    }
    // Whoopee cushions and the golden pie.
    for (final cu in g._cushions) {
      if (cu.away > 0) continue;
      s.box(V3(cu.x, cu.y, 0.08), ax, ay, kUp, 0.35, 0.3, 0.08, const Color(0xFFFF4081));
      s.box(V3(cu.x + 0.42, cu.y, 0.05), ax, ay, kUp, 0.08, 0.06, 0.04, const Color(0xFFF50057));
    }
    if (g._golden != null) {
      final (gx, gy) = g._golden!;
      addPie(s, V3(gx, gy, 0.6 + sin(g.clock * 3) * 0.15), g.clock * 2, mega: true);
    }
    if (g.kingMode) {
      // The golden circle, and a giant pie floating above it.
      const R = PieSplatGameState.kingR;
      s.poly([for (var i = 0; i < 24; i++) V3(cos(i * pi / 12) * R, sin(i * pi / 12) * R, 0.02)],
          const Color(0xFFFFD54F), floor: true, lit: false);
      s.poly([for (var i = 0; i < 24; i++) V3(cos(i * pi / 12) * (R - 0.25), sin(i * pi / 12) * (R - 0.25), 0.025)],
          const Color(0xFFFFECB3), floor: true, lit: false);
      final bob = 3.2 + sin(g.clock * 2) * 0.15;
      // A giant golden pie with a crown on top.
      addPie(s, V3(0, 0, bob), g.clock * 0.8, mega: true);
      s.group(() {
        for (var i = 0; i < 5; i++) {
          final a = i * pi * 2 / 5 + g.clock * 0.8;
          s.box(V3(cos(a) * 0.22, sin(a) * 0.22, bob + 0.42), ax, ay, kUp, 0.06, 0.06, 0.14, const Color(0xFFFFC107));
        }
      });
    }
    final hot = g.hotHolder;
    if (hot != null && !hot.out) {
      final flash = (g.hotT < 3 && (g.clock * 8).floor().isEven);
      addPie(s, V3(hot.x, hot.y, hot.kind.height + 0.75 + sin(g.clock * 10) * 0.05), g.clock * 4, mega: !flash);
    }
    for (final (cx, cy) in g._cakes) {
      addPie(s, V3(cx, cy, 0.18 + sin(g.clock * 3 + cx) * 0.05), g.clock * 1.5 + cy);
    }
    // Everybody at the party.
    for (final p in g.alive) {
      if (p.cakes > 0) {
        // A wobbly stack of pies on their head.
        final top = p.kind.height + 0.15;
        s.group(() {
          for (var i = 0; i < min(p.cakes, 5); i++) {
            final wob = sin(g.clock * 6 + i) * 0.03 * i;
            s.box(V3(p.x + wob, p.y, top + i * 0.14), ax, ay, kUp, 0.19 - i * 0.012, 0.19 - i * 0.012, 0.06,
                kCrust3, top: kCream3);
          }
        });
      }
      addGuy(
        s,
        p.kind,
        p.x,
        p.y,
        p.angle + (p.dashT > 0 ? p.dashT * 26 : 0) + (p.dizzy > 0 && p.splatAge < 0 ? sin(g.clock * 20) * 0.4 : 0),
        walk: p.walk,
        throwT: p.throwT,
        splat: p.splatAge,
        z: p.dashT > 0 ? sin(p.dashT / 0.24 * pi) * 0.4 : 0,
        time: g.clock + p.kind.index,
      );
    }
    for (final p in g._pies) {
      addPie(s, V3(p.x, p.y, p.z), p.spin);
    }
    return s;
  }

  void _overlays(Canvas c, Scene3D s, Size size) {
    // "YOU" marker over the chef.
    final top = s.project(V3(g.me.x, g.me.y, g.me.kind.height + 0.75));
    if (top != null && !g._over && !g.me.out) {
      final bob = sin(g.clock * 5) * 3;
      final p = Path()
        ..moveTo(top.dx - 8, top.dy - 10 + bob)
        ..lineTo(top.dx + 8, top.dy - 10 + bob)
        ..lineTo(top.dx, top.dy + bob)
        ..close();
      c.drawPath(p, Paint()..color = const Color(0xFFFFEB3B));
      c.drawPath(p, Paint()
        ..color = kInk3
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
      if (g.me.triple > 0) {
        _text(c, 'x3 PIES', top - Offset(0, 22 - bob), 13, const Color(0xFFFFD54F));
      }
    }
    for (final p in g.alive) {
      final head = s.project(V3(p.x, p.y, p.kind.height + 0.35));
      if (head == null) continue;
      if (p.dizzy > 0 && !p.bystander) {
        for (var i = 0; i < 3; i++) {
          final a = g.clock * 6 + i * pi * 2 / 3;
          _star(c, head + Offset(cos(a) * 16, sin(a) * 5 - 6), 5);
        }
      }
      if (identical(g.hotHolder, p) && !p.out) {
        _text(c, max(0, g.hotT).toStringAsFixed(1), head - const Offset(0, 46), 18,
            g.hotT < 3 ? const Color(0xFFFF5252) : const Color(0xFFFFAB40));
      }
      if (p.name != null && !p.player) {
        _text(c, p.name!, head + const Offset(0, 4), 12,
            g.teamGame ? kTeamColors[p.team] : Colors.white, maxWidth: 120);
      }
      if (p.lineT > 0 && p.line != null) _bubble(c, head - const Offset(0, 14), p.line!, size);
    }
    for (final f in g._floats) {
      final at = s.project(f.pos + V3(0, 0, f.age * 1.2));
      if (at == null) continue;
      final k = f.age / f.life;
      _text(
        c,
        f.text,
        at,
        f.size * (k < 0.12 ? 0.6 + k * 3.3 : 1),
        f.color.withValues(alpha: (1 - k * k).clamp(0.0, 1.0)),
        maxWidth: size.width - 20,
        clampTo: size,
      );
    }
  }

  void _stick(Canvas c) {
    final from = g._stickFrom, at = g._stickAt;
    if (from == null || at == null) return;
    c.drawCircle(from, 50, Paint()..color = Colors.white.withValues(alpha: 0.25));
    c.drawCircle(from, 50, Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    var d = at - from;
    if (d.distance > 50) d = d / d.distance * 50;
    c.drawCircle(from + d, 24, Paint()..color = Colors.white.withValues(alpha: 0.8));
  }

  void _star(Canvas c, Offset o, double r) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final a = i * pi / 5 - pi / 2;
      final d = i.isEven ? r : r * 0.45;
      final pt = o + Offset(cos(a) * d, sin(a) * d);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    p.close();
    c.drawPath(p, Paint()..color = const Color(0xFFFFEB3B));
  }

  void _bubble(Canvas c, Offset at, String text, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: kInk3, fontSize: 13, fontWeight: FontWeight.w800, height: 1.1),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: min(150, size.width * 0.4));
    final bw = tp.width + 14, bh = tp.height + 8;
    final cx = at.dx.clamp(bw / 2 + 4, max(bw / 2 + 4, size.width - bw / 2 - 4));
    final topY = max(52.0, at.dy - bh - 8);
    final box = Rect.fromLTWH(cx - bw / 2, topY, bw, bh);
    final rr = RRect.fromRectAndRadius(box, const Radius.circular(10));
    final tail = Path()
      ..moveTo(at.dx - 6, box.bottom - 1)
      ..lineTo(at.dx + 6, box.bottom - 1)
      ..lineTo(at.dx, box.bottom + 8)
      ..close();
    final fill = Paint()..color = Colors.white;
    final line = Paint()
      ..color = kInk3
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    c.drawPath(tail, fill);
    c.drawPath(tail, line);
    c.drawRRect(rr, fill);
    c.drawRRect(rr, line);
    tp.paint(c, Offset(box.left + 7, box.top + 4));
  }

  void _text(
    Canvas c,
    String s,
    Offset center,
    double size,
    Color color, {
    double maxWidth = 400,
    Size? clampTo,
  }) {
    TextPainter make(TextStyle st) => TextPainter(
      text: TextSpan(text: s, style: st),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    final outline = make(TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      height: 1.1,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(3, size / 7)
        ..strokeJoin = StrokeJoin.round
        ..color = kInk3.withValues(alpha: color.a),
    ));
    final fill = make(TextStyle(fontSize: size, fontWeight: FontWeight.w900, height: 1.1, color: color));
    var tl = center - Offset(fill.width / 2, fill.height / 2);
    if (clampTo != null) {
      tl = Offset(
        tl.dx.clamp(4, max(4, clampTo.width - fill.width - 4)),
        tl.dy.clamp(4, max(4, clampTo.height - fill.height - 4)),
      );
    }
    outline.paint(c, tl);
    fill.paint(c, tl);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
