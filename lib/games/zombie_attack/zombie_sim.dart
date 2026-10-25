import 'dart:math';
import 'dart:ui' show Offset, Rect;

import 'zombie_data.dart';

/// The playing area, in metres.
const double kWorldW = 64;
const double kWorldH = 64;
const double kPlayerR = 0.8;
const double kPlayerSpeed = 8;
const double kMaxHp = 100;
const double kGrenadeRange = 9;
const double kGrenadeBlast = 5;
const double kWaveBreak = 3;

enum ZombieKind {
  walker(3, 2.6, 0.85),
  runner(2, 4.8, 0.7),
  tank(14, 1.9, 1.35),
  king(70, 2.3, 2.1);

  final double hp;
  final double speed;
  final double radius;
  const ZombieKind(this.hp, this.speed, this.radius);
}

class Zombie {
  final int id;
  final ZombieKind kind;
  Offset pos;
  double hp;
  final double maxHp;
  double hitCool = 0;
  double flash = 0; // > 0 just after being hit
  double wobble; // for the shuffling walk
  double facing = 0;

  Zombie(this.id, this.kind, this.pos, double hpScale, this.wobble)
    : hp = kind.hp * hpScale,
      maxHp = kind.hp * hpScale;

  double get r => kind.radius;
}

class Bullet {
  Offset pos;
  final Offset vel;
  final Gun gun;
  double life;
  final Set<int> hit = {};
  Bullet(this.pos, this.vel, this.gun) : life = gun.range / gun.speed;
}

enum PickupKind { health, grenade }

class Pickup {
  final PickupKind kind;
  final Offset pos;
  double life = 12;
  Pickup(this.kind, this.pos);
}

class Grenade {
  Offset from;
  final Offset to;
  double t = 0;
  static const double fuse = 0.8;
  Grenade(this.from, this.to);
  Offset get pos => Offset.lerp(from, to, min(1, t / fuse * 1.4))!;
}

/// A short-lived explosion ring to draw.
class Boom {
  final Offset pos;
  final double radius;
  double t = 0;
  Boom(this.pos, this.radius);
}

/// A puff of smoke where a zombie went poof.
class Poof {
  final Offset pos;
  final double size;
  double t = 0;
  Poof(this.pos, this.size);
}

/// What the player is pressing this frame.
class ZombieInput {
  Offset move = Offset.zero; // length 0 to 1
  Offset? aim; // which way to shoot (null = not aiming)
  bool fire = false;
  bool autoAim = false; // shoot the nearest zombie by itself (touch help)
  bool grenade = false; // set for one frame to throw
}

enum ZombiePhase { play, rest, over }

enum ZombieEvent {
  shoot,
  hit,
  kill,
  hurt,
  boom,
  pickup,
  waveStart,
  waveClear,
  dead,
}

class ZombieWorld {
  final ZombieMap map;
  final int level; // 0 easy, 1 normal, 2 hard
  final Gun gun;
  final Random rnd;
  final List<Rect> blocks;

  Offset player = const Offset(kWorldW / 2, kWorldH / 2);
  double hp = kMaxHp;
  double aimAngle = -pi / 2;
  double fireCool = 0;
  double hurtT = 0;
  int grenades = 2;
  final ZombieInput input = ZombieInput();

  final List<Zombie> zombies = [];
  final List<Bullet> bullets = [];
  final List<Pickup> pickups = [];
  final List<Grenade> thrown = [];
  final List<Boom> booms = [];
  final List<Poof> poofs = [];
  final List<ZombieEvent> events = [];

  ZombiePhase phase = ZombiePhase.rest;
  double phaseT = 1.5; // first wave starts soon
  int wave = 0;
  int wavesCleared = 0;
  int kills = 0;
  int coinsEarned = 0;
  int _toSpawn = 0;
  double _spawnT = 0;
  int _nextId = 0;
  double time = 0;

  ZombieWorld({
    this.map = ZombieMap.town,
    this.level = 1,
    Gun? gun,
    Random? random,
  }) : gun = gun ?? kGuns.first,
       rnd = random ?? Random(),
       blocks = buildBlocks(map);

  double get _zombieSpeed => const [0.8, 1.0, 1.18][level];
  double get _zombieDamage => const [6.0, 10.0, 14.0][level];
  bool get bossWave => wave % 5 == 0;
  int get zombiesLeft => _toSpawn + zombies.length;

  /// Obstacles for each map. The middle is always kept clear for you.
  static List<Rect> buildBlocks(ZombieMap map) {
    final r = Random(map.index + 11);
    final out = <Rect>[];
    bool clear(Rect b) =>
        (b.center - const Offset(kWorldW / 2, kWorldH / 2)).distance > 9 &&
        out.every((o) => !o.inflate(3).overlaps(b));
    var tries = 0;
    final want = switch (map) {
      ZombieMap.town => 10,
      ZombieMap.graveyard => 22,
      ZombieMap.school => 12,
    };
    while (out.length < want && tries++ < 500) {
      final (w, h) = switch (map) {
        // Houses and cars.
        ZombieMap.town =>
          r.nextBool()
              ? (6 + r.nextDouble() * 3, 5 + r.nextDouble() * 3)
              : (r.nextBool() ? (4.2, 2.0) : (2.0, 4.2)),
        // Gravestones and the odd tomb.
        ZombieMap.graveyard => r.nextDouble() < 0.2 ? (4.0, 2.6) : (1.4, 0.9),
        // Benches, a climbing frame and a slide.
        ZombieMap.school => r.nextDouble() < 0.3 ? (5.0, 4.0) : (3.6, 1.0),
      };
      final x = 4 + r.nextDouble() * (kWorldW - 8 - w);
      final y = 4 + r.nextDouble() * (kWorldH - 8 - h);
      final b = Rect.fromLTWH(x, y, w, h);
      if (clear(b)) out.add(b);
    }
    return out;
  }

  // ---- the main loop -----------------------------------------------------

  void step(double dt) {
    events.clear();
    time += dt;
    for (final b in booms) {
      b.t += dt;
    }
    booms.removeWhere((b) => b.t > 0.5);
    for (final p in poofs) {
      p.t += dt;
    }
    poofs.removeWhere((p) => p.t > 0.6);
    if (phase == ZombiePhase.over) return;

    _movePlayer(dt);
    _shoot(dt);
    _moveBullets(dt);
    _moveGrenades(dt);
    _moveZombies(dt);
    _pickups(dt);
    _waves(dt);
    if (hp <= 0) {
      hp = 0;
      phase = ZombiePhase.over;
      events.add(ZombieEvent.dead);
    }
  }

  void _waves(double dt) {
    if (phase == ZombiePhase.rest) {
      phaseT -= dt;
      if (phaseT <= 0) {
        wave++;
        phase = ZombiePhase.play;
        _toSpawn = 3 + wave * 3 - (level == 0 ? 1 : 0);
        if (bossWave) _toSpawn = max(1, _toSpawn - 4);
        _spawnT = 0.3;
        if (bossWave) _spawn(ZombieKind.king);
        events.add(ZombieEvent.waveStart);
      }
      return;
    }
    _spawnT -= dt;
    if (_toSpawn > 0 && _spawnT <= 0) {
      _spawnT = max(0.25, 1.0 - wave * 0.05);
      _toSpawn--;
      final roll = rnd.nextDouble();
      final kind = wave >= 5 && roll < 0.12
          ? ZombieKind.tank
          : wave >= 3 && roll < 0.35
          ? ZombieKind.runner
          : ZombieKind.walker;
      _spawn(kind);
    }
    if (_toSpawn == 0 && zombies.isEmpty) {
      wavesCleared++;
      coinsEarned += kWaveCoins[level] + (bossWave ? 50 : 0);
      phase = ZombiePhase.rest;
      phaseT = kWaveBreak;
      events.add(ZombieEvent.waveClear);
    }
  }

  void _spawn(ZombieKind kind) {
    // Come in from a random edge, away from you.
    for (var i = 0; i < 20; i++) {
      final side = rnd.nextInt(4);
      final t = rnd.nextDouble();
      final p = switch (side) {
        0 => Offset(t * kWorldW, 1.5),
        1 => Offset(t * kWorldW, kWorldH - 1.5),
        2 => Offset(1.5, t * kWorldH),
        _ => Offset(kWorldW - 1.5, t * kWorldH),
      };
      if ((p - player).distance < 14) continue;
      if (blocks.any((b) => b.inflate(kind.radius).contains(p))) continue;
      final hpScale = 1 + (wave - 1) * 0.08;
      zombies.add(
        Zombie(_nextId++, kind, p, hpScale, rnd.nextDouble() * 2 * pi),
      );
      return;
    }
  }

  // ---- you ---------------------------------------------------------------

  void _movePlayer(double dt) {
    hurtT = max(0, hurtT - dt);
    var m = input.move;
    if (m.distance > 1) m = m / m.distance;
    player = _slide(player + m * kPlayerSpeed * dt, kPlayerR);
  }

  Zombie? nearestZombie(double within) {
    Zombie? best;
    var bestD = within;
    for (final z in zombies) {
      final d = (z.pos - player).distance - z.r;
      if (d < bestD) {
        bestD = d;
        best = z;
      }
    }
    return best;
  }

  void _shoot(double dt) {
    fireCool = max(0, fireCool - dt);
    var aim = input.aim;
    var fire = input.fire;
    if ((aim == null || aim.distance < 0.1) && (input.autoAim || fire)) {
      // Touch help: point at the nearest zombie in range and shoot it.
      final z = nearestZombie(gun.range * 0.95);
      aim = z == null ? null : z.pos - player;
      fire = z != null;
    }
    if (aim != null && aim.distance > 0.1) aimAngle = aim.direction;
    if (input.grenade) {
      input.grenade = false;
      if (grenades > 0) {
        grenades--;
        final to = _slide(
          player + Offset.fromDirection(aimAngle, kGrenadeRange),
          0.3,
        );
        thrown.add(Grenade(player, to));
      }
    }
    if (!fire || fireCool > 0) return;
    fireCool = 1 / gun.fireRate;
    for (var i = 0; i < gun.pellets; i++) {
      final spread = gun.pellets == 1
          ? (rnd.nextDouble() - 0.5) * gun.spread
          : -gun.spread / 2 + gun.spread * i / (gun.pellets - 1);
      final a = aimAngle + spread;
      final dir = Offset.fromDirection(a);
      bullets.add(Bullet(player + dir * 1.1, dir * gun.speed, gun));
    }
    events.add(ZombieEvent.shoot);
  }

  // ---- bullets and bangs -------------------------------------------------

  void _moveBullets(double dt) {
    for (final b in bullets) {
      b.pos += b.vel * dt;
      b.life -= dt;
      if (_blocked(b.pos, 0.05)) {
        b.life = 0;
        if (b.gun.blast > 0) _explode(b.pos, b.gun.blast, b.gun.damage);
        continue;
      }
      for (final z in zombies) {
        if (b.hit.contains(z.id) || z.hp <= 0) continue;
        if ((z.pos - b.pos).distance < z.r + 0.2) {
          b.hit.add(z.id);
          if (b.gun.blast > 0) {
            _explode(b.pos, b.gun.blast, b.gun.damage);
            b.life = 0;
            break;
          }
          _damage(z, b.gun.damage, b.vel / b.vel.distance);
          if (!b.gun.pierce) {
            b.life = 0;
            break;
          }
        }
      }
    }
    bullets.removeWhere((b) => b.life <= 0);
    _bury();
  }

  void _moveGrenades(double dt) {
    for (final g in thrown) {
      g.t += dt;
      if (g.t >= Grenade.fuse) _explode(g.to, kGrenadeBlast, 9);
    }
    thrown.removeWhere((g) => g.t >= Grenade.fuse);
    _bury();
  }

  void _explode(Offset at, double radius, double damage) {
    booms.add(Boom(at, radius));
    events.add(ZombieEvent.boom);
    for (final z in zombies) {
      final d = (z.pos - at).distance;
      if (d < radius + z.r) {
        final push = d > 0.01 ? (z.pos - at) / d : const Offset(1, 0);
        _damage(z, damage * (1 - 0.5 * d / (radius + z.r)), push * 2);
      }
    }
  }

  void _damage(Zombie z, double amount, Offset push) {
    z.hp -= amount;
    z.flash = 0.12;
    // Knock it back a little (big ones barely move).
    z.pos = _slide(z.pos + push * (0.5 / z.r), z.r);
    events.add(ZombieEvent.hit);
  }

  /// Takes away zombies that ran out of health.
  void _bury() {
    zombies.removeWhere((z) {
      if (z.hp > 0) return false;
      kills++;
      poofs.add(Poof(z.pos, z.r * 1.8));
      events.add(ZombieEvent.kill);
      final roll = rnd.nextDouble();
      if (z.kind == ZombieKind.king || roll < 0.06) {
        pickups.add(Pickup(PickupKind.health, z.pos));
      } else if (roll < 0.1) {
        pickups.add(Pickup(PickupKind.grenade, z.pos));
      }
      return true;
    });
  }

  // ---- zombies -----------------------------------------------------------

  void _moveZombies(double dt) {
    for (final z in zombies) {
      z.hitCool = max(0, z.hitCool - dt);
      z.flash = max(0, z.flash - dt);
      z.wobble += dt * (z.kind == ZombieKind.runner ? 9 : 5);
      final to = player - z.pos;
      final d = to.distance;
      if (d > 0.01) z.facing = to.direction;
      // Shuffle towards you, swaying a bit.
      var dir = d > 0.01 ? to / d : Offset.zero;
      dir = Offset.fromDirection(dir.direction + sin(z.wobble) * 0.25);
      var next = z.pos + dir * z.kind.speed * _zombieSpeed * dt;
      // Don't stack up: push away from other zombies.
      for (final o in zombies) {
        if (identical(o, z)) continue;
        final gap = next - o.pos;
        final gd = gap.distance;
        final reach = z.r + o.r;
        if (gd < reach && gd > 0.001) next += gap / gd * (reach - gd) * 0.5;
      }
      z.pos = _slide(next, z.r);
      // Bite!
      if (d < z.r + kPlayerR + 0.1 && z.hitCool <= 0) {
        z.hitCool = 0.9;
        final bite = _zombieDamage * (z.kind == ZombieKind.king ? 2 : 1);
        hp -= bite;
        hurtT = 0.35;
        events.add(ZombieEvent.hurt);
      }
    }
  }

  void _pickups(double dt) {
    for (final p in pickups) {
      p.life -= dt;
      if ((p.pos - player).distance < kPlayerR + 0.9) {
        p.life = 0;
        events.add(ZombieEvent.pickup);
        switch (p.kind) {
          case PickupKind.health:
            hp = min(kMaxHp, hp + 30);
          case PickupKind.grenade:
            grenades = min(5, grenades + 1);
        }
      }
    }
    pickups.removeWhere((p) => p.life <= 0);
  }

  // ---- walls -------------------------------------------------------------

  bool _blocked(Offset p, double r) =>
      p.dx < 0 ||
      p.dy < 0 ||
      p.dx > kWorldW ||
      p.dy > kWorldH ||
      blocks.any((b) => b.inflate(r).contains(p));

  /// Keeps a circle out of the obstacles and inside the world, sliding
  /// along whatever it bumps into.
  Offset _slide(Offset p, double r) {
    var x = p.dx.clamp(r, kWorldW - r).toDouble();
    var y = p.dy.clamp(r, kWorldH - r).toDouble();
    for (final b in blocks) {
      final cx = x.clamp(b.left, b.right).toDouble();
      final cy = y.clamp(b.top, b.bottom).toDouble();
      final dx = x - cx, dy = y - cy;
      final d2 = dx * dx + dy * dy;
      if (d2 >= r * r) continue;
      if (d2 > 1e-6) {
        final d = sqrt(d2);
        x = cx + dx / d * r;
        y = cy + dy / d * r;
      } else {
        // Centre inside the box: pop out the nearest side.
        final left = x - b.left, right = b.right - x;
        final top = y - b.top, bottom = b.bottom - y;
        final m = [left, right, top, bottom].reduce(min);
        if (m == left) {
          x = b.left - r;
        } else if (m == right) {
          x = b.right + r;
        } else if (m == top) {
          y = b.top - r;
        } else {
          y = b.bottom + r;
        }
      }
    }
    return Offset(x, y);
  }
}
