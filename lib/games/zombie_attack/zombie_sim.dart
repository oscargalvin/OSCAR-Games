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

/// Size of the safe zone in each corner of the map. Zombies can't get in
/// and can't bite you while you're inside.
const double kSafeSize = 8;
const List<Rect> kSafeZones = [
  Rect.fromLTWH(0, 0, kSafeSize, kSafeSize),
  Rect.fromLTWH(kWorldW - kSafeSize, 0, kSafeSize, kSafeSize),
  Rect.fromLTWH(0, kWorldH - kSafeSize, kSafeSize, kSafeSize),
  Rect.fromLTWH(kWorldW - kSafeSize, kWorldH - kSafeSize, kSafeSize, kSafeSize),
];

bool inSafeZone(Offset p) => kSafeZones.any((z) => z.contains(p));

/// How long a sword swing shows for.
const double kSwingTime = 0.25;

/// In Zombie vs Human, the wave when the zombie player turns up as the
/// Zombie King.
const int kKingArrives = 4;

/// The zombie player's brains: they pay for zombies with them.
const double kMaxBrains = 10;
const double kBrainsPerSecond = 0.8;

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

/// Zombies the zombie player can send in, and what they cost in brains.
enum ZombieOrder {
  walker('Walker', 1, ZombieKind.walker),
  runner('Runner', 2, ZombieKind.runner),
  sword('Sword', 3, ZombieKind.walker),
  tank('Tank', 5, ZombieKind.tank);

  final String title;
  final int cost;
  final ZombieKind kind;
  const ZombieOrder(this.title, this.cost, this.kind);
}

/// Playing alone, two people against the zombies, or one person against a
/// friend who plays the zombies.
enum ZombieMode { solo, coop, versus }

class Zombie {
  final int id;
  final ZombieKind kind;
  Offset pos;
  double hp;
  double maxHp;
  double hitCool = 0;
  double flash = 0; // > 0 just after being hit
  double wobble; // for the shuffling walk
  double facing = 0;
  bool sword = false; // carries a sword, and drops it when beaten
  bool controlled = false; // the zombie player is driving this one

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

enum PickupKind { health, grenade, sword }

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

/// What a player is pressing this frame.
class ZombieInput {
  Offset move = Offset.zero; // length 0 to 1
  Offset? aim; // which way to shoot (null = not aiming)
  bool fire = false;
  bool autoAim = false; // shoot the nearest zombie by itself (touch help)
  bool grenade = false; // set for one frame to throw
  bool swap = false; // set for one frame to change weapon
}

/// A person fighting the zombies.
class Survivor {
  String name;
  Offset pos = const Offset(kWorldW / 2, kWorldH / 2);
  double hp = kMaxHp;
  double aimAngle = -pi / 2;
  double fireCool = 0;
  double hurtT = 0;
  double swingT = 0; // > 0 while a sword swing is showing
  int grenades = 2;
  bool keptSword = false; // won the 5% roll this game
  final ZombieInput input = ZombieInput();
  final List<Gun> weapons;
  int weaponIndex = 0;

  Survivor(this.name, Gun gun) : weapons = [gun];

  Gun get gun => weapons[weaponIndex.clamp(0, weapons.length - 1)];
  bool get alive => hp > 0;
}

/// The friend playing the zombies in Zombie vs Human. They float round
/// the map sending zombies in, then become the Zombie King at wave 4.
class ZombieBoss {
  String name;
  Offset pos = const Offset(kWorldW / 2, 6);
  double brains = 3;
  final ZombieInput input = ZombieInput();
  final List<ZombieOrder> orders = []; // zombies they asked for
  int kingId = -1; // the King they drive, once it arrives
  double smashCool = 0;
  double smashT = 0; // > 0 while a smash shows
  ZombieBoss(this.name);
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
  swing,
  newWeapon, // picked up a sword
  keepWeapon, // ...and it's yours to keep!
  kingArrives, // the zombie player turned up as the Zombie King
  smash, // the Zombie King player smashed
  spawned, // the zombie player sent a zombie in
}

class ZombieWorld {
  final ZombieMap map;
  final int level; // 0 easy, 1 normal, 2 hard
  final ZombieMode mode;
  final Random rnd;
  final List<Rect> blocks;

  /// Everyone fighting the zombies. On this phone you are
  /// survivors[youIndex], or the zombie player when youIndex is -1.
  final List<Survivor> survivors;
  int youIndex = 0;
  final ZombieBoss? boss;

  /// False on a friend's phone: the room maker's phone runs the real game
  /// and this one just carries things on between updates.
  bool authority = true;

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

  /// Who won a Zombie vs Human game: 'humans' or 'zombies'.
  String? winner;
  int _toSpawn = 0;
  double _spawnT = 0;
  int _nextId = 0;
  double time = 0;

  ZombieWorld({
    this.map = ZombieMap.town,
    this.level = 1,
    this.mode = ZombieMode.solo,
    Gun? gun,
    Gun? friendGun,
    String name = 'You',
    String friendName = 'Friend',
    Random? random,
  }) : survivors = [
         Survivor(name, gun ?? kGuns.first),
         if (mode == ZombieMode.coop)
           Survivor(friendName, friendGun ?? kGuns.first),
       ],
       boss = mode == ZombieMode.versus ? ZombieBoss(friendName) : null,
       rnd = random ?? Random(),
       blocks = buildBlocks(map) {
    if (survivors.length == 2) {
      survivors[0].pos = const Offset(kWorldW / 2 - 1.5, kWorldH / 2);
      survivors[1].pos = const Offset(kWorldW / 2 + 1.5, kWorldH / 2);
    }
  }

  // ---- you ---------------------------------------------------------------

  bool get youAreBoss => youIndex < 0;
  Survivor get you => survivors[youIndex.clamp(0, survivors.length - 1)];

  Offset get player => you.pos;
  set player(Offset p) => you.pos = p;
  double get hp => you.hp;
  set hp(double v) => you.hp = v;
  double get aimAngle => you.aimAngle;
  set aimAngle(double v) => you.aimAngle = v;
  double get hurtT => you.hurtT;
  double get swingT => you.swingT;
  int get grenades => you.grenades;
  bool get keptSword => you.keptSword;
  ZombieInput get input => youAreBoss ? boss!.input : you.input;
  List<Gun> get weapons => you.weapons;
  int get weaponIndex => you.weaponIndex;
  Gun get gun => you.gun;

  /// Where the camera follows on this phone.
  Offset get viewPos => youAreBoss ? (king?.pos ?? boss!.pos) : player;

  /// The King the zombie player is driving, if it has arrived.
  Zombie? get king {
    final b = boss;
    if (b == null || b.kingId < 0) return null;
    for (final z in zombies) {
      if (z.id == b.kingId) return z;
    }
    return null;
  }

  double get _zombieSpeed => const [0.8, 1.0, 1.18][level];
  double get _zombieDamage => const [6.0, 10.0, 14.0][level];
  bool get bossWave => mode != ZombieMode.versus && wave % 5 == 0;
  int get zombiesLeft => _toSpawn + zombies.where((z) => !z.controlled).length;

  /// Obstacles for each map. The middle is always kept clear for you.
  static List<Rect> buildBlocks(ZombieMap map) {
    final r = Random(map.index + 11);
    final out = <Rect>[];
    bool clear(Rect b) =>
        (b.center - const Offset(kWorldW / 2, kWorldH / 2)).distance > 9 &&
        kSafeZones.every((z) => !z.inflate(2).overlaps(b)) &&
        out.every((o) => !o.inflate(3).overlaps(b));
    var tries = 0;
    final want = switch (map) {
      ZombieMap.town => 10,
      ZombieMap.graveyard => 22,
      ZombieMap.school => 12,
      ZombieMap.farm => 14,
      ZombieMap.beach => 16,
      ZombieMap.snow => 24,
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
        // Barns and hay bales.
        ZombieMap.farm =>
          r.nextDouble() < 0.25
              ? (8.0, 6.0)
              : (r.nextBool() ? (2.4, 1.3) : (1.3, 2.4)),
        // Beach huts, rocks and palm trees.
        ZombieMap.beach => switch (r.nextDouble()) {
          < 0.25 => (4.0, 4.0),
          < 0.55 => (2.2, 1.8),
          _ => (0.8, 0.8),
        },
        // Pine trees and snowmen.
        ZombieMap.snow => r.nextDouble() < 0.25 ? (1.4, 1.4) : (1.0, 1.0),
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
    if (!authority) {
      _coast(dt);
      return;
    }

    for (final s in survivors) {
      _moveSurvivor(s, dt);
      _shoot(s, dt);
    }
    _moveBoss(dt);
    _moveBullets(dt);
    _moveGrenades(dt);
    _moveZombies(dt);
    _pickups(dt);
    _waves(dt);
    for (final s in survivors) {
      if (s.hp < 0) s.hp = 0;
    }
    if (survivors.every((s) => !s.alive)) {
      phase = ZombiePhase.over;
      if (mode == ZombieMode.versus) winner = 'zombies';
      events.add(ZombieEvent.dead);
    }
  }

  /// On a friend's phone: keep things moving smoothly until the next
  /// update from the room maker's phone arrives.
  void _coast(double dt) {
    if (!youAreBoss && you.alive) {
      final s = you;
      var m = s.input.move;
      if (m.distance > 1) m = m / m.distance;
      s.pos = _slide(s.pos + m * kPlayerSpeed * dt, kPlayerR);
      final aim = s.input.aim;
      if (aim != null && aim.distance > 0.1) s.aimAngle = aim.direction;
    }
    final b = boss;
    if (b != null && youAreBoss && b.kingId < 0) {
      b.pos = _clampWorld(b.pos + _unit(b.input.move) * 14 * dt);
    }
    for (final s in survivors) {
      s.hurtT = max(0, s.hurtT - dt);
      s.swingT = max(0, s.swingT - dt);
    }
    for (final x in bullets) {
      x.pos += x.vel * dt;
    }
    for (final g in thrown) {
      g.t += dt;
    }
    for (final z in zombies) {
      z.flash = max(0, z.flash - dt);
      z.wobble += dt * (z.kind == ZombieKind.runner ? 9 : 5);
      if (z.controlled) continue;
      final t = _target(z.pos);
      if (t == null) continue;
      final to = t.pos - z.pos;
      final d = to.distance;
      if (d > z.r + kPlayerR) {
        z.pos = _slide(z.pos + to / d * z.kind.speed * _zombieSpeed * dt, z.r);
      }
    }
  }

  void _waves(double dt) {
    if (phase == ZombiePhase.rest) {
      phaseT -= dt;
      if (phaseT <= 0) {
        wave++;
        phase = ZombiePhase.play;
        _toSpawn = 3 + wave * 3 - (level == 0 ? 1 : 0);
        if (mode == ZombieMode.coop) _toSpawn = (_toSpawn * 1.5).round();
        // The zombie player sends extra zombies in, so fewer come by
        // themselves.
        if (mode == ZombieMode.versus) {
          _toSpawn = max(2, (_toSpawn * 0.6).round());
        }
        if (bossWave) _toSpawn = max(1, _toSpawn - 4);
        _spawnT = 0.3;
        if (bossWave) _spawn(ZombieKind.king);
        // Anyone knocked out last wave comes back.
        for (final s in survivors) {
          if (!s.alive) {
            s
              ..hp = kMaxHp / 2
              ..hurtT = 0;
          }
        }
        final b = boss;
        if (b != null && wave >= kKingArrives && b.kingId < 0) {
          _kingArrives(b);
        }
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
      final z = _spawn(kind);
      // From wave 2, some walkers and runners carry a sword.
      if (z != null &&
          wave >= 2 &&
          z.kind != ZombieKind.tank &&
          rnd.nextDouble() < 0.15) {
        z.sword = true;
      }
    }
    if (_toSpawn == 0 && zombies.every((z) => z.controlled)) {
      wavesCleared++;
      coinsEarned += kWaveCoins[level] + (bossWave ? 50 : 0);
      phase = ZombiePhase.rest;
      phaseT = kWaveBreak;
      events.add(ZombieEvent.waveClear);
    }
  }

  Zombie? _spawn(ZombieKind kind) {
    // Come in from a random edge, away from everyone.
    for (var i = 0; i < 20; i++) {
      final side = rnd.nextInt(4);
      final t = rnd.nextDouble();
      final p = switch (side) {
        0 => Offset(t * kWorldW, 1.5),
        1 => Offset(t * kWorldW, kWorldH - 1.5),
        2 => Offset(1.5, t * kWorldH),
        _ => Offset(kWorldW - 1.5, t * kWorldH),
      };
      if (survivors.any((s) => (p - s.pos).distance < 14)) continue;
      if (kSafeZones.any((z) => z.inflate(3).contains(p))) continue;
      if (blocks.any((b) => b.inflate(kind.radius).contains(p))) continue;
      return _add(kind, p);
    }
    return null;
  }

  Zombie _add(ZombieKind kind, Offset p) {
    final hpScale = 1 + (max(1, wave) - 1) * 0.08;
    final z = Zombie(_nextId++, kind, p, hpScale, rnd.nextDouble() * 2 * pi);
    zombies.add(z);
    return z;
  }

  // ---- the zombie player -------------------------------------------------

  void _moveBoss(double dt) {
    final b = boss;
    if (b == null) return;
    b.brains = min(kMaxBrains, b.brains + kBrainsPerSecond * dt);
    b.smashCool = max(0, b.smashCool - dt);
    b.smashT = max(0, b.smashT - dt);
    final k = king;
    if (k == null) {
      // Floating over the map, choosing where to send zombies in.
      b.pos = _clampWorld(b.pos + _unit(b.input.move) * 14 * dt);
    } else {
      b.pos = k.pos;
    }
    for (final order in [...b.orders]) {
      b.orders.remove(order);
      if (b.brains < order.cost) continue;
      final at = _bossSpawnPoint(b.pos, order.kind);
      if (at == null) continue;
      b.brains -= order.cost;
      final z = _add(order.kind, at);
      if (order == ZombieOrder.sword) z.sword = true;
      events.add(ZombieEvent.spawned);
    }
  }

  /// Somewhere near [near] for a new zombie: not in a wall or safe zone,
  /// and not right on top of anyone.
  Offset? _bossSpawnPoint(Offset near, ZombieKind kind) {
    for (var i = 0; i < 25; i++) {
      final p = i == 0
          ? near
          : _clampWorld(
              near +
                  Offset.fromDirection(
                    rnd.nextDouble() * 2 * pi,
                    1.0 + i * 0.4,
                  ),
            );
      if (survivors.any((s) => s.alive && (p - s.pos).distance < 7)) continue;
      if (kSafeZones.any((z) => z.inflate(kind.radius + 0.5).contains(p))) {
        continue;
      }
      if (blocks.any((b) => b.inflate(kind.radius).contains(p))) continue;
      return p;
    }
    return null;
  }

  void _kingArrives(ZombieBoss b) {
    final at =
        _bossSpawnPoint(b.pos, ZombieKind.king) ??
        _bossSpawnPoint(const Offset(kWorldW / 2, 4), ZombieKind.king) ??
        const Offset(kWorldW / 2, 4);
    final z = _add(ZombieKind.king, at)
      ..controlled = true
      ..hp = 55
      ..maxHp = 55;
    b.kingId = z.id;
    events.add(ZombieEvent.kingArrives);
  }

  /// The Zombie King player walks and smashes.
  void _driveKing(Zombie z, double dt) {
    final b = boss!;
    final move = _unit(b.input.move);
    final next = z.pos + move * 5.5 * dt;
    z.pos = _keepOutOfSafeZones(_slide(next, z.r), z.r);
    if (move.distance > 0.1) z.wobble += dt * 5;
    final aim = b.input.aim;
    if (aim != null && aim.distance > 0.1) {
      z.facing = aim.direction;
    } else if (move.distance > 0.1) {
      z.facing = move.direction;
    }
    if (!b.input.fire || b.smashCool > 0) return;
    b.smashCool = 0.9;
    b.smashT = 0.3;
    events.add(ZombieEvent.smash);
    final ahead = Offset.fromDirection(z.facing);
    for (final s in survivors) {
      if (!s.alive || inSafeZone(s.pos)) continue;
      final to = s.pos - z.pos;
      final d = to.distance;
      if (d > z.r + 2.2) continue;
      if (d > 0.01 && (to.dx * ahead.dx + to.dy * ahead.dy) / d < cos(1.1)) {
        continue;
      }
      _hurt(s, 22);
      final push = d > 0.01 ? to / d : ahead;
      s.pos = _slide(s.pos + push * 1.5, kPlayerR);
    }
  }

  // ---- survivors ---------------------------------------------------------

  void _moveSurvivor(Survivor s, double dt) {
    s.hurtT = max(0, s.hurtT - dt);
    if (!s.alive) return;
    var m = s.input.move;
    if (m.distance > 1) m = m / m.distance;
    s.pos = _slide(s.pos + m * kPlayerSpeed * dt, kPlayerR);
  }

  Zombie? nearestZombie(double within, [Offset? from]) {
    final at = from ?? player;
    Zombie? best;
    var bestD = within;
    for (final z in zombies) {
      final d = (z.pos - at).distance - z.r;
      if (d < bestD) {
        bestD = d;
        best = z;
      }
    }
    return best;
  }

  void _shoot(Survivor s, double dt) {
    s.fireCool = max(0, s.fireCool - dt);
    s.swingT = max(0, s.swingT - dt);
    final input = s.input;
    if (!s.alive) {
      input
        ..grenade = false
        ..swap = false;
      return;
    }
    var aim = input.aim;
    var fire = input.fire;
    if ((aim == null || aim.distance < 0.1) && (input.autoAim || fire)) {
      // Touch help: point at the nearest zombie in range and shoot it.
      final z = nearestZombie(s.gun.range * 0.95, s.pos);
      aim = z == null ? null : z.pos - s.pos;
      fire = z != null;
    }
    if (aim != null && aim.distance > 0.1) s.aimAngle = aim.direction;
    if (input.swap) {
      input.swap = false;
      if (s.weapons.length > 1) {
        s.weaponIndex = (s.weaponIndex + 1) % s.weapons.length;
        s.fireCool = 0.15;
      }
    }
    // No shooting, swinging or throwing from inside a safe zone.
    final safe = inSafeZone(s.pos);
    if (input.grenade) {
      input.grenade = false;
      if (s.grenades > 0 && !safe) {
        s.grenades--;
        final to = _slide(
          s.pos + Offset.fromDirection(s.aimAngle, kGrenadeRange),
          0.3,
        );
        thrown.add(Grenade(s.pos, to));
      }
    }
    if (!fire || s.fireCool > 0 || safe) return;
    final gun = s.gun;
    s.fireCool = 1 / gun.fireRate;
    if (gun.melee) {
      _swing(s);
      return;
    }
    for (var i = 0; i < gun.pellets; i++) {
      final spread = gun.pellets == 1
          ? (rnd.nextDouble() - 0.5) * gun.spread
          : -gun.spread / 2 + gun.spread * i / (gun.pellets - 1);
      final a = s.aimAngle + spread;
      final dir = Offset.fromDirection(a);
      bullets.add(Bullet(s.pos + dir * 1.1, dir * gun.speed, gun));
    }
    events.add(ZombieEvent.shoot);
  }

  /// A sword slice: hits every zombie in front of you, within reach.
  void _swing(Survivor s) {
    s.swingT = kSwingTime;
    events.add(ZombieEvent.swing);
    final ahead = Offset.fromDirection(s.aimAngle);
    for (final z in zombies) {
      final to = z.pos - s.pos;
      final d = to.distance;
      if (d > s.gun.range + z.r) continue;
      if (d > 0.01) {
        final cosA = (to.dx * ahead.dx + to.dy * ahead.dy) / d;
        if (cosA < cos(1.2) && d > z.r + kPlayerR) continue;
      }
      _damage(z, s.gun.damage, (d > 0.01 ? to / d : ahead) * 2.5);
    }
    _bury();
  }

  void _hurt(Survivor s, double amount) {
    s.hp -= amount;
    s.hurtT = 0.35;
    events.add(ZombieEvent.hurt);
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
      if (z.controlled) {
        // The zombie player's King is beaten: the humans win!
        phase = ZombiePhase.over;
        winner = 'humans';
        coinsEarned += 100;
        return true;
      }
      final roll = rnd.nextDouble();
      if (z.sword) {
        pickups.add(Pickup(PickupKind.sword, z.pos));
      } else if (z.kind == ZombieKind.king || roll < 0.06) {
        pickups.add(Pickup(PickupKind.health, z.pos));
      } else if (roll < 0.1) {
        pickups.add(Pickup(PickupKind.grenade, z.pos));
      }
      return true;
    });
  }

  // ---- zombies -----------------------------------------------------------

  /// The person a zombie at [p] goes after: the nearest one still standing.
  Survivor? _target(Offset p) {
    Survivor? best;
    var bestD = double.infinity;
    for (final s in survivors) {
      if (!s.alive) continue;
      final d = (s.pos - p).distance;
      if (d < bestD) {
        bestD = d;
        best = s;
      }
    }
    return best;
  }

  void _moveZombies(double dt) {
    for (final z in [...zombies]) {
      z.hitCool = max(0, z.hitCool - dt);
      z.flash = max(0, z.flash - dt);
      if (z.controlled) {
        _driveKing(z, dt);
        continue;
      }
      z.wobble += dt * (z.kind == ZombieKind.runner ? 9 : 5);
      final target = _target(z.pos);
      if (target == null) continue;
      final to = target.pos - z.pos;
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
      z.pos = _keepOutOfSafeZones(_slide(next, z.r), z.r);
      // Bite! (Not while you're in a safe zone.)
      if (d < z.r + kPlayerR + 0.1 &&
          z.hitCool <= 0 &&
          !inSafeZone(target.pos)) {
        z.hitCool = 0.9;
        _hurt(target, _zombieDamage * (z.kind == ZombieKind.king ? 2 : 1));
      }
    }
  }

  void _pickups(double dt) {
    for (final p in pickups) {
      p.life -= dt;
      for (final s in survivors) {
        if (!s.alive || p.life <= 0) continue;
        if ((p.pos - s.pos).distance >= kPlayerR + 0.9) continue;
        p.life = 0;
        events.add(ZombieEvent.pickup);
        switch (p.kind) {
          case PickupKind.health:
            s.hp = min(kMaxHp, s.hp + 30);
          case PickupKind.grenade:
            s.grenades = min(5, s.grenades + 1);
          case PickupKind.sword:
            _gotSword(s);
        }
      }
    }
    pickups.removeWhere((p) => p.life <= 0);
  }

  /// A dropped sword: use it for the rest of this game, and there's a
  /// small chance it's yours to keep.
  void _gotSword(Survivor s) {
    final sword = gunById('sword');
    var i = s.weapons.indexWhere((g) => g.id == sword.id);
    if (i < 0) {
      s.weapons.add(sword);
      i = s.weapons.length - 1;
      events.add(ZombieEvent.newWeapon);
      if (!s.keptSword && rnd.nextDouble() < kKeepSwordChance) {
        s.keptSword = true;
        events.add(ZombieEvent.keepWeapon);
      }
    }
    s.weaponIndex = i;
  }

  /// Pushes a zombie back out of any safe zone it walked into.
  Offset _keepOutOfSafeZones(Offset p, double r) {
    for (final zone in kSafeZones) {
      final z = zone.inflate(r);
      if (!z.contains(p)) continue;
      // Only the sides facing into the map can be crossed.
      final outX = zone.left == 0 ? z.right : z.left;
      final outY = zone.top == 0 ? z.bottom : z.top;
      if ((outX - p.dx).abs() < (outY - p.dy).abs()) {
        p = Offset(outX, p.dy);
      } else {
        p = Offset(p.dx, outY);
      }
    }
    return p;
  }

  // ---- walls -------------------------------------------------------------

  static Offset _unit(Offset m) => m.distance > 1 ? m / m.distance : m;

  static Offset _clampWorld(Offset p) =>
      Offset(p.dx.clamp(1, kWorldW - 1), p.dy.clamp(1, kWorldH - 1));

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
