import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/sound_service.dart';
import 'boost_ball_3d.dart';
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

class _Spark {
  V3 pos;
  V3 vel;
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

  // The camera follows behind your car, looking at the ball (ball cam) or
  // straight ahead.
  bool _ballCam = true;
  double _camYaw = pi / 2;
  V3 _camPos = const V3(kFieldW / 2, 10, 5);
  double _camPitch = -0.1;
  Rot _spin = Rot();
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
    _you.input.relative = true;
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
    _updateCamera(dt);
    final b = _match.ball;
    final roll = Offset(b.vx, b.vy).distance;
    if (roll > 0.1) {
      _spin = _spin.turned(V3(-b.vy, b.vx, 0), roll * dt / kBallR);
    }
    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel = V3(s.vel.x * 0.97, s.vel.y * 0.97, s.vel.z - 20 * dt);
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
    var steer = 0.0, throttle = 0.0;
    if (_stickStart != null) {
      final d = _stickNow - _stickStart!;
      if (d.distance > 6) {
        steer = (d.dx / 50).clamp(-1.0, 1.0);
        throttle = (-d.dy / 50).clamp(-1.0, 1.0);
      }
    }
    if (_keys.contains(LogicalKeyboardKey.arrowLeft) ||
        _keys.contains(LogicalKeyboardKey.keyA)) {
      steer = -1;
    }
    if (_keys.contains(LogicalKeyboardKey.arrowRight) ||
        _keys.contains(LogicalKeyboardKey.keyD)) {
      steer = 1;
    }
    if (_keys.contains(LogicalKeyboardKey.arrowUp) ||
        _keys.contains(LogicalKeyboardKey.keyW)) {
      throttle = 1;
    }
    if (_keys.contains(LogicalKeyboardKey.arrowDown) ||
        _keys.contains(LogicalKeyboardKey.keyS)) {
      throttle = -1;
    }
    inp
      ..steer = steer
      ..throttle = throttle
      ..boost =
          _boostHeld ||
          _keys.contains(LogicalKeyboardKey.shiftLeft) ||
          _keys.contains(LogicalKeyboardKey.shiftRight);
  }

  void _updateCamera(double dt) {
    final c = _you;
    final b = _match.ball;
    final toBall = Offset(b.x - c.x, b.y - c.y);
    final wantYaw = _ballCam && toBall.distance > 2
        ? toBall.direction
        : c.heading;
    var d = (wantYaw - _camYaw) % (2 * pi);
    if (d > pi) d -= 2 * pi;
    _camYaw += d * min(1.0, dt * 5);
    final dir = V3(cos(_camYaw), sin(_camYaw), 0);
    var want = V3(c.x, c.y, c.z * 0.6) - dir * 11 + const V3(0, 0, 4.6);
    want = V3(
      want.x.clamp(1.5, kFieldW - 1.5),
      want.y.clamp(1.5, kFieldL - 1.5),
      max(want.z, BoostBallMatch.floorHeight(want.x, want.y) + 1.5),
    );
    final k = min(1.0, dt * 8);
    _camPos = _camPos + (want - _camPos) * k;
    var pitch = -0.14;
    if (_ballCam) {
      final to = V3(b.x, b.y, b.z) - _camPos;
      final flat = sqrt(to.x * to.x + to.y * to.y);
      pitch = (atan2(to.z, max(flat, 1)) * 0.8 - 0.06).clamp(-0.4, 0.5);
    }
    _camPitch += (pitch - _camPitch) * min(1.0, dt * 6);
  }

  Camera _camera(Size size) {
    final landscape = size.width > size.height;
    final focal = max(size.width, size.height) * (landscape ? 0.5 : 0.56);
    final centre = Offset(
      size.width / 2,
      size.height * (landscape ? 0.5 : 0.44),
    );
    final look = V3(
      cos(_camYaw) * cos(_camPitch),
      sin(_camYaw) * cos(_camPitch),
      sin(_camPitch),
    );
    return Camera.lookAt(_camPos, _camPos + look, focal, centre);
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
    final b = _match.ball;
    final at = V3(b.x, b.y, b.z);
    final team = _match.lastScorerTeam ?? 0;
    final colours = team == 0
        ? const [kBlueTeam, Colors.white, Color(0xFF90CAF9)]
        : const [kOrangeTeam, Colors.white, Color(0xFFFFCC80)];
    for (var i = 0; i < 90; i++) {
      final a = _rnd.nextDouble() * 2 * pi;
      final up = _rnd.nextDouble();
      final sp = 6 + _rnd.nextDouble() * 18;
      _sparks.add(
        _Spark(
          at,
          V3(cos(a) * sp, sin(a) * sp, 6 + up * 16),
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
                  left: 8,
                  top: 64,
                  child: SafeArea(child: _ballCamButton()),
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
                        'Drag here: up to go, sideways to steer',
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

  Widget _ballCamButton() {
    return GestureDetector(
      onTap: () => setState(() => _ballCam = !_ballCam),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _ballCam ? const Color(0xCC2196F3) : Colors.black45,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white54),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Text(
              _ballCam ? 'BALL CAM' : 'CAR CAM',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
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

  late Camera cam;

  BoostBallMatch get m => s._match;

  @override
  void paint(Canvas canvas, Size size) {
    cam = s._camera(size);
    canvas.save();
    if (s._shake > 0) {
      final r = s._rnd;
      canvas.translate(
        (r.nextDouble() - 0.5) * 10 * s._shake,
        (r.nextDouble() - 0.5) * 10 * s._shake,
      );
    }
    _paintSky(canvas, size);
    final r = Renderer(cam);
    final stadium = Stadium.instance;
    for (final f in stadium.floor) {
      r.addFace(f, floor: true);
    }
    for (final f in stadium.lines) {
      r.addFace(f, floor: true);
    }
    _addPads(r);
    for (final c in m.cars) {
      if (c.alive) drawShadow(r, c.x, c.y, 2.4, c.z);
    }
    drawShadow(r, m.ball.x, m.ball.y, kBallR, m.ball.z - kBallR);
    for (final f in stadium.solid) {
      r.addFace(f);
    }
    for (final c in m.cars) {
      if (!c.alive) continue;
      final team = c.team == 0 ? kBlueTeam : kOrangeTeam;
      drawCar(
        r,
        CarModel.of(c.spec.body),
        Pose.ofCar(c),
        carPaint(_paintOf(c), team),
        boosting: c.boosting,
        rnd: s._rnd,
      );
    }
    drawBall(r, m.ball, s._spin);
    r.draw(canvas);
    _paintLabels(canvas);
    for (final sp in s._sparks) {
      final c = cam.toCam(sp.pos);
      if (c.z < 0.5) continue;
      canvas.drawCircle(
        cam.screen(c),
        max(1.5, 14 / c.z),
        Paint()..color = sp.colour.withValues(alpha: sp.life.clamp(0, 1)),
      );
    }
    canvas.restore();
    _paintMiniMap(canvas, size);
    _paintStick(canvas);
    _paintMessages(canvas, size);
  }

  void _paintSky(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF070B1E), Color(0xFF1B2551), Color(0xFF3A3F7A)],
        ).createShader(Offset.zero & size),
    );
    // Stars that turn with the camera.
    final star = Paint()..color = Colors.white70;
    final rnd = Random(3);
    for (var i = 0; i < 60; i++) {
      final a = rnd.nextDouble() * 2 * pi;
      final h = rnd.nextDouble();
      var dx = (a - s._camYaw) % (2 * pi);
      if (dx > pi) dx -= 2 * pi;
      final x = size.width / 2 - dx / 1.2 * size.width;
      final y =
          cam.centre.dy -
          (0.2 + h * 0.9) * size.height * 0.6 +
          s._camPitch * cam.focal;
      if (x < 0 || x > size.width || y < 0) continue;
      canvas.drawCircle(Offset(x, y), 1 + rnd.nextDouble(), star);
    }
  }

  void _addPads(Renderer r) {
    for (final p in m.pads) {
      final rad = p.big ? 1.6 : 0.85;
      const n = 6;
      final ready = p.ready;
      r.add(
        [
          for (var i = 0; i < n; i++)
            V3(
              p.pos.dx + cos(i / n * 2 * pi) * rad,
              p.pos.dy + sin(i / n * 2 * pi) * rad,
              0.06,
            ),
        ],
        ready
            ? (p.big ? const Color(0xFFFF9100) : const Color(0xFFFFD54F))
            : const Color(0xFF1B3A1E),
        lit: false,
        floor: true,
      );
      if (p.big && ready) {
        // A glowing orb hovers over full-boost pads.
        final bob = 1.4 + 0.25 * sin(m.phaseT * 3 + p.pos.dx);
        final c = V3(p.pos.dx, p.pos.dy, bob);
        const pts = [
          V3(0.7, 0, 0),
          V3(0, 0.7, 0),
          V3(-0.7, 0, 0),
          V3(0, -0.7, 0),
        ];
        for (var i = 0; i < 4; i++) {
          for (final tip in const [V3(0, 0, 0.9), V3(0, 0, -0.9)]) {
            r.add(
              [c + pts[i], c + pts[(i + 1) % 4], c + tip],
              i.isEven ? const Color(0xFFFFC400) : const Color(0xFFFF6D00),
              lit: false,
            );
          }
        }
      }
    }
  }

  Color _paintOf(Car c) {
    if (c.isYou) return kCarColours[c.colour];
    final shades = c.team == 0
        ? const [Color(0xFF1565C0), Color(0xFF42A5F5), Color(0xFF0D47A1)]
        : const [Color(0xFFE64A19), Color(0xFFFF8A65), Color(0xFFBF360C)];
    return shades[c.name.length % shades.length];
  }

  void _paintLabels(Canvas canvas) {
    for (final c in m.cars) {
      if (!c.alive || c.isYou) continue;
      final at = cam.toCam(V3(c.x, c.y, c.z + 3.2));
      if (at.z < 1 || at.z > 70) continue;
      _text(
        canvas,
        c.name,
        cam.screen(at),
        11,
        c.team == 0 ? const Color(0xFFBBDEFB) : const Color(0xFFFFCCBC),
      );
    }
  }

  void _paintMiniMap(Canvas canvas, Size size) {
    final landscape = size.width > size.height;
    const w = 58.0, h = w * kFieldL / kFieldW;
    final box = Rect.fromLTWH(size.width - w - 10, landscape ? 60 : 64, w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box.inflate(3), const Radius.circular(6)),
      Paint()..color = Colors.black45,
    );
    canvas.drawRect(box, Paint()..color = const Color(0xAA2E7D32));
    Offset at(double x, double y) =>
        Offset(box.left + x / kFieldW * w, box.bottom - y / kFieldL * h);
    canvas.drawRect(
      Rect.fromPoints(
        at(kFieldW / 2 - kGoalW / 2, 0),
        at(kFieldW / 2 + kGoalW / 2, -2),
      ),
      Paint()..color = kBlueTeam,
    );
    canvas.drawRect(
      Rect.fromPoints(
        at(kFieldW / 2 - kGoalW / 2, kFieldL),
        at(kFieldW / 2 + kGoalW / 2, kFieldL + 2),
      ),
      Paint()..color = kOrangeTeam,
    );
    for (final c in m.cars) {
      if (!c.alive) continue;
      canvas.drawCircle(
        at(c.x, c.y),
        c.isYou ? 3.5 : 2.6,
        Paint()
          ..color = c.isYou
              ? Colors.white
              : (c.team == 0 ? kBlueTeam : kOrangeTeam),
      );
    }
    canvas.drawCircle(
      at(m.ball.x, m.ball.y),
      2.6,
      Paint()..color = const Color(0xFFFFEB3B),
    );
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
    final mid = Offset(size.width / 2, size.height * 0.3);
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
