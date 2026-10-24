import 'dart:math';
import 'dart:ui' show Offset;

import '../outplay/outplay_net.dart';
import 'boost_ball_data.dart';
import 'boost_ball_sim.dart';

/// Boost Ball rooms share the online lobby with Outplay, so their map name
/// starts with this to keep the two games apart.
const String kBoostRoomPrefix = 'bb:';

bool isBoostRoom(String mapId) => mapId.startsWith(kBoostRoomPrefix);

String boostRoomMap(BoostMode mode) => '$kBoostRoomPrefix${mode.name}';

BoostMode boostRoomMode(String mapId) => BoostMode.byName(
  mapId.substring(min(mapId.length, kBoostRoomPrefix.length)),
);

const List<String> kBotNames = [
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

/// Someone in the waiting room.
class NetPlayer {
  final String id;
  String name;
  String car;
  int colour;
  int team = 0;
  NetPlayer(this.id, this.name, this.car, this.colour);
}

double _r(double v) => (v * 100).roundToDouble() / 100;
double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

/// An online game of Boost Ball. The person who made the room runs the real
/// game and sends everyone else what is happening 20 times a second; the
/// others send what they're pressing and copy the game in between.
class BoostBallSession {
  final OutplayRoom room;
  final OutplayDirectory? lister;
  final String myName;
  final CarSpec myCar;
  final int myColour;
  final double length;
  final Random rnd;

  late final BoostMode mode = boostRoomMode(room.mapId);
  int get teamSize => room.teamSize.clamp(1, 3);
  bool get isHost => room.isHost;

  /// Who is in the room before the game starts (host keeps the real list).
  final List<NetPlayer> lobby = [];

  BoostBallMatch? match;
  Car? you;

  /// Set when the game can't go on (the room maker left).
  String? ended;

  /// Things that happened (joins, leaves) for the screen to show.
  final List<String> notes = [];

  double _sendT = 0;
  double _helloT = 0;
  double _listT = 0;
  int _jumps = 0;
  final Map<String, int> _theirJumps = {};
  final List<MatchEvent> _outEvents = [];

  BoostBallSession({
    required this.room,
    required this.myName,
    required this.myCar,
    required this.myColour,
    this.lister,
    this.length = 150,
    Random? random,
  }) : rnd = random ?? Random() {
    if (isHost) lobby.add(NetPlayer(room.myId, myName, myCar.id, myColour));
  }

  bool get started => match != null;

  /// Names of everyone waiting for the game to start.
  List<String> get waiting =>
      isHost ? [for (final p in lobby) p.name] : _waiting;
  List<String> _waiting = const [];
  int get needed => teamSize * 2;

  /// Moves the game on: reads messages, sends ours and steps the match.
  void update(double dt) {
    for (final m in room.takeMessages()) {
      _receive(m);
    }
    if (isHost) {
      _listT -= dt;
      if (lister != null && _listT <= 0 && !room.showCode) {
        _listT = 2;
        lister!.announce(
          RoomInfo(
            code: room.code,
            name: myName,
            avatar: const [],
            mapId: room.mapId,
            players: lobby.length,
            playing: started,
            teamSize: teamSize,
          ),
        );
      }
      if (!started && lobby.length >= needed) startNow();
      _helloT -= dt;
      if (!started && _helloT <= 0) {
        _helloT = 1;
        room.send({
          't': 'lobby',
          'n': [for (final p in lobby) p.name],
        });
      }
    } else if (!started) {
      _helloT -= dt;
      if (_helloT <= 0) {
        _helloT = 1.5;
        room.send({
          't': 'hi',
          'id': room.myId,
          'n': myName,
          'car': myCar.id,
          'col': myColour,
        });
      }
    }
    final m = match;
    if (m == null) return;
    final me = you!;
    if (!isHost && me.input.jump) _jumps++;
    m.step(dt);
    _sendT -= dt;
    if (isHost) {
      _outEvents.addAll(m.events);
      if (_sendT <= 0) {
        _sendT = 0.05;
        room.send(_snapshot(m));
        _outEvents.clear();
      }
    } else if (_sendT <= 0) {
      _sendT = 0.05;
      room.send({
        't': 'in',
        'id': room.myId,
        's': _r(me.input.steer),
        'th': _r(me.input.throttle),
        'b': me.input.boost,
        'j': _jumps,
      });
    }
  }

  /// The room maker starts the game, filling empty places with bots.
  void startNow() {
    if (!isHost || started) return;
    // Share people out between the two teams.
    for (var i = 0; i < lobby.length; i++) {
      lobby[i].team = i.isEven ? 0 : 1;
    }
    final roster = <Map<String, dynamic>>[];
    final names = [...kBotNames]..shuffle(rnd);
    var bot = 0;
    for (final team in [0, 1]) {
      final people = lobby.where((p) => p.team == team).toList();
      for (var i = 0; i < teamSize; i++) {
        if (i < people.length) {
          final p = people[i];
          roster.add({
            'id': p.id,
            'n': p.name,
            'car': p.car,
            'col': p.colour,
            'team': team,
            'h': true,
          });
        } else {
          roster.add({
            'id': 'bot$bot',
            'n': names[bot++ % names.length],
            'car': kCars[rnd.nextInt(kCars.length)].id,
            'col': 0,
            'team': team,
            'h': false,
          });
        }
      }
    }
    room.start();
    _build(roster);
    room.send({'t': 'go', 'cars': roster});
  }

  void _build(List<dynamic> roster) {
    final cars = <Car>[];
    for (final raw in roster) {
      if (raw is! Map) continue;
      final id = raw['id'] as String? ?? '';
      final mine = id == room.myId;
      final car =
          Car(
              team: _i(raw['team']).clamp(0, 1),
              name: mine ? 'You' : (raw['n'] as String? ?? 'Player'),
              spec: carById(raw['car'] as String? ?? ''),
              isYou: mine,
              colour: _i(raw['col']).clamp(0, kCarColours.length - 1),
            )
            ..netId = id
            ..human = raw['h'] == true
            // The room maker's phone drives the bots; everyone else just copies.
            ..netControlled = !mine && (!isHost || raw['h'] == true);
      if (mine) {
        car.input.relative = true;
        you = car;
      }
      cars.add(car);
    }
    match = BoostBallMatch(
      teamSize: teamSize,
      players: cars,
      length: length,
      mode: mode,
      random: rnd,
    )..authority = isHost;
  }

  void _receive(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'hi' when isHost:
        final id = m['id'] as String? ?? '';
        if (id.isEmpty) return;
        final name = (m['n'] as String? ?? 'Player').trim();
        var p = lobby.where((p) => p.id == id).firstOrNull;
        if (p == null) {
          p = NetPlayer(id, name, m['car'] as String? ?? '', _i(m['col']));
          lobby.add(p);
          notes.add('$name joined');
          final game = match;
          if (game != null) _takeOverBot(game, p);
        }
      case 'go' when !isHost:
        if (started) return;
        final to = m['to'] as String?;
        if (to != null && to != room.myId) return;
        final cars = m['cars'];
        if (cars is List) _build(cars);
      case 'names' when !isHost:
        final game = match;
        final list = m['cars'];
        if (game == null || list is! List) return;
        for (var i = 0; i < list.length && i < game.cars.length; i++) {
          final c = game.cars[i];
          final raw = list[i];
          if (raw is! Map || c.isYou) continue;
          c
            ..name = raw['n'] as String? ?? c.name
            ..human = raw['h'] == true
            ..colour = _i(raw['col']).clamp(0, kCarColours.length - 1)
            ..netId = raw['id'] as String? ?? c.netId;
        }
      case 'in' when isHost:
        final c = match?.cars
            .where((c) => c.netId == m['id'] && c.netControlled)
            .firstOrNull;
        if (c == null) return;
        final j = _i(m['j']);
        final seen = _theirJumps[c.netId] ?? 0;
        c.input
          ..relative = true
          ..steer = _d(m['s']).clamp(-1, 1)
          ..throttle = _d(m['th']).clamp(-1, 1)
          ..boost = m['b'] == true
          ..jump = c.input.jump || j > seen;
        _theirJumps[c.netId] = j;
      case 's' when !isHost:
        final game = match;
        if (game != null) _apply(game, m);
      case 'bye':
        final id = m['id'] as String? ?? '';
        final gone = lobby.where((p) => p.id == id).firstOrNull;
        lobby.removeWhere((p) => p.id == id);
        final game = match;
        final car = game?.cars.where((c) => c.netId == id).firstOrNull;
        final name = car?.name ?? gone?.name;
        if (name != null) notes.add('$name left');
        if (car != null && isHost) {
          // A bot drives their car for the rest of the game.
          car
            ..netControlled = false
            ..human = false
            ..input.relative = false;
        }
      case 'lobby' when !isHost:
        _waiting = [for (final n in (m['n'] as List?) ?? const []) '$n'];
      case 'full' when !isHost && !started:
        if (m['to'] == room.myId) ended = 'That game is already full.';
      case 'hostLeft':
        ended = 'The room maker left the game.';
    }
  }

  /// Someone joined a game that already started: they take a bot's car.
  void _takeOverBot(BoostBallMatch game, NetPlayer p) {
    final bots = game.cars.where((c) => !c.human && !c.isYou).toList()
      ..sort((a, b) {
        int count(int t) =>
            game.cars.where((c) => c.team == t && c.human).length;
        return count(a.team).compareTo(count(b.team));
      });
    if (bots.isEmpty) {
      room.send({'t': 'full', 'to': p.id});
      return;
    }
    final c = bots.first
      ..name = p.name
      ..colour = p.colour.clamp(0, kCarColours.length - 1)
      ..netId = p.id
      ..human = true
      ..netControlled = true
      ..input.stick = Offset.zero;
    p.team = c.team;
    final roster = [
      for (final car in game.cars)
        {
          'id': car.netId,
          'n': car.isYou ? myName : car.name,
          'car': car.spec.id,
          'col': car.colour,
          'team': car.team,
          'h': car.human || car.isYou,
        },
    ];
    room.send({'t': 'go', 'to': p.id, 'cars': roster});
    room.send({'t': 'names', 'cars': roster});
  }

  Map<String, dynamic> _snapshot(BoostBallMatch g) {
    final b = g.ball;
    return {
      't': 's',
      'ph': g.phase.index,
      'pt': _r(g.phaseT),
      'cl': _r(g.clock),
      'ot': g.overtime,
      'sc': g.score,
      'ls': g.lastScorerTeam,
      'f': g.feedT > 0 ? g.feed : null,
      'ft': _r(g.feedT),
      'k': g.lastKph,
      'kt': _r(g.kphT),
      'gk': g.goalKph,
      'ev': [for (final e in _outEvents) e.index],
      'pd': [
        for (var i = 0; i < g.pads.length; i++)
          if (!g.pads[i].ready) [i, _r(g.pads[i].respawnT)],
      ],
      'b': [b.x, b.y, b.z, b.vx, b.vy, b.vz].map(_r).toList(),
      'c': [
        for (final c in g.cars)
          <double>[
            c.x,
            c.y,
            c.z,
            c.vx,
            c.vy,
            c.vz,
            c.fx,
            c.boost,
            (c.grounded ? 1.0 : 0) + (c.boosting ? 2 : 0) + (c.canFlip ? 4 : 0),
            c.upX,
            c.upY,
            c.upZ,
            c.flipT,
            c.demoT,
            c.goals.toDouble(),
            c.input.steer,
            c.input.throttle,
            c.input.stick.dx,
            c.input.stick.dy,
            c.topKph.toDouble(),
            c.fy,
            c.fz,
          ].map(_r).toList(),
      ],
    };
  }

  void _apply(BoostBallMatch g, Map<String, dynamic> m) {
    final phase = MatchPhase.values[_i(m['ph']).clamp(0, 3)];
    if (phase == MatchPhase.kickoff && g.phase != MatchPhase.kickoff) {
      g.events.add(MatchEvent.kickoff);
    }
    g
      ..phase = phase
      ..phaseT = _d(m['pt'])
      ..clock = _d(m['cl'])
      ..overtime = m['ot'] == true
      ..lastScorerTeam = (m['ls'] as num?)?.toInt()
      ..feed = m['f'] as String? ?? g.feed
      ..feedT = _d(m['ft'])
      ..lastKph = _i(m['k'])
      ..kphT = _d(m['kt'])
      ..goalKph = _i(m['gk']);
    final sc = m['sc'];
    if (sc is List && sc.length == 2) {
      g.score[0] = _i(sc[0]);
      g.score[1] = _i(sc[1]);
    }
    for (final e in (m['ev'] as List?) ?? const []) {
      final i = _i(e);
      if (i >= 0 && i < MatchEvent.values.length) {
        g.events.add(MatchEvent.values[i]);
      }
    }
    for (final p in g.pads) {
      p.respawnT = 0;
    }
    for (final raw in (m['pd'] as List?) ?? const []) {
      if (raw is List && raw.length == 2) {
        final i = _i(raw[0]);
        if (i >= 0 && i < g.pads.length) g.pads[i].respawnT = _d(raw[1]);
      }
    }
    final b = m['b'];
    if (b is List && b.length == 6) {
      g.ball
        ..x = _d(b[0])
        ..y = _d(b[1])
        ..z = _d(b[2])
        ..vx = _d(b[3])
        ..vy = _d(b[4])
        ..vz = _d(b[5]);
    }
    final cars = m['c'];
    if (cars is! List) return;
    for (var i = 0; i < cars.length && i < g.cars.length; i++) {
      final v = cars[i];
      if (v is! List || v.length < 22) continue;
      final c = g.cars[i];
      final x = _d(v[0]), y = _d(v[1]), z = _d(v[2]);
      final gap = sqrt(
        (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y) + (z - c.z) * (z - c.z),
      );
      // Your own car runs on your phone straight away, so only nudge it
      // back in line unless it is way off.
      final k = c.isYou && gap < 6 && phase == MatchPhase.play ? 0.25 : 1.0;
      c
        ..x += (x - c.x) * k
        ..y += (y - c.y) * k
        ..z += (z - c.z) * k
        ..boost = _d(v[7])
        ..demoT = _d(v[13])
        ..goals = _i(v[14])
        ..topKph = _i(v[19]);
      if (k == 1) {
        final flags = _i(v[8]);
        c
          ..vx = _d(v[3])
          ..vy = _d(v[4])
          ..vz = _d(v[5])
          ..fx = _d(v[6])
          ..fy = _d(v[20])
          ..fz = _d(v[21])
          ..grounded = flags & 1 != 0
          ..canFlip = flags & 4 != 0
          ..upX = _d(v[9])
          ..upY = _d(v[10])
          ..upZ = _d(v[11])
          ..flipT = _d(v[12]);
      }
      if (!c.isYou) {
        final flags = _i(v[8]);
        c.boosting = flags & 2 != 0;
        c.input
          ..relative = c.human
          ..steer = _d(v[15])
          ..throttle = _d(v[16])
          ..stick = Offset(_d(v[17]), _d(v[18]))
          ..boost = c.boosting;
      }
    }
  }

  void close() {
    lister?.unannounce();
    room.close();
  }
}
