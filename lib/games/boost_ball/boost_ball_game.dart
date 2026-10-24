import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/sound_service.dart';
import 'boost_ball_data.dart';
import 'boost_ball_sim.dart';

const Color kBlueTeam = Color(0xFF2196F3);
const Color kOrangeTeam = Color(0xFFFF7043);

const List<String> _botNames = [
  'Turbo',
  'Zippy',
  'Nitro',
  'Bolt',
  'Skid',
  'Rocket Rex',
  'Vroom',
  'Drifty',
  'Bumper',
  'Gizmo',
];

/// Where the pitch sits on screen. On a tall screen the pitch runs up the
/// screen (you attack upwards); on a wide screen it runs left to right.
class _View {
  final bool landscape;
  final double scale;
  final Offset centre;

  _View(this.landscape, this.scale, this.centre);

  factory _View.of(Size size) {
    final landscape = size.width > size.height;
    const long = kFieldL + kGoalDepth * 2 + 4;
    const wide = kFieldW + 4;
    if (landscape) {
      const top = 54.0, bottom = 6.0;
      final s = min(size.width / long, (size.height - top - bottom) / wide);
      return _View(
        true,
        s,
        Offset(size.width / 2, top + (size.height - top - bottom) / 2),
      );
    }
    const top = 64.0, bottom = 176.0;
    final s = min(size.width / wide, (size.height - top - bottom) / long);
    return _View(
      false,
      s,
      Offset(size.width / 2, top + (size.height - top - bottom) / 2),
    );
  }

  /// A point on the pitch (at height [z]) to the screen.
  Offset at(double x, double y, [double z = 0]) {
    final dx = x - kFieldW / 2, dy = y - kFieldL / 2;
    final p = landscape
        ? centre + Offset(dy, dx) * scale
        : centre + Offset(dx, -dy) * scale;
    return p - Offset(0, z * scale * 0.55);
  }

  /// A direction on the pitch to a direction on screen.
  Offset dirToScreen(Offset d) =>
      landscape ? Offset(d.dy, d.dx) : Offset(d.dx, -d.dy);

  /// A direction on screen (like the joystick) to a pitch direction.
  Offset dirToPitch(Offset d) =>
      landscape ? Offset(d.dy, d.dx) : Offset(d.dx, -d.dy);
}

class _Spark {
  Offset pos; // screen
  Offset vel;
  final Color colour;
  double life;
  _Spark(this.pos, this.vel, this.colour, this.life);
}

/// A match of Boost Ball against bots.
class BoostBallGameScreen extends StatefulWidget {
  final int teamSize;
  final int difficulty;
  final double length;

  const BoostBallGameScreen({
    super.key,
    this.teamSize = 1,
    this.difficulty = 1,
    this.length = 150,
  });

  @override
  State<BoostBallGameScreen> createState() => _BoostBallGameScreenState();
}

class _BoostBallGameScreenState extends State<BoostBallGameScreen>
    with SingleTickerProviderStateMixin {
  final _save = BoostBallSave.instance;
  final _rnd = Random();
  final _focus = FocusNode();
  late final Ticker _ticker;
  late final BoostBallMatch _match;
  late final Car _you;
  Duration _last = Duration.zero;
  Size _size = Size.zero;

  // Touch controls.
  int? _stickPointer;
  Offset? _stickStart;
  Offset _stickNow = Offset.zero;
  bool _boostHeld = false;
  final Set<LogicalKeyboardKey> _keys = {};

  final List<_Spark> _sparks = [];
  double _shake = 0;
  int _lastCount = -1;
  bool _paid = false;
  int _coinsWon = 0;

  @override
  void initState() {
    super.initState();
    final names = [..._botNames]..shuffle(_rnd);
    var n = 0;
    _you = Car(
      team: 0,
      name: 'You',
      isYou: true,
      spec: carById(_save.car),
      colour: _save.colour,
    );
    final cars = <Car>[_you];
    for (var i = 1; i < widget.teamSize; i++) {
      cars.add(
        Car(
          team: 0,
          name: names[n++],
          spec: kCars[_rnd.nextInt(kCars.length)],
          difficulty: 1,
        ),
      );
    }
    for (var i = 0; i < widget.teamSize; i++) {
      cars.add(
        Car(
          team: 1,
          name: names[n++],
          spec: kCars[_rnd.nextInt(kCars.length)],
          difficulty: widget.difficulty,
        ),
      );
    }
    _match = BoostBallMatch(
      teamSize: widget.teamSize,
      players: cars,
      length: widget.length,
      random: _rnd,
    );
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 0.016
        : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    _readControls();
    _match.step(dt);
    _handleEvents();
    _shake = max(0, _shake - dt * 3);
    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel = Offset(s.vel.dx * 0.96, s.vel.dy * 0.96 + 300 * dt);
      s.life -= dt;
    }
    _sparks.removeWhere((s) => s.life <= 0);
    if (_match.phase == MatchPhase.kickoff) {
      final count = (kKickoffTime - _match.phaseT).ceil();
      if (count != _lastCount && count > 0) {
        _lastCount = count;
        SoundService.instance.play(GameSound.countdownTick);
      }
    }
    if (_match.phase == MatchPhase.over && !_paid) _finish();
    setState(() {});
  }

  void _readControls() {
    final inp = _you.input;
    var stick = Offset.zero;
    if (_stickStart != null) {
      final d = _stickNow - _stickStart!;
      stick = d.distance < 6 ? Offset.zero : d / max(d.distance, 50);
    }
    var kx = 0.0, ky = 0.0;
    if (_keys.contains(LogicalKeyboardKey.arrowLeft) ||
        _keys.contains(LogicalKeyboardKey.keyA)) {
      kx -= 1;
    }
    if (_keys.contains(LogicalKeyboardKey.arrowRight) ||
        _keys.contains(LogicalKeyboardKey.keyD)) {
      kx += 1;
    }
    if (_keys.contains(LogicalKeyboardKey.arrowUp) ||
        _keys.contains(LogicalKeyboardKey.keyW)) {
      ky -= 1;
    }
    if (_keys.contains(LogicalKeyboardKey.arrowDown) ||
        _keys.contains(LogicalKeyboardKey.keyS)) {
      ky += 1;
    }
    if (kx != 0 || ky != 0) {
      stick = Offset(kx, ky) / Offset(kx, ky).distance;
    }
    final view = _View.of(_size);
    inp.stick = view.dirToPitch(stick);
    inp.boost =
        _boostHeld ||
        _keys.contains(LogicalKeyboardKey.shiftLeft) ||
        _keys.contains(LogicalKeyboardKey.shiftRight);
  }

  void _jump() {
    if (_match.phase == MatchPhase.play || _match.phase == MatchPhase.goal) {
      _you.input.jump = true;
    }
  }

  void _handleEvents() {
    for (final e in _match.events) {
      switch (e) {
        case MatchEvent.hit:
          SoundService.instance.play(GameSound.place);
        case MatchEvent.bigHit:
          SoundService.instance.play(GameSound.hit);
          _shake = max(_shake, 0.3);
        case MatchEvent.goal:
          SoundService.instance.play(GameSound.win);
          _shake = 1;
          _goalSparks();
        case MatchEvent.demolish:
          SoundService.instance.play(GameSound.hit);
          _shake = max(_shake, 0.6);
        case MatchEvent.whistle:
          SoundService.instance.play(GameSound.countdown);
        case MatchEvent.boostPad:
          SoundService.instance.play(GameSound.eat);
        case MatchEvent.kickoff:
          _lastCount = -1;
      }
    }
    _match.events.clear();
  }

  void _goalSparks() {
    final view = _View.of(_size);
    final b = _match.ball;
    final at = view.at(b.x, b.y, b.z);
    final team = _match.lastScorerTeam ?? 0;
    final colours = team == 0
        ? const [kBlueTeam, Colors.white, Color(0xFF90CAF9)]
        : const [kOrangeTeam, Colors.white, Color(0xFFFFCC80)];
    for (var i = 0; i < 90; i++) {
      final a = _rnd.nextDouble() * 2 * pi;
      final sp = 80 + _rnd.nextDouble() * 320;
      _sparks.add(
        _Spark(
          at,
          Offset(cos(a), sin(a)) * sp - const Offset(0, 120),
          colours[i % colours.length],
          0.8 + _rnd.nextDouble() * 1.2,
        ),
      );
    }
  }

  void _finish() {
    _paid = true;
    final won = _match.leader == 0;
    if (won) {
      _coinsWon = kWinCoins[widget.difficulty];
      _save.coins += _coinsWon;
      _save.wins++;
      SoundService.instance.play(GameSound.levelComplete);
    } else {
      _save.losses++;
      SoundService.instance.play(GameSound.levelFail);
    }
    _save.goals += _you.goals;
    _save.save();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent) {
      _keys.add(e.logicalKey);
      if (e.logicalKey == LogicalKeyboardKey.space) _jump();
    } else if (e is KeyUpEvent) {
      _keys.remove(e.logicalKey);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1A2B),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (context, box) {
            _size = box.biggest;
            final landscape = _size.width > _size.height;
            return Stack(
              children: [
                // Drag anywhere on the left side to drive.
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) {
                      if (_stickPointer == null &&
                          e.localPosition.dx < _size.width * 0.55) {
                        _stickPointer = e.pointer;
                        _stickStart = e.localPosition;
                        _stickNow = e.localPosition;
                      }
                    },
                    onPointerMove: (e) {
                      if (e.pointer == _stickPointer) {
                        _stickNow = e.localPosition;
                      }
                    },
                    onPointerUp: (e) => _release(e.pointer),
                    onPointerCancel: (e) => _release(e.pointer),
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _PitchPainter(this),
                    ),
                  ),
                ),
                _scoreBar(),
                Positioned(
                  left: 8,
                  top: 8,
                  child: SafeArea(
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black38,
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
                Positioned(
                  right: 18,
                  bottom: landscape ? 16 : 24,
                  child: _jumpButton(),
                ),
                Positioned(
                  right: landscape ? 104 : 112,
                  bottom: landscape ? 28 : 40,
                  child: _boostButton(),
                ),
                if (_stickStart == null)
                  Positioned(
                    left: 24,
                    bottom: landscape ? 20 : 54,
                    child: const IgnorePointer(
                      child: Text(
                        'Drag here to drive',
                        style: TextStyle(
                          color: Colors.white54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if (_match.phase == MatchPhase.over) _endCard(),
              ],
            );
          },
        ),
      ),
    );
  }

  void _release(int pointer) {
    if (pointer == _stickPointer) {
      _stickPointer = null;
      _stickStart = null;
    }
  }

  Widget _scoreBar() {
    final t = _match.clock.ceil();
    final time = _match.overtime
        ? 'OT'
        : '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
    Widget box(String text, Color c) => Container(
      width: 46,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            box('${_match.score[0]}', kBlueTeam),
            Container(
              width: 70,
              height: 34,
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                time,
                style: TextStyle(
                  color: _match.overtime || t <= 10
                      ? const Color(0xFFFFD54F)
                      : Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            box('${_match.score[1]}', kOrangeTeam),
          ],
        ),
      ),
    );
  }

  Widget _jumpButton() {
    return Listener(
      onPointerDown: (_) => _jump(),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: const Color(0xFF43A047).withValues(alpha: 0.85),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70, width: 3),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.keyboard_double_arrow_up_rounded, color: Colors.white),
            Text(
              'JUMP',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boostButton() {
    final full = _you.boost / kMaxBoost;
    return Listener(
      onPointerDown: (_) => _boostHeld = true,
      onPointerUp: (_) => _boostHeld = false,
      onPointerCancel: (_) => _boostHeld = false,
      child: SizedBox(
        width: 76,
        height: 76,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: full,
                strokeWidth: 6,
                backgroundColor: Colors.black38,
                color: const Color(0xFFFFB300),
              ),
            ),
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: (_boostHeld ? const Color(0xFFFF6D00) : kOrangeTeam)
                    .withValues(alpha: 0.85),
                shape: BoxShape.circle,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'BOOST',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '${_you.boost.round()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
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

  Widget _endCard() {
    final leader = _match.leader;
    final title = leader == 0
        ? 'YOU WIN!'
        : leader == 1
        ? 'YOU LOSE'
        : 'DRAW';
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        alignment: Alignment.center,
        child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(22),
            constraints: const BoxConstraints(maxWidth: 360),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2A41),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: leader == 0 ? kBlueTeam : kOrangeTeam,
                width: 3,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: leader == 0 ? const Color(0xFF90CAF9) : kOrangeTeam,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Blue ${_match.score[0]} - ${_match.score[1]} Orange',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  'You scored ${_you.goals}',
                  style: const TextStyle(color: Colors.white70),
                ),
                if (_coinsWon > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '+$_coinsWon coins',
                    style: const TextStyle(
                      color: Color(0xFFFFD54F),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => BoostBallGameScreen(
                          teamSize: widget.teamSize,
                          difficulty: widget.difficulty,
                          length: widget.length,
                        ),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBlueTeam,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'PLAY AGAIN',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back to garage'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Drawing.
// ===========================================================================

class _PitchPainter extends CustomPainter {
  final _BoostBallGameScreenState s;
  _PitchPainter(this.s);

  late _View v;

  BoostBallMatch get m => s._match;

  @override
  void paint(Canvas canvas, Size size) {
    v = _View.of(size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E1A2B), Color(0xFF1C2E4A)],
        ).createShader(Offset.zero & size),
    );
    canvas.save();
    if (s._shake > 0) {
      final r = s._rnd;
      canvas.translate(
        (r.nextDouble() - 0.5) * 10 * s._shake,
        (r.nextDouble() - 0.5) * 10 * s._shake,
      );
    }
    _paintPitch(canvas);
    _paintPads(canvas);
    _paintShadows(canvas);
    // Draw low things first so jumping cars and high balls sit on top.
    final things = <(double, void Function())>[
      for (final c in m.cars)
        if (c.alive) (c.z, () => _paintCar(canvas, c)),
      (m.ball.z - kBallR, () => _paintBall(canvas)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final t in things) {
      t.$2();
    }
    _paintGoalFrames(canvas);
    canvas.restore();
    for (final sp in s._sparks) {
      canvas.drawCircle(
        sp.pos,
        3,
        Paint()..color = sp.colour.withValues(alpha: sp.life.clamp(0, 1)),
      );
    }
    _paintStick(canvas);
    _paintMessages(canvas, size);
  }

  Path _pitchPath() {
    final pts = [
      const Offset(kCorner, 0),
      const Offset(kFieldW / 2 - kGoalW / 2, 0),
      const Offset(kFieldW / 2 - kGoalW / 2, -kGoalDepth),
      const Offset(kFieldW / 2 + kGoalW / 2, -kGoalDepth),
      const Offset(kFieldW / 2 + kGoalW / 2, 0),
      const Offset(kFieldW - kCorner, 0),
      const Offset(kFieldW, kCorner),
      const Offset(kFieldW, kFieldL - kCorner),
      const Offset(kFieldW - kCorner, kFieldL),
      const Offset(kFieldW / 2 + kGoalW / 2, kFieldL),
      const Offset(kFieldW / 2 + kGoalW / 2, kFieldL + kGoalDepth),
      const Offset(kFieldW / 2 - kGoalW / 2, kFieldL + kGoalDepth),
      const Offset(kFieldW / 2 - kGoalW / 2, kFieldL),
      const Offset(kCorner, kFieldL),
      const Offset(0, kFieldL - kCorner),
      const Offset(0, kCorner),
    ];
    return Path()..addPolygon([for (final p in pts) v.at(p.dx, p.dy)], true);
  }

  void _paintPitch(Canvas canvas) {
    final pitch = _pitchPath();
    canvas.drawPath(
      pitch,
      Paint()
        ..color = Colors.black45
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.save();
    canvas.clipPath(pitch);
    // Mown stripes.
    for (var i = -1; i < 11; i++) {
      final a = v.at(-5, i * 10.0), b = v.at(kFieldW + 5, i * 10.0 + 10);
      canvas.drawRect(
        Rect.fromPoints(a, b),
        Paint()
          ..color = i.isEven
              ? const Color(0xFF2E7D32)
              : const Color(0xFF388E3C),
      );
    }
    // The goals, in team colours.
    for (final (y0, c) in [(-kGoalDepth, kBlueTeam), (kFieldL, kOrangeTeam)]) {
      final r = Rect.fromPoints(
        v.at(kFieldW / 2 - kGoalW / 2, y0),
        v.at(kFieldW / 2 + kGoalW / 2, y0 + kGoalDepth),
      );
      canvas.drawRect(r, Paint()..color = c.withValues(alpha: 0.35));
      final net = Paint()
        ..color = Colors.white24
        ..strokeWidth = 1;
      for (var x = r.left; x < r.right; x += 6) {
        canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), net);
      }
      for (var y = r.top; y < r.bottom; y += 6) {
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), net);
      }
    }
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, v.scale * 0.35);
    canvas.drawLine(v.at(0, kFieldL / 2), v.at(kFieldW, kFieldL / 2), line);
    canvas.drawCircle(v.at(kFieldW / 2, kFieldL / 2), 9 * v.scale, line);
    canvas.drawCircle(
      v.at(kFieldW / 2, kFieldL / 2),
      v.scale * 0.8,
      Paint()..color = Colors.white,
    );
    for (final (y0, y1) in [(0.0, 14.0), (kFieldL, kFieldL - 14)]) {
      canvas.drawRect(
        Rect.fromPoints(v.at(kFieldW / 2 - 16, y0), v.at(kFieldW / 2 + 16, y1)),
        line,
      );
    }
    // Team-coloured ends of the pitch.
    for (final (y0, y1, c) in [
      (0.0, 3.0, kBlueTeam),
      (kFieldL - 3, kFieldL, kOrangeTeam),
    ]) {
      canvas.drawRect(
        Rect.fromPoints(v.at(-5, y0), v.at(kFieldW + 5, y1)),
        Paint()..color = c.withValues(alpha: 0.25),
      );
    }
    canvas.restore();
    // The walls round the outside.
    canvas.drawPath(
      pitch,
      Paint()
        ..color = const Color(0xFFB0BEC5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(3, v.scale * 0.9)
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintGoalFrames(Canvas canvas) {
    for (final (y, c) in [(0.0, kBlueTeam), (kFieldL, kOrangeTeam)]) {
      final postL = v.at(kFieldW / 2 - kGoalW / 2, y);
      final postR = v.at(kFieldW / 2 + kGoalW / 2, y);
      final barL = v.at(kFieldW / 2 - kGoalW / 2, y, kGoalH);
      final barR = v.at(kFieldW / 2 + kGoalW / 2, y, kGoalH);
      final p = Paint()
        ..color = Color.lerp(c, Colors.white, 0.4)!
        ..strokeWidth = max(2.5, v.scale * 0.7)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(postL, barL, p);
      canvas.drawLine(postR, barR, p);
      canvas.drawLine(barL, barR, p);
    }
  }

  void _paintPads(Canvas canvas) {
    for (final p in m.pads) {
      final at = v.at(p.pos.dx, p.pos.dy);
      final r = (p.big ? 1.6 : 0.8) * v.scale;
      if (!p.ready) {
        canvas.drawCircle(at, r, Paint()..color = Colors.black26);
        continue;
      }
      final glow = 0.6 + 0.4 * sin(m.phaseT * 4 + p.pos.dx);
      canvas.drawCircle(
        at,
        r * 1.8,
        Paint()
          ..color = const Color(0xFFFFB300).withValues(alpha: 0.25 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..color = p.big ? const Color(0xFFFF9100) : const Color(0xFFFFD54F),
      );
    }
  }

  void _paintShadows(Canvas canvas) {
    final shade = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    for (final c in m.cars) {
      if (!c.alive) continue;
      final r = kCarR * v.scale * (1 - min(0.4, c.z / 20));
      canvas.drawOval(
        Rect.fromCenter(
          center: v.at(c.x, c.y),
          width: r * 2.2,
          height: r * 1.4,
        ),
        shade,
      );
    }
    final b = m.ball;
    final r = kBallR * v.scale * (1 - min(0.5, (b.z - kBallR) / 25));
    canvas.drawOval(
      Rect.fromCenter(center: v.at(b.x, b.y), width: r * 2, height: r * 1.3),
      shade,
    );
    if (b.z > kBallR + 3) {
      // A ring on the grass shows where a high ball is.
      canvas.drawCircle(
        v.at(b.x, b.y),
        kBallR * v.scale,
        Paint()
          ..color = Colors.white38
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _paintBall(Canvas canvas) {
    final b = m.ball;
    final at = v.at(b.x, b.y, b.z);
    final r = kBallR * v.scale * (1 + (b.z - kBallR) * 0.02);
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          colors: const [Colors.white, Color(0xFFCFD8DC), Color(0xFF78909C)],
        ).createShader(Rect.fromCircle(center: at, radius: r)),
    );
    // Spinning hexagon patches.
    final patch = Paint()..color = const Color(0xFF37474F);
    for (var i = 0; i < 5; i++) {
      final a = b.spin + i * 2 * pi / 5;
      final p = at + Offset(cos(a), sin(a) * 0.8) * r * 0.55;
      canvas.drawCircle(p, r * 0.2, patch);
    }
    canvas.drawCircle(at, r * 0.22, patch);
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  Color _paintOf(Car c) {
    if (c.isYou) return kCarColours[c.colour];
    final shades = c.team == 0
        ? const [Color(0xFF1565C0), Color(0xFF42A5F5), Color(0xFF0D47A1)]
        : const [Color(0xFFE64A19), Color(0xFFFF8A65), Color(0xFFBF360C)];
    return shades[c.name.length % shades.length];
  }

  void _paintCar(Canvas canvas, Car c) {
    final at = v.at(c.x, c.y, c.z);
    final dir = v.dirToScreen(c.forward);
    final grow = 1 + c.z * 0.03;
    final u =
        v.scale * grow * 1.2; // cars drawn a bit big so they're easy to see
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(dir.direction);
    if (c.flipT > 0) {
      // Spin round during a flip.
      canvas.rotate((0.5 - c.flipT) / 0.5 * 2 * pi);
    }
    final team = c.team == 0 ? kBlueTeam : kOrangeTeam;
    final body = _paintOf(c);

    // Boost flame out the back.
    if (c.boosting) {
      final flick = 0.7 + s._rnd.nextDouble() * 0.6;
      final flame = Path()
        ..moveTo(-2.2 * u, -0.7 * u)
        ..lineTo(-(3.6 + 1.8 * flick) * u, 0)
        ..lineTo(-2.2 * u, 0.7 * u)
        ..close();
      canvas.drawPath(flame, Paint()..color = const Color(0xFFFF6D00));
      canvas.drawPath(
        flame,
        Paint()
          ..color = const Color(0xFFFFEB3B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.3 * u,
      );
    }

    // Glow in your team colour so you can tell who's who.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 5.2 * u, height: 3.2 * u),
        Radius.circular(1 * u),
      ),
      Paint()
        ..color = team.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.6 * u),
    );

    final tyre = Paint()..color = const Color(0xFF212121);
    void wheels(double len, double wide, double w, double h) {
      for (final x in [-len, len]) {
        for (final y in [-wide, wide]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(x * u, y * u),
                width: w * u,
                height: h * u,
              ),
              Radius.circular(0.3 * u),
            ),
            tyre,
          );
        }
      }
    }

    RRect box(double x, double y, double w, double h, double r) =>
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * u, y * u, w * u, h * u),
          Radius.circular(r * u),
        );
    final paintBody = Paint()..color = body;
    final dark = Paint()..color = const Color(0xFF102027);
    final edge = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.15 * u;

    switch (c.spec.body) {
      case CarBody.sport:
        wheels(1.4, 1.15, 1.1, 0.6);
        canvas.drawRRect(box(-2.3, -1.15, 4.6, 2.3, 0.8), paintBody);
        canvas.drawRRect(box(-2.3, -1.15, 4.6, 2.3, 0.8), edge);
        canvas.drawRRect(box(0.2, -0.9, 1.0, 1.8, 0.3), dark); // windscreen
        canvas.drawRRect(box(-1.4, -0.85, 0.9, 1.7, 0.3), dark);
        canvas.drawRect(
          Rect.fromLTWH(-2.6 * u, -1.2 * u, 0.4 * u, 2.4 * u),
          dark,
        ); // spoiler
        canvas.drawRect(
          Rect.fromLTWH(-2.3 * u, -0.2 * u, 4.6 * u, 0.4 * u),
          Paint()..color = Colors.white70,
        );
      case CarBody.hornet:
        wheels(1.5, 1.0, 1.0, 0.5);
        final p = Path()
          ..moveTo(2.8 * u, 0)
          ..lineTo(0.8 * u, -1.0 * u)
          ..lineTo(-2.3 * u, -1.0 * u)
          ..lineTo(-2.3 * u, 1.0 * u)
          ..lineTo(0.8 * u, 1.0 * u)
          ..close();
        canvas.drawPath(p, paintBody);
        canvas.drawPath(p, edge);
        for (final x in [-1.6, -0.6]) {
          canvas.drawRect(
            Rect.fromLTWH(x * u, -1.0 * u, 0.4 * u, 2.0 * u),
            Paint()..color = const Color(0xFFFFD600),
          );
        }
        canvas.drawRRect(box(0.1, -0.6, 0.9, 1.2, 0.3), dark);
      case CarBody.truck:
        wheels(1.5, 1.25, 1.2, 0.7);
        canvas.drawRRect(box(-2.5, -1.3, 5.0, 2.6, 0.3), paintBody);
        canvas.drawRRect(box(-2.5, -1.3, 5.0, 2.6, 0.3), edge);
        canvas.drawRRect(box(0.6, -1.1, 1.6, 2.2, 0.2), dark); // cab roof
        canvas.drawRect(
          Rect.fromLTWH(-2.2 * u, -1.0 * u, 2.4 * u, 2.0 * u),
          Paint()..color = Colors.black26,
        ); // truck bed
        canvas.drawRect(
          Rect.fromLTWH(2.4 * u, -1.2 * u, 0.3 * u, 2.4 * u),
          Paint()..color = const Color(0xFFB0BEC5),
        ); // bull bar
      case CarBody.goatKart:
        wheels(1.3, 1.1, 0.9, 0.55);
        canvas.drawRRect(box(-1.9, -0.8, 3.8, 1.6, 0.6), paintBody);
        canvas.drawRRect(box(-1.9, -0.8, 3.8, 1.6, 0.6), edge);
        // The goat driver.
        canvas.drawCircle(
          Offset(-0.2 * u, 0),
          0.75 * u,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          Offset(0.5 * u, 0),
          0.45 * u,
          Paint()..color = const Color(0xFFEEEEEE),
        );
        final horn = Paint()
          ..color = const Color(0xFF8D6E63)
          ..strokeWidth = 0.25 * u
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(-0.3 * u, -0.4 * u),
          Offset(-0.9 * u, -0.9 * u),
          horn,
        );
        canvas.drawLine(
          Offset(-0.3 * u, 0.4 * u),
          Offset(-0.9 * u, 0.9 * u),
          horn,
        );
        canvas.drawCircle(Offset(0.15 * u, -0.3 * u), 0.12 * u, dark);
        canvas.drawCircle(Offset(0.15 * u, 0.3 * u), 0.12 * u, dark);
      case CarBody.monster:
        wheels(1.5, 1.5, 1.6, 1.0);
        canvas.drawRRect(box(-2.2, -1.1, 4.4, 2.2, 0.6), paintBody);
        canvas.drawRRect(box(-2.2, -1.1, 4.4, 2.2, 0.6), edge);
        canvas.drawRRect(box(-0.4, -0.8, 1.4, 1.6, 0.3), dark);
        final flameDecal = Paint()..color = const Color(0xFFFFC107);
        canvas.drawPath(
          Path()
            ..moveTo(1.8 * u, -0.9 * u)
            ..lineTo(1.0 * u, -0.5 * u)
            ..lineTo(1.6 * u, -0.3 * u)
            ..lineTo(0.9 * u, 0)
            ..lineTo(1.9 * u, 0.2 * u)
            ..close(),
          flameDecal,
        );
    }
    // Headlights.
    final nose = c.spec.body == CarBody.hornet ? 2.0 : 2.1;
    for (final y in [-0.7, 0.7]) {
      canvas.drawCircle(
        Offset(nose * u, y * u),
        0.22 * u,
        Paint()..color = const Color(0xFFFFF9C4),
      );
    }
    canvas.restore();

    // Your car gets an arrow over it.
    if (c.isYou) {
      final tip = at - Offset(0, 3.4 * u);
      final arrow = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - 7, tip.dy - 10)
        ..lineTo(tip.dx + 7, tip.dy - 10)
        ..close();
      canvas.drawPath(arrow, Paint()..color = Colors.white);
      canvas.drawPath(
        arrow,
        Paint()
          ..color = kBlueTeam
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    } else if (v.scale > 3) {
      _text(
        canvas,
        c.name,
        at - Offset(0, 3.6 * u),
        10,
        c.team == 0 ? const Color(0xFFBBDEFB) : const Color(0xFFFFCCBC),
      );
    }
  }

  void _paintStick(Canvas canvas) {
    final start = s._stickStart;
    if (start == null) return;
    canvas.drawCircle(
      start,
      50,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      start,
      50,
      Paint()
        ..color = Colors.white38
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    var d = s._stickNow - start;
    if (d.distance > 50) d = d / d.distance * 50;
    canvas.drawCircle(start + d, 22, Paint()..color = Colors.white60);
  }

  void _paintMessages(Canvas canvas, Size size) {
    final mid = Offset(size.width / 2, v.centre.dy - 20);
    switch (m.phase) {
      case MatchPhase.kickoff:
        final n = (kKickoffTime - m.phaseT).ceil();
        _text(canvas, n > 0 ? '$n' : 'GO!', mid, 64, Colors.white);
        if (m.overtime) {
          _text(
            canvas,
            'OVERTIME',
            mid + const Offset(0, 56),
            22,
            const Color(0xFFFFD54F),
          );
        }
      case MatchPhase.goal:
        final c = m.lastScorerTeam == 0 ? const Color(0xFF90CAF9) : kOrangeTeam;
        final pop = 1 + 0.15 * sin(min(1.0, m.phaseT * 3) * pi);
        _text(canvas, 'GOAL!', mid, 60 * pop, c);
      case MatchPhase.play:
        if (m.phaseT < 0.8 && !m.overtime) {
          _text(
            canvas,
            'GO!',
            mid,
            64,
            Colors.white.withValues(alpha: 1 - m.phaseT / 0.8),
          );
        }
      case MatchPhase.over:
        break;
    }
    if (m.feedT > 0 && m.feed != null) {
      _text(
        canvas,
        m.feed!,
        mid + const Offset(0, 48),
        18,
        Colors.white.withValues(alpha: m.feedT.clamp(0, 1)),
        maxWidth: size.width - 40,
      );
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset centre,
    double size,
    Color colour, {
    double? maxWidth,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: colour,
          fontSize: size,
          fontWeight: FontWeight.w900,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth ?? double.infinity);
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _PitchPainter old) => true;
}
