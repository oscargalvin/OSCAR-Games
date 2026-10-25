import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/sound_service.dart';
import '../boost_ball/boost_ball_3d.dart' show V3;
import 'outplay_3d.dart';
import 'outplay_art.dart';
import 'outplay_avatar.dart';
import 'outplay_data.dart';
import 'outplay_maps.dart';
import 'outplay_net.dart';
import '../../widgets/full_screen_game.dart';

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
    with SingleTickerProviderStateMixin, FullScreenGame {
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
      // Boost Ball rooms share the lobby: leave them out.
      final ours = [
        for (final r in rooms)
          if (!r.mapId.startsWith('bb:') && !r.mapId.startsWith('za:')) r,
      ];
      if (mounted) setState(() => _waitingRooms = ours);
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
                  !r.mapId.startsWith('bb:') &&
                  !r.mapId.startsWith('za:') &&
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
      if (room.mapId.startsWith('bb:')) {
        room.close();
        throw 'That code is for a Boost Ball game. Open Boost Ball to join it.';
      }
      if (room.mapId.startsWith('za:')) {
        room.close();
        throw 'That code is for Zombie Attack. Open Zombie Attack to join it.';
      }
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

class _ViewPainter extends CustomPainter {
  final _OutplayGameScreenState s;
  _ViewPainter(this.s);

  late double _w, _h, _horizon, _proj, _camZ;
  late Offset _cam, _dir, _plane;

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
    _paintWorld(canvas);
    final pose = _weaponPose();
    _muzzle =
        (pose == null
            ? null
            : _s3.project(pose.$1 + pose.$2.unit * (pose.$4 / 2))) ??
        Offset(_w * 0.47, _h * 0.66);
    _paintTracers(canvas);
    _paintHooks(canvas);
    if (map.id == 'leaf_maze') _paintFallingLeaves(canvas);
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
        map.id == 'courtyard' ||
        map.id == 'leaf_maze') {
      final x = ((0.3 - s._you.angle / (2 * pi)) % 1) * _w * 2 - _w * 0.5;
      canvas.drawCircle(
        Offset(x, _horizon * 0.3),
        26,
        Paint()..color = const Color(0xFFFFF59D),
      );
    }
  }

  /// Leaves drifting down past you in the Leaf Maze.
  void _paintFallingLeaves(Canvas canvas) {
    const colours = [
      Color(0xFF66BB6A),
      Color(0xFF9CCC65),
      Color(0xFFFFB300),
      Color(0xFFEF6C00),
    ];
    final t = s._clock;
    final turn = s._you.angle / (2 * pi);
    for (var i = 0; i < 18; i++) {
      final speed = 0.06 + (i % 5) * 0.015;
      final fall = (t * speed + i * 0.137) % 1;
      final x = ((i * 0.618 - turn * 1.5) % 1) * _w + sin(t * 1.3 + i) * 18;
      final y = fall * _h;
      final size = 5.0 + (i % 3) * 2.5;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * (1 + i % 3) + i);
      final leaf = Path()
        ..moveTo(-size, 0)
        ..quadraticBezierTo(0, -size * 0.7, size, 0)
        ..quadraticBezierTo(0, size * 0.7, -size, 0)
        ..close();
      canvas.drawPath(
        leaf,
        Paint()..color = colours[i % colours.length].withValues(alpha: 0.85),
      );
      canvas.drawLine(
        Offset(-size, 0),
        Offset(size, 0),
        Paint()
          ..color = Colors.black26
          ..strokeWidth = 0.8,
      );
      canvas.restore();
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

  // -------------------------------------------------------------------------
  // The world in 3D.
  // -------------------------------------------------------------------------

  late Scene3D _s3;
  Offset _muzzle = Offset.zero;

  /// Close enough to bother drawing, and not far behind you.
  bool _near(Offset p, double r) {
    final d = p - _cam;
    return d.distance < r && d.dx * _dir.dx + d.dy * _dir.dy > -1.5;
  }

  void _paintWorld(Canvas canvas) {
    // Far-off ground, past where the floor tiles stop.
    canvas.drawRect(
      Rect.fromLTRB(0, _horizon, _w, _h),
      Paint()..color = Color.lerp(map.floorA, map.skyBottom, 0.65)!,
    );
    final sc = _s3 = Scene3D(
      op3(_cam, _camZ),
      opDir(s._you.angle),
      _proj,
      Offset(_w / 2, _horizon),
      fog: map.skyBottom,
    );
    _addFloor(sc);
    _addWalls(sc);
    _addRing(sc);
    _addStrap(sc);
    _addThings(sc);
    sc.draw(canvas);
  }

  void _addFloor(Scene3D sc) {
    final fancy =
        _ring != null ||
        map.hazard == MapHazard.lava ||
        map.hazard == MapHazard.water ||
        map.hazard == MapHazard.karts;
    void tile(double x0, double y0, double x1, double y1, Color c) => sc.poly(
      [
        op3(Offset(x0, y0), 0),
        op3(Offset(x1, y0), 0),
        op3(Offset(x1, y1), 0),
        op3(Offset(x0, y1), 0),
      ],
      c,
      lit: false,
      floor: true,
    );
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.solidAt(x, y)) continue;
        final mid = Offset(x + 0.5, y + 0.5);
        if (!_near(mid, 40)) continue;
        final n = !fancy ? 1 : (_near(mid, 10) ? 3 : 2);
        for (var j = 0; j < n; j++) {
          for (var i = 0; i < n; i++) {
            final x0 = x + i / n, y0 = y + j / n;
            // One sample per tile, off the middle so the croc bumps
            // (drawn below) don't paint the whole square.
            final c = n == 1
                ? _floorColor(x + 0.25, y + 0.25)
                : _floorColor(x0 + 0.5 / n, y0 + 0.5 / n);
            tile(x0, y0, x0 + 1 / n, y0 + 1 / n, c);
          }
        }
      }
    }
    if (map.hazard == MapHazard.cars) {
      // White road edges and a dashed yellow middle line.
      const top = OutplayMap.roadTop, bottom = OutplayMap.roadBottom;
      final w = map.width.toDouble();
      tile(0, top, w, top + 0.12, Colors.white);
      tile(0, bottom - 0.12, w, bottom, Colors.white);
      final mid = (top + bottom) / 2;
      for (var x = 0.0; x < w; x += 2) {
        tile(x, mid - 0.08, x + 1, mid + 0.08, const Color(0xFFFFEB3B));
      }
    }
    if (map.hazard == MapHazard.bouncy) {
      // The bumps on a croc's footbed.
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          final mid = Offset(x + 0.5, y + 0.5);
          if (map.solidAt(x, y) || !_near(mid, 9)) continue;
          sc.box(
            op3(mid, 0.02),
            const V3(1, 0, 0),
            const V3(0, 1, 0),
            kUp,
            0.07,
            0.07,
            0.02,
            const Color(0xFFA9D672),
          );
        }
      }
    }
  }

  void _addWalls(Scene3D sc) {
    final h = map.wallHeight;
    final eye = op3(_cam, _camZ);
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        final cell = map.cell(x, y);
        if (!OutplayMap.isSolid(cell)) continue;
        final mid = Offset(x + 0.5, y + 0.5);
        if (!_near(mid, 26)) continue;
        final colour = _wallColor(cell);
        if (cell == 'P' || cell == 'U' || cell == 'N') {
          // A padded ring post.
          sc.group(() {
            sc.box(
              op3(mid, 0.55),
              const V3(1, 0, 0),
              const V3(0, 1, 0),
              kUp,
              0.22,
              0.22,
              0.55,
              colour,
              top: Color.lerp(colour, Colors.white, 0.3),
            );
          }, bias: 0.1);
          continue;
        }
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          if (map.solidAt(x + dx, y + dy)) continue;
          final fc = mid + Offset(dx * 0.5, dy * 0.5);
          final normal = V3(dx.toDouble(), -dy.toDouble(), 0);
          if (normal.dot(eye - op3(fc, h / 2)) <= 0) continue;
          final along = dx != 0 ? const V3(0, 1, 0) : const V3(1, 0, 0);
          sc.group(() {
            sc.quad(
              op3(fc, h / 2),
              along * 0.5,
              kUp * (h / 2),
              colour,
              normal: normal,
            );
            if (_near(fc, 11)) {
              _wallDetail(sc, cell, colour, fc, along, normal, h, x + y);
            }
          }, bias: 0.35);
        }
        if (_camZ > h) {
          sc.quad(
            op3(mid, h),
            const V3(0.5, 0, 0),
            const V3(0, 0.5, 0),
            Color.lerp(colour, Colors.white, 0.12)!,
            normal: kUp,
          );
        }
      }
    }
  }

  /// Bricks, books, croc holes and fans on a wall face.
  void _wallDetail(
    Scene3D sc,
    String cell,
    Color colour,
    Offset fc,
    V3 along,
    V3 normal,
    double h,
    int seed,
  ) {
    // A patch from [a0] to [a1] across the face and [z0] to [z1] up it.
    void patch(double a0, double a1, double z0, double z1, Color c) {
      final centre =
          op3(fc, (z0 + z1) / 2) +
          along * ((a0 + a1) / 2 - 0.5) +
          normal * 0.006;
      sc.quad(
        centre,
        along * ((a1 - a0) / 2),
        kUp * ((z1 - z0) / 2),
        c,
        normal: normal,
        decal: true,
      );
    }

    final dark = Color.lerp(colour, Colors.black, 0.3)!;
    // Darker block edges so walls look like blocks.
    patch(0, 0.03, 0, h, dark);
    patch(0.97, 1, 0, h, dark);
    switch (cell) {
      case 'R': // bricks
        final mortar = Color.lerp(colour, Colors.black, 0.25)!;
        for (var r = 0; r < 4; r++) {
          final z = h * r / 4;
          if (r > 0) patch(0, 1, z - 0.012, z + 0.012, mortar);
          final off = r.isEven ? 0.5 : 0.25;
          patch(off - 0.012, off + 0.012, z, z + h / 4, mortar);
          if (r.isOdd) patch(0.75 - 0.012, 0.75 + 0.012, z, z + h / 4, mortar);
        }
      case 'C': // crate planks and frame
        final wood = Color.lerp(colour, Colors.black, 0.25)!;
        for (final z in [h / 3, h * 2 / 3]) {
          patch(0, 1, z - 0.015, z + 0.015, wood);
        }
        patch(0, 1, h - 0.06, h, wood);
        patch(0, 1, 0, 0.06, wood);
        patch(0, 0.07, 0, h, wood);
        patch(0.93, 1, 0, h, wood);
      case '#': // stone blocks
        final seam = Color.lerp(colour, Colors.black, 0.2)!;
        patch(0, 1, h / 2 - 0.012, h / 2 + 0.012, seam);
        patch(0.5 - 0.012, 0.5 + 0.012, 0, h / 2, seam);
      case 'B': // panels
        final edge = Color.lerp(colour, Colors.white, 0.25)!;
        patch(0.1, 0.9, h * 0.1, h * 0.13, edge);
        patch(0.1, 0.9, h * 0.87, h * 0.9, edge);
      case 'W': // stripy wallpaper
        final stripe = Color.lerp(colour, Colors.white, 0.1)!;
        for (var i = 0; i < 3; i++) {
          patch(i / 3 + 0.05, i / 3 + 0.2, 0, h, stripe);
        }
      case 'Y': // tyres with red and white bands
        for (var i = 0; i < 4; i++) {
          patch(
            i / 4,
            (i + 1) / 4,
            h * 0.42,
            h * 0.58,
            i.isEven ? const Color(0xFFE53935) : Colors.white,
          );
        }
      case 'H': // straw lines on hay
        final straw = Color.lerp(colour, Colors.brown, 0.3)!;
        for (final f in [0.3, 0.7]) {
          patch(0, 1, h * f, h * f + 0.05, straw);
        }
      case 'G': // leafy hedge
        final leaf = Color.lerp(colour, Colors.black, 0.22)!;
        for (var i = 0; i < 6; i++) {
          final a = ((seed * 7 + i * 13) % 10) / 10;
          final z = ((seed * 3 + i * 7) % 9) / 9 * h * 0.85;
          patch(a, a + 0.12, z, z + 0.12, leaf);
        }
      case 'D': // bookshelves
        const books = [
          Color(0xFFC62828),
          Color(0xFF2E7D32),
          Color(0xFF1565C0),
          Color(0xFFF9A825),
        ];
        for (var r = 0; r < 4; r++) {
          final z0 = h * (0.08 + r * 0.23);
          for (var b = 0; b < 6; b++) {
            patch(
              0.06 + b * 0.148,
              0.19 + b * 0.148,
              z0,
              z0 + h * 0.18,
              books[(b + r * 3 + seed) % 4],
            );
          }
        }
      case 'X' || 'J': // croc holes and a rounded rim
        final hole = Color.lerp(colour, Colors.black, 0.45)!;
        final rows = max(2, (h * 2.5).round());
        for (var r = 0; r < rows; r++) {
          for (var c = 0; c < 3; c++) {
            if (r.isOdd && c.isEven) continue;
            final a = (c + 0.5) / 3, z = h * (r + 0.7) / (rows + 0.4);
            patch(a - 0.07, a + 0.07, z - 0.07, z + 0.07, hole);
          }
        }
        patch(0, 1, h - 0.1, h, Color.lerp(colour, Colors.white, 0.18)!);
      case 'A': // cheering fans in the stands
        const shirts = [
          Color(0xFFEF5350),
          Color(0xFFFFCA28),
          Color(0xFF42A5F5),
          Color(0xFF66BB6A),
          Color(0xFFAB47BC),
          Color(0xFFFFFFFF),
        ];
        for (var col = 0; col < 5; col++) {
          for (var r = 0; r < 4; r++) {
            final bounce = sin(s._clock * 6 + col + r * 2 + seed) > 0.6
                ? 0.04
                : 0.0;
            final z = h * (0.1 + r * 0.22) + bounce;
            final a = (col + 0.5) / 5;
            patch(
              a - 0.07,
              a + 0.07,
              z,
              z + h * 0.09,
              shirts[(col * 7 + r * 13 + seed) % shirts.length],
            );
            patch(
              a - 0.035,
              a + 0.035,
              z + h * 0.09,
              z + h * 0.14,
              const Color(0xFFFFCC80),
            );
          }
        }
    }
  }

  /// The boxing ring's ropes.
  void _addRing(Scene3D sc) {
    final ring = _ring;
    if (ring == null) return;
    final corners = [
      ring.topLeft,
      ring.topRight,
      ring.bottomRight,
      ring.bottomLeft,
    ];
    const colours = [Color(0xFFE53935), Colors.white, Color(0xFF1E88E5)];
    for (var side = 0; side < 4; side++) {
      final a = corners[side], b = corners[(side + 1) % 4];
      final dir = op3(b, 0) - op3(a, 0);
      final along = dir.unit;
      final across = along.cross(kUp).unit;
      const pieces = 8;
      for (var i = 0; i < pieces; i++) {
        final mid = Offset.lerp(a, b, (i + 0.5) / pieces)!;
        if (!_near(mid, 26)) continue;
        for (var r = 0; r < 3; r++) {
          sc.box(
            op3(mid, 0.35 + r * 0.22),
            along,
            across,
            kUp,
            dir.length / pieces / 2,
            0.025,
            0.025,
            colours[r],
          );
        }
      }
    }
  }

  /// The croc's heel strap, arching over the back of the shoe.
  void _addStrap(Scene3D sc) {
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
    Offset world(double t) => Offset(sx + sin(pi * t) * 2.6, a + (b - a) * t);
    double height(double t) => h - 0.15 + sin(pi * t) * 0.9;
    for (var i = 0; i < steps; i++) {
      final t0 = i / steps, t1 = (i + 1) / steps;
      final p0 = world(t0), p1 = world(t1);
      sc.poly([
        op3(p0, height(t0)),
        op3(p1, height(t1)),
        op3(p1, height(t1) + 0.55),
        op3(p0, height(t0) + 0.55),
      ], const Color(0xFF689F38));
    }
    // The round rivets that hold the strap on.
    for (final t in [0.0, 1.0]) {
      sc.box(
        op3(world(t), height(t) + 0.27),
        const V3(1, 0, 0),
        const V3(0, 1, 0),
        kUp,
        0.2,
        0.2,
        0.2,
        const Color(0xFFFFCA28),
      );
    }
  }

  void _addThings(Scene3D sc) {
    const xAxis = V3(1, 0, 0), yAxis = V3(0, 1, 0);
    for (final p in s._people) {
      if (p.isYou || !p.alive || !_near(p.pos, 30)) continue;
      final snakeOut =
          s._hooks.any((h) => identical(h.owner, p)) || p.netHook != null;
      addPerson(
        sc,
        p.look,
        p.pos,
        p.z,
        p.angle,
        walk: p.walkCycle,
        hurt: p.hurtT > 0,
        slow: p.slowT > 0,
        held: snakeOut ? null : (p.gun?.look ?? p.held.look),
        heldColour: p.gun?.color ?? p.held.color,
        skin: p.skinOf(p.heldId),
        swing: p.swingT > 0 ? sin(p.swingT / 0.22 * pi) : 0,
      );
      final f = opDir(p.angle);
      final head = op3(p.pos, p.z + 1.12);
      final depth = sc.depthOf(op3(p.pos, p.z + 0.5));
      if (p.flashT > 0 && p.gun != null) {
        final r = f.cross(kUp).unit;
        sc.box(
          op3(p.pos, p.z + 0.62) + f * 0.6 + r * 0.06,
          f,
          r,
          kUp,
          0.06,
          0.06,
          0.06,
          const Color(0xEEFFF176),
        );
      }
      // Name and health above their head.
      sc.later(depth - 0.05, (c) {
        final at = sc.project(head);
        if (at == null || depth < 0.3) return;
        final scale = _proj / depth;
        final friend = s._allies(p, s._you);
        _text(
          c,
          p.name,
          at - Offset(0, max(9, scale * 0.07)),
          (scale * 0.1).clamp(9.0, 16.0),
          friend ? const Color(0xFF80D8FF) : Colors.white,
        );
        final bar = Rect.fromCenter(
          center: at,
          width: max(30.0, scale * 0.55),
          height: max(4, scale * 0.03),
        );
        c.drawRect(bar, Paint()..color = Colors.black54);
        c.drawRect(
          Rect.fromLTWH(bar.left, bar.top, bar.width * p.hp / 100, bar.height),
          Paint()
            ..color = friend
                ? const Color(0xFF40C4FF)
                : const Color(0xFFEF5350),
        );
      });
    }
    for (final car in s._cars) {
      if (!_near(car.pos, 30)) continue;
      _addCar(sc, car);
    }
    for (final k in s._karts) {
      if (!_near(k.pos, 30)) continue;
      _addKart(sc, k);
    }
    final ghosts = s._ghosts;
    for (var i = 0; i < ghosts.length; i++) {
      final g = ghosts[i];
      if (!_near(g, 30)) continue;
      final bob = 0.25 + 0.12 * sin(s._clock * 2 + i);
      // Ghosts always look at you.
      final f = (op3(_cam, 0) - op3(g, 0)).unit;
      final r = f.cross(kUp).unit;
      const body = Color(0xCCF3E5F5);
      sc.group(() {
        sc.box(op3(g, bob + 0.3), f, r, kUp, 0.25, 0.27, 0.3, body);
        sc.box(op3(g, bob + 0.66), f, r, kUp, 0.2, 0.22, 0.08, body);
        for (final side in [-1.0, 0.0, 1.0]) {
          sc.box(
            op3(g, bob - 0.04) + r * (side * 0.17),
            f,
            r,
            kUp,
            0.07,
            0.07,
            0.05,
            body,
          );
        }
        const eye = Color(0xFF1A1033);
        for (final side in [-1.0, 1.0]) {
          sc.quad(
            op3(g, bob + 0.48) + f * 0.252 + r * (side * 0.1),
            r * 0.045,
            kUp * 0.05,
            eye,
            normal: f,
            lit: false,
            decal: true,
          );
        }
        sc.quad(
          op3(g, bob + 0.3) + f * 0.252,
          r * 0.06,
          kUp * 0.06,
          eye,
          normal: f,
          lit: false,
          decal: true,
        );
      });
    }
    for (final b in s._balls) {
      if (!_near(b.pos, 30)) continue;
      final f = op3(b.vel, 0).unit;
      final r = f.cross(kUp).unit;
      if (b.gun.look == WeaponLook.rpgMini) {
        // A little rocket with a fiery tail.
        sc.group(() {
          sc.box(
            op3(b.pos, 0.42),
            f,
            r,
            kUp,
            0.12,
            0.05,
            0.05,
            const Color(0xFF455A64),
            front: const Color(0xFFE53935),
          );
          sc.box(
            op3(b.pos, 0.42) - f * 0.18,
            f,
            r,
            kUp,
            0.07,
            0.06,
            0.06,
            const Color(0xDDFF6D00),
          );
        });
        continue;
      }
      final size = b.gun.look == WeaponLook.bubble ? 0.21 : 0.12;
      final spin = s._clock * 5;
      sc.group(() {
        sc.box(
          op3(b.pos, 0.45),
          V3(cos(spin), sin(spin), 0),
          V3(-sin(spin), cos(spin), 0),
          kUp,
          size / 2,
          size / 2,
          size / 2,
          b.gun.shotColor.withValues(alpha: 0.9),
        );
      });
    }
    for (final p in s._pops) {
      if (!_near(p.pos, 30)) continue;
      final k = p.t / 0.35;
      final r = p.radius * (0.5 + k);
      sc.group(() {
        sc.box(
          op3(p.pos, 0.3),
          xAxis,
          yAxis,
          kUp,
          r,
          r,
          r * 0.5,
          p.color.withValues(alpha: 0.45 * (1 - k)),
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
        _addSign(sc, at + const Offset(0, -0.7), pad.$2, pad.$3);
      }
    }
    for (final p in s._popups) {
      final at3 = op3(p.pos, 1.1 + p.t * 0.6);
      final depth = sc.depthOf(at3);
      if (depth < 0.3) continue;
      sc.later(depth - 0.1, (c) {
        final at = sc.project(at3);
        if (at == null) return;
        _text(
          c,
          p.text,
          at,
          (_proj / depth * 0.25).clamp(10.0, 30.0),
          p.color.withValues(alpha: 1 - p.t / 0.7),
        );
      });
    }
  }

  void _addCar(Scene3D sc, _Car car) {
    final f = V3(car.speed >= 0 ? 1 : -1, 0, 0);
    final r = f.cross(kUp).unit;
    V3 at(double fw, double rt, double up) =>
        op3(car.pos, up) + f * fw + r * rt;
    sc.group(() {
      sc.box(at(0, 0, 0.3), f, r, kUp, 0.75, 0.36, 0.15, car.color);
      sc.box(
        at(-0.08, 0, 0.58),
        f,
        r,
        kUp,
        0.4,
        0.32,
        0.13,
        const Color(0xFFB3E5FC),
        top: car.color,
      );
      for (final fw in [-0.48, 0.48]) {
        for (final side in [-1.0, 1.0]) {
          sc.box(
            at(fw, side * 0.36, 0.14),
            f,
            r,
            kUp,
            0.14,
            0.05,
            0.14,
            const Color(0xFF212121),
          );
        }
      }
      for (final side in [-1.0, 1.0]) {
        sc.box(
          at(0.76, side * 0.24, 0.32),
          f,
          r,
          kUp,
          0.01,
          0.07,
          0.04,
          const Color(0xFFFFF59D),
        );
      }
    });
  }

  /// A go-kart with a goat driving it.
  void _addKart(Scene3D sc, _Kart k) {
    final f = opDir(k.heading);
    final r = f.cross(kUp).unit;
    V3 at(double fw, double rt, double up) => op3(k.pos, up) + f * fw + r * rt;
    void b(V3 p, double hx, double hy, double hz, Color c) =>
        sc.box(p, f, r, kUp, hx, hy, hz, c);
    const goat = Color(0xFFF5F5F5);
    sc.group(() {
      b(at(0, 0, 0.16), 0.48, 0.3, 0.08, k.color);
      b(at(0.4, 0, 0.26), 0.06, 0.12, 0.04, Colors.white);
      for (final fw in [-0.32, 0.32]) {
        for (final side in [-1.0, 1.0]) {
          b(at(fw, side * 0.33, 0.1), 0.1, 0.05, 0.1, const Color(0xFF212121));
        }
      }
      // The goat: body, head, horns, ears and a little beard.
      b(at(-0.1, 0, 0.36), 0.14, 0.13, 0.14, goat);
      b(at(0.05, 0, 0.58), 0.1, 0.09, 0.09, goat);
      for (final side in [-1.0, 1.0]) {
        b(
          at(0.02, side * 0.06, 0.71),
          0.02,
          0.02,
          0.05,
          const Color(0xFF8D6E63),
        );
        b(
          at(0.03, side * 0.12, 0.6),
          0.03,
          0.04,
          0.015,
          const Color(0xFFEEEEEE),
        );
        sc.quad(
          at(0.152, side * 0.04, 0.61),
          r * 0.015,
          kUp * 0.015,
          const Color(0xFF15172A),
          normal: f,
          lit: false,
          decal: true,
        );
      }
      b(at(0.12, 0, 0.47), 0.02, 0.02, 0.04, const Color(0xFFBDBDBD));
    });
  }

  void _addSign(Scene3D sc, Offset at, String label, Color colour) {
    const f = V3(0, -1, 0); // the signs face down the map
    const r = V3(-1, 0, 0);
    final eye = op3(_cam, _camZ);
    final board = op3(at, 1.0);
    final depth = sc.depthOf(board);
    sc.group(() {
      sc.box(op3(at, 0.4), f, r, kUp, 0.04, 0.04, 0.4, const Color(0xFF90A4AE));
      sc.box(board, f, r, kUp, 0.04, 0.8, 0.2, colour);
    }, depth: depth);
    // The words, on whichever side you can see.
    final front = f.dot(eye - board) > 0;
    final face = board + f * (front ? 0.045 : -0.045);
    sc.later(depth - 0.01, (c) {
      paintOnPlane(c, sc, face, r * (front ? -1 : 1), kUp * -1, 1.6, 0.4, (
        c,
        w,
        h,
      ) {
        _text(
          c,
          label,
          Offset(w / 2, h / 2),
          h * 0.42,
          Colors.white,
          maxWidth: w * 0.95,
        );
      });
    });
  }

  /// Where your weapon is: its middle, which way it points, which way is
  /// down for it and how long it is.
  (V3, V3, V3, double)? _weaponPose() {
    final you = s._you;
    if (!you.alive) return null;
    final sc = _s3;
    // Placed by where it should land on screen, so it sits in the corner
    // the same way on a tall or a wide screen.
    final m = min(_w, _h);
    final k = m / _proj;
    V3 at(double sx, double sy, double z) => sc.camToWorld(
      V3((sx - _w / 2) / _proj * z, -(sy - _horizon) / _proj * z, z),
    );
    final bobX = sin(you.walkCycle * 0.5) * 6;
    final bobY = (cos(you.walkCycle) * 4).abs();
    if (you.gun != null) {
      final r = s._recoil;
      return (
        at(_w - 0.28 * m + bobX, _horizon + 0.35 * m + bobY + r * 14, 0.55),
        sc.fromCamDir(-0.3, 0.06 + r * 0.1, 1),
        sc.fromCamDir(-0.3, -1, 0.15),
        0.354 * k,
      );
    }
    if (s._hooks.any((h) => identical(h.owner, you))) return null;
    final held = you.held;
    final swing = you.swingT > 0 ? sin(you.swingT / 0.22 * pi) : 0.0;
    final big =
        held.look == WeaponLook.scythe ||
        held.look == WeaponLook.slapper ||
        held.look == WeaponLook.snake;
    return (
      at(
        _w - 0.25 * m - swing * 0.3 * m + bobX,
        _horizon + 0.25 * m + swing * 0.05 * m + bobY,
        0.5,
      ),
      sc.fromCamDir(-0.2 - swing * 1.4, 0.75 - swing * 0.9, 0.6 + swing * 0.4),
      sc.fromCamDir(-0.5, -0.3, 0.6),
      (big ? 0.477 : 0.323) * k,
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
    final pose = _weaponPose();
    if (pose == null) return;
    final you = s._you;
    final gun = you.gun;
    final (mid, along, down, length) = pose;
    final tip = paintWeapon3D(
      canvas,
      _s3,
      gun?.look ?? you.held.look,
      gun?.color ?? you.held.color,
      mid,
      along,
      down,
      length,
      skin: you.skinOf(you.heldId),
    );
    if (gun != null &&
        tip != null &&
        you.flashT > 0 &&
        gun.look != WeaponLook.flamer) {
      canvas.drawCircle(
        tip,
        16,
        Paint()..color = gun.shotColor.withValues(alpha: 0.8),
      );
    }
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
