import 'dart:math';
import 'dart:ui' show Offset;

import 'boost_ball_data.dart';

// The pitch, in metres. x runs across, y runs from the blue goal (y = 0)
// to the orange goal (y = kFieldL). Blue attacks up the pitch.
const double kFieldW = 64;
const double kFieldL = 100;
const double kGoalW = 18;
const double kGoalDepth = 7;
const double kGoalH = 8;
const double kCorner = 10; // the corners are cut off at 45 degrees
const double kCeiling = 30;
const double kBallR = 2.4;
const double kCarR = 2.2;
const double kGravity = 32;
const double kMaxBoost = 100;
const double kKickoffTime = 3;
const double kGoalPause = 3;

/// What a player (or a bot) is pressing this frame.
class CarInput {
  /// Which way to drive, in pitch directions (length 0 to 1).
  Offset stick = Offset.zero;
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
  final String name;
  final bool isYou;
  final CarSpec spec;
  final int colour;
  final int difficulty; // bots only

  double x = 0, y = 0, z = 0;
  double vx = 0, vy = 0, vz = 0;
  double heading = 0;
  double boost = 33;
  bool boosting = false;
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
  bool get grounded => z <= 0.001;
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

/// One game of Boost Ball: the cars, the ball and the rules.
class BoostBallMatch {
  final int teamSize;
  final double length; // seconds
  final Random rnd;
  final List<Car> cars = [];
  final Ball ball = Ball();
  final List<BoostPad> pads = [];
  final List<MatchEvent> events = [];

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
    Random? random,
  }) : rnd = random ?? Random(),
       clock = length {
    cars.addAll(players);
    for (final x in [6.0, kFieldW - 6]) {
      for (final y in [12.0, kFieldL - 12]) {
        pads.add(BoostPad(Offset(x, y), true));
      }
      pads.add(BoostPad(Offset(x, kFieldL / 2), true));
    }
    for (final x in [16.0, kFieldW / 2, kFieldW - 16]) {
      for (final y in [26.0, 40.0, 60.0, 74.0]) {
        pads.add(BoostPad(Offset(x, y), false));
      }
    }
    for (final x in [kFieldW / 2 - 14, kFieldW / 2 + 14]) {
      pads.add(BoostPad(Offset(x, kFieldL / 2), false));
    }
    resetKickoff();
  }

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
          ..boost = 33
          ..flipT = 0
          ..demoT = 0
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
    switch (phase) {
      case MatchPhase.kickoff:
        for (final c in cars) {
          if (!c.isYou) _think(c, dt);
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
          if (!c.isYou) _think(c, dt);
          _moveCar(c, dt);
          c.input.jump = false;
        }
        if (phaseT >= kGoalPause) {
          if (overtime || (clock <= 0 && leader != null)) {
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

    clock -= dt;
    if (clock <= 0 && !overtime) {
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
      if (!c.isYou) _think(c, dt);
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
    var throttle = 0.0;
    if (push > 0.15) {
      final want = stick.direction;
      final diff = _angleDiff(c.heading, want);
      final rate = c.spec.turn * (c.grounded ? 1 : 0.7);
      c.heading += diff.clamp(-rate * dt, rate * dt);
      throttle = push * (diff.abs() > 1.6 ? 0.35 : 1);
    }
    c.boosting = inp.boost && c.boost > 0;
    if (c.boosting) c.boost = max(0, c.boost - 33 * dt);

    final f = c.forward;
    final right = Offset(-f.dy, f.dx);
    if (c.grounded) {
      var along = c.vx * f.dx + c.vy * f.dy;
      var side = c.vx * right.dx + c.vy * right.dy;
      final top = c.spec.speed * (c.boosting ? 1.5 : 1);
      along += (c.spec.accel * throttle + (c.boosting ? 32 : 0)) * dt;
      if (along > top) along = max(top, along - 40 * dt);
      if (throttle == 0 && !c.boosting) along *= pow(0.35, dt).toDouble();
      side *= pow(0.01, dt).toDouble(); // tyres grip
      c.vx = f.dx * along + right.dx * side;
      c.vy = f.dy * along + right.dy * side;
    } else {
      if (c.boosting) {
        c.vx += f.dx * 20 * dt;
        c.vy += f.dy * 20 * dt;
        c.vz += 10 * dt; // boosting in the air lifts you a little
      }
      c.vz -= kGravity * dt;
      c.airT += dt;
    }

    if (inp.jump) {
      if (c.grounded) {
        c.vz = c.spec.jump;
        c.z = 0.01;
        c.airT = 0;
        c.canFlip = true;
      } else if (c.canFlip && c.airT < 1.6) {
        // Flip: a burst of speed and a big hit.
        final dir = push > 0.2 ? stick / stick.distance : f;
        c.vx += dir.dx * 15;
        c.vy += dir.dy * 15;
        c.vz = max(c.vz, 4);
        c.heading = dir.direction;
        c.flipT = 0.5;
        c.canFlip = false;
      }
    }

    c.x += c.vx * dt;
    c.y += c.vy * dt;
    c.z += c.vz * dt;
    if (c.z <= 0) {
      c.z = 0;
      c.vz = 0;
      c.airT = 0;
    }
    final v = _collideWalls(c.x, c.y, c.z, kCarR, c.vx, c.vy, 0.1);
    c
      ..x = v.$1
      ..y = v.$2
      ..vx = v.$3
      ..vy = v.$4;

    if (c.grounded) {
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

  void _respawn(Car c) {
    c
      ..x = kFieldW / 2 + (rnd.nextDouble() - 0.5) * 20
      ..y = c.team == 0 ? 6 : kFieldL - 6
      ..z = 0
      ..vx = 0
      ..vy = 0
      ..vz = 0
      ..boost = 33
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
    if (b.z < kBallR) {
      b.z = kBallR;
      if (b.vz < 0) {
        b.vz = -b.vz * 0.6;
        if (b.vz < 2.5) b.vz = 0;
      }
    }
    if (b.z > kCeiling - kBallR) {
      b.z = kCeiling - kBallR;
      if (b.vz > 0) b.vz = -b.vz * 0.7;
    }
    final onGround = b.z <= kBallR + 0.01;
    final drag = pow(onGround ? 0.62 : 0.8, dt).toDouble();
    b.vx *= drag;
    b.vy *= drag;
    final sp = b.speed;
    if (sp > 55) {
      b.vx *= 55 / sp;
      b.vy *= 55 / sp;
      b.vz *= 55 / sp;
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
    final cz = c.z + 1.1;
    final dx = b.x - c.x, dy = b.y - c.y, dz = b.z - cz;
    final dist = sqrt(dx * dx + dy * dy + dz * dz);
    const reach = kBallR + kCarR;
    if (dist >= reach || dist < 0.001) return;
    final nx = dx / dist, ny = dy / dist, nz = dz / dist;
    // Push the ball out so it is just touching.
    b.x = c.x + nx * reach;
    b.y = c.y + ny * reach;
    b.z = max(kBallR, cz + nz * reach);
    final rel = (c.vx - b.vx) * nx + (c.vy - b.vy) * ny + (c.vz - b.vz) * nz;
    var power = max(0.0, rel) * 1.35 * c.spec.hit + 5;
    final flipped = c.flipT > 0;
    if (flipped) power *= 1.6;
    b.vx += nx * power + c.vx * 0.25;
    b.vy += ny * power + c.vy * 0.25;
    // Hits along the ground pop the ball up a bit.
    b.vz += nz * power + (c.grounded ? 3 + max(0.0, rel) * 0.2 : 2);
    c.vx -= nx * max(0.0, rel) * 0.25;
    c.vy -= ny * max(0.0, rel) * 0.25;
    c.hitCool = 0.12;
    lastTouch = c;
    events.add(power > 30 ? MatchEvent.bigHit : MatchEvent.hit);
  }

  bool _checkGoal() {
    int? scorer;
    if (ball.y < -kBallR) scorer = 1;
    if (ball.y > kFieldL + kBallR) scorer = 0;
    if (scorer == null) return false;
    score[scorer]++;
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
