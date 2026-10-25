import 'dart:math';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/sound_service.dart';
import '../../widgets/full_screen_game.dart';
import 'zombie_3d.dart';
import 'zombie_data.dart';
import 'zombie_net.dart';
import 'zombie_sim.dart';

/// One game of Zombie Attack: survive as many waves as you can.
class ZombieGameScreen extends StatefulWidget {
  final ZombieMap map;
  final int level;
  final String gunId;

  /// A 2-player game with a friend on another phone.
  final ZombieSession? session;

  const ZombieGameScreen({
    super.key,
    this.map = ZombieMap.town,
    this.level = 1,
    this.gunId = 'pistol',
    this.session,
  });

  @override
  State<ZombieGameScreen> createState() => _ZombieGameScreenState();
}

class _ZombieGameScreenState extends State<ZombieGameScreen>
    with SingleTickerProviderStateMixin, FullScreenGame {
  late ZombieWorld _solo;
  ZombieSession? get _net => widget.session;

  /// The game on this phone. For 2 players it only exists once your friend
  /// has joined.
  ZombieWorld get _w => _net?.world ?? _solo;
  bool get _waiting => _net != null && _net!.world == null;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final _save = ZombieSave.instance;
  bool _paid = false;
  Size _size = Size.zero;
  final FocusNode _focus = FocusNode();
  final Set<LogicalKeyboardKey> _keys = {};

  // Touch: the left side is a move stick, the right side turns the camera.
  int? _movePointer, _lookPointer;
  Offset? _moveStart, _lookLast;
  Offset _moveNow = Offset.zero;
  bool _touch = false; // playing on a touch screen
  bool _shooting = false; // holding the SHOOT button

  /// Which way the camera looks (a map angle) and how high above you it is.
  double _yaw = -pi / 2;
  double _pitch = 0.42;

  String? _banner;
  double _bannerT = 0;
  double _shake = 0;
  double _soundT = 0;

  // What you had last frame, to notice changes on either phone.
  double _lastHp = kMaxHp;
  int _lastWeapons = 1;
  bool _lastKept = false;

  @override
  void initState() {
    super.initState();
    _start();
    _ticker = createTicker(_tick)..start();
  }

  void _start() {
    _solo = ZombieWorld(
      map: widget.map,
      level: widget.level,
      gun: gunById(widget.gunId),
    );
    _paid = false;
    _lastHp = kMaxHp;
    _lastWeapons = 1;
    _lastKept = false;
    _yaw = -pi / 2;
    _shooting = false;
    _banner = 'GET READY!';
    _bannerT = 1.5;
  }

  @override
  void dispose() {
    _net?.close();
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.25);
    _last = now;
    if (_waiting) {
      _net!.update(dt);
      if (!_waiting) {
        _say('GET READY!');
        if (_w.youAreBoss) {
          // You start floating at the top of the map: look down over it.
          _yaw = pi / 2;
          _pitch = 0.8;
        }
      }
      setState(() {});
      return;
    }
    _readControls(dt);
    // Slow frames take a few small steps so nothing jumps through walls.
    final steps = (dt * 60).ceil().clamp(1, 15);
    final events = <ZombieEvent>[];
    for (var i = 0; i < steps; i++) {
      if (_net != null) {
        _net!.update(dt / steps);
      } else {
        _w.step(dt / steps);
      }
      events.addAll(_w.events);
    }
    _noticeChanges();
    if (_net != null && _net!.notes.isNotEmpty) {
      _say(_net!.notes.last.toUpperCase());
      _net!.notes.clear();
    }
    _bannerT = max(0, _bannerT - dt);
    _shake = max(0, _shake - dt * 3);
    _soundT = max(0, _soundT - dt);
    for (final e in events) {
      switch (e) {
        case ZombieEvent.shoot:
          if (_soundT <= 0) {
            SoundService.instance.play(GameSound.shoot);
            _soundT = 0.09;
          }
        case ZombieEvent.kill:
          SoundService.instance.play(GameSound.hit);
        case ZombieEvent.hurt:
          break; // see _noticeChanges
        case ZombieEvent.boom:
          _shake = max(_shake, 0.7);
        case ZombieEvent.pickup:
          SoundService.instance.play(GameSound.eat);
        case ZombieEvent.waveStart:
          _say(
            _w.bossWave ? 'WAVE ${_w.wave}: ZOMBIE KING!' : 'WAVE ${_w.wave}',
          );
          if (_w.mode == ZombieMode.versus && _w.wave == kKingArrives - 1) {
            _say('WAVE ${_w.wave}: THE KING COMES NEXT WAVE!');
          }
          SoundService.instance.play(GameSound.countdown);
        case ZombieEvent.waveClear:
          _say('WAVE ${_w.wave} CLEARED!');
          SoundService.instance.play(GameSound.levelComplete);
        case ZombieEvent.dead:
          SoundService.instance.play(GameSound.gameOver);
        case ZombieEvent.swing:
          SoundService.instance.play(GameSound.bowTwang);
        case ZombieEvent.kingArrives:
          _say(
            _w.youAreBoss
                ? 'YOU ARE THE ZOMBIE KING!'
                : 'THE ZOMBIE KING IS HERE!',
          );
          _bannerT = 3;
          SoundService.instance.play(GameSound.countdown);
        case ZombieEvent.smash:
          _shake = max(_shake, 0.4);
          SoundService.instance.play(GameSound.hit);
        case ZombieEvent.spawned:
          SoundService.instance.play(GameSound.place);
        case ZombieEvent.hit:
        case ZombieEvent.newWeapon:
        case ZombieEvent.keepWeapon:
          break; // see _noticeChanges
      }
    }
    if (_w.phase == ZombiePhase.over && !_paid) _finish();
    setState(() {});
  }

  void _say(String text) {
    _banner = text;
    _bannerT = 2;
  }

  /// Things that happen to you, worked out the same way whichever phone
  /// is running the game.
  void _noticeChanges() {
    final w = _w;
    if (w.youAreBoss) return;
    final s = w.you;
    if (s.hp < _lastHp - 0.01) {
      _shake = 0.5;
      SoundService.instance.play(GameSound.noMatch);
      if (s.hp <= 0 && w.survivors.any((o) => o.alive)) {
        _say('KNOCKED OUT! BACK NEXT WAVE');
        _bannerT = 3;
      }
    }
    if (s.weapons.length > _lastWeapons) {
      _say('YOU GOT A SWORD!');
      SoundService.instance.play(GameSound.win);
    }
    if (s.keptSword && !_lastKept) {
      // The 5% roll: the sword is yours for every game from now on.
      _save.guns.add('sword');
      _save.save();
      _say('LUCKY! THE SWORD IS YOURS TO KEEP!');
      _bannerT = 3.5;
    }
    _lastHp = s.hp;
    _lastWeapons = s.weapons.length;
    _lastKept = s.keptSword;
  }

  /// True if this phone's side won a Zombie vs Human game.
  bool get _youWon => _w.winner == (_w.youAreBoss ? 'zombies' : 'humans');

  int get _coinsForYou {
    final w = _w;
    if (w.mode != ZombieMode.versus) return w.coinsEarned;
    if (w.youAreBoss) return _youWon ? 100 : 20;
    return w.coinsEarned;
  }

  void _finish() {
    _paid = true;
    _save.coins += _coinsForYou;
    _save.kills += _w.youAreBoss ? 0 : _w.kills;
    if (_w.mode == ZombieMode.solo) {
      _save.bestWave = max(_save.bestWave, _w.wavesCleared);
    }
    _save.save();
  }

  // ---- controls ----------------------------------------------------------

  void _readControls(double dt) {
    final inp = _w.input;
    if (!_w.youAreBoss && !_w.you.alive) {
      inp
        ..move = Offset.zero
        ..fire = false;
      return;
    }
    // Turning with the keyboard.
    var turn = 0.0;
    if (_keys.contains(LogicalKeyboardKey.arrowLeft) ||
        _keys.contains(LogicalKeyboardKey.keyQ)) {
      turn -= 1;
    }
    if (_keys.contains(LogicalKeyboardKey.arrowRight) ||
        _keys.contains(LogicalKeyboardKey.keyE)) {
      turn += 1;
    }
    _yaw += turn * 2.6 * dt;

    // The stick and keys move you the way the camera is looking.
    var stick = Offset.zero; // x = right, y = forwards
    if (_moveStart != null) {
      final d = _moveNow - _moveStart!;
      if (d.distance > 6) stick = Offset(d.dx, -d.dy) / 45;
    }
    if (_keys.contains(LogicalKeyboardKey.keyA)) stick += const Offset(-1, 0);
    if (_keys.contains(LogicalKeyboardKey.keyD)) stick += const Offset(1, 0);
    if (_keys.contains(LogicalKeyboardKey.keyW) ||
        _keys.contains(LogicalKeyboardKey.arrowUp)) {
      stick += const Offset(0, 1);
    }
    if (_keys.contains(LogicalKeyboardKey.keyS) ||
        _keys.contains(LogicalKeyboardKey.arrowDown)) {
      stick += const Offset(0, -1);
    }
    final ahead = Offset(cos(_yaw), sin(_yaw));
    final right = Offset(-sin(_yaw), cos(_yaw));
    inp
      ..move = ahead * stick.dy + right * stick.dx
      // Shoot where the camera looks, nudged onto a zombie close to it.
      ..aim = (_w.youAreBoss ? _kingAimHelp(ahead) : _aimHelp(ahead)) ?? ahead
      ..fire = _shooting || _keys.contains(LogicalKeyboardKey.keyF)
      ..autoAim = false;
  }

  /// The way to a zombie that is nearly where you are looking, if any.
  /// Touch screens get more help.
  Offset? _aimHelp(Offset ahead) {
    final cone = _touch ? 0.45 : 0.22;
    Offset? best;
    var bestScore = double.infinity;
    for (final z in _w.zombies) {
      final to = z.pos - _w.player;
      final d = to.distance;
      if (d < 0.01 || d > _w.gun.range) continue;
      var diff = (to.direction - ahead.direction).abs() % (2 * pi);
      if (diff > pi) diff = 2 * pi - diff;
      if (diff > cone) continue;
      final score = diff * 10 + d * 0.1;
      if (score < bestScore) {
        bestScore = score;
        best = to;
      }
    }
    return best;
  }

  /// For the Zombie King: turn towards a person who's nearly in front.
  Offset? _kingAimHelp(Offset ahead) {
    final k = _w.king;
    if (k == null) return null;
    for (final s in _w.survivors) {
      final to = s.pos - k.pos;
      if (!s.alive || to.distance > k.r + 3) continue;
      var diff = (to.direction - ahead.direction).abs() % (2 * pi);
      if (diff > pi) diff = 2 * pi - diff;
      if (diff < 0.6) return to;
    }
    return null;
  }

  void _down(PointerDownEvent e) {
    _focus.requestFocus();
    if (e.kind == PointerDeviceKind.touch) {
      _touch = true;
    } else if (e.kind == PointerDeviceKind.mouse) {
      _touch = false;
    }
    if (e.kind != PointerDeviceKind.touch) {
      // Mouse: drag anywhere to turn the camera.
      _lookPointer = e.pointer;
      _lookLast = e.localPosition;
      return;
    }
    if (e.localPosition.dx < _size.width / 2) {
      if (_movePointer == null) {
        _movePointer = e.pointer;
        _moveStart = _moveNow = e.localPosition;
      }
    } else if (_lookPointer == null) {
      _lookPointer = e.pointer;
      _lookLast = e.localPosition;
    }
  }

  void _move(PointerEvent e) {
    if (e.pointer == _movePointer) _moveNow = e.localPosition;
    if (e.pointer == _lookPointer && _lookLast != null) {
      final d = e.localPosition - _lookLast!;
      _lookLast = e.localPosition;
      _yaw += d.dx * (_touch ? 0.011 : 0.008);
      _pitch = (_pitch + d.dy * 0.004).clamp(0.12, 1.2);
    }
  }

  void _up(PointerEvent e) {
    if (e.pointer == _movePointer) {
      _movePointer = null;
      _moveStart = null;
    }
    if (e.pointer == _lookPointer) {
      _lookPointer = null;
      _lookLast = null;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent) {
      _keys.add(e.logicalKey);
      if (e.logicalKey == LogicalKeyboardKey.keyG) _grenade();
      if (e.logicalKey == LogicalKeyboardKey.space) _jump();
      if (e.logicalKey == LogicalKeyboardKey.keyR) _swap();
      if (_w.youAreBoss) {
        const keys = [
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.digit4,
        ];
        final i = keys.indexOf(e.logicalKey);
        if (i >= 0) _order(ZombieOrder.values[i]);
      }
    } else if (e is KeyUpEvent) {
      _keys.remove(e.logicalKey);
    }
    return KeyEventResult.handled;
  }

  void _grenade() {
    if (_net != null) {
      _net!.grenade();
    } else {
      _w.input.grenade = true;
    }
  }

  void _jump() {
    if (_w.youAreBoss) return;
    if (_net != null) {
      _net!.jump();
    } else {
      _w.input.jump = true;
    }
  }

  void _swap() {
    if (_net != null) {
      _net!.swap();
    } else {
      _w.input.swap = true;
    }
  }

  void _order(ZombieOrder o) {
    final b = _w.boss;
    if (b == null || b.brains < o.cost) return;
    _net?.order(o);
  }

  // ---- screen ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (context, box) {
            _size = box.biggest;
            if (_net?.ended != null && _w.phase != ZombiePhase.over) {
              return _message(_net!.ended!);
            }
            if (_waiting) return _waitingRoom();
            final boss = _w.youAreBoss;
            return Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _down,
                    onPointerMove: _move,
                    onPointerUp: _up,
                    onPointerCancel: _up,
                    child: CustomPaint(
                      painter: Zombie3dPainter(
                        _w,
                        ZombieView(_yaw, _pitch),
                        shake: _shake,
                      ),
                    ),
                  ),
                ),
                Positioned(left: 0, right: 0, top: 0, child: _hud()),
                Positioned(
                  left: 8,
                  top: 8,
                  child: SafeArea(
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                      ),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
                Positioned(
                  right: 20,
                  bottom: 24,
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (boss) ...[
                          if (_w.king == null) _orderButtons(),
                          if (_w.king != null) _shootButton(label: 'SMASH'),
                        ] else ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_w.weapons.length > 1) ...[
                                _swapButton(),
                                const SizedBox(width: 10),
                              ],
                              _jumpButton(),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _grenadeButton(),
                              const SizedBox(width: 14),
                              _shootButton(),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_bannerT > 0 && _banner != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _size.height * 0.24,
                    child: IgnorePointer(child: _bannerText()),
                  ),
                if (!boss &&
                    inSafeZone(_w.player) &&
                    _w.phase != ZombiePhase.over)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _size.height * 0.16,
                    child: IgnorePointer(child: Center(child: _safeTag())),
                  ),
                if (_w.phase == ZombiePhase.over)
                  Positioned.fill(child: _overCard()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _hud() {
    final w = _w;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(64, 10, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (w.youAreBoss)
                        _bar(
                          Icons.psychology_rounded,
                          const Color(0xFFE040FB),
                          w.boss!.brains / kMaxBrains,
                          const Color(0xFFE040FB),
                          '${w.boss!.brains.floor()} brains',
                        )
                      else
                        _bar(
                          Icons.favorite_rounded,
                          const Color(0xFFFF5252),
                          w.hp / kMaxHp,
                          w.hp > 35
                              ? const Color(0xFF66BB6A)
                              : const Color(0xFFFF5252),
                          null,
                        ),
                      // How the other person is doing.
                      for (final o in w.survivors)
                        if (w.youAreBoss || !identical(o, w.you)) ...[
                          const SizedBox(height: 4),
                          _bar(
                            Icons.person_rounded,
                            Colors.white70,
                            o.hp / kMaxHp,
                            const Color(0xFF4FC3F7),
                            o.name,
                            small: true,
                          ),
                        ],
                      if (w.king case final k?) ...[
                        const SizedBox(height: 4),
                        _bar(
                          Icons.workspace_premium_rounded,
                          const Color(0xFFFFC107),
                          k.hp / k.maxHp,
                          const Color(0xFFFFC107),
                          w.youAreBoss ? 'You (King)' : 'Zombie King',
                          small: true,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        w.phase == ZombiePhase.rest && w.wave > 0
                            ? 'Next wave in ${w.phaseT.ceil()}...'
                            : 'Zombies left: ${w.zombiesLeft}',
                        style: _shadowed(13, FontWeight.w700),
                      ),
                      if (w.mode == ZombieMode.versus && w.king == null)
                        Text(
                          'The Zombie King comes at wave $kKingArrives',
                          style: _shadowed(12, FontWeight.w700),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'WAVE ${max(1, w.wave)}',
                  style: _shadowed(22, FontWeight.w900),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on_rounded,
                      color: Color(0xFFFFC93C),
                      size: 16,
                    ),
                    const SizedBox(width: 3),
                    Text('${w.coinsEarned}', style: _shadowed(14)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(
    IconData icon,
    Color iconColour,
    double value,
    Color colour,
    String? label, {
    bool small = false,
  }) => Row(
    children: [
      Icon(icon, color: iconColour, size: small ? 14 : 18),
      const SizedBox(width: 6),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: small ? 7 : 12,
            backgroundColor: Colors.black45,
            color: colour,
          ),
        ),
      ),
      if (label != null) ...[
        const SizedBox(width: 6),
        Text(label, style: _shadowed(small ? 11 : 13, FontWeight.w700)),
      ],
    ],
  );

  /// The zombie player's buttons: pay brains to send zombies in where
  /// you are floating.
  Widget _orderButtons() {
    final brains = _w.boss!.brains;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        for (final o in ZombieOrder.values)
          GestureDetector(
            onTap: () => _order(o),
            child: Container(
              width: 70,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: brains >= o.cost
                    ? const Color(0xCC7B1FA2)
                    : Colors.black38,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white70, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    o.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '${o.cost} ${o.cost == 1 ? 'brain' : 'brains'}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _message(String text) => Container(
    color: const Color(0xFF13241A),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('BACK TO MENU'),
        ),
      ],
    ),
  );

  /// Before your friend joins: show the room code to share.
  Widget _waitingRoom() {
    final net = _net!;
    final setup = net.setup;
    final role = setup.mode == ZombieMode.coop
        ? 'Team up against the zombies'
        : net.youAreZombie
        ? 'You are the zombies!'
        : setup.players > 2 && !net.isHost
        ? 'Zombie vs Humans'
        : setup.players > 2
        ? 'You are a human!'
        : 'You are the human!';
    final here = net.waiting;
    return Container(
      color: const Color(0xFF13241A),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            role,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF69F0AE),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${setup.map.title} • ${kZombieLevels[setup.level]}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 22),
          if (net.isHost && net.room.showCode) ...[
            const Text(
              'Tell your friend this code:',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              net.room.code,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 44,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
              ),
            ),
            const SizedBox(height: 14),
          ],
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(color: Color(0xFF69F0AE)),
          ),
          const SizedBox(height: 10),
          Text(
            here.isEmpty
                ? 'Joining...'
                : '${here.length} of ${setup.players} players here',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (here.isNotEmpty)
            Text(
              here.join(', '),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          const SizedBox(height: 4),
          Text(
            net.room.showCode
                ? 'Waiting for your friends...'
                : 'Waiting for more players...',
            style: const TextStyle(color: Colors.white54),
          ),
          if (net.isHost && here.length >= 2 && here.length < setup.players)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FilledButton(
                onPressed: net.startNow,
                child: Text('START WITH ${here.length}'),
              ),
            ),
          const SizedBox(height: 18),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
        ],
      ),
    );
  }

  static TextStyle _shadowed(
    double size, [
    FontWeight weight = FontWeight.w800,
  ]) => TextStyle(
    color: Colors.white,
    fontSize: size,
    fontWeight: weight,
    shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
  );

  Widget _bannerText() => Text(
    _banner!,
    textAlign: TextAlign.center,
    style: _shadowed(30, FontWeight.w900).copyWith(
      color: _banner!.contains('KING')
          ? const Color(0xFFFF5252)
          : const Color(0xFFB9F6CA),
      letterSpacing: 1.5,
    ),
  );

  Widget _safeTag() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xCC00C853),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.shield_rounded, color: Colors.white, size: 18),
        SizedBox(width: 6),
        Text(
          'SAFE ZONE: NO SHOOTING',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ],
    ),
  );

  /// Changes between your gun and a sword you picked up.
  Widget _swapButton() {
    final next = _w.weapons[(_w.weaponIndex + 1) % _w.weapons.length];
    return GestureDetector(
      onTap: _swap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white70, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz_rounded, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              next.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jumpButton() => GestureDetector(
    onTapDown: (_) => _jump(),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC1E88E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white70, width: 2),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.keyboard_double_arrow_up_rounded, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'JUMP',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    ),
  );

  Widget _grenadeButton() {
    final left = _w.grenades;
    return GestureDetector(
      onTap: _grenade,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: left > 0 ? const Color(0xCC558B2F) : Colors.black38,
          border: Border.all(color: Colors.white70, width: 2),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.brightness_7_rounded, color: Colors.white),
            Text(
              'x$left',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hold to keep shooting (or smashing, for the Zombie King).
  Widget _shootButton({String label = 'SHOOT'}) => Listener(
    onPointerDown: (e) {
      if (e.kind == PointerDeviceKind.touch) _touch = true;
      _shooting = true;
    },
    onPointerUp: (_) => _shooting = false,
    onPointerCancel: (_) => _shooting = false,
    child: Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: !_w.youAreBoss && inSafeZone(_w.player)
            ? Colors.black38
            : _shooting
            ? const Color(0xEEFF5252)
            : const Color(0xBBE53935),
        border: Border.all(color: Colors.white, width: 3),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.gps_fixed_rounded, color: Colors.white, size: 28),
          Text(
            label,
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

  Widget _overCard() {
    final w = _w;
    final best =
        w.mode == ZombieMode.solo &&
        w.wavesCleared >= _save.bestWave &&
        w.wavesCleared > 0;
    final versus = w.mode == ZombieMode.versus;
    final title = !versus
        ? 'THE ZOMBIES GOT YOU!'
        : _youWon
        ? 'YOU WIN!'
        : 'YOU LOSE!';
    final why = !versus
        ? null
        : w.winner == 'humans'
        ? 'The Zombie King was beaten!'
        : 'The zombies got the human!';
    final coins = _coinsForYou;
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2A1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF69F0AE), width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (why != null) ...[
              Text(
                why,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: versus && _youWon
                    ? const Color(0xFF69F0AE)
                    : const Color(0xFFFF8A80),
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'You survived ${w.wavesCleared} '
              '${w.wavesCleared == 1 ? 'wave' : 'waves'}'
              '${best ? ' (your best!)' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 17),
            ),
            const SizedBox(height: 4),
            Text(
              '${w.kills} zombies zapped',
              style: const TextStyle(color: Colors.white70),
            ),
            if (w.keptSword) ...[
              const SizedBox(height: 8),
              const Text(
                'You kept the Zombie Sword!',
                style: TextStyle(
                  color: Color(0xFFB9F6CA),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            if (coins > 0) ...[
              const SizedBox(height: 10),
              Text(
                '+$coins coins',
                style: const TextStyle(
                  color: Color(0xFFFFD54F),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (_net == null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => setState(_start),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43A047),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'PLAY AGAIN',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'BACK TO MENU',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
