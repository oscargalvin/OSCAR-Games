import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/sound_service.dart';
import 'outplay_art.dart';
import 'outplay_avatar.dart';
import 'outplay_data.dart';
import 'outplay_maps.dart';
import 'outplay_net.dart';

enum OutplayMode { lobby, duel, freeForAll, online, teams }

const double _personRadius = 0.25;
const double _walkSpeed = 3.0;
const double _fov = 1.15; // about 66 degrees
const double _jumpSpeed = 3.6;
const double _gravity = 12;

// Lazy Lake: swimming heals for this long, then you drown after _drownTime.
const double _healTime = 3;
const double _drownTime = 5;
const int _duelRoundsToWin = 5;
const int _ffaKillsToWin = 10;
const double _ffaTimeLimit = 180;

const List<String> _botNames = [
  'Blaze', 'Nova', 'Pixel', 'Turbo', 'Ziggy', 'Rex', 'Luna', 'Bolt', //
  'Echo', 'Mango', 'Ninja', 'Comet', 'Frost', 'Jinx', 'Rocket', 'Sparky',
  'Taco', 'Waffles', 'Nugget', 'Pebble',
];

const List<Color> _shirts = [
  Color(0xFFEF5350), Color(0xFFAB47BC), Color(0xFF42A5F5), Color(0xFF26A69A), //
  Color(0xFFFFCA28), Color(0xFFFF7043), Color(0xFF8D6E63), Color(0xFF66BB6A),
  Color(0xFFEC407A), Color(0xFF5C6BC0),
];

class _Person {
  final String name;
  final bool isYou;
  Avatar look;
  final List<Gun?> guns;
  final Melee melee;
  final Map<String, int> levels;
  Offset pos;
  double angle;
  double z = 0;
  double vz = 0;
  double hp = 100;
  bool alive = true;
  double respawnT = 0;
  int slot = 0;
  final List<int> ammo;
  int reloadingSlot = -1;
  double reloadT = 0;
  double cooldown = 0;
  double swingT = 0;
  double hurtT = 0;
  double slowT = 0;
  double flashT = 0;
  double walkCycle = 0;
  double shieldT = 0; // can't be hurt just after coming back
  double ghostT = 0; // a ghost just got them
  double waterT = 0; // how long they've been in the lake
  double kartT = 0; // a go-kart just launched them
  Offset fling = Offset.zero; // sliding after a kart hit or a hook
  int kills = 0;
  int deaths = 0;
  int team = -1; // 0 or 1 in a team game, -1 when it's everyone for themselves

  /// Skins on their weapons (weapon id -> skin id).
  final Map<String, String> skins = {};
  Skin? skinOf(String id) => skinById(skins[id]);
  String get heldId => gun?.id ?? held.id;

  // Online: someone playing on another phone.
  bool remote = false;
  String netId = '';
  Offset netPos = Offset.zero;
  double netQuiet = 0; // seconds since we last heard from them

  // Bot brain.
  List<Point<int>> path = [];
  double pathT = 0;
  double strafe = 1;
  double strafeT = 0;
  double wobble = 0;
  double aimError = 0.2;
  double turnRate = 4;
  double reactDelay = 0.9; // how long a bot looks before it shoots
  double reactT = 0;

  _Person({
    required this.name,
    required this.isYou,
    required this.look,
    required this.guns,
    required this.melee,
    required this.levels,
    required this.pos,
    required this.angle,
  }) : ammo = [guns[0]?.mag ?? 0, guns[1]?.mag ?? 0];

  Color get shirt => look.shirtColour;
  Gun? get gun => slot < 2 ? guns[slot] : null;

  /// A second melee in slot 3, if they unlocked it.
  Melee? melee2;

  /// The melee in their hand (slot 2 is the first melee, slot 3 the second).
  Melee get held => slot == 3 && melee2 != null ? melee2! : melee;
  double pullCooldown = 0; // Sizzler throw

  /// Where an online player's thrown snake is (and whether it bit someone).
  (Offset, bool)? netHook;
  bool get reloading => reloadingSlot == slot && reloadingSlot >= 0;
  int lvl(String id) => levels[id] ?? 1;
  double get speedMul => (gun?.moveMul ?? held.moveMul) * (slowT > 0 ? 0.5 : 1);
  bool get grounded => z <= 0;

  void respawn(Offset at, double facing) {
    pos = at;
    angle = facing;
    hp = 100;
    alive = true;
    z = 0;
    vz = 0;
    ammo[0] = guns[0]?.mag ?? 0;
    ammo[1] = guns[1]?.mag ?? 0;
    reloadingSlot = -1;
    cooldown = 0;
    slowT = 0;
    hurtT = 0;
    slot = 0;
    path = [];
    shieldT = 1.5;
    waterT = 0;
    kartT = 0;
    fling = Offset.zero;
  }
}

class _Ball {
  Offset pos;
  final Offset vel;
  final _Person owner;
  final Gun gun;
  double travelled = 0;
  _Ball(this.pos, this.vel, this.owner, this.gun);
}

class _Car {
  double x;
  final double y;
  final double speed; // negative drives left
  final Color color;
  _Car(this.x, this.y, this.speed, this.color);
  Offset get pos => Offset(x, y);
}

/// A thrown Sizzler: flies out, and if it bites someone it drags them back.
class _Hook {
  final _Person owner;
  Offset pos;
  final Offset dir;
  double travelled = 0;
  _Person? target;
  double pullT = 0;
  double tickT = 0;
  _Hook(this.owner, this.pos, this.dir);
}

class _Kart {
  final Offset pos;
  final double heading;
  final Color color;
  const _Kart(this.pos, this.heading, this.color);
}

class _Tracer {
  final Offset end;
  final Color color;
  final WeaponLook look;
  double t = 0;
  _Tracer(this.end, this.color, this.look);
}

class _Popup {
  final Offset pos;
  final String text;
  final Color color;
  double t = 0;
  _Popup(this.pos, this.text, this.color);
}

class _Pop {
  final Offset pos;
  final double radius;
  final Color color;
  double t = 0;
  _Pop(this.pos, this.radius, this.color);
}

class _Hit {
  final double dist;
  final String cell;
  final int side;
  final double wallX;
  const _Hit(this.dist, this.cell, this.side, this.wallX);
}

enum _Phase { waiting, countdown, fight, roundOver, matchOver }

/// First-person Outplay: the Duel Zone lobby, 1v1 duels and free-for-alls.
class OutplayGameScreen extends StatefulWidget {
  final OutplayMode mode;
  final String mapId;
  final int bots;

  /// How good the bots are: 0 easy, 1 medium, 2 hard.
  final int difficulty;

  /// Players per team in a team game against AI (2 = 2v2...).
  final int teamSize;

  /// The online room, when playing real people.
  final OutplayRoom? room;

  /// Makes online links; tests swap in a pretend one.
  final OutplayLink? Function() makeLink;
  final OutplayDirectory? Function() makeDirectory;

  const OutplayGameScreen({
    super.key,
    this.mode = OutplayMode.lobby,
    this.mapId = 'warehouse',
    this.bots = 1,
    this.difficulty = 1,
    this.teamSize = 2,
    this.room,
    this.makeLink = createLink,
    this.makeDirectory = createDirectory,
  });

  @override
  State<OutplayGameScreen> createState() => _OutplayGameScreenState();
}

class _OutplayGameScreenState extends State<OutplayGameScreen>
    with SingleTickerProviderStateMixin {
  final _rnd = Random();
  final _save = OutplaySave.instance;
  final _focus = FocusNode();
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  late final OutplayMap _map;
  late final _Person _you;
  final List<_Person> _people = [];
  final List<_Ball> _balls = [];
  final List<_Hook> _hooks = [];
  final List<_Car> _cars = [];
  final List<_Tracer> _tracers = [];
  final List<_Popup> _popups = [];
  final List<_Pop> _pops = [];
  final List<String> _feed = [];
  double _feedT = 0;

  _Phase _phase = _Phase.countdown;
  double _phaseT = 0;
  double _clock = 0; // time since the round started (lava, timer)
  int _round = 1;
  int _yourRounds = 0;
  int _botRounds = 0;
  bool _lastRoundYours = false;
  int _coinsEarned = 0;
  bool _youWon = false;
  double _carT = 2;
  double _shootSoundT = 0;
  double _hitMarkT = 0;
  double _recoil = 0;

  // Controls.
  int? _movePointer;
  Offset _moveOrigin = Offset.zero;
  Offset _moveNow = Offset.zero;
  int? _lookPointer;
  double _lookLastX = 0;
  bool _firing = false;
  int? _firePointer;
  double _fireLastX = 0;
  final Set<LogicalKeyboardKey> _keys = {};

  // Duel Zone.
  String? _padHere;
  String? _panel;
  String _pickMap = 'random';
  int _pickBots = 5;

  double _topPad = 0;

  bool get _lobby => widget.mode == OutplayMode.lobby;
  bool get _online => widget.mode == OutplayMode.online;
  // Online games use the free-for-all rules.
  bool get _ffa =>
      widget.mode == OutplayMode.freeForAll ||
      _online ||
      widget.mode == OutplayMode.teams;
  OutplayRoom get _room => widget.room!;
  bool get _onlineTeams => _online && _room.isTeams;
  int get _teamSize => _onlineTeams
      ? _room.teamSize
      : (widget.mode == OutplayMode.teams ? widget.teamSize : 0);
  bool get _teamGame => _teamSize > 0;
  int get _killsToWin => _teamGame ? 5 * _teamSize : _ffaKillsToWin;
  String get _teamLabel => '${_teamSize}v$_teamSize';

  bool _allies(_Person a, _Person b) =>
      !identical(a, b) && a.team >= 0 && a.team == b.team;

  int _teamScore(int team) =>
      _people.where((p) => p.team == team).fold(0, (sum, p) => sum + p.kills);
  double _sendT = 0;
  bool _hostLeft = false;
  bool _closedEarly = false;

  // The Find Players panel.
  final _codeBox = TextEditingController();
  OutplayDirectory? _browser;
  bool _browsing = false;
  List<RoomInfo>? _waitingRooms;
  OutplayDirectory? _lister; // puts your room on the Join list
  double _listT = 0;
  bool _netBusy = false;
  int _qpStep = 0; // Quick Play: 0 size, 1 AI or human, 3 how hard, 2 map
  int _qpSize = 1;
  int _roomSize = 1;
  bool _qpHuman = false;
  int _qpLevel = 1; // AI: 0 easy, 1 medium, 2 hard
  String? _netError;

  @override
  void initState() {
    super.initState();
    _map = _lobby ? kDuelZone : mapById(widget.mapId);
    final spawns = _map.spawnPoints();
    _you = _Person(
      name: 'You',
      isYou: true,
      look: _save.avatar,
      guns: [
        gunById(_save.primary),
        _save.secondSlot && _save.secondary != null
            ? gunById(_save.secondary!)
            : null,
      ],
      melee: meleeById(_save.melee),
      levels: Map.of(_save.levels),
      pos: spawns.first,
      angle: -pi / 2,
    );
    if (_save.meleeSlot2 && _save.melee2 != null) {
      _you.melee2 = meleeById(_save.melee2!);
    }
    _you.skins.addAll(_save.equippedSkins);
    _people.add(_you);
    if (_online) _you.team = _room.isTeams ? _room.myTeam : -1;
    if (widget.mode == OutplayMode.teams) _you.team = 0;
    if (!_lobby && !_online) {
      final tier = _save.wins.clamp(0, 12);
      final names = [..._botNames]..shuffle(_rnd);
      final botCount = widget.mode == OutplayMode.teams
          ? widget.teamSize * 2 - 1
          : widget.bots;
      for (var i = 0; i < botCount; i++) {
        final diff = widget.difficulty;
        final gun =
            kGuns[_rnd.nextInt(
              min(kGuns.length, diff == 0 ? 3 : 3 + tier + (diff == 2 ? 4 : 0)),
            )];
        final level = switch (diff) {
          0 => 1,
          2 => min(kMaxLevel, 2 + tier ~/ 3),
          _ => 1 + (tier ~/ 3).clamp(0, kMaxLevel - 1),
        };
        final bot = _Person(
          name:
              names[i % names.length] +
              (i >= names.length ? '${i ~/ names.length + 1}' : ''),
          isYou: false,
          look: Avatar.random(_rnd),
          guns: [gun, null],
          melee: kMelees[_rnd.nextInt(kMelees.length)],
          levels: {gun.id: level},
          pos: spawns[(i + 1) % spawns.length],
          angle: 0,
        );
        // Some bots show off a skin too.
        for (final id in [gun.id, bot.melee.id]) {
          if (_rnd.nextDouble() < 0.35) {
            final fits = kSkins.where((k) => k.fits(id)).toList();
            bot.skins[id] = fits[_rnd.nextInt(fits.length)].id;
          }
        }
        // In a team game the first bots are on your team.
        if (widget.mode == OutplayMode.teams) {
          bot.team = i < widget.teamSize - 1 ? 0 : 1;
        }
        switch (diff) {
          case 0: // Easy: slow to turn, wobbly aim, slow to shoot.
            bot.aimError = 0.6;
            bot.turnRate = 1.6;
            bot.reactDelay = 1.5;
          case 2: // Hard: snaps on to you and shoots fast.
            bot.aimError = 0.1;
            bot.turnRate = 5;
            bot.reactDelay = 0.35;
          default:
            bot.aimError = (0.4 - tier * 0.012).clamp(0.25, 0.4);
            bot.turnRate = 2.4 + tier * 0.15;
        }
        _people.add(bot);
      }
    }
    _startRound();
    if (_online) {
      _you.netId = _room.myId;
      if (_room.isHost) _lister = widget.makeDirectory();
      if (!_room.started) {
        _phase = _Phase.waiting;
      } else if (_room.joinClock > 2.4) {
        // Joining a game that's already going.
        _clock = _room.joinClock - 2.4;
        _phase = _Phase.fight;
      }
    }
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    _codeBox.dispose();
    _browser?.stopBrowse();
    _lister?.unannounce();
    widget.room?.close();
    super.dispose();
  }

  void _startRound() {
    final spawns = [..._map.spawnPoints()];
    if (_lobby) {
      _you.respawn(spawns.first, -pi / 2);
      _phase = _Phase.fight;
      return;
    }
    // Duels start at opposite ends; free-for-all spreads everyone out.
    spawns.shuffle(_rnd);
    if (_online) {
      // Everyone else places themselves on their own phone. In a 1v1 the
      // room maker takes one end and the other player the other end, so
      // you start face to face.
      if (_onlineTeams) {
        _placeOnTeam(_you, _rnd.nextInt(_teamSize));
      } else {
        _you.respawn(spawns.first, _faceCentre(spawns.first));
      }
      for (final p in _people) {
        p.kills = 0;
        p.deaths = 0;
      }
    } else if (_teamGame) {
      final slot = [0, 0];
      for (final p in _people) {
        _placeOnTeam(p, slot[p.team]++);
      }
    } else if (!_ffa) {
      // Start at opposite ends, looking straight at each other.
      var (a, b) = _duelSpawns();
      if (_rnd.nextBool()) (a, b) = (b, a);
      _you.respawn(a, (b - a).direction);
      _people[1].respawn(b, (a - b).direction);
    } else {
      for (var i = 0; i < _people.length; i++) {
        var at = spawns[i % spawns.length];
        // More players than start spots: squeeze in nearby.
        for (var tries = 0; i >= spawns.length && tries < 20; tries++) {
          final n =
              at +
              Offset(
                _rnd.nextDouble() * 1.6 - 0.8,
                _rnd.nextDouble() * 1.6 - 0.8,
              );
          if (!_blocked(n.dx, n.dy)) {
            at = n;
            break;
          }
        }
        _people[i].respawn(at, _faceCentre(at));
      }
    }
    _balls.clear();
    _hooks.clear();
    _cars.clear();
    _clock = 0;
    _phase = _Phase.countdown;
    _phaseT = 0;
  }

  double _faceCentre(Offset p) => (_map.centre - p).direction;

  /// Puts someone at their team's end of the map, facing the other team.
  /// Team 0 always gets the same end on every phone.
  void _placeOnTeam(_Person p, int slot) {
    final (a, b) = _duelSpawns();
    final home = p.team == 1 ? b : a, away = p.team == 1 ? a : b;
    final facing = (away - home).direction;
    // Teammates stand side by side.
    const offsets = [0.0, 0.9, -0.9, 1.8, -1.8];
    var at = home;
    for (var k = 0; k < offsets.length; k++) {
      final o = offsets[(slot + k) % offsets.length];
      final spot = home + Offset.fromDirection(facing + pi / 2, o);
      if (!_blocked(spot.dx, spot.dy)) {
        at = spot;
        break;
      }
    }
    p.respawn(at, facing);
  }

  /// Two start spots that can see each other, a good fighting distance
  /// apart. Every phone works out the same pair, so online 1v1 players
  /// land in their own spots, face to face.
  (Offset, Offset) _duelSpawns() {
    final corners = _map.cornerSpots;
    if (corners != null && corners.length == 2) return (corners[0], corners[1]);
    final all = _map.spawnPoints();
    var best = (all.first, all.last);
    var bestScore = double.infinity;
    for (var i = 0; i < all.length; i++) {
      for (var j = i + 1; j < all.length; j++) {
        final d = (all[i] - all[j]).distance;
        // A wide clear view, so nothing stands between you.
        final side = Offset.fromDirection(
          (all[j] - all[i]).direction + pi / 2,
          0.4,
        );
        final clear = [
          Offset.zero,
          side,
          -side,
        ].every((o) => _canSee(all[i] + o, all[j] + o));
        final score = (d - 12).abs() + (clear ? 0 : 100);
        if (score < bestScore - 1e-6) {
          bestScore = score;
          best = (all[i], all[j]);
        }
      }
    }
    return best;
  }

  // ---- game loop ----------------------------------------------------------

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 0.016
        : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    _phaseT += dt;
    _shootSoundT -= dt;
    _hitMarkT = max(0, _hitMarkT - dt);
    _recoil = max(0, _recoil - dt * 6);
    _feedT -= dt;
    if (_feedT <= 0 && _feed.isNotEmpty) {
      _feed.removeAt(0);
      _feedT = 2.5;
    }

    if (_online) _netTick(dt);

    switch (_phase) {
      case _Phase.waiting:
        if (_onlineTeams && _room.isHost && _people.length >= _teamSize * 2) {
          _hostStart();
          break;
        }
        _look(dt);
        _updatePerson(_you, dt, _yourMove(), false);
        _separate();
        break;
      case _Phase.countdown:
        _look(dt);
        if (_phaseT >= 2.4) {
          _phase = _Phase.fight;
          _phaseT = 0;
        }
        break;
      case _Phase.fight:
        _clock += dt;
        _look(dt);
        _updatePerson(_you, dt, _yourMove(), _firing || _keyFire);
        for (final p in _people) {
          if (!p.isYou && !p.remote) _updateBot(p, dt);
        }
        _separate();
        _updateBalls(dt);
        _updateHooks(dt);
        _updateHazards(dt);
        _updateGhosts();
        _updateRespawns(dt);
        if (_lobby) _checkPads();
        if (_ffa && _clock >= _ffaTimeLimit) _finishMatch();
        break;
      case _Phase.roundOver:
        _updateBalls(dt);
        if (_phaseT >= 2) {
          if (_yourRounds >= _duelRoundsToWin ||
              _botRounds >= _duelRoundsToWin) {
            _finishMatch();
          } else {
            _round++;
            _startRound();
          }
        }
        break;
      case _Phase.matchOver:
        break;
    }

    for (final p in _people) {
      p.swingT = max(0, p.swingT - dt);
      p.hurtT = max(0, p.hurtT - dt);
      p.slowT = max(0, p.slowT - dt);
      p.flashT = max(0, p.flashT - dt);
      p.shieldT = max(0, p.shieldT - dt);
      p.ghostT = max(0, p.ghostT - dt);
      p.kartT = max(0, p.kartT - dt);
      p.pullCooldown = max(0, p.pullCooldown - dt);
      // Sliding after a go-kart or a Sizzler hook.
      if (p.fling != Offset.zero) {
        if (p.alive && !p.remote) _moveBy(p, p.fling * dt);
        p.fling *= exp(-3.0 * dt);
        if (p.fling.distance < 0.05) p.fling = Offset.zero;
      }
      // Jumping and falling.
      if (p.z > 0 || p.vz > 0) {
        p.vz -= _gravity * dt;
        p.z += p.vz * dt;
        if (p.z <= 0) {
          p.z = 0;
          p.vz = 0;
        }
      }
    }
    for (final t in _tracers) {
      t.t += dt;
    }
    _tracers.removeWhere((t) => t.t > 0.09);
    for (final p in _popups) {
      p.t += dt;
    }
    _popups.removeWhere((p) => p.t > 0.7);
    for (final p in _pops) {
      p.t += dt;
    }
    _pops.removeWhere((p) => p.t > 0.35);
    setState(() {});
  }

  bool get _keyFire =>
      _keys.contains(LogicalKeyboardKey.keyF) ||
      _keys.contains(LogicalKeyboardKey.enter);

  void _look(double dt) {
    var turn = 0.0;
    if (_keys.contains(LogicalKeyboardKey.arrowLeft) ||
        _keys.contains(LogicalKeyboardKey.keyQ)) {
      turn -= 1;
    }
    if (_keys.contains(LogicalKeyboardKey.arrowRight) ||
        _keys.contains(LogicalKeyboardKey.keyE)) {
      turn += 1;
    }
    _you.angle += turn * 2.6 * dt;
  }

  /// Your walking direction, relative to the world.
  Offset _yourMove() {
    var fwd = 0.0, side = 0.0;
    if (_movePointer != null) {
      final d = _moveNow - _moveOrigin;
      if (d.distance > 8) {
        final v = d / max(d.distance, 50.0);
        fwd = -v.dy;
        side = v.dx;
      }
    }
    if (_keys.contains(LogicalKeyboardKey.keyW) ||
        _keys.contains(LogicalKeyboardKey.arrowUp)) {
      fwd += 1;
    }
    if (_keys.contains(LogicalKeyboardKey.keyS) ||
        _keys.contains(LogicalKeyboardKey.arrowDown)) {
      fwd -= 1;
    }
    if (_keys.contains(LogicalKeyboardKey.keyA)) side -= 1;
    if (_keys.contains(LogicalKeyboardKey.keyD)) side += 1;
    final len = sqrt(fwd * fwd + side * side);
    if (len > 1) {
      fwd /= len;
      side /= len;
    }
    final a = _you.angle;
    return Offset(cos(a), sin(a)) * fwd + Offset(-sin(a), cos(a)) * side;
  }

  void _updatePerson(_Person p, double dt, Offset move, bool fire) {
    if (!p.alive) return;
    if (move != Offset.zero) {
      final swim = p.grounded && _map.isWater(p.pos) ? 0.7 : 1.0;
      _moveBy(p, move * (_walkSpeed * p.speedMul * swim * dt));
      p.walkCycle += dt * 9 * move.distance;
    }
    p.cooldown -= dt;
    if (p.reloadingSlot >= 0) {
      p.reloadT -= dt;
      if (p.reloadT <= 0) {
        p.ammo[p.reloadingSlot] = p.guns[p.reloadingSlot]!.mag;
        p.reloadingSlot = -1;
      }
    }
    if (_lobby || _phase == _Phase.waiting) return;
    final gun = p.gun;
    if (gun != null) {
      if (fire && p.cooldown <= 0 && !p.reloading) {
        if (p.ammo[p.slot] <= 0) {
          _startReload(p);
        } else {
          _shoot(p, gun);
          p.cooldown = gun.fireInterval * levelSpeedMul(p.lvl(gun.id));
        }
      }
      if (p.ammo[p.slot] <= 0 && !p.reloading) _startReload(p);
    } else if (fire && p.cooldown <= 0) {
      _swing(p);
    }
  }

  void _jump(_Person p) {
    if (!p.alive || !p.grounded) return;
    // The squishy croc footbed throws you higher.
    p.vz = _jumpSpeed * (_map.hazard == MapHazard.bouncy ? 1.45 : 1);
  }

  void _startReload(_Person p) {
    final g = p.gun;
    if (g == null || p.ammo[p.slot] >= g.mag || p.reloading) return;
    p.reloadingSlot = p.slot;
    p.reloadT = g.reload;
  }

  void _switchSlot(_Person p, int slot) {
    if (slot < 2 && p.guns[slot] == null) return;
    if (slot == 3 && p.melee2 == null) return;
    if (p.slot == slot) return;
    p.slot = slot;
    if (p.reloadingSlot != slot) p.reloadingSlot = -1;
    p.cooldown = max(p.cooldown, 0.15);
  }

  void _shoot(_Person p, Gun g) {
    p.ammo[p.slot]--;
    p.flashT = 0.06;
    if (p.isYou) {
      _recoil = 1;
      if (_shootSoundT <= 0) {
        SoundService.instance.play(GameSound.shoot);
        _shootSoundT = 0.14;
      }
    }
    final dmg = g.damage * levelDamageMul(p.lvl(g.id));
    for (var i = 0; i < g.pellets; i++) {
      final a = p.angle + (_rnd.nextDouble() * 2 - 1) * g.spread;
      final dir = Offset(cos(a), sin(a));
      if (g.kind == ShotKind.ball) {
        final start = p.pos + dir * 0.35, vel = dir * g.ballSpeed;
        _balls.add(_Ball(start, vel, p, g));
        if (_online && p.isYou) {
          _room.send({
            't': 'ball',
            'id': _you.netId,
            'x': start.dx,
            'y': start.dy,
            'vx': vel.dx,
            'vy': vel.dy,
            'g': g.id,
          });
        }
        continue;
      }
      final wall = _cast(p.pos, a).dist;
      final reach = min(wall, g.range);
      _Person? best;
      var bestF = reach;
      for (final o in _people) {
        if (identical(o, p) || !o.alive || _lobby || _allies(o, p)) continue;
        final d = o.pos - p.pos;
        final f = d.dx * dir.dx + d.dy * dir.dy;
        if (f <= 0 || f >= bestF) continue;
        final lateral = (d.dx * dir.dy - d.dy * dir.dx).abs();
        // You get a little aim help; it's harder on a phone.
        final tolerance = _personRadius + (p.isYou ? 0.18 + 0.02 * f : 0.05);
        if (lateral < tolerance) {
          best = o;
          bestF = f;
        }
      }
      final end = p.pos + dir * bestF;
      if (p.isYou) _tracers.add(_Tracer(end, g.shotColor, g.look));
      if (best != null) _damage(best, dmg, p, slow: g.slow);
    }
  }

  void _swing(_Person p) {
    final m = p.held;
    p.cooldown = m.cooldown * levelSpeedMul(p.lvl(m.id));
    p.swingT = min(0.22, m.cooldown * 0.9);
    if (p.isYou) SoundService.instance.play(GameSound.tap);
    for (final o in _people) {
      if (identical(o, p) || !o.alive || _allies(o, p)) continue;
      final d = o.pos - p.pos;
      if (d.distance > m.reach + _personRadius) continue;
      final diff = _angleDiff(p.angle, d.direction).abs();
      if (diff > m.arc / 2 + 0.3) continue;
      _damage(
        o,
        m.damage * levelDamageMul(p.lvl(m.id)),
        p,
        // The Sizzler hooks them right up to you.
        knock: m.hook
            ? Offset.fromDirection(d.direction + pi, max(0, d.distance - 0.7))
            : Offset.fromDirection(d.direction, m.knockback),
      );
    }
  }

  static const double _snakeRange = 8;
  static const double _snakeSpeed = 18;
  static const double _pullTime = 0.8;

  /// Throws the Sizzler snake: whoever it bites gets pulled in and
  /// takes damage on the way.
  void _throwSnake(_Person p) {
    if (_lobby || _phase != _Phase.fight || !p.alive) return;
    if (p.gun != null || !p.held.hook || p.pullCooldown > 0) return;
    if (_hooks.any((h) => identical(h.owner, p))) return;
    p.pullCooldown = 4;
    p.swingT = 0.22;
    final dir = Offset(cos(p.angle), sin(p.angle));
    _hooks.add(_Hook(p, p.pos + dir * 0.4, dir));
    if (p.isYou) SoundService.instance.play(GameSound.tap);
  }

  void _updateHooks(double dt) {
    for (final h in _hooks) {
      if (!h.owner.alive) {
        h.travelled = 99;
        continue;
      }
      final t = h.target;
      if (t == null) {
        final step = h.dir * (_snakeSpeed * dt);
        h.pos += step;
        h.travelled += step.distance;
        for (final o in _people) {
          if (identical(o, h.owner) || !o.alive || _allies(o, h.owner)) {
            continue;
          }
          if ((o.pos - h.pos).distance < _personRadius + 0.3) {
            // Bite! Yank them towards the thrower.
            h.target = o;
            final back = h.owner.pos - o.pos;
            _damage(
              o,
              10 * levelDamageMul(h.owner.lvl(h.owner.held.id)),
              h.owner,
              knock: Offset.fromDirection(
                back.direction,
                // The fling slows as it slides, so aim a bit long to
                // land them right in front of you.
                max(1.2, (back.distance - 0.9) * 1.4),
              ),
            );
            break;
          }
        }
        if (h.target == null &&
            _map.solidAt(h.pos.dx.floor(), h.pos.dy.floor())) {
          h.travelled = 99;
        }
      } else {
        h.pullT += dt;
        h.pos = t.pos;
        h.tickT -= dt;
        // More bites while they're being dragged in.
        if (h.tickT <= 0 && t.alive) {
          h.tickT = 0.2;
          _damage(t, 6 * levelDamageMul(h.owner.lvl(h.owner.held.id)), h.owner);
        }
      }
    }
    _hooks.removeWhere(
      (h) =>
          (h.target == null && h.travelled > _snakeRange) ||
          h.travelled > 50 ||
          (h.target != null && (h.pullT > _pullTime || !h.target!.alive)),
    );
  }

  void _updateBalls(double dt) {
    final remove = <_Ball>{};
    for (final b in _balls) {
      final step = b.vel * dt;
      b.pos += step;
      b.travelled += step.distance;
      var popped = false;
      for (final o in _people) {
        if (identical(o, b.owner) || !o.alive || _allies(o, b.owner)) continue;
        if ((o.pos - b.pos).distance < _personRadius + 0.15) {
          popped = true;
          break;
        }
      }
      if (!popped &&
          (b.travelled > b.gun.range ||
              _map.solidAt(b.pos.dx.floor(), b.pos.dy.floor()))) {
        popped = true;
      }
      if (popped) {
        remove.add(b);
        _popBall(b);
      }
    }
    _balls.removeWhere(remove.contains);
  }

  void _popBall(_Ball b) {
    final g = b.gun;
    final radius = max(g.splash, _personRadius + 0.2);
    _pops.add(_Pop(b.pos, radius, g.shotColor));
    final dmg = g.damage * levelDamageMul(b.owner.lvl(g.id));
    for (final o in _people) {
      if (identical(o, b.owner) || !o.alive || _allies(o, b.owner)) continue;
      final d = (o.pos - b.pos).distance;
      if (d < radius + _personRadius) {
        final falloff = g.splash > 0
            ? 1 - 0.4 * (d / (radius + _personRadius))
            : 1;
        _damage(o, dmg * falloff, b.owner, slow: g.slow);
      }
    }
  }

  void _updateHazards(double dt) {
    if (_map.hazard == MapHazard.water) {
      for (final p in _people) {
        if (!p.alive || p.remote) continue;
        if (!_map.isWater(p.pos)) {
          p.waterT = 0;
          continue;
        }
        if (!p.grounded) continue;
        p.waterT += dt;
        // The first 3 seconds in the lake heal you...
        if (p.waterT <= _healTime && _phase == _Phase.fight) {
          p.hp = min(100, p.hp + 18 * dt);
        }
        // ...but stay in longer than 5 and you drown.
        if (p.waterT > _drownTime) {
          p.shieldT = 0;
          _damage(p, 999, null, quiet: true, cause: 'drowned in the lake');
        }
      }
    }
    if (_map.hazard == MapHazard.karts) {
      for (final k in _karts) {
        for (final p in _people) {
          if (!p.alive || p.remote || p.kartT > 0 || p.z > 0.35) continue;
          if ((p.pos - k.pos).distance > 0.55 + _personRadius) continue;
          // Boing! Launched into the air, no damage.
          p.kartT = 1.2;
          p.vz = 6.5;
          final side = (p.pos - k.pos).direction;
          p.fling =
              Offset.fromDirection(k.heading, 5.5) +
              Offset.fromDirection(side, 3);
          if (p.isYou) _addFeed('A goat kart launched you!');
        }
      }
    }
    if (_map.hazard == MapHazard.lava) {
      for (final p in _people) {
        if (p.alive && p.grounded && _map.isLava(p.pos, _clock)) {
          _damage(p, 22 * dt, null, quiet: true);
        }
      }
    }
    if (_map.hazard == MapHazard.cars) {
      _carT -= dt;
      // Online, the host sends the cars so everyone sees the same ones.
      if (_carT <= 0 && (!_online || _room.isHost)) {
        _carT = 1.6 + _rnd.nextDouble() * 2.2;
        final leftLane = _rnd.nextBool();
        final y = leftLane ? 5.8 : 7.2;
        final speed = (6 + _rnd.nextDouble() * 3) * (leftLane ? 1 : -1);
        final x = speed > 0 ? 0.5 : _map.width - 0.5;
        final colour = _rnd.nextInt(_shirts.length);
        _cars.add(_Car(x, y, speed, _shirts[colour]));
        if (_online) {
          _room.send({'t': 'car', 'x': x, 'y': y, 's': speed, 'c': colour});
        }
      }
      for (final c in _cars) {
        c.x += c.speed * dt;
        for (final p in _people) {
          if (!p.alive || p.z > 0.22) continue;
          if ((p.pos.dx - c.x).abs() < 0.75 + _personRadius &&
              (p.pos.dy - c.y).abs() < 0.42 + _personRadius) {
            _damage(p, 40, null, quiet: true, cause: 'got hit by a car');
            final away = p.pos.dy < c.y ? -1.0 : 1.0;
            _moveBy(p, Offset(c.speed.sign * 0.6, away * 1.2));
          }
        }
      }
      _cars.removeWhere((c) => c.x < -1 || c.x > _map.width + 1);
    }
  }

  /// Where ghost [i] is. They float along fixed loops based on the clock,
  /// so in online games everyone sees them in the same place.
  List<Offset> get _ghosts {
    if (_map.hazard != MapHazard.ghosts) return const [];
    final c = _map.centre;
    final ax = _map.width / 2 - 1.6, ay = _map.height / 2 - 1.6;
    return [
      for (var i = 0; i < 4; i++)
        Offset(
          c.dx + ax * sin(_clock * (0.13 + i * 0.03) + i * 1.7),
          c.dy + ay * sin(_clock * (0.17 + i * 0.025) + i * 2.9),
        ),
    ];
  }

  /// The go-karts on Crazy Goat Cars. Like the ghosts they follow the
  /// clock, so every phone in an online game sees them in the same place.
  List<_Kart> get _karts {
    if (_map.hazard != MapHazard.karts) return const [];
    final len = _map.loopLength;
    return [
      for (var i = 0; i < 6; i++)
        () {
          final speed = 4.6 + (i * 37 % 6) * 0.45;
          final along = i * len / 6 + _clock * speed;
          final lane = i.isEven ? -0.7 : 0.7;
          final a = _map.loopPoint(along), b = _map.loopPoint(along + 0.05);
          final heading = (b - a).direction;
          final out = Offset.fromDirection(heading - pi / 2, lane);
          return _Kart(a + out, heading, _shirts[(i * 3) % _shirts.length]);
        }(),
    ];
  }

  void _updateGhosts() {
    for (final g in _ghosts) {
      for (final p in _people) {
        if (!p.alive || p.ghostT > 0 || (p.pos - g).distance > 0.55) continue;
        p.ghostT = 1.2;
        _damage(
          p,
          12,
          null,
          quiet: true,
          cause: 'got spooked by a ghost',
          slow: 1,
        );
      }
    }
  }

  void _updateRespawns(double dt) {
    if (!_ffa) return;
    for (final p in _people) {
      if (p.alive || p.remote) continue;
      p.respawnT -= dt;
      if (p.respawnT <= 0 && _teamGame) {
        // Back to your team's end of the map, facing the other team.
        _placeOnTeam(p, _rnd.nextInt(3));
      } else if (p.respawnT <= 0) {
        // Pick the start spot furthest from everyone else.
        Offset best = _map.spawnPoints().first;
        var bestScore = -1.0;
        for (final s in _map.spawnPoints()) {
          var nearest = 99.0;
          for (final o in _people) {
            if (o.alive) nearest = min(nearest, (o.pos - s).distance);
          }
          final score = nearest + _rnd.nextDouble();
          if (score > bestScore) {
            bestScore = score;
            best = s;
          }
        }
        p.respawn(best, _faceCentre(best));
      }
    }
  }

  void _damage(
    _Person p,
    double amount,
    _Person? by, {
    double slow = 0,
    bool quiet = false,
    String? cause,
    Offset knock = Offset.zero,
    bool fromNet = false,
  }) {
    if (!p.alive || _phase != _Phase.fight || _lobby) return;
    if (p.shieldT > 0 && _ffa) return;
    if (by != null && _allies(by, p)) return; // no hurting your own team
    if (_online) {
      if (p.remote) {
        // Their own phone takes the damage; we just tell them about it.
        if (by == null || !by.isYou) return;
        _room.send({
          't': 'hit',
          'to': p.netId,
          'by': _you.netId,
          'dmg': amount,
          'slow': slow,
          'kx': knock.dx,
          'ky': knock.dy,
        });
        _hitMarkT = 0.15;
        _popups.add(_Popup(p.pos, amount.round().toString(), Colors.white));
        SoundService.instance.play(GameSound.hit);
        return;
      }
      // Hits from other players only count when their phone says so.
      if (by != null && by.remote && !fromNet) return;
    }
    // Bots hit softer so the game stays easy.
    if (by != null && !by.isYou && !by.remote && p.isYou) amount *= 0.5;
    p.hp -= amount;
    // Big pulls slide you over; small knocks just bump you.
    if (knock.distance > 1.1) {
      p.fling += knock * 3;
    } else if (knock != Offset.zero) {
      _moveBy(p, knock);
    }
    p.hurtT = 0.15;
    if (slow > 0) p.slowT = max(p.slowT, slow);
    if (by != null && by.isYou) {
      _hitMarkT = 0.15;
      _popups.add(_Popup(p.pos, amount.round().toString(), Colors.white));
      SoundService.instance.play(GameSound.hit);
    }
    if (p.hp > 0) return;
    p.hp = 0;
    p.alive = false;
    p.deaths++;
    p.respawnT = 3;
    if (by != null && !identical(by, p)) by.kills++;
    final killer = by == null ? null : (by.isYou ? 'You' : by.name);
    final victim = p.isYou ? 'you' : p.name;
    if (_online && p.isYou) {
      _room.send({'t': 'ko', 'v': _you.netId, 'k': by?.netId, 'c': cause});
    }
    _addFeed(
      killer == null
          ? '${p.isYou ? 'You' : p.name} ${cause ?? 'fell in the lava'}'
          : '$killer outplayed $victim',
    );

    if (!_ffa) {
      _lastRoundYours = !p.isYou;
      if (_lastRoundYours) {
        _yourRounds++;
      } else {
        _botRounds++;
      }
      _phase = _Phase.roundOver;
      _phaseT = 0;
    } else {
      _checkScores();
    }
  }

  /// Ends the game once a player (or a team) has enough KOs.
  void _checkScores() {
    if (_phase == _Phase.matchOver || _phase == _Phase.waiting) return;
    final done = _teamGame
        ? _teamScore(0) >= _killsToWin || _teamScore(1) >= _killsToWin
        : _people.any((p) => p.kills >= _killsToWin);
    if (done) _finishMatch();
  }

  void _addFeed(String text) {
    _feed.add(text);
    if (_feed.length > 3) _feed.removeAt(0);
    _feedT = 2.5;
  }

  void _finishMatch() {
    if (_phase == _Phase.matchOver) return;
    _lister?.unannounce();
    _lister = null;
    if (_teamGame) {
      _youWon = _teamScore(_you.team) > _teamScore(1 - _you.team);
      _coinsEarned = _youWon ? 100 : 0;
    } else if (_ffa) {
      final top = _people.map((p) => p.kills).reduce(max);
      _youWon = _you.kills == top && top > 0;
      // Coins only for winning the whole game.
      _coinsEarned = _youWon ? (_online ? 100 : 80) : 0;
    } else {
      _youWon = _yourRounds > _botRounds;
      _coinsEarned = _youWon ? 100 : 0;
    }
    _save.coins += _coinsEarned;
    if (_youWon) {
      _save.wins++;
    } else {
      _save.losses++;
    }
    _save.save();
    SoundService.instance.play(_youWon ? GameSound.win : GameSound.gameOver);
    _phase = _Phase.matchOver;
    _phaseT = 0;
    _firing = false;
  }

  // ---- online -------------------------------------------------------------

  void _netTick(double dt) {
    for (final m in _room.takeMessages()) {
      _onNet(m);
    }
    for (final p in [..._people]) {
      if (!p.remote) continue;
      p.netQuiet += dt;
      if (p.netQuiet > 8) {
        _people.remove(p);
        _addFeed('${p.name} left');
        continue;
      }
      // Glide towards where their phone says they are.
      final gap = p.netPos - p.pos;
      if (gap.distance > 3) {
        p.pos = p.netPos;
      } else {
        p.pos += gap * min(1.0, dt * 12);
        p.walkCycle += gap.distance * min(1.0, dt * 12) * 3;
      }
    }
    _listT -= dt;
    if (_lister != null && _listT <= 0) {
      _listT = 2;
      _lister!.announce(
        RoomInfo(
          code: _room.code,
          name: _myName,
          avatar: _you.look.toList(),
          mapId: _map.id,
          players: _people.length,
          playing: _phase != _Phase.waiting,
          teamSize: _room.teamSize,
          friends: _room.showCode,
        ),
      );
    }
    _sendT -= dt;
    if (_sendT <= 0) {
      _sendT = 1 / 15;
      _room.send({
        't': 's',
        'id': _you.netId,
        'n': _myName,
        'av': _you.look.toList(),
        'g0': _you.guns[0]?.id,
        'g1': _you.guns[1]?.id,
        'm': _you.melee.id,
        'm2': _you.melee2?.id,
        'x': _you.pos.dx,
        'y': _you.pos.dy,
        'a': _you.angle,
        'z': _you.z,
        'hp': _you.hp,
        'al': _you.alive,
        'sl': _you.slot,
        'sk': _you.skins[_you.heldId],
        if (_hooks.any((h) => identical(h.owner, _you)))
          'hk': () {
            final h = _hooks.firstWhere((h) => identical(h.owner, _you));
            return [h.pos.dx, h.pos.dy, h.target != null];
          }(),
        'sw': _you.swingT > 0,
        'fl': _you.flashT > 0,
        'k': _you.kills,
        'tm': _you.team,
        'd': _you.deaths,
      });
    }
  }

  String get _myName {
    final n = _save.name.trim();
    return n.isEmpty ? _guestName : n;
  }

  late final String _guestName = 'Player ${10 + _rnd.nextInt(90)}';

  _Person? _byNetId(Object? id) {
    if (id == null) return null;
    for (final p in _people) {
      if (p.netId == id) return p;
    }
    return null;
  }

  double _num(Object? v) => (v as num?)?.toDouble() ?? 0;

  void _onNet(Map<String, dynamic> m) {
    switch (m['t']) {
      case 's':
        final id = m['id'] as String?;
        if (id == null || id == _you.netId) return;
        var p = _byNetId(id);
        final at = Offset(_num(m['x']), _num(m['y']));
        if (p == null) {
          final g1 = m['g1'] as String?;
          p =
              _Person(
                  name: (m['n'] as String?) ?? 'Player',
                  isYou: false,
                  look: Avatar.fromList(m['av']),
                  guns: [
                    gunById((m['g0'] as String?) ?? ''),
                    g1 == null ? null : gunById(g1),
                  ],
                  melee: meleeById((m['m'] as String?) ?? ''),
                  levels: {},
                  pos: at,
                  angle: _num(m['a']),
                )
                ..melee2 = m['m2'] is String
                    ? meleeById(m['m2'] as String)
                    : null
                ..remote = true
                ..netId = id;
          _people.add(p);
          if (_phase != _Phase.waiting) _addFeed('${p.name} joined');
        }
        p.netPos = at;
        p.netQuiet = 0;
        p.angle = _num(m['a']);
        p.z = _num(m['z']);
        p.vz = 0;
        p.hp = _num(m['hp']);
        p.alive = m['al'] == true;
        p.slot = ((m['sl'] as int?) ?? 0).clamp(0, 3);
        if (p.slot == 1 && p.guns[1] == null) p.slot = 0;
        if (p.slot == 3 && p.melee2 == null) p.slot = 2;
        final sk = m['sk'];
        if (sk is String && skinById(sk) != null) {
          p.skins[p.heldId] = sk;
        } else {
          p.skins.remove(p.heldId);
        }
        final hk = m['hk'];
        p.netHook = hk is List && hk.length == 3
            ? (Offset(_num(hk[0]), _num(hk[1])), hk[2] == true)
            : null;
        if (m['sw'] == true && p.swingT <= 0) p.swingT = 0.2;
        if (m['fl'] == true) p.flashT = 0.06;
        p.kills = (m['k'] as int?) ?? p.kills;
        p.team = (m['tm'] as int?) ?? p.team;
        p.deaths = (m['d'] as int?) ?? p.deaths;
        if (_phase == _Phase.fight) _checkScores();
        break;
      case 'hit':
        if (m['to'] != _you.netId) return;
        final by = _byNetId(m['by']);
        if (by == null) return;
        _damage(
          _you,
          _num(m['dmg']),
          by,
          slow: _num(m['slow']),
          knock: Offset(_num(m['kx']), _num(m['ky'])),
          fromNet: true,
        );
        break;
      case 'ko':
        final victim = _byNetId(m['v']);
        if (victim == null || identical(victim, _you)) return;
        final killer = m['k'] == _you.netId ? _you : _byNetId(m['k']);
        victim.alive = false;
        victim.deaths++;
        if (killer != null) killer.kills++;
        _addFeed(
          killer == null
              ? '${victim.name} ${(m['c'] as String?) ?? 'fell in the lava'}'
              : '${killer.isYou ? 'You' : killer.name} outplayed ${victim.name}',
        );
        _checkScores();
        break;
      case 'ball':
        final owner = _byNetId(m['id']);
        if (owner == null) return;
        _balls.add(
          _Ball(
            Offset(_num(m['x']), _num(m['y'])),
            Offset(_num(m['vx']), _num(m['vy'])),
            owner,
            gunById((m['g'] as String?) ?? ''),
          ),
        );
        break;
      case 'car':
        if (_map.hazard != MapHazard.cars) return;
        final c = ((m['c'] as int?) ?? 0) % _shirts.length;
        _cars.add(_Car(_num(m['x']), _num(m['y']), _num(m['s']), _shirts[c]));
        break;
      case 'start':
        if (_phase == _Phase.waiting) {
          _startRound();
        }
        break;
      case 'bye':
        final p = _byNetId(m['id']);
        if (p != null) {
          _people.remove(p);
          _addFeed('${p.name} left');
        }
        break;
      case 'hostLeft':
        _hostLeft = true;
        if (_phase == _Phase.waiting) {
          _closedEarly = true;
          _phase = _Phase.matchOver;
        } else {
          _finishMatch();
        }
        break;
    }
  }

  void _hostStart() {
    if (!_room.isHost || _phase != _Phase.waiting) return;
    _room.start();
    _startRound();
  }

  // ---- bots ---------------------------------------------------------------

  void _updateBot(_Person b, double dt) {
    if (!b.alive) return;
    // Find who to fight: the closest person it can see, else the closest.
    _Person? target;
    var bestScore = double.infinity;
    for (final o in _people) {
      if (identical(o, b) || !o.alive || _allies(o, b)) continue;
      final d = (o.pos - b.pos).distance;
      final score = d + (_canSee(b.pos, o.pos) ? 0 : 6);
      if (score < bestScore) {
        bestScore = score;
        target = o;
      }
    }

    var move = Offset.zero;
    var fire = false;
    if (target != null) {
      final to = target.pos - b.pos;
      final dist = to.distance;
      final sees = _canSee(b.pos, target.pos);
      final gun = b.guns[0]!;
      final wantSlot = dist < 1.3 ? 2 : 0;
      if (b.slot != wantSlot) _switchSlot(b, wantSlot);
      // Sizzler bots sometimes throw the snake to drag you in.
      if (b.melee.hook &&
          b.pullCooldown <= 0 &&
          dist > 2.5 &&
          dist < _snakeRange - 1 &&
          b.reactT > 1.2 &&
          _angleDiff(b.angle, to.direction).abs() < 0.08 &&
          _rnd.nextDouble() < dt * 0.6) {
        _switchSlot(b, 2);
        _throwSnake(b);
        if (b.pullCooldown <= 0) _switchSlot(b, 0);
      }

      b.strafeT -= dt;
      if (b.strafeT <= 0) {
        b.strafe = _rnd.nextBool() ? 1 : -1;
        b.strafeT = 0.7 + _rnd.nextDouble() * 1.5;
      }

      if (sees) {
        b.reactT += dt;
        final dir = to / dist;
        final side = Offset(-dir.dy, dir.dx) * b.strafe;
        final want = (gun.range * 0.5).clamp(1.2, 7.0);
        final push = b.slot == 2
            ? 1.0
            : (dist > want + 1 ? 0.8 : (dist < want - 1 ? -0.6 : 0.0));
        move = dir * push + side * 0.7;
        b.wobble += dt * 2.1;
        final aimAt = to.direction + b.aimError * sin(b.wobble);
        final diff = _angleDiff(b.angle, aimAt);
        final turn = b.turnRate * dt;
        b.angle += diff.clamp(-turn, turn);
        final reach = b.slot == 2 ? b.melee.reach + 0.2 : gun.range;
        fire =
            b.reactT > b.reactDelay &&
            diff.abs() < 0.12 + 0.3 / max(dist, 0.5) &&
            dist < reach;
      } else {
        b.reactT = 0;
        b.pathT -= dt;
        if (b.pathT <= 0 || b.path.isEmpty) {
          b.path = _findPath(b.pos, target.pos);
          b.pathT = 0.5;
        }
        while (b.path.isNotEmpty &&
            (Offset(b.path.first.x + 0.5, b.path.first.y + 0.5) - b.pos)
                    .distance <
                0.3) {
          b.path.removeAt(0);
        }
        if (b.path.isNotEmpty) {
          final next = Offset(b.path.first.x + 0.5, b.path.first.y + 0.5);
          move = next - b.pos;
        } else {
          move = to;
        }
        final diff = _angleDiff(b.angle, move.direction);
        final turn = b.turnRate * dt;
        b.angle += diff.clamp(-turn, turn);
      }
    }

    // Swim to heal, but get out before drowning.
    if (_map.hazard == MapHazard.water && b.waterT > 2.6) {
      move = (b.pos - _map.centre) + move * 0.2;
    }
    // Stay out of the lava and hop over cars.
    if (_map.hazard == MapHazard.lava &&
        (b.pos - _map.centre).distance > _map.safeRadius(_clock) - 1.2) {
      move = (_map.centre - b.pos) + move * 0.3;
    }
    if (_map.hazard == MapHazard.cars && b.grounded) {
      for (final c in _cars) {
        final ahead = (b.pos.dx - c.x) * c.speed.sign;
        if (ahead > 0 && ahead < 2.2 && (b.pos.dy - c.y).abs() < 0.9) {
          if (_rnd.nextDouble() < 0.7) _jump(b);
          break;
        }
      }
    }

    if (move.distance > 1) move = move / move.distance;
    _updatePerson(b, dt, move * 0.9, fire);
  }

  List<Point<int>> _findPath(Offset from, Offset to) {
    final start = Point(from.dx.floor(), from.dy.floor());
    final goal = Point(to.dx.floor(), to.dy.floor());
    final prev = <Point<int>, Point<int>>{};
    final queue = Queue<Point<int>>()..add(start);
    prev[start] = start;
    const dirs = [Point(1, 0), Point(-1, 0), Point(0, 1), Point(0, -1)];
    while (queue.isNotEmpty) {
      final c = queue.removeFirst();
      if (c == goal) break;
      for (final d in dirs) {
        final n = Point(c.x + d.x, c.y + d.y);
        if (prev.containsKey(n) || _map.solidAt(n.x, n.y)) continue;
        prev[n] = c;
        queue.add(n);
      }
    }
    if (!prev.containsKey(goal)) return [];
    final path = <Point<int>>[];
    var c = goal;
    while (c != start) {
      path.add(c);
      c = prev[c]!;
    }
    return path.reversed.toList();
  }

  // ---- world helpers ------------------------------------------------------

  void _moveBy(_Person p, Offset d) {
    // Slide along walls: try each axis on its own.
    final nx = p.pos.dx + d.dx;
    if (!_blocked(nx, p.pos.dy)) p.pos = Offset(nx, p.pos.dy);
    final ny = p.pos.dy + d.dy;
    if (!_blocked(p.pos.dx, ny)) p.pos = Offset(p.pos.dx, ny);
  }

  bool _blocked(double x, double y) {
    const r = _personRadius;
    return _map.solidAt((x - r).floor(), (y - r).floor()) ||
        _map.solidAt((x + r).floor(), (y - r).floor()) ||
        _map.solidAt((x - r).floor(), (y + r).floor()) ||
        _map.solidAt((x + r).floor(), (y + r).floor());
  }

  void _separate() {
    for (var i = 0; i < _people.length; i++) {
      for (var j = i + 1; j < _people.length; j++) {
        final a = _people[i], b = _people[j];
        if (!a.alive || !b.alive) continue;
        final d = a.pos - b.pos;
        final dist = d.distance;
        if (dist < _personRadius * 2 && dist > 0.0001) {
          final push = d / dist * ((_personRadius * 2 - dist) / 2);
          _moveBy(a, push);
          _moveBy(b, -push);
        }
      }
    }
  }

  bool _canSee(Offset a, Offset b) {
    final d = b - a;
    return _cast(a, d.direction).dist >= d.distance;
  }

  /// Steps along a ray square by square until it hits a wall.
  _Hit _cast(Offset from, double angle) {
    final dx = cos(angle), dy = sin(angle);
    var mapX = from.dx.floor(), mapY = from.dy.floor();
    final deltaX = dx == 0 ? 1e30 : (1 / dx).abs();
    final deltaY = dy == 0 ? 1e30 : (1 / dy).abs();
    final stepX = dx < 0 ? -1 : 1;
    final stepY = dy < 0 ? -1 : 1;
    var sideX = dx < 0
        ? (from.dx - mapX) * deltaX
        : (mapX + 1 - from.dx) * deltaX;
    var sideY = dy < 0
        ? (from.dy - mapY) * deltaY
        : (mapY + 1 - from.dy) * deltaY;
    var side = 0;
    for (var i = 0; i < 64; i++) {
      if (sideX < sideY) {
        sideX += deltaX;
        mapX += stepX;
        side = 0;
      } else {
        sideY += deltaY;
        mapY += stepY;
        side = 1;
      }
      final c = _map.cell(mapX, mapY);
      if (OutplayMap.isSolid(c)) {
        final dist = side == 0 ? sideX - deltaX : sideY - deltaY;
        var wallX = side == 0 ? from.dy + dist * dy : from.dx + dist * dx;
        wallX -= wallX.floorToDouble();
        return _Hit(dist, c, side, wallX);
      }
    }
    return const _Hit(64, '#', 0, 0);
  }

  static double _angleDiff(double from, double to) {
    var d = (to - from) % (2 * pi);
    if (d > pi) d -= 2 * pi;
    return d;
  }

  // ---- Duel Zone ----------------------------------------------------------

  void _checkPads() {
    String? here;
    for (final pad in ['Q', 'F', 'O']) {
      final c = _map.padCentre(pad);
      if (c != null && (c - _you.pos).distance < 0.7) here = pad;
    }
    if (here != _padHere) {
      _padHere = here;
      if (here != null) {
        _panel = here;
        _movePointer = null;
        SoundService.instance.play(GameSound.place);
      }
    }
  }

  Future<void> _launch(OutplayMode mode) async {
    final ids = kArenaMaps.map((m) => m.id).toList();
    final mapId = _pickMap == 'random'
        ? ids[_rnd.nextInt(ids.length)]
        : _pickMap;
    await _launchWith(
      OutplayGameScreen(
        mode: mode,
        mapId: mapId,
        bots: mode == OutplayMode.duel ? 1 : _pickBots,
        difficulty: _qpLevel,
        teamSize: _qpSize,
      ),
    );
  }

  Future<void> _launchWith(OutplayGameScreen game) async {
    _closePanel();
    _ticker.stop();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => game));
    if (!mounted) return;
    // Step back off the pad when you return.
    _you.pos = _map.spawnPoints().first;
    _you.angle = -pi / 2;
    _padHere = null;
    _last = Duration.zero;
    _keys.clear();
    _ticker.start();
  }

  // ---- input --------------------------------------------------------------

  void _onDown(PointerDownEvent e, Size size) {
    if (e.localPosition.dx < size.width * 0.45) {
      _movePointer = e.pointer;
      _moveOrigin = e.localPosition;
      _moveNow = e.localPosition;
    } else {
      _lookPointer = e.pointer;
      _lookLastX = e.localPosition.dx;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer == _movePointer) {
      var d = e.localPosition - _moveOrigin;
      if (d.distance > 60) d = d / d.distance * 60;
      _moveNow = _moveOrigin + d;
    } else if (e.pointer == _lookPointer) {
      _you.angle += (e.localPosition.dx - _lookLastX) * 0.009;
      _lookLastX = e.localPosition.dx;
    }
  }

  void _onUp(PointerEvent e) {
    if (e.pointer == _movePointer) _movePointer = null;
    if (e.pointer == _lookPointer) _lookPointer = null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    // Let the name and room code boxes have the keyboard.
    if (_panel != null) {
      _keys.clear();
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (e is KeyDownEvent) {
      _keys.add(k);
      if (k == LogicalKeyboardKey.space) _jump(_you);
      if (k == LogicalKeyboardKey.digit1) _switchSlot(_you, 0);
      if (k == LogicalKeyboardKey.digit2) _switchSlot(_you, 1);
      if (k == LogicalKeyboardKey.digit3) _switchSlot(_you, 2);
      if (k == LogicalKeyboardKey.digit4) _switchSlot(_you, 3);
      if (k == LogicalKeyboardKey.keyR) _throwSnake(_you);
      if (k == LogicalKeyboardKey.keyR) _startReload(_you);
    } else if (e is KeyUpEvent) {
      _keys.remove(k);
    }
    return KeyEventResult.handled;
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (context, c) {
            final size = c.biggest;
            _topPad = MediaQuery.of(context).padding.top;
            return Stack(
              fit: StackFit.expand,
              children: [
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _onDown(e, size),
                  onPointerMove: _onMove,
                  onPointerUp: _onUp,
                  onPointerCancel: _onUp,
                  child: CustomPaint(painter: _ViewPainter(this)),
                ),
                SafeArea(child: _buildHud(size)),
                if (_phase == _Phase.countdown || _phase == _Phase.roundOver)
                  _buildBanner(),
                if (_phase == _Phase.waiting) _buildWaiting(),
                if (_phase == _Phase.matchOver) _buildMatchOver(),
                if (_panel != null) _buildPadPanel(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHud(Size size) {
    return Stack(
      children: [
        // Top bar.
        Positioned(
          left: 4,
          right: 8,
          top: 4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _roundButton(
                icon: _lobby ? Icons.arrow_back_rounded : Icons.close_rounded,
                tooltip: _lobby ? 'Back to loadout' : 'Leave match',
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildScore()),
              const SizedBox(width: 92), // room for the mini-map
            ],
          ),
        ),
        if (_feed.isNotEmpty)
          Positioned(
            left: 12,
            top: 64,
            right: 110,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final f in _feed)
                  Container(
                    margin: const EdgeInsets.only(bottom: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      f,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (!_lobby) ...[
          // Weapon slots stacked above the fire button.
          Positioned(right: 20, bottom: 118, child: _slotButtons()),
          Positioned(right: 16, bottom: 20, child: _fireButton()),
          if (_holdingSizzler)
            Positioned(right: 112, bottom: 26, child: _pullButton()),
        ],
        Positioned(
          right: _lobby ? 24 : 92,
          bottom: _lobby ? 30 : 124,
          child: _holdButton(
            size: 60,
            color: const Color(0xFF66BB6A),
            icon: Icons.keyboard_double_arrow_up_rounded,
            label: 'JUMP',
            onDown: () => _jump(_you),
          ),
        ),
      ],
    );
  }

  Widget _buildScore() {
    Widget hp() => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 10,
        child: LinearProgressIndicator(
          value: _you.hp / 100,
          backgroundColor: Colors.white24,
          valueColor: AlwaysStoppedAnimation(
            _you.hp > 35 ? const Color(0xFF66BB6A) : const Color(0xFFEF5350),
          ),
        ),
      ),
    );
    const style = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w900,
      fontSize: 16,
      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
    );
    if (_lobby) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text('DUEL ZONE', style: style),
      );
    }
    if (_phase == _Phase.waiting) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: const Text('ONLINE', style: style),
      );
    }
    String line;
    if (_teamGame) {
      final left = max(0, (_ffaTimeLimit - _clock).ceil());
      line =
          'Your team ${_teamScore(_you.team)} - ${_teamScore(1 - _you.team)} '
          'Them  ·  first to $_killsToWin  ·  '
          '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}';
    } else if (_ffa) {
      final top = _people.map((p) => p.kills).reduce(max);
      final left = max(0, (_ffaTimeLimit - _clock).ceil());
      line =
          'KOs ${_you.kills}  ·  Top $top/$_killsToWin  ·  '
          '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}';
    } else {
      line = 'You $_yourRounds - $_botRounds ${_people[1].name}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(line, style: style),
        ),
        const SizedBox(height: 4),
        hp(),
      ],
    );
  }

  Widget _roundButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }

  Widget _holdButton({
    required double size,
    required Color color,
    required IconData icon,
    required String label,
    VoidCallback? onDown,
    VoidCallback? onUp,
    void Function(PointerMoveEvent)? onMove,
  }) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onDown?.call(),
      onPointerMove: onMove,
      onPointerUp: (_) => onUp?.call(),
      onPointerCancel: (_) => onUp?.call(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.75),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70, width: 3),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: size * 0.4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fireButton() {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _firing = true;
        _firePointer = e.pointer;
        _fireLastX = e.position.dx;
      },
      // Slide your thumb on the fire button to aim while shooting.
      onPointerMove: (e) {
        if (e.pointer != _firePointer) return;
        _you.angle += (e.position.dx - _fireLastX) * 0.009;
        _fireLastX = e.position.dx;
      },
      onPointerUp: (_) {
        _firing = false;
        _firePointer = null;
      },
      onPointerCancel: (_) {
        _firing = false;
        _firePointer = null;
      },
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          color: (_firing ? const Color(0xFFFF5252) : const Color(0xFFE53935))
              .withValues(alpha: 0.8),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70, width: 3),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _you.slot >= 2
                  ? Icons.back_hand_rounded
                  : Icons.gps_fixed_rounded,
              color: Colors.white,
              size: 34,
            ),
            Text(
              _you.slot >= 2 ? 'HIT' : 'FIRE',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slotButtons() {
    final slots = [
      _slotButton(0),
      _slotButton(1),
      _slotButton(2),
      if (_you.melee2 != null) _slotButton(3),
    ];
    // Short screens (a phone on its side) get two columns.
    if (slots.length > 3 && MediaQuery.of(context).size.height < 520) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(children: slots.sublist(2)),
          const SizedBox(width: 6),
          Column(children: slots.sublist(0, 2)),
        ],
      );
    }
    return Column(children: slots);
  }

  bool get _holdingSizzler => _you.alive && _you.gun == null && _you.held.hook;

  Widget _pullButton() {
    final ready = _you.pullCooldown <= 0;
    return GestureDetector(
      onTapDown: (_) => _throwSnake(_you),
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: (ready ? const Color(0xFF43A047) : Colors.black54).withValues(
            alpha: 0.85,
          ),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70, width: 3),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.u_turn_left_rounded,
              color: Colors.white,
              size: 24,
            ),
            Text(
              ready ? 'PULL' : _you.pullCooldown.ceil().toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slotButton(int slot) {
    final gun = slot < 2 ? _you.guns[slot] : null;
    final empty = slot < 2 && gun == null;
    final selected = _you.slot == slot;
    final slotMelee = slot == 3 ? _you.melee2! : _you.melee;
    String label;
    if (empty) {
      label = '—';
    } else if (gun == null) {
      label = (slot == 3 ? _you.melee2! : _you.melee).name.split(' ').first;
    } else if (_you.reloadingSlot == slot) {
      label = '...';
    } else {
      label = '${_you.ammo[slot]}';
    }
    return GestureDetector(
      onTap: empty
          ? null
          : () => selected ? _startReload(_you) : _switchSlot(_you, slot),
      child: Opacity(
        opacity: empty ? 0.35 : 1,
        child: Container(
          width: 46,
          height: 46,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: selected ? const Color(0xCC3A4675) : Colors.black45,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0xFF4FC3F7) : Colors.white24,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (empty)
                const Icon(Icons.lock_rounded, color: Colors.white54, size: 18)
              else
                WeaponIcon(
                  look: gun?.look ?? slotMelee.look,
                  color: gun?.color ?? slotMelee.color,
                  size: 34,
                  skin: _you.skinOf(gun?.id ?? slotMelee.id),
                ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBanner() {
    String big, small;
    if (_phase == _Phase.countdown) {
      final left = 3 - (_phaseT / 0.6).floor();
      big = left > 0 ? '$left' : 'FIGHT!';
      small = _ffa
          ? '${_teamGame ? (_online ? 'Online $_teamLabel' : _teamLabel) : (_online ? 'Online' : 'Free-for-all')} · ${_map.name} · first to $_killsToWin KOs'
          : 'Round $_round · ${_map.name}';
    } else {
      big = _lastRoundYours ? 'OUTPLAYED!' : 'You got outplayed';
      small = _lastRoundYours ? 'Nice one!' : 'Get them next round';
    }
    return IgnorePointer(
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  big,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                small,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMatchOver() {
    final ranking = [..._people]..sort((a, b) => b.kills.compareTo(a.kills));
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF262E4F),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _youWon
                  ? const Color(0xFF4FC3F7)
                  : const Color(0xFFFF6B6B),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hostLeft)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'The player who made the room left.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              Text(
                _closedEarly ? 'ROOM CLOSED' : (_youWon ? 'VICTORY' : 'DEFEAT'),
                style: TextStyle(
                  color: _youWon
                      ? const Color(0xFF4FC3F7)
                      : const Color(0xFFFF6B6B),
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              if (_teamGame)
                Text(
                  'Your team ${_teamScore(_you.team)} - '
                  '${_teamScore(1 - _you.team)} Them',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (_ffa)
                for (final p in ranking.take(5))
                  Text(
                    '${p.isYou ? 'You' : p.name}: ${p.kills} KOs',
                    style: TextStyle(
                      color: p.isYou ? const Color(0xFF4FC3F7) : Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  )
              else
                Text(
                  '$_yourRounds - $_botRounds',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.monetization_on_rounded,
                    color: Color(0xFFFFC93C),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _coinsEarned > 0
                          ? '+$_coinsEarned coins'
                          : 'Win to get coins',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFFC93C),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to Duel Zone'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaiting() {
    final others = _people.length - 1;
    final names = [
      _myName,
      for (final p in _people)
        if (p.remote) p.name,
    ];
    return Positioned(
      left: 16,
      right: 16,
      top: _topPad + 70,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF42A5F5), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _onlineTeams
                    ? (_room.showCode
                          ? 'Waiting for players… ${others + 1}/${_teamSize * 2}'
                          : 'Finding players… ${others + 1}/${_teamSize * 2}')
                    : (others > 0 ? 'Players here' : 'Waiting for players…'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _onlineTeams && _room.showCode
                    ? '$_teamLabel on ${_map.name}. It starts as soon as '
                          '${_teamSize * 2} people are in.'
                          '${others > 0 ? '\nHere: ${names.join(', ')}' : ''}'
                          '\nTell your friends the room code:'
                    : _onlineTeams
                    ? (others == 0
                          ? 'Quick Play $_teamLabel on ${_map.name}. '
                                'It starts as soon as everyone is here.'
                          : names.join(', '))
                    : (others == 0
                          ? 'People pressing Join can see you and jump in. '
                                'Or tell a friend your room code:'
                          : names.join(', ')),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              // Room codes are only for Find Players rooms.
              if ((others == 0 && !_onlineTeams) ||
                  (_onlineTeams && _room.showCode))
                Text(
                  _room.code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    letterSpacing: 6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              const SizedBox(height: 10),
              if (_onlineTeams)
                const SizedBox.shrink()
              else if (_room.isHost)
                ElevatedButton(
                  onPressed: others > 0 ? _hostStart : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF42A5F5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 12,
                    ),
                  ),
                  child: Text(others > 0 ? 'START' : 'Nobody here yet'),
                )
              else
                const Text(
                  'Waiting for the room maker to press Start…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Find Players panel -------------------------------------------------

  void _closePanel() {
    _stopBrowsing();
    setState(() {
      _panel = null;
      _qpStep = 0;
      _netError = null;
    });
  }

  void _startBrowsing() {
    final dir = widget.makeDirectory();
    if (dir == null) {
      setState(() => _netError = 'Online play only works on the website.');
      return;
    }
    _stopBrowsing();
    _browser = dir;
    setState(() {
      _browsing = true;
      _netError = null;
      _waitingRooms = null;
    });
    dir.browse((rooms) {
      if (mounted) setState(() => _waitingRooms = rooms);
    });
  }

  void _stopBrowsing() {
    _browser?.stopBrowse();
    _browser = null;
    _browsing = false;
  }

  Future<void> _editPlayer() async {
    _stopBrowsing();
    _ticker.stop();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const OutplayAvatarScreen()));
    if (!mounted) return;
    _you.look = _save.avatar;
    _last = Duration.zero;
    _keys.clear();
    _ticker.start();
    setState(() {});
  }

  /// Quick Play against humans: join a room of people waiting for the same
  /// size of game on the same map, or make one and wait for people to come.
  Future<void> _quickMatch(int size) async {
    if (_save.name.trim().isEmpty) {
      await _editPlayer();
      if (_save.name.trim().isEmpty || !mounted) return;
    }
    final dir = widget.makeDirectory();
    if (dir == null || widget.makeLink() == null) {
      setState(() => _netError = 'Online play only works on the website.');
      return;
    }
    setState(() {
      _netBusy = true;
      _netError = null;
    });
    var rooms = const <RoomInfo>[];
    dir.browse((r) => rooms = r);
    await Future<void>.delayed(
      Duration(milliseconds: 2500 + _rnd.nextInt(1000)),
    );
    dir.stopBrowse();
    if (!mounted) return;
    setState(() => _netBusy = false);
    final open =
        rooms
            .where(
              (r) =>
                  r.teamSize == size &&
                  !r.friends &&
                  !r.playing &&
                  r.players < size * 2 &&
                  // Picked a map? Only fight people who picked the same one.
                  (_pickMap == 'random' || r.mapId == _pickMap),
            )
            .toList()
          // Fill up the fullest room first so games start sooner.
          ..sort((a, b) => b.players.compareTo(a.players));
    for (final r in open.take(2)) {
      await _goOnline(joinCode: r.code);
      if (!mounted || _netError == null) return;
    }
    await _goOnline(teamSize: size);
  }

  Future<void> _goOnline({
    String? joinCode,
    int teamSize = 0,
    bool showCode = false,
  }) async {
    final make = widget.makeLink;
    if (make() == null) {
      setState(() => _netError = 'Online play only works on the website.');
      return;
    }
    setState(() {
      _netBusy = true;
      _netError = null;
    });
    final ids = kArenaMaps.map((m) => m.id).toList();
    final mapId = _pickMap == 'random'
        ? ids[_rnd.nextInt(ids.length)]
        : _pickMap;
    OutplayRoom room;
    try {
      room = joinCode == null
          ? await OutplayRoom.host(
              () => make()!,
              mapId,
              teamSize: teamSize,
              showCode: showCode,
            )
          : await OutplayRoom.join(() => make()!, joinCode);
    } catch (e) {
      if (mounted) {
        setState(() {
          _netBusy = false;
          _netError = '$e';
        });
      }
      return;
    }
    if (!mounted) {
      room.close();
      return;
    }
    _stopBrowsing();
    setState(() => _netBusy = false);
    await _launchWith(
      OutplayGameScreen(
        mode: OutplayMode.online,
        mapId: room.mapId,
        room: room,
        makeLink: widget.makeLink,
        makeDirectory: widget.makeDirectory,
      ),
    );
  }

  Widget _panelShell(Color color, List<Widget> children) => Container(
    color: Colors.black45,
    alignment: Alignment.bottomCenter,
    child: SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF262E4F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 2),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    ),
  );

  Widget _panelTitle(String title, String text, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 4),
      Text(text, style: const TextStyle(color: Colors.white70)),
    ],
  );

  Widget _mapPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      const Text(
        'Map',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (id, name) in [
            ('random', 'Random'),
            for (final m in kArenaMaps) (m.id, m.name),
          ])
            ChoiceChip(
              label: Text(name),
              selected: _pickMap == id,
              onSelected: (_) => setState(() => _pickMap = id),
            ),
        ],
      ),
    ],
  );

  Widget _netStatus() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_netBusy)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text('Connecting…', style: TextStyle(color: Colors.white70)),
        ),
      if (_netError != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            _netError!,
            style: const TextStyle(color: Color(0xFFFF8A80)),
          ),
        ),
    ],
  );

  Widget _buildOnlinePanel() {
    const color = Color(0xFF42A5F5);
    final hasPlayer = _save.name.trim().isNotEmpty;
    final me = Row(
      children: [
        AvatarPreview(avatar: _save.avatar, height: 64),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            hasPlayer ? _save.name : 'No player yet',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: _editPlayer,
          icon: const Icon(Icons.edit_rounded, size: 18),
          label: Text(hasPlayer ? 'Change' : 'Make'),
        ),
      ],
    );

    if (!hasPlayer) {
      return _panelShell(color, [
        _panelTitle(
          'Find Players',
          'First pick a name and make your player, so everyone knows '
              'who they are fighting!',
          color,
        ),
        const SizedBox(height: 12),
        me,
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _editPlayer,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('MAKE MY PLAYER'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _closePanel,
            child: const Text('Close'),
          ),
        ),
      ]);
    }

    if (_browsing) {
      final rooms = _waitingRooms;
      return _panelShell(color, [
        _panelTitle(
          'People waiting',
          'Tap someone to play against them.',
          color,
        ),
        const SizedBox(height: 10),
        if (rooms == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (rooms.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Nobody is waiting right now. Go back and make a room, '
              'then people can find you here!',
              style: TextStyle(color: Colors.white),
            ),
          )
        else
          for (final r in rooms) _roomTile(r),
        _netStatus(),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _netBusy ? null : () => setState(_stopBrowsing),
            child: const Text('Back'),
          ),
        ),
      ]);
    }

    return _panelShell(color, [
      _panelTitle(
        'Find Players',
        'Play real people online! Make a room, pick 1v1 to 4v4 and give '
            'friends the code. It starts when everyone is in.',
        color,
      ),
      const SizedBox(height: 12),
      me,
      _mapPicker(),
      const SizedBox(height: 12),
      const Text(
        'Room size',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var n = 1; n <= 4; n++)
            ChoiceChip(
              label: Text('${n}v$n'),
              selected: _roomSize == n,
              onSelected: (_) => setState(() => _roomSize = n),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _netBusy
                  ? null
                  : () => _goOnline(teamSize: _roomSize, showCode: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('MAKE A ROOM'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: _netBusy ? null : _startBrowsing,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF66BB6A),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('JOIN'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _codeBox,
              maxLength: 4,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                color: Colors.white,
                letterSpacing: 4,
                fontWeight: FontWeight.w800,
              ),
              decoration: const InputDecoration(
                labelText: 'Got a room code?',
                counterText: '',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: _netBusy ? null : _joinByCode,
            child: const Text('GO'),
          ),
        ],
      ),
      _netStatus(),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _closePanel,
          child: const Text('Close'),
        ),
      ),
    ]);
  }

  void _joinByCode() {
    final code = _codeBox.text.trim().toUpperCase();
    if (code.length != 4) {
      setState(() => _netError = 'Room codes have 4 letters.');
      return;
    }
    _goOnline(joinCode: code);
  }

  Widget _roomTile(RoomInfo r) {
    final map = mapById(r.mapId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFF1B2138),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _netBusy ? null : () => _goOnline(joinCode: r.code),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
            child: Row(
              children: [
                AvatarPreview(avatar: Avatar.fromList(r.avatar), height: 56),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        r.teamSize > 0
                            ? '${map.name} · ${r.players}/${r.teamSize * 2} in'
                            : '${map.name} · ${r.players} '
                                  '${r.players == 1 ? 'player' : 'players'}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: r.playing
                        ? const Color(0xFFFFA726)
                        : const Color(0xFF66BB6A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    r.playing
                        ? 'PLAYING'
                        : (r.teamSize > 0
                              ? '${r.teamSize}V${r.teamSize}'
                              : 'WAITING'),
                    style: const TextStyle(
                      color: kOutplayInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPadPanel() {
    final pad = _panel!;
    if (pad == 'O') return _buildOnlinePanel();
    if (pad == 'Q') return _buildQuickPanel();
    const color = Color(0xFFFFA726);
    return _panelShell(color, [
      _panelTitle(
        'Free-for-all',
        'Everyone against everyone. First to $_ffaKillsToWin KOs wins.',
        color,
      ),
      _mapPicker(),
      const SizedBox(height: 12),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Players',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: _pickBots > 1 ? () => setState(() => _pickBots--) : null,
            icon: const Icon(
              Icons.remove_circle_outline_rounded,
              color: Colors.white,
            ),
          ),
          Text(
            '${_pickBots + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          IconButton(
            onPressed: _pickBots < 19
                ? () => setState(() => _pickBots++)
                : null,
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: Colors.white,
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _closePanel,
              child: const Text('Not now'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () => _launch(OutplayMode.freeForAll),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('PLAY'),
            ),
          ),
        ],
      ),
    ]);
  }

  /// Quick Play, one question at a time: how big, AI or human, which map.
  Widget _buildQuickPanel() {
    const color = Color(0xFF66BB6A);
    Widget big(String label, VoidCallback onTap, {IconData? icon, Color? bg}) =>
        ElevatedButton(
          onPressed: _netBusy ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: bg ?? color,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon), const SizedBox(width: 8)],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        );
    Widget back(VoidCallback onTap) => SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _netBusy ? null : onTap,
        child: const Text('Back'),
      ),
    );
    final size = '${_qpSize}v$_qpSize';

    switch (_qpStep) {
      case 0:
        return _panelShell(color, [
          _panelTitle('Quick Play', 'What do you want to play?', color),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.6,
            children: [
              for (var n = 1; n <= 4; n++)
                big(
                  '${n}v$n',
                  () => setState(() {
                    _qpSize = n;
                    _qpStep = 1;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _closePanel,
              child: const Text('Not now'),
            ),
          ),
        ]);
      case 1:
        return _panelShell(color, [
          _panelTitle('Quick Play $size', 'AI or human?', color),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: big(
                  'AI',
                  () => setState(() {
                    _qpHuman = false;
                    _qpStep = 3;
                  }),
                  icon: Icons.smart_toy_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: big(
                  'HUMAN',
                  () => setState(() {
                    _qpHuman = true;
                    _qpStep = 2;
                  }),
                  icon: Icons.person_rounded,
                  bg: const Color(0xFF42A5F5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          back(() => setState(() => _qpStep = 0)),
        ]);
      case 3:
        const levels = [
          ('EASY', Color(0xFF66BB6A), Icons.sentiment_satisfied_rounded),
          ('MEDIUM', Color(0xFFFFB300), Icons.sentiment_neutral_rounded),
          ('HARD', Color(0xFFE53935), Icons.local_fire_department_rounded),
        ];
        return _panelShell(color, [
          _panelTitle('Quick Play $size · AI', 'How hard?', color),
          const SizedBox(height: 14),
          for (var i = 0; i < levels.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: big(
                  levels[i].$1,
                  () => setState(() {
                    _qpLevel = i;
                    _qpStep = 2;
                  }),
                  icon: levels[i].$3,
                  bg: levels[i].$2,
                ),
              ),
            ),
          back(() => setState(() => _qpStep = 1)),
        ]);
      default:
        return _panelShell(color, [
          _panelTitle(
            'Quick Play $size · '
            '${_qpHuman ? 'Human' : 'AI · ${const ['Easy', 'Medium', 'Hard'][_qpLevel]}'}',
            _qpHuman
                ? 'Pick a map. You will play people who picked the same map.'
                : 'Pick a map.',
            color,
          ),
          _mapPicker(),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: big('PLAY', _startQuickPlay, icon: Icons.play_arrow_rounded),
          ),
          if (_netBusy)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _qpSize == 1
                    ? 'Looking for someone to fight…'
                    : 'Looking for players…',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          if (_netError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _netError!,
                style: const TextStyle(color: Color(0xFFFF8A80)),
              ),
            ),
          const SizedBox(height: 10),
          back(
            () => setState(() {
              _qpStep = _qpHuman ? 1 : 3;
              _netError = null;
            }),
          ),
        ]);
    }
  }

  void _startQuickPlay() {
    if (_qpHuman) {
      _quickMatch(_qpSize);
    } else if (_qpSize == 1) {
      _launch(OutplayMode.duel);
    } else {
      _launch(OutplayMode.teams);
    }
  }
}

// ===========================================================================
// Drawing the first-person view.
// ===========================================================================

class _Sprite {
  final double dist;
  final void Function(Canvas canvas) draw;
  _Sprite(this.dist, this.draw);
}

class _ViewPainter extends CustomPainter {
  final _OutplayGameScreenState s;
  _ViewPainter(this.s);

  late double _w, _h, _horizon, _proj, _camZ;
  late Offset _cam, _dir, _plane;
  late List<double> _zbuf;
  late double _colW;

  OutplayMap get map => s._map;

  @override
  void paint(Canvas canvas, Size size) {
    _w = size.width;
    _h = size.height;
    if (_w <= 0 || _h <= 0) return;
    final you = s._you;
    _horizon = _h * 0.5;
    _proj = (_w / 2) / tan(_fov / 2);
    final bob = you.grounded ? sin(you.walkCycle) * 0.012 : 0.0;
    _camZ = 0.5 + you.z + bob;
    _cam = you.pos;
    _dir = Offset(cos(you.angle), sin(you.angle));
    _plane = Offset(-_dir.dy, _dir.dx) * tan(_fov / 2);

    _paintSky(canvas);
    _paintFloor(canvas);
    _paintWalls(canvas);
    _paintStrap(canvas);
    _paintRopes(canvas);
    _paintSprites(canvas);
    _paintTracers(canvas);
    _paintHooks(canvas);
    _paintWeapon(canvas);
    _paintOverlays(canvas);
    _paintMiniMap(canvas);
    _paintMoveStick(canvas);
  }

  void _paintSky(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, _w, _horizon + 2);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [map.skyTop, map.skyBottom],
        ).createShader(rect),
    );
    if (map.hazard == MapHazard.lava) {
      // Smoke puffs drifting from the crater.
      final t = s._clock;
      for (var i = 0; i < 6; i++) {
        final x = ((i * 0.19 + t * 0.01 + s._you.angle / (2 * pi)) % 1) * _w;
        canvas.drawCircle(
          Offset(x, _horizon * (0.25 + 0.1 * (i % 3))),
          _w * 0.08,
          Paint()..color = const Color(0x33212121),
        );
      }
    } else if (map.id == 'arena') {
      // Big lights hanging over the ring.
      for (var i = 0; i < 5; i++) {
        final x =
            ((i * 0.21 - s._you.angle / (2 * pi)) % 1) * _w * 1.4 - _w * 0.2;
        canvas.drawCircle(
          Offset(x, _horizon * 0.35),
          18,
          Paint()..color = const Color(0x66FFF9C4),
        );
        canvas.drawCircle(
          Offset(x, _horizon * 0.35),
          7,
          Paint()..color = const Color(0xFFFFFDE7),
        );
      }
    } else if (map.hazard == MapHazard.cars ||
        map.hazard == MapHazard.water ||
        map.hazard == MapHazard.karts ||
        map.id == 'courtyard') {
      final x = ((0.3 - s._you.angle / (2 * pi)) % 1) * _w * 2 - _w * 0.5;
      canvas.drawCircle(
        Offset(x, _horizon * 0.3),
        26,
        Paint()..color = const Color(0xFFFFF59D),
      );
    }
  }

  Color _floorColor(double x, double y) {
    final cx = x.floor(), cy = y.floor();
    final c = map.cell(cx, cy);
    final t = s._clock;
    if (c == 'Q') return const Color(0xFF66BB6A);
    if (c == 'F') return const Color(0xFFFFA726);
    if (c == 'O') return const Color(0xFF42A5F5);
    if (map.hazard == MapHazard.lava && map.isLava(Offset(x, y), t)) {
      final glow = 0.5 + 0.5 * sin(t * 2.4 + x * 1.3 + y * 0.9);
      return Color.lerp(
        const Color(0xFFD84315),
        const Color(0xFFFFB300),
        glow,
      )!;
    }
    if (map.hazard == MapHazard.cars &&
        y >= OutplayMap.roadTop &&
        y <= OutplayMap.roadBottom) {
      final mid = (OutplayMap.roadTop + OutplayMap.roadBottom) / 2;
      if ((y - mid).abs() < 0.08 && (x % 2) < 1) return const Color(0xFFFFEB3B);
      if (y - OutplayMap.roadTop < 0.12 || OutplayMap.roadBottom - y < 0.12) {
        return Colors.white;
      }
      return const Color(0xFF424242);
    }
    if (map.hazard == MapHazard.water) {
      final d = map.lakeDistance(Offset(x, y));
      if (d < 1) {
        // Rippling lake water, deeper blue in the middle.
        final ripple = 0.5 + 0.5 * sin(t * 1.8 + x * 2.1 + y * 1.4);
        return Color.lerp(
          Color.lerp(
            const Color(0xFF0277BD),
            const Color(0xFF29B6F6),
            (d * d).clamp(0.0, 1.0),
          ),
          const Color(0xFF81D4FA),
          ripple * 0.25,
        )!;
      }
      if (d < 1.16) return const Color(0xFFFFE082); // sandy beach
    }
    if (map.hazard == MapHazard.karts) {
      final off = map.trackOffset(Offset(x, y));
      if (off.abs() < OutplayMap.trackHalfWidth) {
        // Red and white kerbs along both edges.
        if (off.abs() > OutplayMap.trackHalfWidth - 0.25) {
          return ((x + y) * 1.4).floor().isEven
              ? const Color(0xFFE53935)
              : Colors.white;
        }
        // A chequered start line across the top straight.
        if ((x - map.centre.dx).abs() < 0.4 && y < map.centre.dy) {
          return ((x * 2.5).floor() + (y * 2.5).floor()).isEven
              ? Colors.white
              : const Color(0xFF212121);
        }
        return const Color(0xFF546E7A);
      }
    }
    final ring = _ring;
    if (ring != null && ring.inflate(0.2).contains(Offset(x, y))) {
      // The ring canvas, with a white edge.
      final inner = ring.deflate(0.25);
      return inner.contains(Offset(x, y))
          ? ((cx + cy).isEven
                ? const Color(0xFF1565C0)
                : const Color(0xFF1976D2))
          : Colors.white;
    }
    if (map.hazard == MapHazard.bouncy) {
      // The bumpy croc footbed.
      final fx = x - cx - 0.5, fy = y - cy - 0.5;
      if (fx * fx + fy * fy < 0.03) return const Color(0xFFA9D672);
    }
    return (cx + cy).isEven ? map.floorA : map.floorB;
  }

  void _paintFloor(Canvas canvas) {
    final rowH = max(4.0, _h / 110);
    const cols = 72;
    final colW = _w / cols;
    final left = _dir - _plane;
    final right = _dir + _plane;
    final paint = Paint();
    for (var y = _horizon; y < _h; y += rowH) {
      final p = y + rowH / 2 - _horizon;
      final rowDist = _camZ * _proj / p;
      final fog = (rowDist / 14).clamp(0.0, 0.7);
      var runStart = 0;
      Color? runColor;
      for (var i = 0; i <= cols; i++) {
        Color? c;
        if (i < cols) {
          final f = (i + 0.5) / cols;
          final ray = left + (right - left) * f;
          final wx = _cam.dx + ray.dx * rowDist;
          final wy = _cam.dy + ray.dy * rowDist;
          c = Color.lerp(_floorColor(wx, wy), map.skyBottom, fog);
        }
        if (c != runColor) {
          if (runColor != null) {
            paint.color = runColor;
            canvas.drawRect(
              Rect.fromLTWH(
                runStart * colW,
                y,
                (i - runStart) * colW + 0.6,
                rowH + 0.6,
              ),
              paint,
            );
          }
          runColor = c;
          runStart = i;
        }
      }
    }
  }

  late final Rect? _ring = map.ring?.inflate(0.0);

  Color _wallColor(String c) {
    switch (c) {
      case 'R':
        return const Color(0xFFB5523B);
      case 'B':
        return const Color(0xFF5C6BC0);
      case 'C':
        return const Color(0xFFB98A55);
      case 'K':
        return const Color(0xFF4E3B36);
      case 'W':
        return const Color(0xFF4A2C5E);
      case 'D':
        return const Color(0xFF5D4037);
      case 'X':
        return const Color(0xFF7CB342);
      case 'J':
        return const Color(0xFFFFCA28);
      case 'A':
        return const Color(0xFF263238);
      case 'P':
        return const Color(0xFFE53935);
      case 'U':
        return const Color(0xFF1E88E5);
      case 'N':
        return const Color(0xFFECEFF1);
      case 'G':
        return const Color(0xFF2E7D32);
      case 'Y':
        return const Color(0xFF37474F);
      case 'H':
        return const Color(0xFFE6C065);
      default:
        return const Color(0xFF8A93A8);
    }
  }

  void _paintWalls(Canvas canvas) {
    final rays = (_w / 3).round().clamp(90, 220);
    _colW = _w / rays;
    _zbuf = List.filled(rays, 1e9);
    final paint = Paint();
    final edge = Paint();
    for (var i = 0; i < rays; i++) {
      final f = (i + 0.5) / rays * 2 - 1;
      final ray = _dir + _plane * f;
      final hit = s._cast(_cam, ray.direction);
      // Straighten the fish-eye: use distance along the view direction.
      final perp = max(
        0.05,
        hit.dist * (ray.dx * _dir.dx + ray.dy * _dir.dy) / ray.distance,
      );
      _zbuf[i] = perp;
      final top = _horizon + (_camZ - map.wallHeight) * _proj / perp;
      final bottom = _horizon + _camZ * _proj / perp;
      var color = _wallColor(hit.cell);
      if (hit.side == 1) color = Color.lerp(color, Colors.black, 0.22)!;
      // Darker block edges so walls look like blocks.
      if (hit.wallX < 0.06 || hit.wallX > 0.94) {
        color = Color.lerp(color, Colors.black, 0.3)!;
      }
      color = Color.lerp(color, map.skyBottom, (perp / 16).clamp(0.0, 0.65))!;
      paint.color = color;
      final x = i * _colW;
      canvas.drawRect(Rect.fromLTRB(x, top, x + _colW + 0.6, bottom), paint);
      final wallH = bottom - top;
      if (hit.cell == 'W' && (hit.wallX * 6).floor().isEven) {
        // Stripy old wallpaper.
        edge.color = Color.lerp(color, Colors.white, 0.08)!;
        canvas.drawRect(Rect.fromLTRB(x, top, x + _colW + 0.6, bottom), edge);
      }
      if (hit.cell == 'Y') {
        // Stacks of tyres with red and white bands.
        final band = (hit.wallX * 4).floor().isEven
            ? const Color(0xFFE53935)
            : Colors.white;
        edge.color = Color.lerp(
          band,
          map.skyBottom,
          (perp / 16).clamp(0.0, 0.65),
        )!;
        canvas.drawRect(
          Rect.fromLTWH(x, top + wallH * 0.42, _colW + 0.6, wallH * 0.16),
          edge,
        );
      }
      if (hit.cell == 'H') {
        // Straw lines on the hay bales.
        edge.color = Color.lerp(color, Colors.brown, 0.3)!;
        for (final f in [0.3, 0.7]) {
          canvas.drawRect(
            Rect.fromLTWH(x, top + wallH * f, _colW + 0.6, wallH * 0.05),
            edge,
          );
        }
      }
      if (hit.cell == 'D') {
        // Bookshelves: shelves with coloured books.
        for (var r = 0; r < 4; r++) {
          final y0 = top + wallH * (0.08 + r * 0.23);
          final book = ((hit.wallX * 9).floor() + r * 3) % 4;
          edge.color = Color.lerp(
            const [
              Color(0xFFC62828),
              Color(0xFF2E7D32),
              Color(0xFF1565C0),
              Color(0xFFF9A825),
            ][book],
            map.skyBottom,
            (perp / 16).clamp(0.0, 0.65),
          )!;
          canvas.drawRect(
            Rect.fromLTWH(x, y0, _colW + 0.6, wallH * 0.18),
            edge,
          );
        }
      }
      if (hit.cell == 'X' || hit.cell == 'J') {
        // The round holes in a croc, in rows up the wall.
        edge.color = Color.lerp(color, Colors.black, 0.45)!;
        final perUnit = wallH / map.wallHeight; // screen size of 1 block
        final dx = ((hit.wallX * 3) % 1 - 0.5) / 0.3;
        if (dx.abs() < 1) {
          final half = sqrt(1 - dx * dx) * perUnit * 0.1;
          final holeRows = max(2, (map.wallHeight * 2.5).round());
          for (var r = 0; r < holeRows; r++) {
            // Stagger every other row like the real thing.
            if (r.isOdd && ((hit.wallX * 3).floor().isEven)) continue;
            final cy = top + wallH * (r + 0.7) / (holeRows + 0.4);
            canvas.drawRect(
              Rect.fromLTRB(x, cy - half, x + _colW + 0.6, cy + half),
              edge,
            );
          }
        }
        // The rounded rim along the top.
        edge.color = Color.lerp(color, Colors.white, 0.18)!;
        canvas.drawRect(
          Rect.fromLTWH(x, top, _colW + 0.6, max(1, perUnit * 0.12)),
          edge,
        );
      }
      if (hit.cell == 'A') {
        // Rows of cheering fans in the stands.
        const shirts = [
          Color(0xFFEF5350),
          Color(0xFFFFCA28),
          Color(0xFF42A5F5),
          Color(0xFF66BB6A),
          Color(0xFFAB47BC),
          Color(0xFFFFFFFF),
        ];
        final col = (hit.wallX * 5).floor();
        final fx = (hit.wallX * 5) % 1;
        if (fx > 0.15 && fx < 0.85) {
          for (var r = 0; r < 4; r++) {
            final seed = (col * 7 + r * 13 + hit.cell.hashCode) % shirts.length;
            final bounce = sin(s._clock * 6 + col + r * 2) > 0.6 ? 0.03 : 0.0;
            final y0 = top + wallH * (0.12 + r * 0.22 - bounce);
            edge.color = Color.lerp(
              shirts[seed],
              map.skyBottom,
              (perp / 16).clamp(0.0, 0.6),
            )!;
            canvas.drawRect(
              Rect.fromLTWH(x, y0 + wallH * 0.06, _colW + 0.6, wallH * 0.09),
              edge,
            );
            if (fx > 0.3 && fx < 0.7) {
              edge.color = Color.lerp(
                const Color(0xFFFFCC80),
                map.skyBottom,
                (perp / 16).clamp(0.0, 0.6),
              )!;
              canvas.drawRect(
                Rect.fromLTWH(x, y0, _colW + 0.6, wallH * 0.06),
                edge,
              );
            }
          }
        }
      }
      // Brick and crate details.
      if (hit.cell == 'R' || hit.cell == 'C') {
        edge.color = Color.lerp(color, Colors.black, 0.25)!;
        final rows = hit.cell == 'R' ? 4 : 3;
        for (var r = 1; r < rows; r++) {
          final yy = top + (bottom - top) * r / rows;
          canvas.drawRect(
            Rect.fromLTWH(x, yy, _colW + 0.6, max(1, (bottom - top) / 60)),
            edge,
          );
        }
      }
    }
  }

  /// The boxing ring's ropes, hidden where a post or wall is in front.
  void _paintRopes(Canvas canvas) {
    final ring = _ring;
    if (ring == null) return;
    final corners = [
      ring.topLeft,
      ring.topRight,
      ring.bottomRight,
      ring.bottomLeft,
    ];
    const colours = [Color(0xFFE53935), Colors.white, Color(0xFF1E88E5)];
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var side = 0; side < 4; side++) {
      final a = corners[side], b = corners[(side + 1) % 4];
      for (var r = 0; r < 3; r++) {
        final z = 0.35 + r * 0.22;
        paint.color = colours[r];
        const steps = 20;
        for (var i = 0; i < steps; i++) {
          final p0 = Offset.lerp(a, b, i / steps)!;
          final p1 = Offset.lerp(a, b, (i + 1) / steps)!;
          final t = _toCamera((p0 + p1) / 2);
          if (t.dy < 0.2) continue;
          final s0 = _project(p0, z), s1 = _project(p1, z);
          if (s0 == null || s1 == null) continue;
          final col = (((s0.dx + s1.dx) / 2) / _colW).floor();
          if (col >= 0 && col < _zbuf.length && _zbuf[col] < t.dy) continue;
          paint.strokeWidth = (_proj / t.dy * 0.03).clamp(1.0, 4.0);
          canvas.drawLine(s0, s1, paint);
        }
      }
    }
  }

  /// The croc's heel strap, arching over the back of the shoe.
  void _paintStrap(Canvas canvas) {
    final sx = map.strapX;
    if (sx == null) return;
    final col = sx.floor();
    var y0 = -1, y1 = -1;
    for (var y = 0; y < map.height; y++) {
      if (!map.solidAt(col, y)) {
        if (y0 < 0) y0 = y;
        y1 = y;
      }
    }
    if (y0 < 0) return;
    final a = y0.toDouble(), b = y1 + 1.0;
    final h = map.wallHeight;
    const steps = 24;
    final band = Paint()..color = const Color(0xFF689F38);
    final ink = Paint()
      ..color = kOutplayInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    Offset world(double t) => Offset(sx + sin(pi * t) * 2.6, a + (b - a) * t);
    double height(double t) => h - 0.15 + sin(pi * t) * 0.9;
    for (var i = 0; i < steps; i++) {
      final t0 = i / steps, t1 = (i + 1) / steps;
      final p0 = world(t0), p1 = world(t1);
      final q = [
        _project(p0, height(t0)),
        _project(p1, height(t1)),
        _project(p1, height(t1) + 0.55),
        _project(p0, height(t0) + 0.55),
      ];
      if (q.any((e) => e == null)) continue;
      final path = Path()..addPolygon([for (final e in q) e!], true);
      canvas.drawPath(path, band);
      canvas.drawPath(path, ink);
    }
    // The round rivets that hold the strap on.
    for (final t in [0.0, 1.0]) {
      final c = _project(world(t), height(t) + 0.27);
      final edge = _project(world(t) + const Offset(0.3, 0), height(t) + 0.27);
      if (c == null || edge == null) continue;
      final r = max(3.0, (edge - c).distance);
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFFFFCA28));
      canvas.drawCircle(c, r, ink);
    }
  }

  /// Camera-space position of a world point: (sideways, forward).
  Offset _toCamera(Offset p) {
    final d = p - _cam;
    final inv = 1 / (_plane.dx * _dir.dy - _dir.dx * _plane.dy);
    final tx = inv * (_dir.dy * d.dx - _dir.dx * d.dy);
    final ty = inv * (-_plane.dy * d.dx + _plane.dx * d.dy);
    return Offset(tx, ty);
  }

  /// Where a world point at height [z] appears on screen, or null if behind.
  Offset? _project(Offset p, double z) {
    final t = _toCamera(p);
    if (t.dy < 0.15) return null;
    final sx = _w / 2 * (1 + t.dx / t.dy);
    final sy = _horizon + (_camZ - z) * _proj / t.dy;
    return Offset(sx, sy);
  }

  void _paintSprites(Canvas canvas) {
    final sprites = <_Sprite>[];

    void billboard(
      Offset pos,
      double z0,
      double height,
      double width,
      void Function(Canvas, Rect, double scale) draw,
    ) {
      final t = _toCamera(pos);
      if (t.dy < 0.2) return;
      final sx = _w / 2 * (1 + t.dx / t.dy);
      final scale = _proj / t.dy;
      final top = _horizon + (_camZ - z0 - height) * scale;
      final bottom = _horizon + (_camZ - z0) * scale;
      final halfW = width * scale / 2;
      final rect = Rect.fromLTRB(sx - halfW, top, sx + halfW, bottom);
      if (rect.right < 0 || rect.left > _w) return;
      sprites.add(
        _Sprite(t.dy, (c) {
          // Only draw the parts not hidden behind walls.
          final clip = Path();
          final first = max(0, (rect.left / _colW).floor());
          final last = min(_zbuf.length - 1, (rect.right / _colW).floor());
          var any = false;
          for (var i = first; i <= last; i++) {
            if (_zbuf[i] > t.dy) {
              clip.addRect(Rect.fromLTWH(i * _colW, 0, _colW + 0.8, _h));
              any = true;
            }
          }
          if (!any) return;
          c.save();
          c.clipPath(clip);
          draw(c, rect, scale);
          c.restore();
        }),
      );
    }

    for (final p in s._people) {
      if (p.isYou || !p.alive) continue;
      billboard(
        p.pos,
        p.z,
        0.92,
        0.62,
        (c, r, scale) => _drawPerson(c, p, r, scale),
      );
    }
    for (final car in s._cars) {
      billboard(car.pos, 0, 0.72, 1.5, (c, r, scale) => _drawCar(c, car, r));
    }
    for (final k in s._karts) {
      billboard(k.pos, 0, 0.62, 1.0, (c, r, scale) => _drawKart(c, k, r));
    }
    final ghosts = s._ghosts;
    for (var i = 0; i < ghosts.length; i++) {
      final bob = 0.25 + 0.12 * sin(s._clock * 2 + i);
      billboard(ghosts[i], bob, 0.75, 0.6, (c, r, scale) => _drawGhost(c, r));
    }
    for (final b in s._balls) {
      if (b.gun.look == WeaponLook.rpgMini) {
        // A little rocket with a fiery tail.
        billboard(b.pos, 0.36, 0.16, 0.16, (c, r, scale) {
          c.drawCircle(
            r.center,
            r.width * 0.9,
            Paint()
              ..color = const Color(0x99FFAB00)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, r.width * 0.3),
          );
          c.drawOval(r, Paint()..color = const Color(0xFF455A64));
          c.drawCircle(
            r.center,
            r.width * 0.28,
            Paint()..color = const Color(0xFFFF6D00),
          );
        });
        continue;
      }
      final size = b.gun.look == WeaponLook.bubble ? 0.42 : 0.24;
      billboard(b.pos, 0.38, size, size, (c, r, scale) {
        c.drawOval(r, Paint()..color = b.gun.shotColor.withValues(alpha: 0.85));
        c.drawOval(
          r,
          Paint()
            ..color = Colors.black26
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1, r.width * 0.06),
        );
      });
    }
    for (final p in s._pops) {
      final k = p.t / 0.35;
      final r = p.radius * (0.5 + k);
      billboard(p.pos, 0.2, r, r * 2, (c, rect, scale) {
        c.drawOval(
          rect,
          Paint()..color = p.color.withValues(alpha: 0.5 * (1 - k)),
        );
      });
    }
    if (s._lobby) {
      for (final pad in const [
        ('Q', 'QUICK PLAY', Color(0xFF66BB6A)),
        ('F', 'FREE-FOR-ALL', Color(0xFFFFA726)),
        ('O', 'FIND PLAYERS', Color(0xFF42A5F5)),
      ]) {
        final at = map.padCentre(pad.$1);
        if (at == null) continue;
        // Signs stand just behind their pad.
        billboard(
          at + const Offset(0, -0.7),
          0.25,
          1.0,
          1.6,
          (c, r, scale) => _drawSign(c, r, pad.$2, pad.$3),
        );
      }
    }
    for (final p in s._popups) {
      billboard(p.pos, 1.0 + p.t * 0.6, 0.25, 0.6, (c, r, scale) {
        _text(
          c,
          p.text,
          r.center,
          (r.height).clamp(10.0, 30.0),
          p.color.withValues(alpha: 1 - p.t / 0.7),
        );
      });
    }

    sprites.sort((a, b) => b.dist.compareTo(a.dist));
    for (final sp in sprites) {
      sp.draw(canvas);
    }
  }

  void _drawPerson(Canvas c, _Person p, Rect r, double scale) {
    final w = r.width, h = r.height;
    final step = sin(p.walkCycle) * w * 0.08;

    // Which way are they facing compared to you?
    final toYou = (s._you.pos - p.pos).direction;
    final facing =
        cos(_OutplayGameScreenState._angleDiff(p.angle, toYou)) > -0.2;

    paintAvatar(c, p.look, r, facing: facing, step: step, hurt: p.hurtT > 0);
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(r.left + w * 0.18, r.top + h * 0.3, w * 0.64, h * 0.34),
      Radius.circular(w * 0.12),
    );
    if (facing) {
      // What they're holding, pointed at you.
      c.save();
      c.translate(r.center.dx, r.top + h * 0.5);
      c.rotate(-pi / 2 + 0.3);
      final g = p.gun;
      paintWeapon(
        c,
        g?.look ?? p.held.look,
        g?.color ?? p.held.color,
        w * 0.6,
        skin: p.skinOf(p.heldId),
      );
      c.restore();
      if (p.flashT > 0) {
        c.drawCircle(
          Offset(r.center.dx + w * 0.05, r.top + h * 0.38),
          w * 0.14,
          Paint()..color = const Color(0xDDFFF176),
        );
      }
    }
    if (p.slowT > 0) {
      c.drawRRect(body, Paint()..color = const Color(0x6681D4FA));
    }

    // Name and health above their head.
    final tag = Offset(r.center.dx, r.top - max(10, h * 0.1));
    _text(
      c,
      p.name,
      tag - Offset(0, max(9, h * 0.07)),
      (h * 0.11).clamp(9.0, 16.0),
      // Teammates' names are blue.
      s._allies(p, s._you) ? const Color(0xFF80D8FF) : Colors.white,
    );
    final barW = max(30.0, w * 0.9);
    final bar = Rect.fromCenter(
      center: tag,
      width: barW,
      height: max(4, h * 0.035),
    );
    c.drawRect(bar, Paint()..color = Colors.black54);
    c.drawRect(
      Rect.fromLTWH(bar.left, bar.top, bar.width * p.hp / 100, bar.height),
      Paint()
        ..color = s._allies(p, s._you)
            ? const Color(0xFF40C4FF)
            : const Color(0xFFEF5350),
    );
  }

  void _drawGhost(Canvas c, Rect r) {
    final w = r.width, h = r.height;
    final body = Path()
      ..moveTo(r.left, r.bottom)
      ..lineTo(r.left, r.top + w / 2)
      ..arcToPoint(
        Offset(r.right, r.top + w / 2),
        radius: Radius.circular(w / 2),
      )
      ..lineTo(r.right, r.bottom);
    // Wavy bottom edge.
    for (var i = 1; i <= 4; i++) {
      final x = r.right - w * i / 4;
      body.lineTo(x + w / 8, r.bottom - h * (i.isOdd ? 0.12 : 0));
      body.lineTo(x, r.bottom);
    }
    body.close();
    c.drawPath(body, Paint()..color = const Color(0xCCF3E5F5));
    c.drawPath(
      body,
      Paint()
        ..color = const Color(0x88311B92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1, w * 0.04),
    );
    final eye = Paint()..color = const Color(0xFF1A1033);
    c.drawOval(
      Rect.fromCenter(
        center: Offset(r.center.dx - w * 0.17, r.top + h * 0.33),
        width: w * 0.15,
        height: h * 0.14,
      ),
      eye,
    );
    c.drawOval(
      Rect.fromCenter(
        center: Offset(r.center.dx + w * 0.17, r.top + h * 0.33),
        width: w * 0.15,
        height: h * 0.14,
      ),
      eye,
    );
    c.drawOval(
      Rect.fromCenter(
        center: Offset(r.center.dx, r.top + h * 0.55),
        width: w * 0.2,
        height: h * 0.16,
      ),
      eye,
    );
  }

  void _drawCar(Canvas c, _Car car, Rect r) {
    final w = r.width, h = r.height;
    final ink = Paint()
      ..color = kOutplayInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1, w * 0.015);
    final bodyR = RRect.fromRectAndRadius(
      Rect.fromLTWH(r.left, r.top + h * 0.35, w, h * 0.45),
      Radius.circular(h * 0.12),
    );
    final roof = RRect.fromRectAndRadius(
      Rect.fromLTWH(r.left + w * 0.2, r.top, w * 0.6, h * 0.42),
      Radius.circular(h * 0.15),
    );
    c.drawRRect(roof, Paint()..color = car.color);
    c.drawRRect(roof, ink);
    c.drawRect(
      Rect.fromLTWH(r.left + w * 0.26, r.top + h * 0.07, w * 0.48, h * 0.26),
      Paint()..color = const Color(0xFFB3E5FC),
    );
    c.drawRRect(bodyR, Paint()..color = car.color);
    c.drawRRect(bodyR, ink);
    for (final fx in [0.2, 0.8]) {
      final wheel = Offset(r.left + w * fx, r.top + h * 0.82);
      c.drawCircle(wheel, h * 0.17, Paint()..color = const Color(0xFF212121));
      c.drawCircle(wheel, h * 0.07, Paint()..color = const Color(0xFF9E9E9E));
    }
    c.drawCircle(
      Offset(r.left + w * 0.06, r.top + h * 0.5),
      h * 0.06,
      Paint()..color = const Color(0xFFFFF59D),
    );
    c.drawCircle(
      Offset(r.right - w * 0.06, r.top + h * 0.5),
      h * 0.06,
      Paint()..color = const Color(0xFFFFF59D),
    );
  }

  /// A go-kart with a goat driving it.
  void _drawKart(Canvas c, _Kart k, Rect r) {
    final w = r.width, h = r.height;
    final ink = Paint()
      ..color = kOutplayInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1, w * 0.02);
    // Goat: white head, curly horns, little beard.
    final head = Rect.fromLTWH(
      r.left + w * 0.36,
      r.top + h * 0.1,
      w * 0.28,
      h * 0.34,
    );
    for (final side in [-1.0, 1.0]) {
      final horn = Path()
        ..moveTo(head.center.dx + side * w * 0.06, head.top + h * 0.04)
        ..quadraticBezierTo(
          head.center.dx + side * w * 0.2,
          head.top - h * 0.12,
          head.center.dx + side * w * 0.2,
          head.top + h * 0.06,
        );
      c.drawPath(
        horn,
        Paint()
          ..color = const Color(0xFF8D6E63)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = max(1.5, w * 0.035),
      );
      // Floppy ears.
      c.drawOval(
        Rect.fromCenter(
          center: Offset(head.center.dx + side * w * 0.17, head.top + h * 0.12),
          width: w * 0.1,
          height: h * 0.06,
        ),
        Paint()..color = const Color(0xFFEEEEEE),
      );
    }
    c.drawOval(head, Paint()..color = const Color(0xFFF5F5F5));
    c.drawOval(head, ink);
    for (final side in [-1.0, 1.0]) {
      c.drawCircle(
        Offset(head.center.dx + side * w * 0.05, head.top + h * 0.13),
        max(1.0, w * 0.02),
        Paint()..color = kOutplayInk,
      );
    }
    final beard = Path()
      ..moveTo(head.center.dx - w * 0.03, head.bottom - h * 0.02)
      ..lineTo(head.center.dx, head.bottom + h * 0.1)
      ..lineTo(head.center.dx + w * 0.03, head.bottom - h * 0.02)
      ..close();
    c.drawPath(beard, Paint()..color = const Color(0xFFBDBDBD));
    // The kart.
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(r.left + w * 0.05, r.top + h * 0.45, w * 0.9, h * 0.33),
      Radius.circular(h * 0.1),
    );
    c.drawRRect(body, Paint()..color = k.color);
    c.drawRRect(body, ink);
    c.drawRect(
      Rect.fromLTWH(r.left + w * 0.4, r.top + h * 0.5, w * 0.2, h * 0.12),
      Paint()..color = Colors.white,
    );
    for (final fx in [0.16, 0.84]) {
      final wheel = Offset(r.left + w * fx, r.top + h * 0.82);
      c.drawCircle(wheel, h * 0.16, Paint()..color = const Color(0xFF212121));
      c.drawCircle(wheel, h * 0.06, Paint()..color = const Color(0xFF9E9E9E));
    }
  }

  void _drawSign(Canvas c, Rect r, String label, Color color) {
    final pole = Rect.fromLTWH(
      r.center.dx - r.width * 0.04,
      r.top + r.height * 0.3,
      r.width * 0.08,
      r.height * 0.7,
    );
    c.drawRect(pole, Paint()..color = const Color(0xFF90A4AE));
    final board = RRect.fromRectAndRadius(
      Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.36),
      Radius.circular(r.height * 0.06),
    );
    c.drawRRect(board, Paint()..color = color);
    c.drawRRect(
      board,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1, r.width * 0.02),
    );
    _text(
      c,
      label,
      board.center,
      (r.height * 0.13).clamp(7.0, 26.0),
      Colors.white,
      maxWidth: r.width * 0.95,
    );
  }

  void _text(
    Canvas c,
    String text,
    Offset centre,
    double size,
    Color color, {
    double? maxWidth,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w900,
          shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth ?? double.infinity);
    tp.paint(c, centre - Offset(tp.width / 2, tp.height / 2));
  }

  Offset get _muzzle => Offset(_w * 0.47, _h * 0.66);

  /// The thrown Sizzler: a wiggly green snake from the thrower's hand to
  /// its head, which is biting whoever it caught.
  void _paintHooks(Canvas canvas) {
    final hooks = [
      ...s._hooks,
      for (final p in s._people)
        if (p.netHook != null)
          _Hook(p, p.netHook!.$1, Offset.zero)
            ..target = p.netHook!.$2 ? p : null,
    ];
    for (final h in hooks) {
      final start = h.owner.isYou ? _muzzle : _project(h.owner.pos, 0.85);
      final end = _project(h.pos, h.target != null ? 0.75 : 0.85);
      if (start == null || end == null) continue;
      final d = end - start;
      if (d.distance < 2) continue;
      final side = Offset(-d.dy, d.dx) / d.distance;
      final wiggle = h.target != null ? 5.0 : 9.0;
      final path = Path()..moveTo(start.dx, start.dy);
      const n = 14;
      for (var i = 1; i <= n; i++) {
        final f = i / n;
        final p =
            start +
            d * f +
            side * (sin(f * pi * 4 + s._clock * 18) * wiggle * (1 - f * 0.5));
        path.lineTo(p.dx, p.dy);
      }
      final width = h.owner.isYou ? 14.0 : 6.0;
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF1B5E20)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width + 3,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF66BB6A)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width,
      );
      // Yellow scales down its back.
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFFEB3B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 0.25,
      );
      // Head with eyes and a red tongue.
      final head = max(6.0, width * 0.9);
      final fwd = d / d.distance;
      canvas.drawCircle(end, head, Paint()..color = const Color(0xFF2E7D32));
      for (final sgn in [-1.0, 1.0]) {
        final eye = end - fwd * head * 0.2 + side * head * 0.45 * sgn;
        canvas.drawCircle(eye, head * 0.28, Paint()..color = Colors.yellow);
        canvas.drawCircle(eye, head * 0.12, Paint()..color = Colors.black);
      }
      final tip = end + fwd * head * 1.7;
      canvas.drawLine(
        end + fwd * head * 0.8,
        tip,
        Paint()
          ..color = Colors.redAccent
          ..strokeWidth = max(1.5, head * 0.18),
      );
    }
  }

  void _paintTracers(Canvas canvas) {
    for (final t in s._tracers) {
      final end = _project(t.end, 0.45) ?? Offset(_w / 2, _horizon);
      final a = 1 - t.t / 0.09;
      if (t.look == WeaponLook.zapper) {
        final path = Path()..moveTo(_muzzle.dx, _muzzle.dy);
        const n = 6;
        for (var i = 1; i <= n; i++) {
          final p = Offset.lerp(_muzzle, end, i / n)!;
          path.lineTo(
            p.dx + (i < n ? (s._rnd.nextDouble() - 0.5) * 18 : 0),
            p.dy,
          );
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = t.color.withValues(alpha: a)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      } else if (t.look == WeaponLook.flamer) {
        for (var i = 0; i < 3; i++) {
          final p = Offset.lerp(_muzzle, end, s._rnd.nextDouble())!;
          canvas.drawCircle(
            p,
            10 + s._rnd.nextDouble() * 16,
            Paint()..color = t.color.withValues(alpha: 0.35 * a),
          );
        }
      } else {
        final colors = t.look == WeaponLook.confetti
            ? [Colors.pink, Colors.yellow, Colors.cyan, Colors.lightGreen]
            : [t.color];
        canvas.drawLine(
          _muzzle,
          end,
          Paint()
            ..color = colors[s._rnd.nextInt(colors.length)].withValues(alpha: a)
            ..strokeWidth = t.look == WeaponLook.laser ? 5 : 2.5
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  void _paintWeapon(Canvas canvas) {
    final you = s._you;
    if (!you.alive) return;
    final gun = you.gun;
    final bobX = sin(you.walkCycle * 0.5) * 6;
    final bobY = (cos(you.walkCycle) * 4).abs();
    canvas.save();
    if (gun != null) {
      canvas.translate(_w * 0.6 + bobX, _h * 0.95 + bobY + s._recoil * 14);
      canvas.rotate(-pi / 2 - 0.38 - s._recoil * 0.08);
      paintWeapon(
        canvas,
        gun.look,
        gun.color,
        min(_w, _h) * 0.68,
        skin: you.skinOf(gun.id),
      );
      if (you.flashT > 0 && gun.look != WeaponLook.flamer) {
        canvas.drawCircle(
          Offset(min(_w, _h) * 0.36, 0),
          16,
          Paint()..color = gun.shotColor.withValues(alpha: 0.8),
        );
      }
    } else if (!s._hooks.any((h) => identical(h.owner, you))) {
      // Melee swings across the screen (the Sizzler leaves your hand
      // while it's thrown).
      final m = you.held;
      final swing = you.swingT > 0 ? sin(you.swingT / 0.22 * pi) : 0.0;
      canvas.translate(
        _w * (0.72 - swing * 0.25) + bobX,
        _h * (0.82 - swing * 0.08) + bobY,
      );
      canvas.rotate(-pi / 2 + 0.5 - swing * 1.1);
      final big =
          m.look == WeaponLook.scythe ||
          m.look == WeaponLook.slapper ||
          m.look == WeaponLook.snake;
      paintWeapon(
        canvas,
        m.look,
        m.color,
        min(_w, _h) * (big ? 0.55 : 0.36),
        skin: you.skinOf(m.id),
      );
    }
    canvas.restore();
  }

  void _paintOverlays(Canvas canvas) {
    final you = s._you;
    final c = Offset(_w / 2, _horizon);
    if (!s._lobby) {
      // Crosshair.
      final aiming = s._people.any((p) {
        if (p.isYou || !p.alive) return false;
        final t = _toCamera(p.pos);
        return t.dy > 0 &&
            (t.dx / t.dy).abs() < 0.06 &&
            s._canSee(you.pos, p.pos);
      });
      final cross = Paint()
        ..color = aiming ? const Color(0xFFFF5252) : Colors.white
        ..strokeWidth = 2.5;
      for (final d in const [
        Offset(1, 0),
        Offset(-1, 0),
        Offset(0, 1),
        Offset(0, -1),
      ]) {
        canvas.drawLine(c + d * 5, c + d * 13, cross);
      }
      if (s._hitMarkT > 0) {
        final hm = Paint()
          ..color = Colors.white
          ..strokeWidth = 3;
        for (final d in const [
          Offset(1, 1),
          Offset(-1, 1),
          Offset(1, -1),
          Offset(-1, -1),
        ]) {
          canvas.drawLine(c + d * 8, c + d * 16, hm);
        }
      }
    }
    final screen = Rect.fromLTWH(0, 0, _w, _h);
    void vignette(Color color) {
      canvas.drawRect(
        screen,
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.transparent, color],
            stops: const [0.55, 1],
          ).createShader(screen),
      );
    }

    if (you.hurtT > 0) vignette(const Color(0xAAFF1744));
    if (you.slowT > 0) vignette(const Color(0x8881D4FA));
    if (you.alive && you.grounded && map.isLava(you.pos, s._clock)) {
      vignette(const Color(0x99FF6D00));
    }
    if (you.alive && you.waterT > 0) {
      // Under the lake: heal at first, then hurry out!
      final healing = you.waterT <= _healTime;
      vignette(healing ? const Color(0x8829B6F6) : const Color(0xAA01579B));
      final left = max(0.0, _drownTime - you.waterT);
      _text(
        canvas,
        healing
            ? 'Healing in the lake…'
            : 'GET OUT! ${left.toStringAsFixed(1)}',
        c + const Offset(0, -70),
        healing ? 18 : 24,
        healing ? Colors.white : const Color(0xFFFF8A80),
      );
      // Bubbles show how much breath is left.
      final bubbles = (left / _drownTime * 5).ceil();
      for (var i = 0; i < 5; i++) {
        final at = c + Offset((i - 2) * 18.0, -44);
        canvas.drawCircle(
          at,
          6,
          Paint()..color = i < bubbles ? Colors.white : const Color(0x5501579B),
        );
        canvas.drawCircle(
          at,
          6,
          Paint()
            ..color = const Color(0xFF01579B)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
    if (!you.alive && s._ffa) {
      canvas.drawRect(screen, Paint()..color = const Color(0x88000000));
      _text(canvas, 'Back in ${you.respawnT.ceil()}...', c, 28, Colors.white);
    }
  }

  void _paintMiniMap(Canvas canvas) {
    const size = 84.0;
    final cell = size / max(map.width, map.height);
    final origin = Offset(_w - size - 10, 12 + s._topPad);
    final bg = Rect.fromLTWH(
      origin.dx - 3,
      origin.dy - 3,
      map.width * cell + 6,
      map.height * cell + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bg, const Radius.circular(8)),
      Paint()..color = Colors.black54,
    );
    final wall = Paint()..color = Colors.white60;
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        final ch = map.rows[y][x];
        Paint? p;
        if (OutplayMap.isSolid(ch)) {
          p = wall;
        } else if (map.isLava(Offset(x + 0.5, y + 0.5), s._clock)) {
          p = Paint()..color = const Color(0xAAFF6D00);
        } else if ('QFO'.contains(ch)) {
          p = Paint()..color = _floorColor(x + 0.5, y + 0.5);
        }
        if (p != null) {
          canvas.drawRect(
            Rect.fromLTWH(
              origin.dx + x * cell,
              origin.dy + y * cell,
              cell,
              cell,
            ),
            p,
          );
        }
      }
    }
    for (final g in s._ghosts) {
      canvas.drawCircle(
        origin + g * cell,
        cell * 0.6,
        Paint()..color = const Color(0xCCE1BEE7),
      );
    }
    if (map.hazard == MapHazard.water) {
      canvas.drawOval(
        Rect.fromCenter(
          center: origin + map.centre * cell,
          width: OutplayMap.lakeRx * 2 * cell,
          height: OutplayMap.lakeRy * 2 * cell,
        ),
        Paint()..color = const Color(0xCC29B6F6),
      );
    }
    for (final k in s._karts) {
      canvas.drawCircle(
        origin + k.pos * cell,
        max(2, cell * 0.5),
        Paint()..color = k.color,
      );
    }
    if (map.hazard == MapHazard.cars) {
      canvas.drawRect(
        Rect.fromLTWH(
          origin.dx,
          origin.dy + OutplayMap.roadTop * cell,
          map.width * cell,
          (OutplayMap.roadBottom - OutplayMap.roadTop) * cell,
        ),
        Paint()..color = Colors.white24,
      );
      for (final car in s._cars) {
        canvas.drawRect(
          Rect.fromCenter(
            center: origin + car.pos * cell,
            width: cell * 1.5,
            height: cell * 0.8,
          ),
          Paint()..color = car.color,
        );
      }
    }
    for (final p in s._people) {
      if (p.isYou || !p.alive) continue;
      canvas.drawCircle(
        origin + p.pos * cell,
        max(2, cell * 0.45),
        Paint()
          ..color = s._allies(p, s._you)
              ? const Color(0xFF40C4FF)
              : const Color(0xFFFF5252),
      );
    }
    final me = origin + s._you.pos * cell;
    final a = s._you.angle;
    final tri = Path()
      ..moveTo(me.dx + cos(a) * 6, me.dy + sin(a) * 6)
      ..lineTo(me.dx + cos(a + 2.5) * 4, me.dy + sin(a + 2.5) * 4)
      ..lineTo(me.dx + cos(a - 2.5) * 4, me.dy + sin(a - 2.5) * 4)
      ..close();
    canvas.drawPath(tri, Paint()..color = const Color(0xFF4FC3F7));
  }

  void _paintMoveStick(Canvas canvas) {
    final active = s._movePointer != null;
    final base = active ? s._moveOrigin : Offset(86, _h - 110);
    final knob = active ? s._moveNow : base;
    canvas.drawCircle(
      base,
      60,
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );
    canvas.drawCircle(
      base,
      60,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      knob,
      26,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
    if (!active) {
      _text(canvas, 'MOVE', base, 13, Colors.white70);
    }
    if (!active && s._clock < 8) {
      _text(
        canvas,
        'Drag here to look around',
        Offset(_w * 0.6, _h * 0.42),
        12,
        Colors.white54,
        maxWidth: _w * 0.5,
      );
    }
  }

  @override
  bool shouldRepaint(_ViewPainter oldDelegate) => true;
}
