import 'dart:math';
import 'dart:ui' show Offset;

import '../outplay/outplay_net.dart';
import 'zombie_data.dart';
import 'zombie_sim.dart';

/// Zombie Attack rooms share the online lobby with Outplay and Boost Ball,
/// so their map name starts with this to keep the games apart.
const String kZombieRoomPrefix = 'za:';

bool isZombieRoom(String mapId) => mapId.startsWith(kZombieRoomPrefix);

/// What a 2-player room is: the mode, map, level, and (for Zombie vs
/// Human) whether the room maker plays the zombies.
class ZombieRoomSetup {
  final ZombieMode mode;
  final ZombieMap map;
  final int level;
  final bool hostIsZombie;
  const ZombieRoomSetup(
    this.mode,
    this.map,
    this.level, {
    this.hostIsZombie = false,
  });

  String get roomName =>
      '$kZombieRoomPrefix${mode.name}:${map.name}:$level:${hostIsZombie ? 'z' : 'h'}';

  static ZombieRoomSetup? parse(String mapId) {
    if (!isZombieRoom(mapId)) return null;
    final parts = mapId.substring(kZombieRoomPrefix.length).split(':');
    if (parts.length < 4) return null;
    final mode = ZombieMode.values
        .where((m) => m.name == parts[0] && m != ZombieMode.solo)
        .firstOrNull;
    if (mode == null) return null;
    return ZombieRoomSetup(
      mode,
      ZombieMap.byName(parts[1]),
      (int.tryParse(parts[2]) ?? 1).clamp(0, 2),
      hostIsZombie: parts[3] == 'z',
    );
  }

  /// True if this phone plays the zombies.
  bool zombieHere(bool isHost) =>
      mode == ZombieMode.versus && (hostIsZombie == isHost);
}

double _r(double v) => (v * 100).roundToDouble() / 100;
double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
Offset _o(Object? x, Object? y) => Offset(_d(x), _d(y));

/// A 2-player game of Zombie Attack. The room maker's phone runs the real
/// game and sends the other phone what is happening 15 times a second; the
/// other phone sends what its player is pressing.
class ZombieSession {
  final OutplayRoom room;
  final OutplayDirectory? lister;
  final String myName;
  final String myGun;
  late final ZombieRoomSetup setup;

  ZombieWorld? world;

  /// Set when the game can't go on (the other player left).
  String? ended;

  /// Things that happened (joins, leaves) for the screen to show.
  final List<String> notes = [];

  bool get isHost => room.isHost;
  bool get started => world != null;
  bool get youAreZombie => setup.zombieHere(isHost);

  double _sendT = 0;
  double _helloT = 0;
  double _listT = 0;
  final List<ZombieEvent> _outEvents = [];
  final Random _rnd;

  ZombieSession({
    required this.room,
    required this.myName,
    this.myGun = 'pistol',
    this.lister,
    Random? random,
  }) : _rnd = random ?? Random() {
    setup =
        ZombieRoomSetup.parse(room.mapId) ??
        const ZombieRoomSetup(ZombieMode.coop, ZombieMap.town, 1);
  }

  /// Reads messages, sends ours and moves the game on.
  void update(double dt) {
    // Step first so news from the other phone (and its sounds) lands after
    // this frame's events are cleared.
    world?.step(dt);
    for (final m in room.takeMessages()) {
      _receive(m);
    }
    final w = world;
    if (isHost) {
      _listT -= dt;
      if (lister != null && _listT <= 0 && !room.showCode && w == null) {
        _listT = 2;
        lister!.announce(
          RoomInfo(
            code: room.code,
            name: myName,
            avatar: const [],
            mapId: room.mapId,
            players: 1,
            playing: false,
            teamSize: 1,
          ),
        );
      }
    } else if (w == null) {
      _helloT -= dt;
      if (_helloT <= 0) {
        _helloT = 1;
        room.send({'t': 'hi', 'id': room.myId, 'n': myName, 'gun': myGun});
      }
    }
    if (w == null) return;
    _sendT -= dt;
    if (_sendT > 0) return;
    if (isHost) {
      _outEvents.addAll(w.events);
      _sendT = 1 / 15;
      room.send(_snapshot(w));
      _outEvents.clear();
    } else {
      _sendT = 1 / 20;
      final inp = w.input;
      final aim = inp.aim;
      room.send({
        't': 'in',
        'm': [_r(inp.move.dx), _r(inp.move.dy)],
        'a': aim == null ? null : [_r(aim.dx), _r(aim.dy)],
        'f': inp.fire,
        if (!w.youAreBoss) 'p': [_r(w.player.dx), _r(w.player.dy)],
        if (w.youAreBoss) 'b': [_r(w.boss!.pos.dx), _r(w.boss!.pos.dy)],
      });
    }
  }

  /// Throw a grenade, swap weapons or send a zombie in: these go straight
  /// to the room maker's phone so none get lost.
  void grenade() => _act({'g': 1}, () => world?.input.grenade = true);
  void swap() => _act({'s': 1}, () => world?.input.swap = true);
  void order(ZombieOrder o) =>
      _act({'o': o.index}, () => world?.boss?.orders.add(o));

  void _act(Map<String, dynamic> what, void Function() local) {
    if (isHost) {
      local();
    } else {
      room.send({'t': 'act', ...what});
    }
  }

  void _start(String friendName, String friendGun) {
    if (!isHost || started) return;
    room.start();
    final hostZombie = youAreZombie;
    world = _build(
      hostName: myName,
      hostGun: myGun,
      guestName: friendName,
      guestGun: friendGun,
      hostZombie: hostZombie,
    );
    room.send({
      't': 'go',
      'hn': myName,
      'hg': myGun,
      'gn': friendName,
      'gg': friendGun,
    });
    lister?.unannounce();
  }

  ZombieWorld _build({
    required String hostName,
    required String hostGun,
    required String guestName,
    required String guestGun,
    required bool hostZombie,
  }) {
    final coop = setup.mode == ZombieMode.coop;
    // In Zombie vs Human the only survivor is whoever isn't the zombie.
    final humanName = coop || !hostZombie ? hostName : guestName;
    final humanGun = coop || !hostZombie ? hostGun : guestGun;
    final otherName = coop || !hostZombie ? guestName : hostName;
    final w = ZombieWorld(
      map: setup.map,
      level: setup.level,
      mode: setup.mode,
      gun: gunById(humanGun),
      friendGun: gunById(guestGun),
      name: humanName,
      friendName: otherName,
      random: _rnd,
    )..authority = isHost;
    if (coop) {
      w.youIndex = isHost ? 0 : 1;
    } else {
      w.youIndex = youAreZombie ? -1 : 0;
    }
    return w;
  }

  void _receive(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'hi' when isHost:
        if (started) return;
        final name = (m['n'] as String? ?? 'Friend').trim();
        notes.add('$name joined');
        _start(name.isEmpty ? 'Friend' : name, m['gun'] as String? ?? 'pistol');
      case 'go' when !isHost:
        if (started) return;
        world = _build(
          hostName: m['hn'] as String? ?? 'Friend',
          hostGun: m['hg'] as String? ?? 'pistol',
          guestName: myName,
          guestGun: myGun,
          hostZombie: setup.hostIsZombie,
        );
      case 'in' when isHost:
        final w = world;
        if (w == null) return;
        final inp = _theirInput(w);
        final mv = m['m'];
        if (mv is List && mv.length == 2) inp.move = _o(mv[0], mv[1]);
        final a = m['a'];
        inp.aim = a is List && a.length == 2 ? _o(a[0], a[1]) : null;
        inp.fire = m['f'] == true;
        // Their phone moves them straight away: trust where it says they
        // are unless it's miles off.
        final p = m['p'];
        final theyAreHuman = w.mode == ZombieMode.coop || youAreZombie;
        if (p is List && p.length == 2 && theyAreHuman) {
          final s = w.survivors[w.mode == ZombieMode.coop ? 1 : 0];
          final at = _o(p[0], p[1]);
          if (s.alive && (at - s.pos).distance < 3) s.pos = at;
        }
        final b = m['b'];
        final boss = w.boss;
        if (b is List && b.length == 2 && boss != null && boss.kingId < 0) {
          boss.pos = _o(b[0], b[1]);
        }
      case 'act' when isHost:
        final w = world;
        if (w == null) return;
        if (m['g'] != null) _theirInput(w).grenade = true;
        if (m['s'] != null) _theirInput(w).swap = true;
        final o = m['o'];
        if (o != null && w.boss != null) {
          final i = _i(o);
          if (i >= 0 && i < ZombieOrder.values.length) {
            w.boss!.orders.add(ZombieOrder.values[i]);
          }
        }
      case 's' when !isHost:
        final w = world;
        if (w != null) _apply(w, m);
      case 'bye':
        final w = world;
        if (w == null || w.phase == ZombiePhase.over) return;
        if (w.mode == ZombieMode.coop) {
          notes.add('Your friend left. Keep going!');
          // Their player drops out of the game.
          final s = w.survivors[isHost ? 1 : 0];
          s.hp = 0;
          s.input
            ..move = Offset.zero
            ..fire = false;
        } else {
          ended = 'Your friend left the game.';
        }
      case 'hostLeft':
        ended = 'Your friend left the game.';
    }
  }

  /// What the other phone's player is pressing, on the room maker's phone.
  ZombieInput _theirInput(ZombieWorld w) {
    if (w.mode == ZombieMode.coop) return w.survivors[1].input;
    return youAreZombie ? w.survivors[0].input : w.boss!.input;
  }

  Map<String, dynamic> _snapshot(ZombieWorld w) {
    final b = w.boss;
    return {
      't': 's',
      'ph': w.phase.index,
      'pt': _r(w.phaseT),
      'wv': w.wave,
      'wc': w.wavesCleared,
      'k': w.kills,
      'c': w.coinsEarned,
      'win': w.winner,
      'ev': [for (final e in _outEvents) e.index],
      'sv': [
        for (final s in w.survivors)
          [
            _r(s.pos.dx),
            _r(s.pos.dy),
            _r(s.hp),
            _r(s.aimAngle),
            s.weaponIndex,
            s.grenades,
            _r(s.hurtT),
            _r(s.swingT),
            s.keptSword ? 1 : 0,
            for (final g in s.weapons) kGuns.indexOf(g),
          ],
      ],
      'bs': b == null
          ? null
          : [_r(b.pos.dx), _r(b.pos.dy), _r(b.brains), b.kingId, _r(b.smashT)],
      'z': [
        for (final z in w.zombies)
          [
            z.id,
            z.kind.index,
            _r(z.pos.dx),
            _r(z.pos.dy),
            _r(z.hp),
            _r(z.maxHp),
            _r(z.facing),
            (z.sword ? 1 : 0) + (z.controlled ? 2 : 0),
            _r(z.flash),
          ],
      ],
      'b': [
        for (final x in w.bullets)
          [
            _r(x.pos.dx),
            _r(x.pos.dy),
            _r(x.vel.dx),
            _r(x.vel.dy),
            kGuns.indexOf(x.gun),
          ],
      ],
      'p': [
        for (final p in w.pickups)
          [p.kind.index, _r(p.pos.dx), _r(p.pos.dy), _r(p.life)],
      ],
      'g': [
        for (final g in w.thrown)
          [_r(g.from.dx), _r(g.from.dy), _r(g.to.dx), _r(g.to.dy), _r(g.t)],
      ],
      'bm': [
        for (final x in w.booms)
          [_r(x.pos.dx), _r(x.pos.dy), _r(x.radius), _r(x.t)],
      ],
      'pf': [
        for (final x in w.poofs)
          [_r(x.pos.dx), _r(x.pos.dy), _r(x.size), _r(x.t)],
      ],
    };
  }

  void _apply(ZombieWorld w, Map<String, dynamic> m) {
    w
      ..phase = ZombiePhase.values[_i(m['ph']).clamp(0, 2)]
      ..phaseT = _d(m['pt'])
      ..wave = _i(m['wv'])
      ..wavesCleared = _i(m['wc'])
      ..kills = _i(m['k'])
      ..coinsEarned = _i(m['c'])
      ..winner = m['win'] as String?;
    for (final e in (m['ev'] as List?) ?? const []) {
      final i = _i(e);
      if (i >= 0 && i < ZombieEvent.values.length) {
        w.events.add(ZombieEvent.values[i]);
      }
    }
    final sv = m['sv'];
    if (sv is List) {
      for (var i = 0; i < sv.length && i < w.survivors.length; i++) {
        final v = sv[i];
        if (v is! List || v.length < 10) continue;
        final s = w.survivors[i];
        final at = _o(v[0], v[1]);
        final mine = i == w.youIndex;
        // Your own player moves on your phone straight away, so only nudge
        // it back in line unless it's way off.
        if (!mine || (at - s.pos).distance > 3 || !s.alive) {
          s.pos = at;
        } else {
          s.pos += (at - s.pos) * 0.2;
        }
        s
          ..hp = _d(v[2])
          ..grenades = _i(v[5])
          ..hurtT = _d(v[6])
          ..swingT = _d(v[7])
          ..keptSword = _i(v[8]) == 1;
        if (!mine) s.aimAngle = _d(v[3]);
        final guns = [
          for (final g in v.skip(9))
            if (_i(g) >= 0 && _i(g) < kGuns.length) kGuns[_i(g)],
        ];
        if (guns.isNotEmpty) {
          s.weapons
            ..clear()
            ..addAll(guns);
        }
        s.weaponIndex = _i(v[4]).clamp(0, s.weapons.length - 1);
      }
    }
    final bs = m['bs'];
    final boss = w.boss;
    if (bs is List && bs.length == 5 && boss != null) {
      final at = _o(bs[0], bs[1]);
      boss.kingId = _i(bs[3]);
      // Floating about is done on the zombie player's own phone.
      if (!w.youAreBoss || boss.kingId >= 0) boss.pos = at;
      boss
        ..brains = _d(bs[2])
        ..smashT = _d(bs[4]);
    }
    final zs = m['z'];
    if (zs is List) {
      final old = {for (final z in w.zombies) z.id: z};
      w.zombies.clear();
      for (final v in zs) {
        if (v is! List || v.length < 9) continue;
        final id = _i(v[0]);
        final kind = ZombieKind.values[_i(v[1]).clamp(0, 3)];
        final z = old[id] ?? Zombie(id, kind, Offset.zero, 1, id * 1.7);
        final flags = _i(v[7]);
        z
          ..pos = _o(v[2], v[3])
          ..hp = _d(v[4])
          ..maxHp = _d(v[5])
          ..facing = _d(v[6])
          ..sword = flags & 1 != 0
          ..controlled = flags & 2 != 0
          ..flash = _d(v[8]);
        w.zombies.add(z);
      }
    }
    final bl = m['b'];
    if (bl is List) {
      w.bullets
        ..clear()
        ..addAll([
          for (final v in bl)
            if (v is List && v.length == 5)
              Bullet(
                _o(v[0], v[1]),
                _o(v[2], v[3]),
                kGuns[_i(v[4]).clamp(0, kGuns.length - 1)],
              ),
        ]);
    }
    final ps = m['p'];
    if (ps is List) {
      w.pickups
        ..clear()
        ..addAll([
          for (final v in ps)
            if (v is List && v.length == 4)
              Pickup(PickupKind.values[_i(v[0]).clamp(0, 2)], _o(v[1], v[2]))
                ..life = _d(v[3]),
        ]);
    }
    final gs = m['g'];
    if (gs is List) {
      w.thrown
        ..clear()
        ..addAll([
          for (final v in gs)
            if (v is List && v.length == 5)
              Grenade(_o(v[0], v[1]), _o(v[2], v[3]))..t = _d(v[4]),
        ]);
    }
    final bm = m['bm'];
    if (bm is List) {
      w.booms
        ..clear()
        ..addAll([
          for (final v in bm)
            if (v is List && v.length == 4)
              Boom(_o(v[0], v[1]), _d(v[2]))..t = _d(v[3]),
        ]);
    }
    final pf = m['pf'];
    if (pf is List) {
      w.poofs
        ..clear()
        ..addAll([
          for (final v in pf)
            if (v is List && v.length == 4)
              Poof(_o(v[0], v[1]), _d(v[2]))..t = _d(v[3]),
        ]);
    }
  }

  void close() {
    lister?.unannounce();
    room.close();
  }
}
