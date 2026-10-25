import 'dart:math';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/sound_service.dart';
import 'boost_ball_3d.dart';
import 'boost_ball_data.dart';
import 'boost_ball_net.dart';
import 'boost_ball_sim.dart';
import '../../widgets/full_screen_game.dart';

const Color kBlueTeam = Color(0xFF2196F3);
const Color kOrangeTeam = Color(0xFFFF7043);

class _Spark {
  V3 pos;
  V3 vel;
  final Color colour;
  double life;
  _Spark(this.pos, this.vel, this.colour, this.life);
}

/// What the end card's PLAY AGAIN means for an online game: go and find
/// another one.
const String kPlayAgainOnline = 'again';

/// A match of Boost Ball against bots, or online when [session] is given.
class BoostBallGameScreen extends StatefulWidget {
  final int teamSize;
  final int difficulty;
  final double length;
  final BoostMode mode;
  final BoostBallSession? session;

  const BoostBallGameScreen({
    super.key,
    this.teamSize = 1,
    this.difficulty = 1,
    this.length = 150,
    this.mode = BoostMode.classic,
    this.session,
  });

  @override
  State<BoostBallGameScreen> createState() => _BoostBallGameScreenState();
}

class _BoostBallGameScreenState extends State<BoostBallGameScreen>
    with SingleTickerProviderStateMixin, FullScreenGame {
  final _save = BoostBallSave.instance;
  final _rnd = Random();
  final _focus = FocusNode();
  late final Ticker _ticker;
  BoostBallMatch? _m;
  Car? _y;
  BoostBallMatch get _match => _m!;
  Car get _you => _y!;
  BoostBallSession? get _net => widget.session;
  bool get _online => _net != null;
  bool get _ready => _m != null;
  String? _note;
  double _noteT = 0;
  Duration _last = Duration.zero;
  Size _size = Size.zero;

  // Touch controls.
  int? _stickPointer;
  bool _touchHelp = false; // playing on a touch screen
  Offset? _stickStart;
  Offset _stickNow = Offset.zero;
  bool _boostHeld = false;
  final Set<LogicalKeyboardKey> _keys = {};

  final List<_Spark> _sparks = [];

  // The camera follows behind your car, looking at the ball (ball cam) or
  // straight ahead.
  bool _ballCam = BoostBallSave.instance.ballCam; // remembered
  double _camYaw = pi / 2;
  V3 _camPos = const V3(kFieldW / 2, 10, 5);
  double _camPitch = -0.1;
  Rot _spin = Rot();
  double _shake = 0;
  int _lastCount = -1;
  bool _paid = false;
  int _coinsWon = 0;
  List<Quest> _questsDone = const [];

  @override
  void initState() {
    super.initState();
    if (!_online) _startOffline();
    _ticker = createTicker(_tick)..start();
  }

  void _startOffline() {
    final names = [...kBotNames]..shuffle(_rnd);
    var n = 0;
    final you = Car(
      team: 0,
      name: 'You',
      isYou: true,
      spec: carById(_save.car),
      colour: _save.colour,
    );
    you.input.relative = true;
    final cars = <Car>[you];
    final free = widget.mode == BoostMode.freePlay;
    for (var i = 1; i < widget.teamSize && !free; i++) {
      cars.add(
        Car(
          team: 0,
          name: names[n++],
          spec: kCars[_rnd.nextInt(kCars.length)],
          difficulty: 1,
        ),
      );
    }
    for (var i = 0; i < widget.teamSize && !free; i++) {
      cars.add(
        Car(
          team: 1,
          name: names[n++],
          spec: kCars[_rnd.nextInt(kCars.length)],
          difficulty: widget.difficulty,
        ),
      );
    }
    _y = you;
    _m = BoostBallMatch(
      teamSize: widget.teamSize,
      players: cars,
      length: widget.length,
      mode: widget.mode,
      random: _rnd,
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    _net?.close();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 0.016
        : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    _noteT = max(0, _noteT - dt);
    final net = _net;
    if (net != null) {
      if (_ready) _readControls();
      net.update(dt);
      for (final n in net.notes) {
        _note = n;
        _noteT = 3;
      }
      net.notes.clear();
      if (!_ready && net.match != null) {
        _m = net.match;
        _y = net.you;
        SoundService.instance.play(GameSound.levelComplete);
      }
      if (!_ready || net.ended != null) {
        setState(() {});
        return;
      }
    } else {
      _readControls();
      _match.step(dt);
    }
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
        // Touch help: any drag that isn't pulling back drives forward, so
        // you only have to think about steering.
        if (_touchHelp && d.dy < 20) throttle = max(throttle, 0.9);
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
    final car = V3(c.x, c.y, c.z);
    final onFloor = c.upZ > 0.9;
    // Look at the ball (ball cam) or the way the car points, even if that
    // is up a wall.
    final toBall = V3(b.x, b.y, b.z) - car;
    final want = _ballCam && toBall.length > 2
        ? toBall.unit
        : V3(c.fx, c.fy, c.fz);
    final flat = sqrt(want.x * want.x + want.y * want.y);
    final wantYaw = flat > 0.1 ? atan2(want.y, want.x) : _camYaw;
    var d = (wantYaw - _camYaw) % (2 * pi);
    if (d > pi) d -= 2 * pi;
    _camYaw += d * min(1.0, dt * 5);
    final along = asin(want.z.clamp(-1.0, 1.0));
    final pitch = _ballCam
        ? along * 0.8 - 0.06
        : (onFloor ? -0.14 : along * 0.9 - 0.1);
    _camPitch += (pitch.clamp(-0.6, 1.2) - _camPitch) * min(1.0, dt * 6);
    // Sit behind the car: level on the floor, or along the wall (and a
    // little off it) when driving up the walls or along the roof.
    final V3 back;
    if (onFloor) {
      back = V3(cos(_camYaw), sin(_camYaw), 0) * 11 - const V3(0, 0, 4.6);
    } else {
      final dir = V3(
        cos(_camYaw) * cos(_camPitch),
        sin(_camYaw) * cos(_camPitch),
        sin(_camPitch),
      );
      back = dir * 11 - V3(c.upX, c.upY, c.upZ) * 3.5 - const V3(0, 0, 1.5);
    }
    var at = (onFloor ? V3(c.x, c.y, c.z * 0.6) : car) - back;
    at = V3(
      at.x.clamp(1.5, kFieldW - 1.5),
      at.y.clamp(1.5, kFieldL - 1.5),
      at.z.clamp(BoostBallMatch.floorHeight(at.x, at.y) + 1.5, kCeiling - 1.5),
    );
    final k = min(1.0, dt * 8);
    _camPos = _camPos + (at - _camPos) * k;
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
    _save.bestKph = max(_save.bestKph, _you.topKph);
    final won = _match.leader == _you.team;
    if (won) {
      _coinsWon = kWinCoins[_online ? 1 : widget.difficulty];
      _save.coins += _coinsWon;
      _save.wins++;
      SoundService.instance.play(GameSound.levelComplete);
    } else {
      _save.losses++;
      SoundService.instance.play(GameSound.levelFail);
    }
    _save.goals += _you.goals;
    _questsDone = _save.recordMatch(
      won: won,
      goals: _you.goals,
      demos: _you.demos,
      topKph: _you.topKph,
      mode: _match.mode,
      extreme: !_online && widget.difficulty == 3,
    );
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
    final net = _net;
    if (net != null && net.ended != null) return _leftCard(net.ended!);
    if (net != null && !_ready) return _waitingRoom(net);
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
                      if (e.kind == PointerDeviceKind.touch && !_touchHelp) {
                        _touchHelp = true;
                        // Shots get a nudge towards the goal (not online,
                        // where it wouldn't be fair).
                        _you.assist = !_online;
                      }
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
                _kphPill(),
                if (_noteT > 0 && _note != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 110,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _note!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
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
    final mode = _match.mode;
    final time = _match.overtime
        ? 'OT'
        : switch (mode) {
            BoostMode.suddenDeath => 'NEXT GOAL WINS',
            BoostMode.firstTo5 => 'FIRST TO 5',
            BoostMode.freePlay => 'FREE PLAY',
            _ => '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}',
          };
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
              constraints: const BoxConstraints(minWidth: 70),
              height: 34,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                time,
                style: TextStyle(
                  color: _match.overtime || (mode.timed && t <= 10)
                      ? const Color(0xFFFFD54F)
                      : Colors.white,
                  fontSize: mode.timed ? 18 : 13,
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

  /// How fast the ball went off the last hit.
  Widget _kphPill() {
    final m = _match;
    if (m.kphT <= 0 || m.phase != MatchPhase.play) {
      // Must stay Positioned: a plain child would shrink the whole Stack
      // (and everything in it) to nothing, leaving a black screen.
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }
    final hot = m.lastKph >= 120;
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: SafeArea(
        child: IgnorePointer(
          child: Center(
            child: Opacity(
              opacity: m.kphT.clamp(0.0, 1.0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: hot ? const Color(0xCCE65100) : Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${m.lastKph} KPH',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ballCamButton() {
    return GestureDetector(
      onTap: () {
        setState(() => _ballCam = !_ballCam);
        BoostBallSave.instance
          ..ballCam = _ballCam
          ..save();
      },
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
    final won = leader == _you.team;
    final title = leader == null
        ? 'DRAW'
        : won
        ? 'YOU WIN!'
        : 'YOU LOSE';
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
                    color: won ? const Color(0xFF90CAF9) : kOrangeTeam,
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
                  'You scored ${_you.goals} · '
                  'Hardest hit ${_you.topKph} KPH',
                  textAlign: TextAlign.center,
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
                for (final q in _questsDone) ...[
                  const SizedBox(height: 8),
                  Text(
                    'QUEST DONE: ${q.title}!\n'
                    'Claim ${commas(q.reward)} coins in the garage.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF69F0AE),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _online
                        ? () => Navigator.of(context).pop(kPlayAgainOnline)
                        : () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => BoostBallGameScreen(
                                teamSize: widget.teamSize,
                                difficulty: widget.difficulty,
                                length: widget.length,
                                mode: widget.mode,
                              ),
                            ),
                          ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBlueTeam,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      _online ? 'FIND ANOTHER GAME' : 'PLAY AGAIN',
                      style: const TextStyle(fontWeight: FontWeight.w900),
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

  /// Online, before the game starts: who is here, and (for the room maker)
  /// a button to start straight away with bots in the empty places.
  Widget _waitingRoom(BoostBallSession net) {
    final names = net.waiting;
    return Scaffold(
      backgroundColor: const Color(0xFF0E1A2B),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${net.teamSize}v${net.teamSize} ${net.mode.title}'
                        .toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (net.room.showCode) ...[
                    const Text(
                      'Tell your friends this code:',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      net.room.code,
                      style: const TextStyle(
                        color: Color(0xFFFFD54F),
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(color: kBlueTeam),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    net.isHost
                        ? 'Waiting for players: ${names.length} of ${net.needed}'
                        : 'Waiting for the game to start...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final n in names)
                        Chip(
                          avatar: const Icon(
                            Icons.person_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          label: Text(n),
                          backgroundColor: const Color(0xFF1B2A41),
                          labelStyle: const TextStyle(color: Colors.white),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (net.isHost)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () => setState(net.startNow),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBlueTeam,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text(
                          'START NOW WITH BOTS',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Leave'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _leftCard(String why) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1A2B),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                why,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(kPlayAgainOnline),
                child: const Text('Find another game'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to garage'),
              ),
            ],
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
      final ground = BoostBallMatch.floorHeight(p.pos.dx, p.pos.dy);
      r.add(
        [
          for (var i = 0; i < n; i++)
            V3(
              p.pos.dx + cos(i / n * 2 * pi) * rad,
              p.pos.dy + sin(i / n * 2 * pi) * rad,
              BoostBallMatch.floorHeight(
                    p.pos.dx + cos(i / n * 2 * pi) * rad,
                    p.pos.dy + sin(i / n * 2 * pi) * rad,
                  ) +
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
        final bob = ground + 1.4 + 0.25 * sin(m.phaseT * 3 + p.pos.dx);
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
    if (c.isYou || c.human) return kCarColours[c.colour];
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
    // Orange drives the other way, so turn the map round for them.
    final flip = s._you.team == 1;
    Offset at(double x, double y) => flip
        ? Offset(box.right - x / kFieldW * w, box.top + y / kFieldL * h)
        : Offset(box.left + x / kFieldW * w, box.bottom - y / kFieldL * h);
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
        if (m.goalKph > 0) {
          _text(
            canvas,
            '${m.goalKph} KPH',
            mid + Offset(0, 46 * pop),
            24,
            Colors.white,
          );
        }
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
        // Below the goal speed, so the two don't overlap.
        mid + Offset(0, m.phase == MatchPhase.goal && m.goalKph > 0 ? 84 : 48),
        18,
        Colors.white.withValues(alpha: m.feedT.clamp(0, 1)),
        maxWidth: max(40, size.width - 40),
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
