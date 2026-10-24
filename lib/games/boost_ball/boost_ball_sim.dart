import 'dart:math';
import 'dart:ui' show Offset;

import 'boost_ball_data.dart';

// The pitch, in metres. x runs across, y runs from the blue goal (y = 0)
// to the orange goal (y = kFieldL). Blue attacks up the pitch.
const double kFieldW = 72;
const double kFieldL = 112;
const double kGoalW = 26;
const double kGoalDepth = 9;
const double kGoalH = 13;
const double kCorner = 12; // the corners are cut off at 45 degrees
const double kCeiling = 44;
const double kRampR =
    12; // the bottom of every wall curves up like a skate ramp
const double kTopR = 10; // and the top curves over into the roof
const double kWallH = kCeiling; // the glass walls go right up to the roof
const double kBallR = 2.4;
const double kCarR = 2.2;
const double kGravity = 32;
const double kMaxBallSpeed = 50; // 180 KPH
const double kMaxBoost = 100;
const double kKickoffTime = 3;
const double kGoalPause = 3;

/// What a player (or a bot) is pressing this frame.
class CarInput {
  /// Which way to drive, in pitch directions (length 0 to 1). Bots use this.
  Offset stick = Offset.zero;

  /// Driving like a real car instead: steer (-1 left to 1 right) and
  /// throttle (-1 reverse to 1 forward). Used when [relative] is true.
  bool relative = false;
  double steer = 0;
  double throttle = 0;
  bool boost = false;

  /// True for one frame when jump is pressed.
  bool jump = false;
}

class Ball {
  double x = kFieldW / 2, y = kFieldL / 2, z = kBallR;
  double vx = 0, vy = 0, vz = 0;
  double spin = 0; // just for drawing

  Offset get pos => Offset(x, y);
  double get speed => sqrt(vx * vx + vy * vy + vz * vz);
}

class Car {
  final int team; // 0 blue (attacks +y), 1 orange (attacks -y)
  String name;
  final bool isYou;
  final CarSpec spec;
  int colour;
  final int difficulty; // bots only

  /// Online: a real person drives this car (it gets their paint), and
  /// [netControlled] cars are steered by messages instead of a bot brain.
  bool human = false;
  bool netControlled = false;
  String netId = '';
  int topKph = 0; // this car's hardest hit of the match

  double x = 0, y = 0, z = 0;
  double vx = 0, vy = 0, vz = 0;

  /// Which way the car points, in 3D (it can point up a wall or along the
  /// roof). Always flat along whatever the car is driving on.
  double fx = 1, fy = 0, fz = 0;

  /// The direction the car points, seen from above.
  double get heading => atan2(fy, fx);
  set heading(double a) {
    fx = cos(a);
    fy = sin(a);
    fz = 0;
  }

  double boost = 33;
  bool boosting = false;
  bool grounded = true;

  /// Which way is "up" for the car (it tilts on the curved walls).
  double upX = 0, upY = 0, upZ = 1;
  double airT = 0;
  bool canFlip = false;
  double flipT = 0; // a flip makes your next hit much harder
  double hitCool = 0;
  double demoT = 0; // > 0 while waiting to come back after a demolition
  int goals = 0;
  final CarInput input = CarInput();

  // Bot brain.
  double thinkT = 0;
  Offset aim = Offset.zero;
  bool wantBoost = false;

  Car({
    required this.team,
    required this.name,
    required this.spec,
    this.isYou = false,
    this.colour = 0,
    this.difficulty = 1,
  });

  Offset get pos => Offset(x, y);
  Offset get vel => Offset(vx, vy);
  Offset get forward => Offset(cos(heading), sin(heading));

  /// Driving on a wall or the roof rather than the floor.
  bool get onWall => grounded && upZ < 0.7;
  bool get alive => demoT <= 0;
  double get speed => sqrt(vx * vx + vy * vy);
  bool get supersonic => speed > spec.speed * 1.3;
}

class BoostPad {
  final Offset pos;
  final bool big;
  double respawnT = 0;
  BoostPad(this.pos, this.big);
  bool get ready => respawnT <= 0;
}

enum MatchPhase { kickoff, play, goal, over }

/// Something that happened, for sounds and the game feed.
enum MatchEvent { hit, bigHit, goal, demolish, kickoff, whistle, boostPad }

typedef V = (double, double, double);

/// One game of Boost Ball: the cars, the ball and the rules.
class BoostBallMatch {
  final int teamSize;
  final double length; // seconds
  final Random rnd;
  final List<Car> cars = [];
  final Ball ball = Ball();
  final List<BoostPad> pads = [];
  final List<MatchEvent> events = [];
  final BoostMode mode;

  /// False on a phone that just copies someone else's game (online guests):
  /// it moves things along between updates but never scores or ends it.
  bool authority = true;

  /// How fast the ball went off the last hit, and for how long to show it.
  int lastKph = 0;
  double kphT = 0;
  int goalKph = 0;

  MatchPhase phase = MatchPhase.kickoff;
  double phaseT = 0;
  double clock; // seconds left
  bool overtime = false;
  final List<int> score = [0, 0];
  int? lastScorerTeam;
  Car? lastScorer;
  Car? lastTouch;
  String? feed;
  double feedT = 0;

  BoostBallMatch({
    required this.teamSize,
    required List<Car> players,
    this.length = 150,
    this.mode = BoostMode.classic,
    Random? random,
  }) : rnd = random ?? Random(),
       clock = length {
    cars.addAll(players);
    if (mode != BoostMode.noBoost) {
      for (final x in [10.0, kFieldW - 10]) {
        for (final y in [16.0, kFieldL - 16]) {
          pads.add(BoostPad(Offset(x, y), true));
        }
        pads.add(BoostPad(Offset(x, kFieldL / 2), true));
      }
      for (final x in [20.0, kFieldW / 2, kFieldW - 20]) {
        for (final y in [30.0, 45.0, kFieldL - 45, kFieldL - 30]) {
          pads.add(BoostPad(Offset(x, y), false));
        }
      }
      for (final x in [kFieldW / 2 - 16, kFieldW / 2 + 16]) {
        pads.add(BoostPad(Offset(x, kFieldL / 2), false));
      }
    }
    resetKickoff();
  }

  /// How much boost cars start with (and come back with).
  double get _startBoost => switch (mode) {
    BoostMode.noBoost => 0,
    BoostMode.freePlay => kMaxBoost,
    _ => 33,
  };

  /// The match is over once a goal like this one has gone in.
  bool get _goalEnds => switch (mode) {
    BoostMode.classic ||
    BoostMode.noBoost => overtime || (clock <= 0 && leader != null),
    BoostMode.suddenDeath => true,
    BoostMode.firstTo5 => score[0] >= 5 || score[1] >= 5,
    BoostMode.freePlay => false,
  };

  /// The team that is winning, or null for a draw.
  int? get leader =>
      score[0] == score[1] ? null : (score[0] > score[1] ? 0 : 1);

  void _say(String text) {
    feed = text;
    feedT = 2.5;
  }

  void resetKickoff() {
    ball
      ..x = kFieldW / 2
      ..y = kFieldL / 2
      ..z = kBallR
      ..vx = 0
      ..vy = 0
      ..vz = 0;
    for (final team in [0, 1]) {
      final mine = cars.where((c) => c.team == team).toList();
      for (var i = 0; i < mine.length; i++) {
        // Spread the team out: one in front, the rest wide and back.
        final Offset spot = switch (i) {
          0 => const Offset(kFieldW / 2, 24),
          1 => const Offset(kFieldW / 2 - 16, 18),
          2 => const Offset(kFieldW / 2 + 16, 18),
          _ => Offset(kFieldW / 2 + (i.isEven ? 8 : -8), 8),
        };
        final c = mine[i];
        c
          ..x = spot.dx
          ..y = team == 0 ? spot.dy : kFieldL - spot.dy
          ..z = 0
          ..vx = 0
          ..vy = 0
          ..vz = 0
          ..boost = _startBoost
          ..flipT = 0
          ..demoT = 0
          ..grounded = true
          ..upX = 0
          ..upY = 0
          ..upZ = 1
          ..airT = 0;
        c.heading = atan2(ball.y - c.y, ball.x - c.x);
      }
    }
    for (final p in pads) {
      p.respawnT = 0;
    }
    lastTouch = null;
    phase = MatchPhase.kickoff;
    phaseT = 0;
    events.add(MatchEvent.kickoff);
  }

  /// Moves everything on by [dt] seconds.
  void step(double dt) {
    phaseT += dt;
    feedT = max(0, feedT - dt);
    kphT = max(0, kphT - dt);
    if (mode == BoostMode.freePlay) {
      for (final c in cars) {
        c.boost = kMaxBoost; // practice: boost never runs out
      }
    }
    if (!authority) {
      _follow(dt);
      return;
    }
    switch (phase) {
      case MatchPhase.kickoff:
        for (final c in cars) {
          if (_isBot(c)) _think(c, dt);
        }
        if (phaseT >= kKickoffTime) {
          phase = MatchPhase.play;
          phaseT = 0;
          events.add(MatchEvent.whistle);
        }
        return;
      case MatchPhase.over:
        _moveBall(dt);
        return;
      case MatchPhase.goal:
        // The ball explodes in the net; cars can still drive about.
        for (final c in cars) {
          if (_isBot(c)) _think(c, dt);
          _moveCar(c, dt);
          c.input.jump = false;
        }
        if (phaseT >= kGoalPause) {
          if (_goalEnds) {
            phase = MatchPhase.over;
            phaseT = 0;
          } else {
            resetKickoff();
          }
        }
        return;
      case MatchPhase.play:
        break;
    }

    if (mode.timed) clock -= dt;
    if (mode.timed && clock <= 0 && !overtime) {
      clock = 0;
      // A draw goes to overtime: the next goal wins.
      if (leader == null && ball.z < kBallR + 0.5) {
        overtime = true;
        _say('OVERTIME! Next goal wins');
        resetKickoff();
        return;
      } else if (leader != null && ball.z < kBallR + 0.5) {
        phase = MatchPhase.over;
        phaseT = 0;
        events.add(MatchEvent.whistle);
        return;
      }
    }

    for (final c in cars) {
      if (_isBot(c)) _think(c, dt);
    }
    const steps = 2;
    for (var i = 0; i < steps; i++) {
      final h = dt / steps;
      for (final c in cars) {
        _moveCar(c, h);
      }
      _moveBall(h);
      _bumpCars();
      for (final c in cars) {
        _hitBall(c);
      }
      if (_checkGoal()) break;
    }
    for (final p in pads) {
      p.respawnT = max(0, p.respawnT - dt);
    }
    for (final c in cars) {
      c.input.jump = false;
    }
  }

  bool _isBot(Car c) => !c.isYou && !c.netControlled;

  /// For a phone copying the real game: keep things moving smoothly between
  /// updates, but leave goals, the clock and kickoffs to the real game.
  void _follow(double dt) {
    if (phase == MatchPhase.play && mode.timed && !overtime) {
      clock = max(0, clock - dt);
    }
    if (phase == MatchPhase.play || phase == MatchPhase.goal) {
      const steps = 2;
      for (var i = 0; i < steps; i++) {
        final h = dt / steps;
        for (final c in cars) {
          _moveCar(c, h);
        }
        if (phase == MatchPhase.play) {
          _moveBall(h);
          _bumpCars();
          for (final c in cars) {
            _hitBall(c);
          }
        }
      }
      for (final p in pads) {
        p.respawnT = max(0, p.respawnT - dt);
      }
    } else if (phase == MatchPhase.over) {
      _moveBall(dt);
    }
    for (final c in cars) {
      c.input.jump = false;
    }
  }

  // ---- cars -----------------------------------------------------------------

  void _moveCar(Car c, double dt) {
    c.hitCool = max(0, c.hitCool - dt);
    c.flipT = max(0, c.flipT - dt);
    if (!c.alive) {
      c.demoT -= dt;
      if (c.demoT <= 0) _respawn(c);
      return;
    }
    final inp = c.input;
    final stick = inp.stick;
    final push = min(1.0, stick.distance);
    // The car's own directions: forward and up (it can be on a wall).
    final n = (c.upX, c.upY, c.upZ);
    var f = _flat((c.fx, c.fy, c.fz), n);
    var throttle = 0.0;
    final along0 = c.vx * f.$1 + c.vy * f.$2 + c.vz * f.$3;
    // Steering turns the car around its own up (or the sky's while flying).
    final V axis = c.grounded ? n : (0, 0, 1);
    if (inp.relative) {
      final rate = c.spec.turn * (c.grounded ? 1 : 0.8);
      final grip = c.grounded ? 0.45 + 0.55 * min(1.0, along0.abs() / 8) : 1;
      final back = along0 < -1 ? -1 : 1;
      f = _turn(f, axis, -inp.steer.clamp(-1.0, 1.0) * rate * grip * back * dt);
      throttle = inp.throttle.clamp(-1.0, 1.0);
    } else if (push > 0.15) {
      // Bots point the way they want to go. On a wall that way also leans
      // downhill, so they come back to the floor.
      final want = _flat((
        stick.dx / push,
        stick.dy / push,
        c.onWall ? -0.8 : 0.0,
      ), axis);
      final diff = atan2(_dot(_cross(f, want), axis), _dot(f, want));
      final rate = c.spec.turn * (c.grounded ? 1 : 0.7);
      f = _turn(f, axis, diff.clamp(-rate * dt, rate * dt));
      throttle = push * (diff.abs() > 1.6 ? 0.35 : 1);
    }
    f = _flat(f, axis);
    c.boosting = inp.boost && c.boost > 0;
    if (c.boosting) c.boost = max(0, c.boost - 33 * dt);

    if (c.grounded) {
      final left = _cross(n, f);
      var along = c.vx * f.$1 + c.vy * f.$2 + c.vz * f.$3;
      var side = c.vx * left.$1 + c.vy * left.$2 + c.vz * left.$3;
      final top = c.spec.speed * (c.boosting ? 1.5 : 1);
      final push = (c.spec.accel * throttle + (c.boosting ? 32 : 0)) * dt;
      if (along > top) {
        along = max(top, along - 40 * dt); // too fast (e.g. down a wall)
      } else {
        along = min(push > 0 ? top : along, along + push);
      }
      if (along < -top * 0.5) along = -top * 0.5;
      if (throttle == 0 && !c.boosting) along *= pow(0.35, dt).toDouble();
      side *= pow(0.01, dt).toDouble(); // tyres grip
      c.vx = f.$1 * along + left.$1 * side;
      c.vy = f.$2 * along + left.$2 * side;
      c.vz = f.$3 * along + left.$3 * side;
      // Gravity pulls you back down a wall, but grippy tyres fight most of
      // it, so you can drive as high as you like while you keep going.
      final gn = -kGravity * n.$3;
      final k = n.$3 > 0.7 ? 1.0 : 0.3;
      c.vx += -n.$1 * gn * k * dt;
      c.vy += -n.$2 * gn * k * dt;
      c.vz += (-kGravity - n.$3 * gn) * k * dt;
    } else {
      if (c.boosting) {
        c.vx += f.$1 * 20 * dt;
        c.vy += f.$2 * 20 * dt;
        c.vz += f.$3 * 20 * dt + 10 * dt; // boosting in the air lifts you
      }
      c.vz -= kGravity * dt;
      c.airT += dt;
    }

    var jumped = false;
    if (inp.jump) {
      if (c.grounded) {
        // Jump away from whatever you're driving on (even a wall or the roof).
        c.vx += n.$1 * c.spec.jump;
        c.vy += n.$2 * c.spec.jump;
        c.vz += n.$3 * c.spec.jump;
        if (n.$3 > 0.7) c.vz = max(c.vz, c.spec.jump * n.$3);
        c.airT = 0;
        c.canFlip = true;
        c.grounded = false;
        jumped = true;
      } else if (c.canFlip && c.airT < 1.6) {
        // Flip: a burst of speed and a big hit.
        final flatF = Offset(f.$1, f.$2);
        var dir = push > 0.2
            ? stick / stick.distance
            : (flatF.distance > 0.1 ? flatF / flatF.distance : c.forward);
        if (inp.relative) {
          final r = Offset(dir.dy, -dir.dx);
          final d = dir * inp.throttle + r * inp.steer;
          dir = d.distance > 0.2 ? d / d.distance : dir;
        }
        c.vx += dir.dx * 15;
        c.vy += dir.dy * 15;
        c.vz = max(c.vz, 4);
        f = (dir.dx, dir.dy, 0);
        c.flipT = 0.5;
        c.canFlip = false;
      }
    }

    c.x += c.vx * dt;
    c.y += c.vy * dt;
    c.z += c.vz * dt;
    final v = _collideWalls(c.x, c.y, c.z, 0, c.vx, c.vy, 0.1);
    c
      ..x = v.$1
      ..y = v.$2
      ..vx = v.$3
      ..vy = v.$4;
    // Land on the floor, a wall or the roof. Tyres stick to walls and the
    // roof while you keep moving; slow right down up there and you fall off.
    final speed = sqrt(c.vx * c.vx + c.vy * c.vy + c.vz * c.vz);
    final sticky = c.upZ > 0.7 || speed > 6;
    var touch = _surface(c.x, c.y, c.z, 0);
    if (touch == null && c.grounded && !jumped && sticky) {
      touch = _surface(
        c.x - c.upX * 0.6,
        c.y - c.upY * 0.6,
        c.z - c.upZ * 0.6,
        0,
      );
    }
    // Wheels only land on a wall or the roof if you drove onto it, or hit
    // it going fast; otherwise you just bump off.
    final land =
        touch != null &&
        !jumped &&
        (touch.nz > 0.7 || (sticky && (c.grounded || touch.nz > -0.7)));
    if (touch != null) {
      c
        ..x = touch.x
        ..y = touch.y
        ..z = touch.z;
      final vn = c.vx * touch.nx + c.vy * touch.ny + c.vz * touch.nz;
      // Lose the speed going into the surface (and, while stuck to a wall
      // or the roof, the speed going away from it too).
      if (vn < 0 || (land && touch.nz < 0.7)) {
        c.vx -= touch.nx * vn;
        c.vy -= touch.ny * vn;
        c.vz -= touch.nz * vn;
      }
    }
    if (land) {
      c.grounded = true;
      c.airT = 0;
      c.upX = touch.nx;
      c.upY = touch.ny;
      c.upZ = touch.nz;
    } else {
      c.grounded = false;
      // Level out in the air.
      final k = min(1.0, dt * 3);
      var ux = c.upX * (1 - k),
          uy = c.upY * (1 - k),
          uz = c.upZ + (1 - c.upZ) * k;
      final l = sqrt(ux * ux + uy * uy + uz * uz);
      if (l < 1e-4) {
        ux = 0;
        uy = 0;
        uz = 1;
      } else {
        ux /= l;
        uy /= l;
        uz /= l;
      }
      c
        ..upX = ux
        ..upY = uy
        ..upZ = uz;
    }
    f = _flat(f, (c.upX, c.upY, c.upZ));
    c
      ..fx = f.$1
      ..fy = f.$2
      ..fz = f.$3;

    if (c.grounded && c.upZ > 0.9) {
      for (final p in pads) {
        if (p.ready &&
            c.boost < kMaxBoost &&
            (p.pos - c.pos).distance < (p.big ? 3 : 2.2)) {
          c.boost = min(kMaxBoost, c.boost + (p.big ? 100 : 12));
          p.respawnT = p.big ? 9 : 4;
          if (c.isYou) events.add(MatchEvent.boostPad);
        }
      }
    }
  }

  static double _dot(V v, V w) => v.$1 * w.$1 + v.$2 * w.$2 + v.$3 * w.$3;
  static V _cross(V a, V b) => (
    a.$2 * b.$3 - a.$3 * b.$2,
    a.$3 * b.$1 - a.$1 * b.$3,
    a.$1 * b.$2 - a.$2 * b.$1,
  );

  /// [v] laid flat along a surface facing [n], as a unit vector.
  static V _flat(V v, V n) {
    final d = _dot(v, n);
    var x = v.$1 - n.$1 * d, y = v.$2 - n.$2 * d, z = v.$3 - n.$3 * d;
    var l = sqrt(x * x + y * y + z * z);
    if (l < 1e-4) {
      // Pointing straight into the surface: pick any direction along it.
      final V alt = n.$3.abs() < 0.9 ? (0, 0, 1) : (1, 0, 0);
      final d2 = _dot(alt, n);
      x = alt.$1 - n.$1 * d2;
      y = alt.$2 - n.$2 * d2;
      z = alt.$3 - n.$3 * d2;
      l = sqrt(x * x + y * y + z * z);
    }
    return (x / l, y / l, z / l);
  }

  /// [f] turned by angle [a] around [axis] (anticlockwise looking down it).
  static V _turn(V f, V axis, double a) {
    final s = _cross(axis, f);
    final c = cos(a), sn = sin(a);
    return (f.$1 * c + s.$1 * sn, f.$2 * c + s.$2 * sn, f.$3 * c + s.$3 * sn);
  }

  void _respawn(Car c) {
    c
      ..x = kFieldW / 2 + (rnd.nextDouble() - 0.5) * 20
      ..y = c.team == 0 ? 6 : kFieldL - 6
      ..z = 0
      ..vx = 0
      ..vy = 0
      ..vz = 0
      ..boost = _startBoost
      ..grounded = true
      ..upX = 0
      ..upY = 0
      ..upZ = 1
      ..demoT = 0;
    c.heading = c.team == 0 ? pi / 2 : -pi / 2;
  }

  void _bumpCars() {
    for (var i = 0; i < cars.length; i++) {
      for (var j = i + 1; j < cars.length; j++) {
        final a = cars[i], b = cars[j];
        if (!a.alive || !b.alive || (a.z - b.z).abs() > 2) continue;
        final d = b.pos - a.pos;
        final dist = d.distance;
        if (dist >= kCarR * 2 || dist < 0.001) continue;
        final n = d / dist;
        final relIn = (a.vel - b.vel).dx * n.dx + (a.vel - b.vel).dy * n.dy;
        // Ramming an enemy at full boost blows them up!
        if (a.team != b.team) {
          final aIn = a.vx * n.dx + a.vy * n.dy;
          final bIn = -(b.vx * n.dx + b.vy * n.dy);
          if (a.supersonic && aIn > a.spec.speed * 1.25 && bIn < aIn * 0.4) {
            _demolish(b, a);
            continue;
          }
          if (b.supersonic && bIn > b.spec.speed * 1.25 && aIn < bIn * 0.4) {
            _demolish(a, b);
            continue;
          }
        }
        final overlap = kCarR * 2 - dist;
        final wa = a.spec.weight, wb = b.spec.weight;
        final share = wb / (wa + wb);
        a.x -= n.dx * overlap * share;
        a.y -= n.dy * overlap * share;
        b.x += n.dx * overlap * (1 - share);
        b.y += n.dy * overlap * (1 - share);
        if (relIn > 0) {
          final j = relIn * 1.4;
          a.vx -= n.dx * j * share;
          a.vy -= n.dy * j * share;
          b.vx += n.dx * j * (1 - share);
          b.vy += n.dy * j * (1 - share);
        }
      }
    }
  }

  void _demolish(Car victim, Car by) {
    victim.demoT = 2;
    events.add(MatchEvent.demolish);
    _say('${by.name} DEMOLISHED ${victim.name}!');
  }

  // ---- ball -----------------------------------------------------------------

  void _moveBall(double dt) {
    final b = ball;
    b.vz -= kGravity * dt;
    b.x += b.vx * dt;
    b.y += b.vy * dt;
    b.z += b.vz * dt;
    // Bounce off the floor, or roll up the curved bottom of a wall.
    final touch = _surface(b.x, b.y, b.z, kBallR);
    if (touch != null) {
      b
        ..x = touch.x
        ..y = touch.y
        ..z = touch.z;
      final vn = b.vx * touch.nx + b.vy * touch.ny + b.vz * touch.nz;
      if (vn < 0) {
        final k = vn < -5 ? 1.6 : 1.0; // hard knocks bounce, soft ones roll
        b.vx -= touch.nx * vn * k;
        b.vy -= touch.ny * vn * k;
        b.vz -= touch.nz * vn * k;
      }
    }
    if (b.z > kCeiling - kBallR) {
      b.z = kCeiling - kBallR;
      if (b.vz > 0) b.vz = -b.vz * 0.7;
    }
    final onGround = touch != null;
    final drag = pow(onGround ? 0.62 : 0.8, dt).toDouble();
    b.vx *= drag;
    b.vy *= drag;
    final sp = b.speed;
    if (sp > kMaxBallSpeed) {
      b.vx *= kMaxBallSpeed / sp;
      b.vy *= kMaxBallSpeed / sp;
      b.vz *= kMaxBallSpeed / sp;
    }
    final v = _collideWalls(b.x, b.y, b.z, kBallR, b.vx, b.vy, 0.5);
    b
      ..x = v.$1
      ..y = v.$2
      ..vx = v.$3
      ..vy = v.$4;
    b.spin += Offset(b.vx, b.vy).distance * dt / kBallR;
  }

  void _hitBall(Car c) {
    if (!c.alive || c.hitCool > 0) return;
    final b = ball;
    // The middle of the car is a bit above its wheels, whichever way up.
    final cx = c.x + c.upX * 1.1, cy = c.y + c.upY * 1.1;
    final cz = c.z + c.upZ * 1.1;
    final dx = b.x - cx, dy = b.y - cy, dz = b.z - cz;
    final dist = sqrt(dx * dx + dy * dy + dz * dz);
    const reach = kBallR + kCarR;
    if (dist >= reach || dist < 0.001) return;
    final nx = dx / dist, ny = dy / dist, nz = dz / dist;
    // Push the ball out so it is just touching.
    b.x = cx + nx * reach;
    b.y = cy + ny * reach;
    b.z = (cz + nz * reach).clamp(kBallR, kCeiling - kBallR);
    final rel = (c.vx - b.vx) * nx + (c.vy - b.vy) * ny + (c.vz - b.vz) * nz;
    var power = max(0.0, rel) * 1.15 * c.spec.hit + 5;
    final flipped = c.flipT > 0;
    if (flipped) power *= 1.35;
    b.vx += nx * power + c.vx * 0.25;
    b.vy += ny * power + c.vy * 0.25;
    // Hits pop the ball up off whatever the car is on (on a wall, that
    // lifts it up the wall).
    final pop = c.grounded ? 3 + max(0.0, rel) * 0.2 : 2;
    b.vx += c.grounded ? c.upX * pop : 0;
    b.vy += c.grounded ? c.upY * pop : 0;
    b.vz += nz * power + c.vz * 0.25 + (c.grounded ? c.upZ * pop : pop);
    c.vx -= nx * max(0.0, rel) * 0.25;
    c.vy -= ny * max(0.0, rel) * 0.25;
    c.vz -= nz * max(0.0, rel) * 0.25;
    c.hitCool = 0.12;
    lastTouch = c;
    lastKph = kph(min(b.speed, kMaxBallSpeed));
    kphT = 1.8;
    c.topKph = max(c.topKph, lastKph);
    events.add(power > 30 ? MatchEvent.bigHit : MatchEvent.hit);
  }

  bool _checkGoal() {
    int? scorer;
    if (ball.y < -kBallR) scorer = 1;
    if (ball.y > kFieldL + kBallR) scorer = 0;
    if (scorer == null) return false;
    score[scorer]++;
    goalKph = kph(min(ball.speed, kMaxBallSpeed));
    lastScorerTeam = scorer;
    final touch = lastTouch;
    lastScorer = touch;
    if (touch != null && touch.team == scorer) touch.goals++;
    _say(
      touch == null
          ? 'GOAL!'
          : touch.team == scorer
          ? '${touch.name} SCORED!'
          : 'Own goal by ${touch.name}!',
    );
    events.add(MatchEvent.goal);
    phase = MatchPhase.goal;
    phaseT = 0;
    // Park the ball deep in the net.
    ball
      ..vx = 0
      ..vy = 0
      ..vz = 0
      ..y = scorer == 1 ? -kGoalDepth / 2 : kFieldL + kGoalDepth / 2
      ..z = kBallR;
    return true;
  }

  // ---- walls ----------------------------------------------------------------

  /// The nearest wall: its inward direction and how far away it is. Null
  /// when no wall is close (or inside a goal). Above the crossbar the wall
  /// over each goal counts too.
  static (double, double, double)? nearestRampWall(
    double x,
    double y, [
    double z = 0,
  ]) {
    if (y < 0 || y > kFieldL) return null;
    const c = kFieldW / 2;
    final mouth = (x - c).abs() < kGoalW / 2 + 1 && z < kGoalH + 0.5;
    var best = kRampR;
    (double, double, double)? out;
    void plane(double nx, double ny, double d) {
      final dist = nx * x + ny * y - d;
      if (dist < best) {
        best = dist;
        out = (nx, ny, dist);
      }
    }

    plane(1, 0, 0);
    plane(-1, 0, -kFieldW);
    if (!mouth) {
      plane(0, 1, 0);
      plane(0, -1, -kFieldL);
    }
    const s = 0.7071067811865476;
    plane(s, s, kCorner * s);
    plane(-s, s, (kCorner - kFieldW) * s);
    plane(s, -s, (kCorner - kFieldL) * s);
    plane(-s, -s, (kCorner - kFieldW - kFieldL) * s);
    return out;
  }

  /// How high the curved floor is at a point (0 in the middle of the pitch).
  static double floorHeight(double x, double y) {
    final w = nearestRampWall(x, y);
    if (w == null) return 0;
    final a = kRampR - max(0.0, w.$3);
    return kRampR - sqrt(max(0.0, kRampR * kRampR - a * a));
  }

  /// If a ball of radius [r] centred at (x, y, z) is poking into the floor,
  /// a wall, the roof or the curves joining them, where it should be
  /// instead and which way the surface faces. Null if it is touching
  /// nothing. Cars use r = 0 (their wheels).
  static ({double x, double y, double z, double nx, double ny, double nz})?
  _surface(double x, double y, double z, double r) {
    final w = nearestRampWall(x, y, z);
    if (w != null) {
      final (wx, wy, d) = w;
      // Curves at the bottom and top of the wall are parts of circles
      // around an axis running along the wall. Stay inside them.
      double? cz, rad;
      if (z < kRampR && d < kRampR) {
        cz = kRampR;
        rad = kRampR;
      } else if (z > kCeiling - kTopR && d < kTopR) {
        cz = kCeiling - kTopR;
        rad = kTopR;
      }
      if (cz != null && rad != null) {
        final ad = d - rad, az = z - cz;
        final len = sqrt(ad * ad + az * az);
        final lim = rad - r;
        if (len <= lim || len < 0.0001) return null;
        final k = lim / len;
        final shift = ad * k - ad;
        final nd = -ad / len, nz = -az / len;
        return (
          x: x + wx * shift,
          y: y + wy * shift,
          z: cz + az * k,
          nx: wx * nd,
          ny: wy * nd,
          nz: nz,
        );
      }
      // The straight part of the wall.
      if (d < r + 0.01) {
        final shift = max(0.0, r - d);
        return (
          x: x + wx * shift,
          y: y + wy * shift,
          z: z,
          nx: wx,
          ny: wy,
          nz: 0,
        );
      }
    }
    if (z < r) return (x: x, y: y, z: r, nx: 0, ny: 0, nz: 1);
    if (z > kCeiling - r - 0.01) {
      return (x: x, y: y, z: min(z, kCeiling - r), nx: 0, ny: 0, nz: -1);
    }
    return null;
  }

  /// Keeps a round thing of radius [r] inside the pitch (or inside a goal),
  /// bouncing its speed off any wall it hits.
  (double, double, double, double) _collideWalls(
    double x,
    double y,
    double z,
    double r,
    double vx,
    double vy,
    double bounce,
  ) {
    const c = kFieldW / 2;
    final inMouth = (x - c).abs() < kGoalW / 2 && z < kGoalH;
    final planes = <(double, double, double)>[]; // nx, ny, d: n·p >= d + r
    if (y < 0 && inMouth || y < -0.01 && (x - c).abs() < kGoalW / 2) {
      planes.addAll([
        (1, 0, c - kGoalW / 2),
        (-1, 0, -(c + kGoalW / 2)),
        (0, 1, -kGoalDepth),
      ]);
    } else if (y > kFieldL && inMouth ||
        y > kFieldL + 0.01 && (x - c).abs() < kGoalW / 2) {
      planes.addAll([
        (1, 0, c - kGoalW / 2),
        (-1, 0, -(c + kGoalW / 2)),
        (0, -1, -(kFieldL + kGoalDepth)),
      ]);
    } else {
      planes.addAll([(1, 0, 0), (-1, 0, -kFieldW)]);
      if (!inMouth) planes.addAll([(0, 1, 0), (0, -1, -kFieldL)]);
      const s = 0.7071067811865476;
      planes.addAll([
        (s, s, kCorner * s),
        (-s, s, (kCorner - kFieldW) * s),
        (s, -s, (kCorner - kFieldL) * s),
        (-s, -s, (kCorner - kFieldW - kFieldL) * s),
      ]);
    }
    for (final (nx, ny, d) in planes) {
      final pen = d + r - (nx * x + ny * y);
      if (pen > 0) {
        x += nx * pen;
        y += ny * pen;
        final vn = vx * nx + vy * ny;
        if (vn < 0) {
          vx -= nx * vn * (1 + bounce);
          vy -= ny * vn * (1 + bounce);
        }
      }
    }
    return (x, y, vx, vy);
  }

  // ---- bots -----------------------------------------------------------------

  void _think(Car c, double dt) {
    final inp = c.input;
    if (!c.alive || phase == MatchPhase.over) {
      inp.stick = Offset.zero;
      inp.boost = false;
      return;
    }
    if (phase == MatchPhase.kickoff) {
      inp.stick = Offset.zero;
      inp.boost = false;
      return;
    }
    final level = c.difficulty;
    c.thinkT -= dt;
    final b = ball;
    final dir = c.team == 0 ? 1.0 : -1.0;
    final goal = Offset(kFieldW / 2, c.team == 0 ? kFieldL + 3 : -3);
    final ownGoal = Offset(kFieldW / 2, c.team == 0 ? 0 : kFieldL);
    final toBall = b.pos - c.pos;
    final dist = toBall.distance;

    if (c.thinkT <= 0) {
      c.thinkT = const [0.35, 0.18, 0.06][level] + rnd.nextDouble() * 0.05;
      // Where will the ball be when I get there?
      final t = (dist / 28).clamp(0.0, 1.2);
      var future = Offset(b.x + b.vx * t, b.y + b.vy * t);
      future = Offset(
        future.dx.clamp(3, kFieldW - 3),
        future.dy.clamp(3, kFieldL - 3),
      );
      // The closest teammate goes for the ball; the others hang back.
      final mates = cars.where((o) => o.team == c.team && o.alive).toList()
        ..sort(
          (p, q) =>
              (p.pos - b.pos).distance.compareTo((q.pos - b.pos).distance),
        );
      final attacker = identical(mates.first, c);
      final toGoal = goal - future;
      final g = toGoal / toGoal.distance;
      if (!attacker) {
        final back = mates.indexOf(c);
        c.aim = Offset(
          kFieldW / 2 + (b.x - kFieldW / 2) * 0.5 + (back.isEven ? 6 : -6),
          ownGoal.dy + dir * (back == 1 ? 14 : 30),
        );
        c.wantBoost = (c.aim - c.pos).distance > 30 && c.boost > 50;
      } else {
        final behind = (b.y - c.y) * dir > -1;
        if (behind) {
          // Line up behind the ball, then drive through it at the goal.
          c.aim = dist < 9 ? future + g * 2 : future - g * 4;
        } else if (b.vy * dir < -12) {
          // The ball is flying at our goal: race back and guard it.
          c.aim = Offset(
            (kFieldW / 2 + (b.x - kFieldW / 2) * 0.4).clamp(20, kFieldW - 20),
            ownGoal.dy + dir * 3,
          );
        } else {
          // Wrong side: go round the ball, not through it.
          final side = c.x < b.x ? -1.0 : 1.0;
          c.aim = Offset((b.x + side * 9).clamp(3, kFieldW - 3), b.y - dir * 8);
        }
        final aligned =
            _angleDiff(c.heading, (c.aim - c.pos).direction).abs() < 0.3;
        final boosty = const [0.15, 0.5, 0.9][level];
        c.wantBoost = aligned && c.boost > 10 && rnd.nextDouble() < boosty;
      }
      // Easy bots wobble about.
      final wobble = const [0.5, 0.18, 0.04][level];
      final a = (c.aim - c.pos).direction + (rnd.nextDouble() - 0.5) * wobble;
      final speed = const [0.75, 0.92, 1.0][level];
      inp.stick = Offset.fromDirection(a, speed);
      inp.boost = c.wantBoost;

      // Jump for balls in the air, and flip into the ball on hard.
      final flat = Offset(b.x - c.x, b.y - c.y).distance;
      final facing = _angleDiff(c.heading, toBall.direction).abs() < 0.6;
      // Only flip when the hit would send the ball the right way.
      final goodHit = toBall.dy * dir > dist * 0.3;
      if (c.grounded &&
          flat < 6 &&
          b.z > 3.5 &&
          b.z < 3 + c.spec.jump * 0.45 &&
          facing &&
          rnd.nextDouble() < const [0.3, 0.6, 0.9][level]) {
        inp.jump = true;
      } else if (!c.grounded &&
          c.canFlip &&
          flat < 5 &&
          goodHit &&
          level >= 1 &&
          rnd.nextDouble() < (level == 2 ? 0.8 : 0.3)) {
        inp.stick = Offset.fromDirection(toBall.direction);
        inp.jump = true;
      } else if (c.grounded &&
          level == 2 &&
          flat < 5 &&
          b.z < 4 &&
          facing &&
          goodHit &&
          rnd.nextDouble() < 0.25) {
        inp.jump = true; // first half of a flip
      }
    }
  }

  static double _angleDiff(double from, double to) {
    var d = (to - from) % (2 * pi);
    if (d > pi) d -= 2 * pi;
    return d;
  }
}
