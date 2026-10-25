import 'dart:math';
import 'dart:ui' show Offset;

import '../outplay/outplay_net.dart';
import 'zombie_data.dart';
import 'zombie_sim.dart';

/// Zombie Attack rooms share the online lobby with Outplay and Boost Ball,
/// so their map name starts with this to keep the games apart.
const String kZombieRoomPrefix = 'za:';

bool isZombieRoom(String mapId) => mapId.startsWith(kZombieRoomPrefix);

/// What an online room is: the mode, map, level, how many players, and
/// (for Zombie vs Human) whether the room maker plays the zombies.
class ZombieRoomSetup {
  final ZombieMode mode;
  final ZombieMap map;
  final int level;
  final bool hostIsZombie;
  final int players; // 2 to 4
  const ZombieRoomSetup(
    this.mode,
    this.map,
    this.level, {
    this.hostIsZombie = false,
    this.players = 2,
  });

  String get roomName =>
      '$kZombieRoomPrefix${mode.name}:${map.name}:$level:'
      '${hostIsZombie ? 'z' : 'h'}:$players';

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
      players: parts.length > 4 ? (int.tryParse(parts[4]) ?? 2).clamp(2, 4) : 2,
    );
  }

  /// The OutplayRoom team size that lets enough people in (it allows
  /// teamSize * 2 - 1 joiners; the session turns away anyone extra).
  int get roomTeamSize => players <= 2 ? 1 : 2;

  /// Whether this phone plays the zombies, if it can tell before the game
  /// starts (with 3 or 4 players the room maker decides who when it does).
  bool zombieHere(bool isHost) =>
      mode == ZombieMode.versus &&
      (isHost ? hostIsZombie : players == 2 && !hostIsZombie);
}

double _r(double v) => (v * 100).roundToDouble() / 100;
double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
Offset _o(Object? x, Object? y) => Offset(_d(x), _d(y));

/// Someone in an online game.
class ZombiePlayer {
  final String id;
  final String name;
  final String gun;
  bool zombie = false; // plays the zombies in Zombie vs Human
  ZombiePlayer(this.id, this.name, this.gun);
}

/// An online game of Zombie Attack for 2 to 4 players. The room maker's
/// phone runs the real game and sends everyone what is happening 15 times
/// a second; the others send what their player is pressing.
class ZombieSession {
  final OutplayRoom room;
  final OutplayDirectory? lister;
  final String myName;
  final String myGun;
  late final ZombieRoomSetup setup;

  ZombieWorld? world;

  /// Everyone in the game, room maker first. Until it starts, the room
  /// maker's list of who has joined.
  final List<ZombiePlayer> players = [];

  /// Set when the game can't go on (the room maker left).
  String? ended;

  /// Things that happened (joins, leaves) for the screen to show.
  final List<String> notes = [];

  bool get isHost => room.isHost;
  bool get started => world != null;
  int get needed => setup.players;

  /// True if this phone plays the zombies.
  bool get youAreZombie {
    if (setup.mode != ZombieMode.versus) return false;
    if (started) return world!.youAreBoss;
    return setup.zombieHere(isHost);
  }

  /// Names of everyone waiting for the game to start.
  List<String> get waiting =>
      isHost ? [for (final p in players) p.name] : _waiting;
  List<String> _waiting = const [];

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
    if (isHost) players.add(ZombiePlayer(room.myId, myName, myGun));
  }

  /// Reads messages, sends ours and moves the game on.
  void update(double dt) {
    // Step first so news from the other phones (and its sounds) lands
    // after this frame's events are cleared.
    world?.step(dt);
    for (final m in room.takeMessages()) {
      _receive(m);
    }
    final w = world;
    if (isHost && w == null) {
      _listT -= dt;
      if (lister != null && _listT <= 0 && !room.showCode) {
        _listT = 2;
        lister!.announce(
          RoomInfo(
            code: room.code,
            name: myName,
            avatar: const [],
            mapId: room.mapId,
            players: players.length,
            playing: false,
            teamSize: setup.roomTeamSize,
          ),
        );
      }
      _helloT -= dt;
      if (_helloT <= 0) {
        _helloT = 1;
        room.send({
          't': 'lobby',
          'n': [for (final p in players) p.name],
        });
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
        'id': room.myId,
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
  void jump() {
    // Your own jump shows straight away on your phone.
    world?.input.jump = true;
    if (!isHost) room.send({'t': 'act', 'id': room.myId, 'j': 1});
  }

  void order(ZombieOrder o) =>
      _act({'o': o.index}, () => world?.boss?.orders.add(o));

  void _act(Map<String, dynamic> what, void Function() local) {
    if (isHost) {
      local();
    } else {
      room.send({'t': 'act', 'id': room.myId, ...what});
    }
  }

  /// Everyone is here: the room maker starts the game.
  void startNow() {
    if (!isHost || started || players.length < 2) return;
    if (setup.mode == ZombieMode.versus) {
      // The room maker picked a side; if they're a human, whoever joined
      // first plays the zombies.
      final z = setup.hostIsZombie ? players.first : players[1];
      z.zombie = true;
    }
    room.start();
    lister?.unannounce();
    final roster = [
      for (final p in players)
        {'id': p.id, 'n': p.name, 'gun': p.gun, 'z': p.zombie},
    ];
    world = _build();
    room.send({'t': 'go', 'players': roster});
  }

  ZombieWorld _build() {
    final humans = players.where((p) => !p.zombie).toList();
    final zombie = players.where((p) => p.zombie).firstOrNull;
    final w = ZombieWorld(
      map: setup.map,
      level: setup.level,
      mode: setup.mode,
      people: [for (final p in humans) (p.name, gunById(p.gun))],
      bossName: zombie?.name,
      random: _rnd,
    )..authority = isHost;
    w.youIndex = zombie?.id == room.myId
        ? -1
        : humans.indexWhere((p) => p.id == room.myId).clamp(0, 3);
    return w;
  }

  /// Which survivor a player id drives (or null for the zombie player).
  Survivor? _survivorOf(ZombieWorld w, String id) {
    final humans = players.where((p) => !p.zombie).toList();
    final i = humans.indexWhere((p) => p.id == id);
    return i < 0 || i >= w.survivors.length ? null : w.survivors[i];
  }

  ZombieInput? _inputOf(ZombieWorld w, String id) {
    final p = players.where((p) => p.id == id).firstOrNull;
    if (p == null) return null;
    if (p.zombie) return w.boss?.input;
    return _survivorOf(w, id)?.input;
  }

  void _receive(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'hi' when isHost:
        final id = m['id'] as String? ?? '';
        if (id.isEmpty || players.any((p) => p.id == id)) return;
        if (started || players.length >= needed) {
          room.send({'t': 'full', 'to': id});
          return;
        }
        final name = (m['n'] as String? ?? '').trim();
        players.add(
          ZombiePlayer(
            id,
            name.isEmpty ? 'Player ${players.length + 1}' : name,
            m['gun'] as String? ?? 'pistol',
          ),
        );
        notes.add('${players.last.name} joined');
        if (players.length >= needed) startNow();
      case 'lobby' when !isHost:
        _waiting = [for (final n in (m['n'] as List?) ?? const []) '$n'];
      case 'full' when !isHost && !started:
        if (m['to'] == room.myId) ended = 'That game is already full.';
      case 'go' when !isHost:
        if (started) return;
        final list = m['players'];
        if (list is! List) return;
        final mine = list.whereType<Map>().any((p) => p['id'] == room.myId);
        if (!mine) {
          ended = 'That game started without you.';
          return;
        }
        players
          ..clear()
          ..addAll([
            for (final p in list.whereType<Map>())
              ZombiePlayer(
                p['id'] as String? ?? '',
                p['n'] as String? ?? 'Player',
                p['gun'] as String? ?? 'pistol',
              )..zombie = p['z'] == true,
          ]);
        world = _build();
      case 'in' when isHost:
        final w = world;
        if (w == null) return;
        final id = m['id'] as String? ?? '';
        final inp = _inputOf(w, id);
        if (inp == null) return;
        final mv = m['m'];
        if (mv is List && mv.length == 2) inp.move = _o(mv[0], mv[1]);
        final a = m['a'];
        inp.aim = a is List && a.length == 2 ? _o(a[0], a[1]) : null;
        inp.fire = m['f'] == true;
        // Their phone moves them straight away: trust where it says they
        // are unless it's miles off.
        final p = m['p'];
        final s = _survivorOf(w, id);
        if (p is List && p.length == 2 && s != null && s.alive) {
          final at = _o(p[0], p[1]);
          if ((at - s.pos).distance < 3) s.pos = at;
        }
        final b = m['b'];
        final boss = w.boss;
        final isZombie = players.any((x) => x.id == id && x.zombie);
        if (b is List && b.length == 2 && boss != null && isZombie) {
          if (boss.kingId < 0) boss.pos = _o(b[0], b[1]);
        }
      case 'act' when isHost:
        final w = world;
        if (w == null) return;
        final id = m['id'] as String? ?? '';
        final inp = _inputOf(w, id);
        if (inp == null) return;
        if (m['g'] != null) inp.grenade = true;
        if (m['s'] != null) inp.swap = true;
        if (m['j'] != null) inp.jump = true;
        final o = m['o'];
        final isZombie = players.any((x) => x.id == id && x.zombie);
        if (o != null && w.boss != null && isZombie) {
          final i = _i(o);
          if (i >= 0 && i < ZombieOrder.values.length) {
            w.boss!.orders.add(ZombieOrder.values[i]);
          }
        }
      case 's' when !isHost:
        final w = world;
        if (w != null) _apply(w, m);
      case 'bye':
        final id = m['id'] as String? ?? '';
        final who = players.where((p) => p.id == id).firstOrNull;
        final w = world;
        if (w == null) {
          // Left the waiting room.
          if (isHost) players.removeWhere((p) => p.id == id);
          return;
        }
        if (who == null || w.phase == ZombiePhase.over) return;
        notes.add('${who.name} left');
        if (who.zombie) {
          ended = '${who.name} (the zombies) left the game.';
          return;
        }
        // Their player drops out of the game for good.
        final s = _survivorOf(w, id);
        if (s != null) {
          s
            ..hp = 0
            ..gone = true;
          s.input
            ..move = Offset.zero
            ..fire = false;
        }
      case 'hostLeft':
        ended = 'The room maker left the game.';
    }
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
            _r(s.jumpZ),
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
        if (v is! List || v.length < 11) continue;
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
        if (!mine) {
          s.aimAngle = _d(v[3]);
          s.jumpZ = _d(v[9]);
        }
        final guns = [
          for (final g in v.skip(10))
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
