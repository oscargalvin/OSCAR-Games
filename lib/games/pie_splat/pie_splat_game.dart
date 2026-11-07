import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../services/save_service.dart';
import '../../services/sound_service.dart';
import '../../widgets/full_screen_game.dart';
import 'pie_splat_art.dart';

const String kPieSplatId = 'pie_splat';
const double kRoundSeconds = 60;

enum _Phase { empty, rising, up, splatted, sinking }

class _Hole {
  Goof? who;
  _Phase phase = _Phase.empty;
  double t = 0;
  double stay = 0;
  double cooldown = 0;
  bool targeted = false;
  bool angry = false;
  String? line;
  double lineT = 0;

  bool get hittable =>
      who != null && (phase == _Phase.rising || phase == _Phase.up);

  void say(String text, [double time = 1.6]) {
    line = text;
    lineT = time;
  }
}

class _Pie {
  _Pie(this.from, this.to, this.hole, {this.mega = false})
    : dur = 0.12 + (to - from).distance / 2600;
  final Offset from;
  final Offset to;
  final int hole; // -1 = splat the wall
  final bool mega;
  final double dur;
  double t = 0;
}

class _Float {
  _Float(this.text, this.pos, this.color, {this.size = 22, this.life = 1.0});
  final String text;
  final Offset pos;
  final Color color;
  final double size;
  final double life;
  double age = 0;
}

class _Blob {
  _Blob(this.pos, this.r, this.seed);
  final Offset pos;
  final double r;
  final double seed;
  double age = 0;
}

/// The actual game: goofs pop out of windows, you throw custard pies.
class PieSplatGameScreen extends StatefulWidget {
  const PieSplatGameScreen({super.key, this.seed});

  /// For tests: makes the game play out the same every time.
  final int? seed;

  @override
  State<PieSplatGameScreen> createState() => _PieSplatGameScreenState();
}

class _PieSplatGameScreenState extends State<PieSplatGameScreen>
    with SingleTickerProviderStateMixin, FullScreenGame {
  late final Random _rnd = Random(widget.seed);
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  // Round state.
  double _countdown = 2.4;
  double _timeLeft = kRoundSeconds;
  double _elapsed = 0;
  double _clock = 0;
  int _score = 0;
  int _hearts = 3;
  int _combo = 0;
  int _bestCombo = 0;
  int _splats = 0;
  bool _over = false;
  double _overT = 0;
  bool _newBest = false;
  String _review = '';

  double _spawnIn = 0.4;
  double _shake = 0;
  // Granny throws a pie right back at your screen!
  double _faceSplat = 0;
  Offset _faceSplatAt = Offset.zero;
  double _flash = 0;
  String? _comboWord;
  double _comboT = 0;

  // Whoopee cushion.
  double _whoopeeIn = 9;
  double _whoopeeT = 0; // > 0 while it sits on the grass
  double _whoopeeX = 0.2;
  double _whoopeeSquash = 0;

  final List<_Hole> _holes = [];
  final List<_Pie> _pies = [];
  final List<_Float> _floats = [];
  final List<_Blob> _blobs = [];

  // Layout (rebuilt when the screen size changes).
  Size _size = Size.zero;
  List<Rect> _windows = [];
  Rect _wall = Rect.zero;
  Rect _ground = Rect.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    if (_size == Size.zero) return;
    setState(() => _update(dt));
  }

  // ---------------------------------------------------------------- layout

  void _layout(Size size) {
    if (size == _size) return;
    _size = size;
    const top = 64.0;
    final groundH = (size.height * 0.14).clamp(56.0, 96.0);
    _ground = Rect.fromLTRB(0, size.height - groundH, size.width, size.height);
    _wall = Rect.fromLTRB(6, top, size.width - 6, _ground.top);
    final aspect = _wall.width / max(1, _wall.height);
    int cols, rows;
    if (aspect > 2.3) {
      cols = 5;
      rows = 2;
    } else if (aspect > 1.25) {
      cols = 4;
      rows = 2;
    } else if (aspect < 0.62) {
      cols = 3;
      rows = 4;
    } else {
      cols = 3;
      rows = 3;
    }
    final cw = _wall.width / cols, ch = _wall.height / rows;
    final w = min(cw * 0.78, 190.0), h = min(ch * 0.74, 200.0);
    _windows = [
      for (var r = 0; r < rows; r++)
        for (var c = 0; c < cols; c++)
          Rect.fromCenter(
            center: Offset(
              _wall.left + cw * (c + 0.5),
              _wall.top + ch * (r + 0.56),
            ),
            width: w,
            height: h,
          ),
    ];
    if (_holes.length != _windows.length) {
      _holes
        ..clear()
        ..addAll(List.generate(_windows.length, (_) => _Hole()));
      _pies.clear();
    }
  }

  Offset get _throwFrom => Offset(_size.width / 2, _ground.center.dy);

  double _headR(Rect w) => min(w.width, w.height) * 0.3;

  Offset _headAt(int i, double pop) {
    final w = _windows[i];
    final r = _headR(w);
    return Offset(
      w.center.dx,
      w.bottom + r * 1.2 - pop * (r * 1.2 + w.height * 0.48),
    );
  }

  double _pop(_Hole h) => switch (h.phase) {
    _Phase.empty => 0,
    _Phase.rising => Curves.easeOutBack.transform(min(1.0, h.t / 0.2)),
    _Phase.up || _Phase.splatted => 1,
    _Phase.sinking => 1 - min(1.0, h.t / 0.22),
  };

  Offset get _whoopeePos =>
      Offset(_size.width * _whoopeeX, _ground.top + _ground.height * 0.45);

  double get _whoopeeR => (_ground.height * 0.28).clamp(16.0, 26.0);

  // ---------------------------------------------------------------- update

  void _update(double dt) {
    _clock += dt;
    _shake = max(0, _shake - dt);
    _flash = max(0, _flash - dt);
    _faceSplat = max(0, _faceSplat - dt);
    _comboT = max(0, _comboT - dt);
    _whoopeeSquash = max(0, _whoopeeSquash - dt * 1.5);
    for (final f in _floats) {
      f.age += dt;
    }
    _floats.removeWhere((f) => f.age > f.life);
    for (final b in _blobs) {
      b.age += dt;
    }
    _blobs.removeWhere((b) => b.age > 2.5);

    if (_over) {
      _overT += dt;
      _updateHoles(dt, spawn: false);
      return;
    }
    if (_countdown > 0) {
      final before = _countdown.ceil();
      _countdown -= dt;
      if (_countdown.ceil() != before && _countdown > 0) {
        SoundService.instance.play(GameSound.countdownTick);
      }
      return;
    }

    _timeLeft -= dt;
    _elapsed += dt;

    for (final p in _pies) {
      p.t += dt;
    }
    final landed = _pies.where((p) => p.t >= p.dur).toList();
    _pies.removeWhere((p) => p.t >= p.dur);
    for (final p in landed) {
      _land(p);
    }

    _updateHoles(dt, spawn: true);

    // Whoopee cushion now and then.
    if (_whoopeeT > 0) {
      _whoopeeT -= dt;
    } else {
      _whoopeeIn -= dt;
      if (_whoopeeIn <= 0) {
        _whoopeeT = 3.2;
        _whoopeeIn = 9 + _rnd.nextDouble() * 6;
        _whoopeeX = _rnd.nextBool()
            ? 0.12 + _rnd.nextDouble() * 0.2
            : 0.68 + _rnd.nextDouble() * 0.2;
      }
    }

    if (_timeLeft <= 0 || _hearts <= 0) _finish();
  }

  void _updateHoles(double dt, {required bool spawn}) {
    final d = (_elapsed / kRoundSeconds).clamp(0.0, 1.0);
    for (final h in _holes) {
      h.t += dt;
      h.cooldown -= dt;
      if (h.lineT > 0) h.lineT -= dt;
      switch (h.phase) {
        case _Phase.empty:
          break;
        case _Phase.rising:
          if (h.t >= 0.2) {
            h.phase = _Phase.up;
            h.t = 0;
          }
        case _Phase.up:
          if (h.t >= h.stay && !h.targeted) {
            h.phase = _Phase.sinking;
            h.t = 0;
            if (!h.who!.noSplat && _rnd.nextDouble() < 0.3) {
              h.say(
                [
                  'Too slow!',
                  'Nyah nyah!',
                  'Ha! Missed me!',
                  'Bye bye!',
                ][_rnd.nextInt(4)],
                1.1,
              );
            }
          }
        case _Phase.splatted:
          if (h.t >= 1.3) {
            h.phase = _Phase.sinking;
            h.t = 0;
          }
        case _Phase.sinking:
          if (h.t >= 0.22) {
            h.phase = _Phase.empty;
            h.who = null;
            h.angry = false;
            h.cooldown = 0.3;
            h.t = 0;
          }
      }
    }
    if (!spawn) return;

    _spawnIn -= dt;
    final maxUp = (_holes.length * (0.4 + 0.25 * d)).ceil();
    final up = _holes.where((h) => h.who != null).length;
    if (_spawnIn <= 0 && up < maxUp) {
      final free = [
        for (var i = 0; i < _holes.length; i++)
          if (_holes[i].who == null && _holes[i].cooldown <= 0) i,
      ];
      if (free.isNotEmpty) {
        final h = _holes[free[_rnd.nextInt(free.length)]];
        final chickenOut = _holes.any((h) => h.who == Goof.chicken);
        final roll = _rnd.nextDouble();
        final Goof who;
        if (!chickenOut && roll < 0.045 && _elapsed > 5) {
          who = Goof.chicken;
        } else if (roll < 0.22 + 0.08 * d) {
          who = _rnd.nextBool() ? Goof.granny : Goof.puppy;
        } else {
          const baddies = [
            Goof.snooty,
            Goof.moustache,
            Goof.baby,
            Goof.clown,
            Goof.robot,
          ];
          who = baddies[_rnd.nextInt(baddies.length)];
        }
        h
          ..who = who
          ..phase = _Phase.rising
          ..t = 0
          ..targeted = false
          ..stay =
              (1.7 - 0.8 * d) +
              _rnd.nextDouble() * 0.5 +
              (who.noSplat ? 0.6 : 0) +
              (who == Goof.chicken ? -0.3 : 0);
        if (_rnd.nextDouble() < 0.55) {
          final lines = who.popLines;
          h.say(lines[_rnd.nextInt(lines.length)]);
        } else {
          h.lineT = 0;
        }
      }
      _spawnIn = (0.8 - 0.42 * d) * (0.7 + _rnd.nextDouble() * 0.6);
    }
  }

  // ---------------------------------------------------------------- input

  void _tap(Offset p) {
    if (_over || _countdown > 0) return;
    // The whoopee cushion?
    if (_whoopeeT > 0 && (p - _whoopeePos).distance < _whoopeeR * 1.8) {
      _whoopee();
      return;
    }
    for (var i = 0; i < _windows.length; i++) {
      if (!_windows[i].inflate(8).contains(p)) continue;
      final h = _holes[i];
      if (h.targeted) return;
      if (h.hittable) {
        h.targeted = true;
        _pies.add(_Pie(_throwFrom, _headAt(i, 1), i));
        SoundService.instance.play(GameSound.bowTwang);
        return;
      }
      break;
    }
    _pies.add(_Pie(_throwFrom, p, -1));
    SoundService.instance.play(GameSound.bowTwang);
  }

  void _land(_Pie p) {
    if (p.hole < 0) {
      _blobs.add(_Blob(p.to, 26, _rnd.nextDouble() * 1000));
      _floats.add(_Float(
        ['Splorch!', 'Missed!', 'Oops!', 'Whoops!'][_rnd.nextInt(4)],
        p.to,
        Colors.white,
        size: 18,
      ));
      if (_combo >= 3) {
        _floats.add(_Float('Combo lost!', p.to + const Offset(0, 24), const Color(0xFFFFAB91), size: 15));
      }
      _combo = 0;
      // Someone who is still up laughs at you.
      final up = _holes.where((h) => h.phase == _Phase.up && !h.who!.noSplat).toList();
      if (up.isNotEmpty && _rnd.nextDouble() < 0.6) {
        up[_rnd.nextInt(up.length)].say(
          ['HA! Missed!', 'Hee hee hee!', 'Is that all you got?', 'LOL!'][_rnd.nextInt(4)],
          1.2,
        );
      }
      return;
    }
    final h = _holes[p.hole];
    h.targeted = false;
    if (!h.hittable) {
      // They ducked just in time.
      _blobs.add(_Blob(p.to, 22, _rnd.nextDouble() * 1000));
      return;
    }
    _splat(p.hole, mega: p.mega);
  }

  void _splat(int i, {bool mega = false}) {
    final h = _holes[i];
    final who = h.who!;
    h
      ..phase = _Phase.splatted
      ..t = 0;
    final at = _headAt(i, 1);
    final lines = who.splatLines;
    h.say(lines[_rnd.nextInt(lines.length)], 1.4);

    if (who.noSplat) {
      _hearts--;
      _combo = 0;
      _shake = 0.4;
      h.angry = true;
      _floats.add(_Float('-1 heart', at, const Color(0xFFFF5252), size: 24, life: 1.3));
      _floats.add(_Float(
        who == Goof.granny ? 'NOT GRANNY!' : 'NOT THE PUPPY!',
        Offset(_size.width / 2, _wall.top + 40),
        const Color(0xFFFF5252),
        size: 30,
        life: 1.4,
      ));
      SoundService.instance.play(GameSound.noMatch);
      // Revenge: a pie flies back and splats on your screen.
      _faceSplat = 2.6;
      _faceSplatAt = Offset(
        _size.width * (0.3 + _rnd.nextDouble() * 0.4),
        _wall.top + _wall.height * (0.3 + _rnd.nextDouble() * 0.4),
      );
      h.say(who == Goof.granny ? 'Right! Take THAT!' : '*shakes custard everywhere*', 1.6);
      return;
    }

    _splats++;
    if (who == Goof.chicken) {
      _score += 50;
      _flash = 0.35;
      _shake = 0.3;
      _floats.add(_Float('+50', at, const Color(0xFFFFD54F), size: 28));
      _floats.add(_Float(
        'MEGA PIE!!!',
        Offset(_size.width / 2, _wall.top + 50),
        const Color(0xFFFFD54F),
        size: 38,
        life: 1.5,
      ));
      SoundService.instance.play(GameSound.win);
      // Pies fly at every show-off who is still up.
      for (var j = 0; j < _holes.length; j++) {
        final o = _holes[j];
        if (j == i || !o.hittable || o.targeted || o.who!.noSplat) continue;
        o.targeted = true;
        _pies.add(_Pie(_throwFrom, _headAt(j, 1), j, mega: true));
      }
      return;
    }

    if (!mega) _combo++;
    _bestCombo = max(_bestCombo, _combo);
    final mult = min(4, 1 + _combo ~/ 5);
    final pts = 10 * mult;
    _score += pts;
    _floats.add(_Float(mult > 1 ? '+$pts  x$mult' : '+$pts', at, Colors.white, size: 22));
    SoundService.instance.play(GameSound.hit);
    const words = {
      3: 'Giggle!',
      5: 'Chuckle!',
      8: 'LOL!',
      12: 'ROFL!',
      16: 'HYSTERICAL!',
      22: 'COMEDY LEGEND!',
      30: 'UNSTOPPABLE PIE!',
    };
    final word = words[_combo];
    if (word != null) {
      _comboWord = word;
      _comboT = 1.3;
    }
  }

  void _whoopee() {
    _whoopeeT = 0;
    _whoopeeSquash = 1;
    _score += 25;
    _timeLeft += 3;
    _shake = 0.5;
    _floats.add(_Float('PFFFFRRRRT!', _whoopeePos - const Offset(0, 40), const Color(0xFFFF80AB), size: 30, life: 1.4));
    _floats.add(_Float('+25  +3 sec', _whoopeePos - const Offset(0, 8), Colors.white, size: 18, life: 1.3));
    SoundService.instance.play(GameSound.tooEarly);
    // Everyone giggles (and nobody can be bothered to hide for a bit).
    for (final h in _holes) {
      if (h.phase == _Phase.up) {
        h.say(
          ['Hee hee hee!', 'Who did THAT?!', 'Pardon YOU!', 'Ewww!', 'Excuse me!'][_rnd.nextInt(5)],
          1.3,
        );
        h.stay += 0.6;
      }
    }
  }

  void _finish() {
    if (_over) return;
    _over = true;
    _overT = 0;
    _whoopeeT = 0;
    _pies.clear();
    final save = SaveService.instance;
    _newBest = _score > save.getHighScore(kPieSplatId);
    save.saveHighScore(kPieSplatId, _score);
    _review = const [
      "'I laughed so hard my monocle fell off.' - Lord Snootypants",
      "'Ten out of ten. Very sticky.' - Mr Moustachio",
      "'GOO GOO! (best game ever)' - Baby Burp",
      "'Funnier than me. I am retiring.' - Bonko the Clown",
      "'HUMOUR LEVEL: MAXIMUM.' - Robo-Bob",
      "'Woof.' - Biscuit the Puppy",
    ][_rnd.nextInt(6)];
    SoundService.instance.play(
      _hearts <= 0 ? GameSound.gameOver : GameSound.levelComplete,
    );
  }

  void _restart() {
    setState(() {
      _countdown = 2.4;
      _timeLeft = kRoundSeconds;
      _elapsed = 0;
      _score = 0;
      _hearts = 3;
      _combo = 0;
      _bestCombo = 0;
      _splats = 0;
      _over = false;
      _spawnIn = 0.4;
      _whoopeeIn = 9;
      _whoopeeT = 0;
      _comboT = 0;
      _faceSplat = 0;
      _pies.clear();
      _floats.clear();
      _blobs.clear();
      for (final h in _holes) {
        h
          ..who = null
          ..phase = _Phase.empty
          ..lineT = 0
          ..targeted = false;
      }
    });
  }

  static String rankFor(int score) {
    if (score < 100) return 'Pie Beginner';
    if (score < 250) return 'Custard Cadet';
    if (score < 450) return 'Splat Sergeant';
    if (score < 700) return 'Captain Custard';
    if (score < 1000) return 'Lord of the Pies';
    return 'Supreme Splat Wizard';
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF7EC8F2),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            _layout(box.biggest);
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _tap(d.localPosition),
                    child: CustomPaint(painter: _ScenePainter(this)),
                  ),
                ),
                Positioned(left: 0, right: 0, top: 0, child: _hud()),
                if (_over && _overT > 0.7) Positioned.fill(child: _results()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _hud() {
    const ink = kPieInk;
    Widget pill(Widget child, {Color color = Colors.white}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ink, width: 2.5),
      ),
      child: child,
    );
    final secs = max(0, _timeLeft.ceil());
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: pill(const Icon(Icons.arrow_back_rounded, color: ink, size: 22)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: pill(
                  Text(
                    '$_score',
                    key: const Key('pie_score'),
                    style: const TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  color: const Color(0xFFFFE082),
                ),
              ),
            ),
            pill(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_rounded, color: ink, size: 18),
                  const SizedBox(width: 3),
                  Text(
                    '$secs',
                    style: TextStyle(
                      color: secs <= 10 ? const Color(0xFFD32F2F) : ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            pill(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Icon(
                      i < _hearts ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: const Color(0xFFE53935),
                      size: 18,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _results() {
    final best = SaveService.instance.getHighScore(kPieSplatId);
    const ink = kPieInk;
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      // Shrinks to fit when a phone is held sideways.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340, minWidth: 340),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6DC),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: ink, width: 3),
              boxShadow: const [BoxShadow(color: ink, offset: Offset(0, 6))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _hearts <= 0 ? 'Uh oh! Granny is NOT impressed.' : "Time's up!",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  '$_score',
                  style: const TextStyle(color: Color(0xFFE53935), fontSize: 52, fontWeight: FontWeight.w900, height: 1),
                ),
                Text(
                  _newBest ? 'NEW BEST SCORE!' : 'Best: $best',
                  style: TextStyle(
                    color: _newBest ? const Color(0xFF2E7D32) : ink.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You are a ${rankFor(_score)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: ink, fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Splats: $_splats   Best combo: $_bestCombo',
                  style: TextStyle(color: ink.withValues(alpha: 0.75), fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  _review,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ink.withValues(alpha: 0.8), fontStyle: FontStyle.italic, fontSize: 13),
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
          border: Border.all(color: kPieInk, width: 2.5),
          boxShadow: const [BoxShadow(color: kPieInk, offset: Offset(0, 4))],
        ),
        child: Text(
          label,
          style: const TextStyle(color: kPieInk, fontSize: 17, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ painting

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.g);
  final _PieSplatGameScreenState g;

  @override
  void paint(Canvas c, Size size) {
    if (g._windows.isEmpty) return;
    c.save();
    if (g._shake > 0) {
      final s = g._shake * 14;
      c.translate(sin(g._clock * 70) * s, cos(g._clock * 53) * s);
    }
    _background(c, size);
    for (var i = 0; i < g._windows.length; i++) {
      _window(c, i);
    }
    for (final b in g._blobs) {
      paintWallSplat(c, b.pos, b.r, b.seed, (1 - b.age / 2.5).clamp(0.0, 1.0));
    }
    _groundStuff(c, size);
    for (final p in g._pies) {
      final k = (p.t / p.dur).clamp(0.0, 1.0);
      final pos = Offset.lerp(p.from, p.to, k)! - Offset(0, sin(k * pi) * 50);
      final base = (g._ground.height * 0.32).clamp(18.0, 28.0);
      paintPie(c, pos, base * (1 - 0.35 * k), spin: k * 6);
    }
    for (var i = 0; i < g._holes.length; i++) {
      final h = g._holes[i];
      if (h.lineT > 0 && h.line != null) _bubble(c, i, h.line!, size);
    }
    c.restore();

    for (final f in g._floats) {
      final k = f.age / f.life;
      _text(
        c,
        f.text,
        f.pos - Offset(0, 50 * k),
        f.size * (k < 0.15 ? 0.6 + k * 2.7 : 1),
        f.color.withValues(alpha: (1 - k * k).clamp(0.0, 1.0)),
        maxWidth: size.width - 20,
        clampTo: size,
      );
    }
    if (g._comboT > 0 && g._comboWord != null) {
      final k = 1 - g._comboT / 1.3;
      _text(
        c,
        g._comboWord!,
        Offset(size.width / 2, g._wall.top + g._wall.height * 0.5),
        (min(size.width, 600) / 9) * (k < 0.15 ? 0.5 + k * 3.3 : 1),
        const Color(0xFFFFEB3B).withValues(alpha: (g._comboT / 0.4).clamp(0.0, 1.0)),
        maxWidth: size.width - 20,
      );
    }
    if (g._faceSplat > 0) {
      // Custard all over your screen, sliding slowly down.
      final k = 2.6 - g._faceSplat;
      final grow = Curves.easeOutBack.transform(min(1.0, k / 0.15));
      final r = size.shortestSide * 0.33 * grow;
      final at = g._faceSplatAt + Offset(0, k * 18);
      paintWallSplat(c, at, r, 7, (g._faceSplat / 0.6).clamp(0.0, 1.0));
      if (k > 0.2 && k < 2.0) {
        _text(c, 'SPLAT! Right in your face!', at + Offset(0, r * 0.1), 20, const Color(0xFFFF5252),
            maxWidth: size.width - 30, clampTo: size);
      }
    }
    if (g._flash > 0) {
      c.drawRect(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: g._flash * 1.5));
    }
    if (g._countdown > 0) {
      c.drawRect(Offset.zero & size, Paint()..color = const Color(0x55000000));
      final cd = g._countdown;
      final shown = cd > 1.8 ? '3' : cd > 1.2 ? '2' : cd > 0.6 ? '1' : 'PIE!';
      _text(c, shown, size.center(Offset.zero), min(size.shortestSide * 0.3, 120), Colors.white);
      _text(
        c,
        "Splat the show-offs! Don't splat Granny or the puppy!",
        size.center(Offset(0, min(size.shortestSide * 0.3, 120) * 0.8)),
        16,
        Colors.white,
        maxWidth: min(size.width - 30, 420),
      );
    }
  }

  void _background(Canvas c, Size size) {
    // Sky with fluffy clouds.
    c.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5BB8F0), Color(0xFFB8E4FF)],
        ).createShader(Offset.zero & size),
    );
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (var i = 0; i < 3; i++) {
      final x = ((g._clock * 12 + i * size.width * 0.45) % (size.width + 160)) - 80;
      final y = 30.0 + i * 22;
      c.drawCircle(Offset(x, y), 18, cloud);
      c.drawCircle(Offset(x + 20, y - 8), 22, cloud);
      c.drawCircle(Offset(x + 44, y), 17, cloud);
    }
    // The house wall.
    final wall = RRect.fromRectAndCorners(
      g._wall,
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
    );
    c.drawRRect(wall, Paint()..color = const Color(0xFFF6B79F));
    // Bricks.
    final brick = Paint()
      ..color = const Color(0x22A0402A)
      ..strokeWidth = 1.5;
    c.save();
    c.clipRRect(wall);
    for (var y = g._wall.top + 18; y < g._wall.bottom; y += 18) {
      c.drawLine(Offset(g._wall.left, y), Offset(g._wall.right, y), brick);
      final row = ((y - g._wall.top) / 18).round();
      for (var x = g._wall.left + (row.isEven ? 0 : 20); x < g._wall.right; x += 40) {
        c.drawLine(Offset(x, y - 18), Offset(x, y), brick);
      }
    }
    c.restore();
    c.drawRRect(wall, Paint()
      ..color = kPieInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
  }

  void _window(Canvas c, int i) {
    final w = g._windows[i];
    final h = g._holes[i];
    final rr = RRect.fromRectAndRadius(w, const Radius.circular(10));
    c.drawRRect(rr, Paint()..color = const Color(0xFF2B2140));
    // Warm light inside and little curtains.
    c.drawRRect(
      rr.deflate(4),
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFFFFE0A3).withValues(alpha: 0.5), Colors.transparent],
        ).createShader(w),
    );
    final curtain = Paint()..color = const Color(0xFF8E44AD);
    c.drawPath(
      Path()
        ..moveTo(w.left, w.top)
        ..lineTo(w.left + w.width * 0.28, w.top)
        ..quadraticBezierTo(w.left + w.width * 0.08, w.top + w.height * 0.4, w.left, w.top + w.height * 0.62)
        ..close(),
      curtain,
    );
    c.drawPath(
      Path()
        ..moveTo(w.right, w.top)
        ..lineTo(w.right - w.width * 0.28, w.top)
        ..quadraticBezierTo(w.right - w.width * 0.08, w.top + w.height * 0.4, w.right, w.top + w.height * 0.62)
        ..close(),
      curtain,
    );

    if (h.who != null) {
      final pop = g._pop(h);
      final r = g._headR(w);
      final o = g._headAt(i, pop);
      c.save();
      c.clipRRect(rr);
      c.translate(o.dx, o.dy);
      final wobble = h.phase == _Phase.splatted
          ? sin(h.t * 25) * 0.12 * max(0, 1 - h.t * 2)
          : sin(g._clock * 5 + i) * 0.06;
      c.rotate(wobble);
      paintGoof(
        c,
        h.who!,
        Offset.zero,
        r,
        time: g._clock + i * 1.3,
        splat: h.phase == _Phase.splatted || (h.phase == _Phase.sinking && h.angry)
            ? h.t + (h.phase == _Phase.sinking ? 1.3 : 0)
            : null,
      );
      c.restore();
    }

    // Window frame and sill on top.
    c.drawRRect(rr, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5);
    c.drawRRect(rr.inflate(2.5), Paint()
      ..color = kPieInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    final sill = RRect.fromRectAndRadius(
      Rect.fromLTRB(w.left - 6, w.bottom - 2, w.right + 6, w.bottom + 9),
      const Radius.circular(4),
    );
    c.drawRRect(sill, Paint()..color = Colors.white);
    c.drawRRect(sill, Paint()
      ..color = kPieInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  void _groundStuff(Canvas c, Size size) {
    final gr = g._ground;
    c.drawRect(gr, Paint()..color = const Color(0xFF66BB6A));
    c.drawLine(gr.topLeft, gr.topRight, Paint()
      ..color = kPieInk
      ..strokeWidth = 3);
    final tuft = Paint()
      ..color = const Color(0xFF43A047)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var x = 10.0; x < size.width; x += 34) {
      final y = gr.top + 14 + (x * 7) % 20;
      c.drawLine(Offset(x, y), Offset(x - 4, y - 8), tuft);
      c.drawLine(Offset(x, y), Offset(x + 4, y - 9), tuft);
    }
    // The pie table, with a big stack of pies ready to throw.
    final t = g._throwFrom;
    final pr = (gr.height * 0.32).clamp(18.0, 28.0);
    final table = Rect.fromCenter(center: t + Offset(0, pr * 0.9), width: pr * 4.4, height: pr * 0.5);
    c.drawRRect(RRect.fromRectAndRadius(table, const Radius.circular(4)), Paint()..color = const Color(0xFF8D6E63));
    for (var k = 0; k < 3; k++) {
      paintPie(c, t + Offset((k - 1) * pr * 1.3, pr * 0.35 - (k == 1 ? pr * 0.25 : 0)), pr * 0.75);
    }
    if (g._whoopeeT > 0 || g._whoopeeSquash > 0) {
      final grow = g._whoopeeT > 0 ? min(1.0, (3.2 - g._whoopeeT) / 0.25) : 1.0;
      paintWhoopee(c, g._whoopeePos, g._whoopeeR * grow, g._whoopeeSquash, g._clock);
      if (g._whoopeeT > 0) {
        _text(c, 'TAP ME!', g._whoopeePos - Offset(0, g._whoopeeR * 1.4), 12, kPieInk, maxWidth: 80);
      }
    }
  }

  void _bubble(Canvas c, int i, String text, Size size) {
    final w = g._windows[i];
    final fontSize = (w.width / 9).clamp(11.0, 15.0);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: kPieInk, fontSize: fontSize, fontWeight: FontWeight.w800, height: 1.1),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: max(90, w.width * 1.25));
    final bw = tp.width + 16, bh = tp.height + 10;
    var cx = w.center.dx;
    cx = cx.clamp(bw / 2 + 4, size.width - bw / 2 - 4);
    var top = w.top - bh - 6;
    top = max(top, g._wall.top - 6);
    final box = Rect.fromLTWH(cx - bw / 2, top, bw, bh);
    final rr = RRect.fromRectAndRadius(box, const Radius.circular(12));
    final tail = Path()
      ..moveTo(w.center.dx - 7, box.bottom - 1)
      ..lineTo(w.center.dx + 7, box.bottom - 1)
      ..lineTo(w.center.dx + 2, box.bottom + 9)
      ..close();
    final fill = Paint()..color = Colors.white;
    final line = Paint()
      ..color = kPieInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    c.drawPath(tail, fill);
    c.drawPath(tail, line);
    c.drawRRect(rr, fill);
    c.drawRRect(rr, line);
    tp.paint(c, Offset(box.left + 8, box.top + 5));
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
        ..color = kPieInk.withValues(alpha: color.a),
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
