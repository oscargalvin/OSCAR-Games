import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/save_service.dart';
import '../../services/sound_service.dart';
import '../../widgets/full_screen_game.dart';
import '../boost_ball/boost_ball_3d.dart' show V3;
import '../outplay/outplay_3d.dart' show Scene3D, kUp;
import 'pie_splat_3d.dart';

const String kPieSplatId = 'pie_splat';
const double kRoundSeconds = 90;
const double _halfW = 11, _halfH = 8;
const double _gravity = 14;

/// Someone at the party: you, a pie-throwing goof, or an innocent stranger.
class Guy {
  Guy(this.kind, this.x, this.y, {this.player = false}) : tx = x, ty = y;
  final Kind kind;
  final bool player;
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
  String? line;
  double lineT = 0;
  double tx, ty;
  double think = 0;
  Guy? target;

  bool get stranger => kind.stranger;
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

class _Cushion {
  _Cushion(this.x, this.y);
  double x, y;
  double away = 0; // > 0 while it is waiting to come back
}

/// Pie Splat Party in 3D: a garden party pie fight.
class PieSplatGameScreen extends StatefulWidget {
  const PieSplatGameScreen({super.key, this.seed});

  /// For tests: makes the party play out the same every time.
  final int? seed;

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

  static final List<Rect> tables = [
    Rect.fromCenter(center: const Offset(-5.5, 2.5), width: 2.6, height: 1.4),
    Rect.fromCenter(center: const Offset(5.5, 2.5), width: 2.6, height: 1.4),
    Rect.fromCenter(center: const Offset(0, -3), width: 2.2, height: 1.2),
  ];

  double _countdown = 2.4;
  double _timeLeft = kRoundSeconds;
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
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setup() {
    guys.clear();
    me = Guy(Kind.chef, 0, -5.5, player: true);
    final goofs = [Kind.snooty, Kind.moustache, Kind.clown, Kind.robot, Kind.baby]
      ..shuffle(_rnd);
    final spots = [(-7.0, 5.5), (7.0, 5.5), (0.0, 6.0)];
    guys.add(me);
    for (var i = 0; i < 3; i++) {
      final g = Guy(goofs[i], spots[i].$1, spots[i].$2)
        ..angle = -pi / 2
        ..throwCd = 2 + i * 0.6;
      guys.add(g);
    }
    guys.add(Guy(Kind.granny, -3, 0));
    guys.add(Guy(Kind.waiter, 3.5, -0.5));
    guys.add(Guy(Kind.puppy, 1.5, -3.8));
    _cushions
      ..clear()
      ..add(_Cushion(-7, -4))
      ..add(_Cushion(7.5, -1));
    _pies.clear();
    _floats.clear();
    _blobs.clear();
    _golden = null;
    _goldenIn = 10;
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    setState(() => _update(dt));
  }

  Iterable<Guy> get fighters => guys.where((g) => !g.stranger);

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

    if (_over) {
      _overT += dt;
      return;
    }
    if (_countdown > 0) {
      _countdown -= dt;
      return;
    }
    _timeLeft -= dt;

    _playerInput(dt);
    for (final g in guys) {
      if (g.player) continue;
      g.stranger ? _strangerBrain(g, dt) : _botBrain(g, dt);
    }
    for (final g in guys) {
      _move(g, dt);
    }
    _updatePies(dt);
    _updateStuffOnGrass(dt);

    if (_timeLeft <= 0) _finish();
  }

  void _moveCamera(double dt) {
    final k = min(1.0, dt * 4);
    _camX += (me.x * 0.75 - _camX) * k;
    _camY += (me.y - _camY) * k;
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

  void _playerInput(double dt) {
    final (mx, my) = _stick;
    me.throwCd -= dt;
    me.dashCd -= dt;
    if (me.dizzy > 0 || me.dashT > 0) return;
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
      final others = fighters.where((o) => o != g).toList();
      g.target = _rnd.nextDouble() < 0.45 ? me : others[_rnd.nextInt(others.length)];
      // Find a spot a few steps away from the target to throw from.
      final a = _rnd.nextDouble() * pi * 2;
      final d = 4.5 + _rnd.nextDouble() * 3;
      g.tx = (g.target!.x + cos(a) * d).clamp(-_halfW + 1, _halfW - 1);
      g.ty = (g.target!.y + sin(a) * d).clamp(-_halfH + 1, _halfH - 1);
    }
    final dx = g.tx - g.x, dy = g.ty - g.y;
    final d = sqrt(dx * dx + dy * dy);
    final speed = 3.4 * (g.kind == Kind.baby ? 1.15 : 1);
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
      g.throwCd = 1.6 + _rnd.nextDouble() * 1.3;
      final flight = max(0.25, td / 13);
      final miss = 0.5 + _rnd.nextDouble() * 0.9;
      final ma = _rnd.nextDouble() * pi * 2;
      _throw(
        g,
        t.x + t.vx * flight * 0.5 + cos(ma) * miss,
        t.y + t.vy * flight * 0.5 + sin(ma) * miss,
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
        g.tx = (_rnd.nextDouble() * 2 - 1) * (_halfW - 1.5);
        g.ty = (_rnd.nextDouble() * 2 - 1) * (_halfH - 1.5);
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
    g.x = g.x.clamp(-_halfW + r, _halfW - r);
    g.y = g.y.clamp(-_halfH + r, _halfH - r);
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
    for (final o in guys) {
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
    if (_over || _countdown > 0 || me.dizzy > 0 || me.throwCd > 0) return;
    me.throwCd = 0.42;
    Guy? best;
    var bestScore = 1e9;
    for (final g in fighters) {
      if (g.player) continue;
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
    if (me.triple > 0) {
      me.triple--;
      for (final s in [-0.3, 0.3]) {
        final a = atan2(ty - me.y, tx - me.x) + s;
        final d = sqrt(pow(tx - me.x, 2) + pow(ty - me.y, 2));
        _throw(me, me.x + cos(a) * d, me.y + sin(a) * d, tz);
      }
    }
  }

  /// The DODGE button: a quick dash you can't be splatted during.
  void dodge() {
    if (_over || _countdown > 0 || me.dizzy > 0 || me.dashCd > 0) return;
    final (mx, my) = _stick;
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
      for (final g in guys) {
        if (g.player || g.stranger || identical(g, p.by) || p.dodgeChecked) continue;
        final d = sqrt(pow(g.x - p.x, 2) + pow(g.y - p.y, 2));
        if (d < 2.2) {
          p.dodgeChecked = true;
          if (g.dashCd <= 0 && g.dizzy <= 0 && _rnd.nextDouble() < 0.28) {
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
      for (final g in guys) {
        if (identical(g, p.by) || g.dashT > 0) continue;
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
      if (onTable || p.z <= 0 || p.x.abs() > _halfW + 3 || p.y.abs() > _halfH + 3) {
        if (!onTable && p.z <= 0) {
          _blobs.add(_Blob(p.x, p.y, 0.45, _rnd.nextDouble() * 1000));
        }
        gone.add(p);
      }
    }
    _pies.removeWhere(gone.contains);
  }

  void _splat(Guy g, Guy by) {
    g.splatAge = 0;
    g.dizzy = g.stranger ? 1.5 : 0.9;
    final lines = g.kind.splatLines;
    g.say(lines[_rnd.nextInt(lines.length)], 1.8);
    final head = V3(g.x, g.y, g.kind.height + 0.2);
    if (g.player) {
      _faceSplat = 1.8;
      _shake = 0.3;
      SoundService.instance.play(GameSound.hit);
    }
    if (g.stranger) {
      by.score -= 15;
      by.oops++;
      if (by.player) {
        _shake = 0.4;
        _floats.add(_Float('-15', head, const Color(0xFFFF5252), size: 26, life: 1.4));
        _floats.add(_Float(
          switch (g.kind) {
            Kind.granny => 'NOT GRANNY!',
            Kind.waiter => 'NOT THE WAITER!',
            _ => 'NOT THE PUPPY!',
          },
          head + const V3(0, 0, 0.7),
          const Color(0xFFFF5252),
          size: 30,
          life: 1.5,
        ));
        SoundService.instance.play(GameSound.noMatch);
      } else {
        _floats.add(_Float('Oops! -15 ${by.kind.short}', head, const Color(0xFFFFAB91), size: 15));
        by.say(['Oops!', 'Sorry Granny!', 'Whoopsie!', 'It was HIM!'][_rnd.nextInt(4)], 1.4);
      }
      return;
    }
    by.score += 10;
    by.splats++;
    _floats.add(_Float(
      by.player ? '+10 SPLAT!' : 'SPLAT!',
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
    for (final c in _cushions) {
      if (c.away > 0) {
        c.away -= dt;
        if (c.away <= 0) {
          c.x = (_rnd.nextDouble() * 2 - 1) * (_halfW - 2);
          c.y = (_rnd.nextDouble() * 2 - 1) * (_halfH - 2);
          if (tables.any((t) => t.inflate(1).contains(Offset(c.x, c.y)))) c.away = 0.5;
        }
        continue;
      }
      for (final g in guys) {
        if (g.dashT > 0) continue;
        if (pow(g.x - c.x, 2) + pow(g.y - c.y, 2) < 0.5) {
          _whoopee(c, g);
          break;
        }
      }
    }
    if (_golden == null) {
      _goldenIn -= dt;
      if (_goldenIn <= 0) {
        var gx = 0.0, gy = 0.0;
        do {
          gx = (_rnd.nextDouble() * 2 - 1) * (_halfW - 2);
          gy = (_rnd.nextDouble() * 2 - 1) * (_halfH - 2);
        } while (tables.any((t) => t.inflate(1).contains(Offset(gx, gy))));
        _golden = (gx, gy);
      }
    } else {
      final (gx, gy) = _golden!;
      for (final g in fighters) {
        if (pow(g.x - gx, 2) + pow(g.y - gy, 2) < 0.6) {
          g.triple = 3;
          _golden = null;
          _goldenIn = 12;
          _floats.add(_Float(
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
      if (g.player || g.triple <= 0 || g.throwT < 0.99) continue;
      final mine = _pies.where((p) => identical(p.by, g));
      if (mine.isEmpty) continue;
      g.triple--;
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
    _floats.add(_Float('PFFFFRRRRT!', V3(c.x, c.y, 1.2), const Color(0xFFFF80AB), size: 28, life: 1.5));
    g.say(
      g.kind == Kind.puppy
          ? '*sniffs it suspiciously*'
          : ['Pardon me!', 'It was NOT me!', 'Oh dear...', 'Excuse ME!'][_rnd.nextInt(4)],
      1.6,
    );
    SoundService.instance.play(GameSound.tooEarly);
    for (final o in guys) {
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
    final save = SaveService.instance;
    final s = max(0, me.score);
    _newBest = s > save.getHighScore(kPieSplatId);
    save.saveHighScore(kPieSplatId, s);
    SoundService.instance.play(place == 1 ? GameSound.win : GameSound.levelComplete);
  }

  List<Guy> get ranking => fighters.toList()..sort((a, b) => b.score.compareTo(a.score));

  int get place => ranking.indexOf(me) + 1;

  void _restart() {
    setState(() {
      _setup();
      _countdown = 2.4;
      _timeLeft = kRoundSeconds;
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
    const places = ['1st', '2nd', '3rd', '4th'];
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
                  Text(
                    '${me.score} pts · ${places[place - 1]}',
                    key: const Key('pie_score'),
                    style: const TextStyle(color: kInk3, fontSize: 18, fontWeight: FontWeight.w900),
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

  static String rankFor(int place, int score) {
    if (place == 1) return 'Supreme Splat Wizard';
    if (score >= 100) return 'Captain Custard';
    if (score >= 40) return 'Splat Sergeant';
    if (score >= 0) return 'Custard Cadet';
    return 'Granny Splatter (oh dear)';
  }

  Widget _results() {
    final best = SaveService.instance.getHighScore(kPieSplatId);
    final rank = ranking;
    final headline = switch (place) {
      1 => 'YOU WIN THE PIE PARTY!',
      2 => 'So close! 2nd place!',
      3 => '3rd place! Not bad!',
      _ => 'Last place... you got creamed!',
    };
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
                    color: rank[i].player ? const Color(0xFFFFE082) : Colors.white,
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
                      Expanded(
                        child: Text(
                          rank[i].kind.short,
                          style: const TextStyle(color: kInk3, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        '${rank[i].score}',
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
                'Splats: ${me.splats}   Strangers splatted: ${me.oops}',
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
                  _button('Play again', const Color(0xFFFF4081), _restart),
                  _button('Menu', Colors.white, () => Navigator.of(context).pop()),
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
      final k = 1.8 - g._faceSplat;
      final a = (g._faceSplat / 0.5).clamp(0.0, 1.0);
      final grow = Curves.easeOutBack.transform(min(1.0, k / 0.15));
      final cream = Paint()..color = kCream3.withValues(alpha: a);
      final rnd = Random(5);
      final centre = Offset(size.width / 2, size.height * 0.45 + k * 30);
      final r = size.shortestSide * 0.42 * grow;
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
        "Splat the show-offs. Dodge their pies. Don't splat the strangers!",
        size.center(Offset(0, big * 0.85)),
        16,
        Colors.white,
        maxWidth: min(size.width - 30, 420),
      );
    }
  }

  Scene3D _scene(Size size) {
    final portrait = size.width < size.height;
    final back = portrait ? 6.5 : 7.0;
    final up = portrait ? 11.0 : 8.0;
    final camX = g._camX.clamp(-5.0, 5.0);
    final camY = g._camY.clamp(-_halfH + 4.0, _halfH - 4.0);
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
    for (var i = 0; i < 11; i++) {
      final x0 = -_halfW + i * 2.0;
      s.poly([
        V3(x0, -_halfH, 0),
        V3(x0 + 2, -_halfH, 0),
        V3(x0 + 2, _halfH, 0),
        V3(x0, _halfH, 0),
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

    for (final p in g.guys) {
      shadow(p.x, p.y, p.radius * 0.9);
    }
    for (final p in g._pies) {
      shadow(p.x, p.y, 0.22);
    }

    // The fence.
    const fence = Color(0xFFFFFFFF);
    const ax = V3(1, 0, 0), ay = V3(0, 1, 0);
    for (var x = -_halfW; x <= _halfW + 0.01; x += 2) {
      for (final y in [-_halfH, _halfH]) {
        s.box(V3(x, y, 0.45), ax, ay, kUp, 0.08, 0.08, 0.45, fence);
      }
    }
    for (var y = -_halfH + 2; y < _halfH; y += 2) {
      for (final x in [-_halfW, _halfW]) {
        s.box(V3(x, y, 0.45), ax, ay, kUp, 0.08, 0.08, 0.45, fence);
      }
    }
    for (final y in [-_halfH, _halfH]) {
      s.box(V3(0, y, 0.6), ax, ay, kUp, _halfW, 0.04, 0.06, fence);
    }
    for (final x in [-_halfW, _halfW]) {
      s.box(V3(x, 0, 0.6), ax, ay, kUp, 0.04, _halfH, 0.06, fence);
    }
    // Balloons on the corners.
    const balloons = [Color(0xFFFF4081), Color(0xFFFFEB3B), Color(0xFF40C4FF), Color(0xFF69F0AE)];
    var bi = 0;
    for (final x in [-_halfW, _halfW]) {
      for (final y in [-_halfH, _halfH]) {
        final bob = sin(g.clock * 2 + bi) * 0.12;
        s.box(V3(x, y, 1.4), ax, ay, kUp, 0.015, 0.015, 0.6, Colors.white);
        s.box(V3(x, y, 2.3 + bob), ax, ay, kUp, 0.3, 0.3, 0.38, balloons[bi % 4]);
        bi++;
      }
    }
    // Party tables with cakes.
    for (final t in PieSplatGameState.tables) {
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
    // Everybody at the party.
    for (final p in g.guys) {
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
    if (top != null && !g._over) {
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
    for (final p in g.guys) {
      final head = s.project(V3(p.x, p.y, p.kind.height + 0.35));
      if (head == null) continue;
      if (p.dizzy > 0 && !p.stranger) {
        for (var i = 0; i < 3; i++) {
          final a = g.clock * 6 + i * pi * 2 / 3;
          _star(c, head + Offset(cos(a) * 16, sin(a) * 5 - 6), 5);
        }
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
