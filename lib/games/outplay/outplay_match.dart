import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/sound_service.dart';
import 'outplay_art.dart';
import 'outplay_data.dart';

// The arena is laid out in these "world" units and scaled to fit the phone.
const double _arenaW = 480;
const double _arenaH = 720;
const double _radius = 20;
const double _walkSpeed = 190;
const int _roundsToWin = 5;

const Color _floor = Color(0xFF2B3350);
const Color _floorLine = Color(0xFF323B5C);
const Color _wallColor = Color(0xFF5C6A9C);
const Color _youColor = Color(0xFF4FC3F7);
const Color _botColor = Color(0xFFFF6B6B);

class _MapLayout {
  final String name;
  final List<Rect> walls;
  const _MapLayout(this.name, this.walls);
}

const List<_MapLayout> _maps = [
  _MapLayout('Crossroads', [
    Rect.fromLTWH(60, 170, 120, 24),
    Rect.fromLTWH(300, 170, 120, 24),
    Rect.fromLTWH(200, 330, 80, 60),
    Rect.fromLTWH(60, 526, 120, 24),
    Rect.fromLTWH(300, 526, 120, 24),
    Rect.fromLTWH(20, 330, 50, 60),
    Rect.fromLTWH(410, 330, 50, 60),
  ]),
  _MapLayout('Pillars', [
    Rect.fromLTWH(95, 190, 50, 50),
    Rect.fromLTWH(335, 190, 50, 50),
    Rect.fromLTWH(215, 335, 50, 50),
    Rect.fromLTWH(95, 480, 50, 50),
    Rect.fromLTWH(335, 480, 50, 50),
    Rect.fromLTWH(200, 130, 80, 20),
    Rect.fromLTWH(200, 570, 80, 20),
  ]),
  _MapLayout('Split', [
    Rect.fromLTWH(0, 345, 170, 30),
    Rect.fromLTWH(310, 345, 170, 30),
    Rect.fromLTWH(120, 180, 60, 60),
    Rect.fromLTWH(300, 480, 60, 60),
    Rect.fromLTWH(310, 200, 50, 40),
    Rect.fromLTWH(120, 480, 50, 40),
  ]),
];

class _Fighter {
  final bool isPlayer;
  final List<Gun?> guns;
  final Melee melee;
  final Map<String, int> levels;
  Offset pos;
  double aim;
  double hp = 100;
  int slot = 0; // 0 and 1 are guns, 2 is melee
  final List<int> ammo;
  int reloadingSlot = -1;
  double reloadT = 0;
  double cooldown = 0;
  int burstLeft = 0;
  double burstT = 0;
  double swingT = 0;
  double hurtT = 0;

  _Fighter({
    required this.isPlayer,
    required this.guns,
    required this.melee,
    required this.levels,
    required this.pos,
    required this.aim,
  }) : ammo = [guns[0]?.mag ?? 0, guns[1]?.mag ?? 0];

  Gun? get gun => slot < 2 ? guns[slot] : null;
  bool get reloading => reloadingSlot == slot && reloadingSlot >= 0;
  int lvl(String id) => levels[id] ?? 1;

  double get moveMul => gun?.moveMul ?? melee.moveMul;

  void resetForRound(Offset at, double facing) {
    pos = at;
    aim = facing;
    hp = 100;
    ammo[0] = guns[0]?.mag ?? 0;
    ammo[1] = guns[1]?.mag ?? 0;
    reloadingSlot = -1;
    cooldown = 0;
    burstLeft = 0;
    swingT = 0;
    hurtT = 0;
  }
}

class _Bullet {
  Offset pos;
  final Offset vel;
  final double damage;
  double travel;
  final bool fromPlayer;
  final double splash;
  final Color color;
  final bool flame;
  _Bullet(
    this.pos,
    this.vel,
    this.damage,
    this.travel,
    this.fromPlayer,
    this.splash,
    this.color,
    this.flame,
  );
}

class _Popup {
  Offset pos;
  final String text;
  final Color color;
  double t = 0;
  _Popup(this.pos, this.text, this.color);
}

class _Boom {
  final Offset pos;
  final double radius;
  double t = 0;
  _Boom(this.pos, this.radius);
}

enum _Phase { countdown, fight, roundOver, matchOver }

class _Stick {
  final Offset origin;
  Offset current;
  _Stick(this.origin) : current = origin;
  Offset get delta => current - origin;
}

/// One duel against a bot: first to five rounds wins.
class OutplayMatchScreen extends StatefulWidget {
  const OutplayMatchScreen({super.key});

  @override
  State<OutplayMatchScreen> createState() => _OutplayMatchScreenState();
}

class _OutplayMatchScreenState extends State<OutplayMatchScreen>
    with SingleTickerProviderStateMixin {
  final _rnd = Random();
  final _save = OutplaySave.instance;
  final _focus = FocusNode();
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  late _Fighter _you;
  late _Fighter _bot;
  late _MapLayout _map;
  final List<_Bullet> _bullets = [];
  final List<_Popup> _popups = [];
  final List<_Boom> _booms = [];

  _Phase _phase = _Phase.countdown;
  double _phaseT = 0;
  int _round = 1;
  int _yourRounds = 0;
  int _botRounds = 0;
  bool _lastRoundYours = false;
  int _coinsEarned = 0;
  double _shootSoundT = 0;

  // Bot brain.
  late final int _tier;
  double _botStrafe = 1;
  double _botStrafeT = 0;
  double _botStuckT = 0;
  Offset _botLastPos = Offset.zero;
  double _botWobble = 0;
  double _botBlindT = 0;
  double _botFlankT = 0;
  Offset? _botFlank;

  // Touch controls.
  final Map<int, _Stick> _moveStick = {};
  final Map<int, _Stick> _aimStick = {};
  final Set<LogicalKeyboardKey> _keys = {};
  Size _arenaPx = Size.zero;

  @override
  void initState() {
    super.initState();
    _tier = _save.wins.clamp(0, 12);
    _map = _maps[_rnd.nextInt(_maps.length)];
    _you = _Fighter(
      isPlayer: true,
      guns: [
        gunById(_save.primary),
        _save.secondSlot && _save.secondary != null
            ? gunById(_save.secondary!)
            : null,
      ],
      melee: meleeById(_save.melee),
      levels: Map.of(_save.levels),
      pos: const Offset(_arenaW / 2, _arenaH - 60),
      aim: -pi / 2,
    );
    // The bot gets better guns as you win more matches.
    final pool = kGuns.take(min(kGuns.length, 2 + _tier)).toList();
    final botGun = pool[_rnd.nextInt(pool.length)];
    final botLevel = 1 + (_tier ~/ 3).clamp(0, kMaxLevel - 1);
    _bot = _Fighter(
      isPlayer: false,
      guns: [botGun, null],
      melee: kMelees.first,
      levels: {botGun.id: botLevel, 'fist': botLevel},
      pos: const Offset(_arenaW / 2, 60),
      aim: pi / 2,
    );
    _startRound();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startRound() {
    _you.resetForRound(const Offset(_arenaW / 2, _arenaH - 60), -pi / 2);
    _bot.resetForRound(const Offset(_arenaW / 2, 60), pi / 2);
    _you.slot = 0;
    _bot.slot = 0;
    _bullets.clear();
    _booms.clear();
    _botFlank = null;
    _botBlindT = 0;
    _botFlankT = 0;
    _phase = _Phase.countdown;
    _phaseT = 0;
  }

  // ---- game loop ----------------------------------------------------------

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 0.016
        : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    _phaseT += dt;
    _shootSoundT -= dt;

    switch (_phase) {
      case _Phase.countdown:
        if (_phaseT >= 2.4) {
          _phase = _Phase.fight;
          _phaseT = 0;
        }
        _updateAimOnly();
        break;
      case _Phase.fight:
        _updateFighter(_you, dt, _playerInput());
        _updateFighter(_bot, dt, _botInput(dt));
        _separate();
        _updateBullets(dt);
        break;
      case _Phase.roundOver:
        _updateBullets(dt);
        if (_phaseT >= 1.8) {
          if (_yourRounds >= _roundsToWin || _botRounds >= _roundsToWin) {
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

    for (final f in [_you, _bot]) {
      f.swingT = max(0, f.swingT - dt);
      f.hurtT = max(0, f.hurtT - dt);
    }
    for (final p in _popups) {
      p.t += dt;
      p.pos = p.pos.translate(0, -40 * dt);
    }
    _popups.removeWhere((p) => p.t > 0.8);
    for (final b in _booms) {
      b.t += dt;
    }
    _booms.removeWhere((b) => b.t > 0.4);
    setState(() {});
  }

  void _updateAimOnly() {
    final i = _playerInput();
    if (i.aim != null) _you.aim = i.aim!;
  }

  _Input _playerInput() {
    var move = Offset.zero;
    if (_moveStick.isNotEmpty) {
      final d = _moveStick.values.first.delta;
      final len = d.distance;
      if (len > 6) move = d / max(len, 48.0);
    }
    var kx = 0.0, ky = 0.0;
    if (_keys.contains(LogicalKeyboardKey.keyA)) kx -= 1;
    if (_keys.contains(LogicalKeyboardKey.keyD)) kx += 1;
    if (_keys.contains(LogicalKeyboardKey.keyW)) ky -= 1;
    if (_keys.contains(LogicalKeyboardKey.keyS)) ky += 1;
    if (kx != 0 || ky != 0) {
      move = Offset(kx, ky) / Offset(kx, ky).distance;
    }

    double? aim;
    var fire = false;
    if (_aimStick.isNotEmpty) {
      fire = true;
      final d = _aimStick.values.first.delta;
      if (d.distance > 18) {
        aim = d.direction;
        // A little aim help: snap onto the enemy when close to them.
        final toBot = (_bot.pos - _you.pos).direction;
        if (_angleDiff(aim, toBot).abs() < 0.22 &&
            _lineOfSight(_you.pos, _bot.pos)) {
          aim = toBot;
        }
      } else {
        aim = (_bot.pos - _you.pos).direction; // tap to auto-aim
      }
    }
    var ax = 0.0, ay = 0.0;
    if (_keys.contains(LogicalKeyboardKey.arrowLeft)) ax -= 1;
    if (_keys.contains(LogicalKeyboardKey.arrowRight)) ax += 1;
    if (_keys.contains(LogicalKeyboardKey.arrowUp)) ay -= 1;
    if (_keys.contains(LogicalKeyboardKey.arrowDown)) ay += 1;
    if (ax != 0 || ay != 0) {
      aim = Offset(ax, ay).direction;
      fire = true;
    }
    if (_keys.contains(LogicalKeyboardKey.space)) {
      aim = (_bot.pos - _you.pos).direction;
      fire = true;
    }
    if (aim == null && move != Offset.zero) aim = move.direction;
    return _Input(move, aim, fire);
  }

  _Input _botInput(double dt) {
    final b = _bot;
    final toYou = _you.pos - b.pos;
    final dist = toYou.distance;
    final sees = _lineOfSight(b.pos, _you.pos);
    final gun = b.guns[0]!;

    // Use fists when right up close, otherwise the gun.
    final wantSlot = dist < 60 ? 2 : 0;
    if (b.slot != wantSlot) _switchSlot(b, wantSlot);

    _botStrafeT -= dt;
    if (_botStrafeT <= 0) {
      _botStrafe = _rnd.nextBool() ? 1 : -1;
      _botStrafeT = 0.8 + _rnd.nextDouble() * 1.4;
    }
    // Notice when stuck on a wall and wander a different way.
    _botStuckT += dt;
    if (_botStuckT > 0.5) {
      if ((b.pos - _botLastPos).distance < 12) {
        _botStrafe = -_botStrafe;
        _botStrafeT = 0.9;
      }
      _botLastPos = b.pos;
      _botStuckT = 0;
    }

    // If it can't see you for a while, head for a spot that can.
    _botBlindT = sees ? 0 : _botBlindT + dt;
    if (sees) _botFlank = null;
    _botFlankT -= dt;
    if (_botFlank != null && _botFlankT <= 0) _botFlank = null; // give up
    if (_botBlindT > 1.5 && _botFlank == null) {
      // Prefer a spot it can walk straight to; otherwise any spot that sees you.
      Offset? fallback;
      for (var i = 0; i < 40; i++) {
        final p = Offset(
          _radius + _rnd.nextDouble() * (_arenaW - _radius * 2),
          _radius + _rnd.nextDouble() * (_arenaH - _radius * 2),
        );
        if (_hitsWall(p) || !_lineOfSight(p, _you.pos)) continue;
        if (_lineOfSight(b.pos, p)) {
          _botFlank = p;
          break;
        }
        fallback ??= p;
      }
      _botFlank ??= fallback;
      _botFlankT = 2.5;
    }

    var move = Offset.zero;
    final flank = _botFlank;
    if (flank != null) {
      final d = flank - b.pos;
      if (d.distance < 20) {
        _botFlank = null;
        _botBlindT = 0;
      } else {
        move = d / d.distance;
      }
    } else if (dist > 0.01) {
      final dir = toYou / dist;
      final side = Offset(-dir.dy, dir.dx) * _botStrafe;
      if (sees) {
        final want = (gun.range * 0.45).clamp(110.0, 380.0);
        final push = dist > want + 40 ? 0.8 : (dist < want - 40 ? -0.7 : 0.0);
        move = dir * push + side * 0.8;
      } else {
        move = dir * 0.9 + side * 0.6;
      }
      if (move.distance > 1) move = move / move.distance;
    }

    // Aim with some wobble, which shrinks as you beat more bots.
    _botWobble += dt * 2.3;
    final error = (0.26 - _tier * 0.017).clamp(0.06, 0.26) * sin(_botWobble);
    final target = toYou.direction + error;
    final turn = (4.0 + _tier * 0.4) * dt;
    final diff = _angleDiff(b.aim, target);
    final aim = b.aim + diff.clamp(-turn, turn);

    final reach = b.slot == 2 ? b.melee.reach + _radius * 2 : gun.range;
    final fire = _phaseT > 0.5 && sees && diff.abs() < 0.3 && dist < reach;
    return _Input(move * 0.92, aim, fire);
  }

  void _updateFighter(_Fighter f, double dt, _Input input) {
    if (input.aim != null) f.aim = input.aim!;
    final speed = _walkSpeed * f.moveMul;
    f.pos += input.move * speed * dt;
    _collideWalls(f);

    f.cooldown -= dt;
    if (f.reloadingSlot >= 0) {
      f.reloadT -= dt;
      if (f.reloadT <= 0) {
        f.ammo[f.reloadingSlot] = f.guns[f.reloadingSlot]!.mag;
        f.reloadingSlot = -1;
      }
    }

    final gun = f.gun;
    if (gun != null) {
      if (f.burstLeft > 0) {
        f.burstT -= dt;
        if (f.burstT <= 0 && f.ammo[f.slot] > 0) {
          _shoot(f, gun);
          f.burstLeft--;
          f.burstT = 0.07;
        }
      } else if (input.fire && f.cooldown <= 0 && !f.reloading) {
        if (f.ammo[f.slot] <= 0) {
          _startReload(f);
        } else {
          _shoot(f, gun);
          f.burstLeft = gun.burst - 1;
          f.burstT = 0.07;
          f.cooldown = gun.fireInterval * levelSpeedMul(f.lvl(gun.id));
        }
      }
      if (f.ammo[f.slot] <= 0 && !f.reloading && f.burstLeft == 0) {
        _startReload(f);
      }
    } else if (input.fire && f.cooldown <= 0) {
      _swing(f);
    }
  }

  void _startReload(_Fighter f) {
    final g = f.gun;
    if (g == null || f.ammo[f.slot] >= g.mag) return;
    f.reloadingSlot = f.slot;
    f.reloadT = g.reload;
    f.burstLeft = 0;
  }

  void _switchSlot(_Fighter f, int slot) {
    if (slot < 2 && f.guns[slot] == null) return;
    if (f.slot == slot) return;
    f.slot = slot;
    f.burstLeft = 0;
    if (f.reloadingSlot != slot) f.reloadingSlot = -1;
    f.cooldown = max(f.cooldown, 0.15);
  }

  void _shoot(_Fighter f, Gun g) {
    f.ammo[f.slot]--;
    final dmg = g.damage * levelDamageMul(f.lvl(g.id));
    final muzzle = f.pos + Offset.fromDirection(f.aim, _radius + 14);
    for (var i = 0; i < g.pellets; i++) {
      final a = f.aim + (_rnd.nextDouble() * 2 - 1) * g.spread;
      final speed =
          g.bulletSpeed * (g.pellets > 1 ? 0.85 + _rnd.nextDouble() * 0.3 : 1);
      _bullets.add(
        _Bullet(
          muzzle,
          Offset.fromDirection(a, speed),
          dmg,
          g.range,
          f.isPlayer,
          g.splash,
          g.color,
          g.look == WeaponLook.flamer,
        ),
      );
    }
    if (f.isPlayer && _shootSoundT <= 0) {
      SoundService.instance.play(GameSound.shoot);
      _shootSoundT = 0.14;
    }
  }

  void _swing(_Fighter f) {
    final m = f.melee;
    f.cooldown = m.cooldown * levelSpeedMul(f.lvl(m.id));
    f.swingT = 0.2;
    final other = f.isPlayer ? _bot : _you;
    final d = other.pos - f.pos;
    if (d.distance <= m.reach + _radius * 2 &&
        _angleDiff(f.aim, d.direction).abs() <= m.arc / 2 + 0.25) {
      _damage(other, m.damage * levelDamageMul(f.lvl(m.id)), other.pos);
      other.pos += Offset.fromDirection(d.direction, 14);
      _collideWalls(other);
    }
    if (f.isPlayer) SoundService.instance.play(GameSound.tap);
  }

  void _updateBullets(double dt) {
    final remove = <_Bullet>{};
    for (final b in _bullets) {
      final stepLen = b.vel.distance * dt;
      final steps = max(1, (stepLen / 8).ceil());
      final step = b.vel * (dt / steps);
      for (var i = 0; i < steps; i++) {
        b.pos += step;
        b.travel -= step.distance;
        final target = b.fromPlayer ? _bot : _you;
        if (_phase == _Phase.fight &&
            (b.pos - target.pos).distance < _radius + 3) {
          if (b.splash > 0) {
            _explode(b);
          } else {
            _damage(target, b.damage, b.pos);
          }
          remove.add(b);
          break;
        }
        if (b.travel <= 0 || _hitsWall(b.pos)) {
          if (b.splash > 0) _explode(b);
          remove.add(b);
          break;
        }
      }
    }
    _bullets.removeWhere(remove.contains);
  }

  void _explode(_Bullet b) {
    _booms.add(_Boom(b.pos, b.splash));
    if (_phase != _Phase.fight) return;
    final target = b.fromPlayer ? _bot : _you;
    final d = (target.pos - b.pos).distance - _radius;
    if (d < b.splash) {
      final falloff = 1 - 0.5 * (max(0, d) / b.splash);
      _damage(target, b.damage * falloff, target.pos);
    }
  }

  void _damage(_Fighter f, double amount, Offset at) {
    if (_phase != _Phase.fight || f.hp <= 0) return;
    f.hp -= amount;
    f.hurtT = 0.15;
    _popups.add(
      _Popup(
        at,
        amount.round().toString(),
        f.isPlayer ? _botColor : Colors.white,
      ),
    );
    if (!f.isPlayer) SoundService.instance.play(GameSound.hit);
    if (f.hp <= 0) {
      f.hp = 0;
      _lastRoundYours = !f.isPlayer;
      if (_lastRoundYours) {
        _yourRounds++;
        _coinsEarned += 15;
      } else {
        _botRounds++;
      }
      _phase = _Phase.roundOver;
      _phaseT = 0;
    }
  }

  void _finishMatch() {
    final won = _yourRounds > _botRounds;
    _coinsEarned += won ? 60 : 20;
    _save.coins += _coinsEarned;
    if (won) {
      _save.wins++;
    } else {
      _save.losses++;
    }
    _save.save();
    SoundService.instance.play(won ? GameSound.win : GameSound.gameOver);
    _phase = _Phase.matchOver;
    _phaseT = 0;
  }

  // ---- physics helpers ----------------------------------------------------

  void _collideWalls(_Fighter f) {
    var p = Offset(
      f.pos.dx.clamp(_radius, _arenaW - _radius),
      f.pos.dy.clamp(_radius, _arenaH - _radius),
    );
    for (final w in _map.walls) {
      final cx = p.dx.clamp(w.left, w.right);
      final cy = p.dy.clamp(w.top, w.bottom);
      final d = p - Offset(cx, cy);
      final dist = d.distance;
      if (dist < _radius) {
        if (dist > 0.001) {
          p = Offset(cx, cy) + d / dist * _radius;
        } else {
          p = Offset(p.dx, w.top - _radius);
        }
      }
    }
    f.pos = p;
  }

  void _separate() {
    final d = _you.pos - _bot.pos;
    final dist = d.distance;
    if (dist < _radius * 2 && dist > 0.001) {
      final push = d / dist * (_radius * 2 - dist) / 2;
      _you.pos += push;
      _bot.pos -= push;
      _collideWalls(_you);
      _collideWalls(_bot);
    }
  }

  bool _hitsWall(Offset p) {
    if (p.dx < 0 || p.dy < 0 || p.dx > _arenaW || p.dy > _arenaH) return true;
    for (final w in _map.walls) {
      if (w.contains(p)) return true;
    }
    return false;
  }

  bool _lineOfSight(Offset a, Offset b) {
    final d = b - a;
    final steps = (d.distance / 10).ceil();
    for (var i = 1; i < steps; i++) {
      if (_hitsWall(a + d * (i / steps))) return false;
    }
    return true;
  }

  static double _angleDiff(double from, double to) {
    var d = (to - from) % (2 * pi);
    if (d > pi) d -= 2 * pi;
    return d;
  }

  // ---- input --------------------------------------------------------------

  void _pointerDown(PointerDownEvent e) {
    if (e.localPosition.dx < _arenaPx.width / 2) {
      _moveStick
        ..clear()
        ..[e.pointer] = _Stick(e.localPosition);
    } else {
      _aimStick
        ..clear()
        ..[e.pointer] = _Stick(e.localPosition);
    }
  }

  void _pointerMove(PointerMoveEvent e) {
    final s = _moveStick[e.pointer] ?? _aimStick[e.pointer];
    if (s == null) return;
    // Keep the knob within reach of where the thumb started.
    var d = e.localPosition - s.origin;
    if (d.distance > 60) d = d / d.distance * 60;
    s.current = s.origin + d;
  }

  void _pointerUp(PointerEvent e) {
    _moveStick.remove(e.pointer);
    _aimStick.remove(e.pointer);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    if (e is KeyDownEvent) {
      _keys.add(k);
      if (k == LogicalKeyboardKey.digit1) _switchSlot(_you, 0);
      if (k == LogicalKeyboardKey.digit2) _switchSlot(_you, 1);
      if (k == LogicalKeyboardKey.digit3) _switchSlot(_you, 2);
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
      backgroundColor: const Color(0xFF1B2138),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    _arenaPx = c.biggest;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: _pointerDown,
                          onPointerMove: _pointerMove,
                          onPointerUp: _pointerUp,
                          onPointerCancel: _pointerUp,
                          child: CustomPaint(painter: _ArenaPainter(this)),
                        ),
                        if (_phase != _Phase.fight) _buildBanner(),
                      ],
                    );
                  },
                ),
              ),
              _buildWeaponBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            tooltip: 'Leave match',
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(child: _hpBar('You', _you.hp, _youColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '$_yourRounds - $_botRounds',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(child: _hpBar('Bot', _bot.hp, _botColor, alignRight: true)),
        ],
      ),
    );
  }

  Widget _hpBar(
    String label,
    double hp,
    Color color, {
    bool alignRight = false,
  }) {
    return Column(
      crossAxisAlignment: alignRight
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: LinearProgressIndicator(
              value: hp / 100,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBanner() {
    String big;
    String small;
    switch (_phase) {
      case _Phase.countdown:
        final left = 3 - (_phaseT / 0.6).floor();
        big = left > 0 ? '$left' : 'FIGHT!';
        small = 'Round $_round  ·  ${_map.name}';
        break;
      case _Phase.roundOver:
        big = _lastRoundYours ? 'OUTPLAYED!' : 'You got outplayed';
        small = _lastRoundYours ? '+15 coins' : 'Get them next round';
        break;
      case _Phase.matchOver:
        return _buildMatchOver();
      case _Phase.fight:
        return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMatchOver() {
    final won = _yourRounds > _botRounds;
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF262E4F),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: won ? _youColor : _botColor, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                won ? 'VICTORY' : 'DEFEAT',
                style: TextStyle(
                  color: won ? _youColor : _botColor,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$_yourRounds - $_botRounds',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.monetization_on_rounded,
                    color: Color(0xFFFFC93C),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '+$_coinsEarned coins',
                    style: const TextStyle(
                      color: Color(0xFFFFC93C),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back to lobby'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const OutplayMatchScreen(),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                    ),
                    child: const Text('Play again'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeaponBar() {
    Widget slotButton(int slot) {
      final selected = _you.slot == slot;
      final gun = slot < 2 ? _you.guns[slot] : null;
      final empty = slot < 2 && gun == null;
      final look = gun?.look ?? _you.melee.look;
      final color = gun?.color ?? _you.melee.color;
      String label;
      if (empty) {
        label = slot == 1 && !_save.secondSlot ? 'Locked' : 'Empty';
      } else if (gun == null) {
        label = _you.melee.name;
      } else if (_you.reloadingSlot == slot) {
        label = 'Reloading';
      } else {
        label = '${_you.ammo[slot]}/${gun.mag}';
      }
      return Expanded(
        child: GestureDetector(
          onTap: empty ? null : () => _switchSlot(_you, slot),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF3A4675)
                  : const Color(0xFF262E4F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? _youColor : Colors.white12,
                width: 2,
              ),
            ),
            child: Opacity(
              opacity: empty ? 0.35 : 1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  empty
                      ? const SizedBox(
                          height: 28,
                          child: Icon(
                            Icons.lock_rounded,
                            color: Colors.white54,
                            size: 22,
                          ),
                        )
                      : WeaponIcon(look: look, color: color, size: 46),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
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
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: Row(
        children: [
          slotButton(0),
          slotButton(1),
          slotButton(2),
          SizedBox(
            width: 52,
            child: IconButton(
              tooltip: 'Reload',
              onPressed: () => _startReload(_you),
              icon: const Icon(
                Icons.autorenew_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Input {
  final Offset move;
  final double? aim;
  final bool fire;
  const _Input(this.move, this.aim, this.fire);
}

class _ArenaPainter extends CustomPainter {
  final _OutplayMatchScreenState s;
  _ArenaPainter(this.s);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = min(size.width / _arenaW, size.height / _arenaH);
    final ox = (size.width - _arenaW * scale) / 2;
    final oy = (size.height - _arenaH * scale) / 2;

    canvas.save();
    canvas.translate(ox, oy);
    canvas.scale(scale);

    // Floor and grid.
    final arena = const Rect.fromLTWH(0, 0, _arenaW, _arenaH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(arena, const Radius.circular(18)),
      Paint()..color = _floor,
    );
    final line = Paint()
      ..color = _floorLine
      ..strokeWidth = 2;
    for (double x = 40; x < _arenaW; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, _arenaH), line);
    }
    for (double y = 40; y < _arenaH; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(_arenaW, y), line);
    }

    // Walls with a chunky shadow.
    for (final w in s._map.walls) {
      final r = RRect.fromRectAndRadius(w, const Radius.circular(8));
      canvas.drawRRect(
        r.shift(const Offset(0, 6)),
        Paint()..color = const Color(0xFF1A1F35),
      );
      canvas.drawRRect(r, Paint()..color = _wallColor);
      canvas.drawRRect(
        r,
        Paint()
          ..color = kOutplayInk
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    // Bullets.
    for (final b in s._bullets) {
      if (b.flame) {
        final life = (b.travel / 230).clamp(0.0, 1.0);
        canvas.drawCircle(
          b.pos,
          6 + (1 - life) * 10,
          Paint()
            ..color = Color.lerp(
              const Color(0xFFFFEB3B),
              const Color(0xFFFF5722),
              1 - life,
            )!.withValues(alpha: 0.75),
        );
      } else if (b.splash > 0) {
        canvas.drawCircle(b.pos, 7, Paint()..color = b.color);
        canvas.drawCircle(
          b.pos - b.vel / b.vel.distance * 10,
          5,
          Paint()..color = const Color(0xAAFFC107),
        );
      } else {
        final tail = b.pos - b.vel / b.vel.distance * 14;
        canvas.drawLine(
          tail,
          b.pos,
          Paint()
            ..color = const Color(0xFFFFF59D)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    _paintFighter(canvas, s._bot, _botColor);
    _paintFighter(canvas, s._you, _youColor);

    for (final b in s._booms) {
      final t = b.t / 0.4;
      canvas.drawCircle(
        b.pos,
        b.radius * (0.4 + t * 0.6),
        Paint()
          ..color = const Color(0xFFFF9800).withValues(alpha: 0.6 * (1 - t)),
      );
    }

    for (final p in s._popups) {
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            color: p.color.withValues(alpha: 1 - p.t / 0.8),
            fontSize: 22,
            fontWeight: FontWeight.w900,
            shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p.pos - Offset(tp.width / 2, 40));
    }
    canvas.restore();

    // Thumb sticks, in screen space.
    for (final st in [...s._moveStick.values, ...s._aimStick.values]) {
      canvas.drawCircle(st.origin, 60, Paint()..color = Colors.white12);
      canvas.drawCircle(
        st.origin,
        60,
        Paint()
          ..color = Colors.white30
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(st.current, 26, Paint()..color = Colors.white38);
    }
    if (s._moveStick.isEmpty &&
        s._aimStick.isEmpty &&
        s._phase != _Phase.matchOver) {
      _hint(
        canvas,
        size,
        'Drag to move',
        Offset(size.width * 0.25, size.height - 24),
      );
      _hint(
        canvas,
        size,
        'Tap or drag to shoot',
        Offset(size.width * 0.75, size.height - 24),
      );
    }
  }

  void _hint(Canvas canvas, Size size, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width / 2 - 8);
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintFighter(Canvas canvas, _Fighter f, Color color) {
    if (f.hp <= 0) {
      canvas.drawCircle(f.pos, _radius, Paint()..color = Colors.white10);
      return;
    }
    // Melee swing arc.
    if (f.swingT > 0 && f.slot == 2) {
      final m = f.melee;
      final r = _radius + m.reach;
      canvas.drawArc(
        Rect.fromCircle(center: f.pos, radius: r),
        f.aim - m.arc / 2,
        m.arc,
        true,
        Paint()..color = Colors.white.withValues(alpha: 0.25 * f.swingT / 0.2),
      );
    }

    canvas.drawCircle(
      f.pos.translate(0, 5),
      _radius,
      Paint()..color = Colors.black26,
    );

    // Weapon held out in front.
    canvas.save();
    canvas.translate(f.pos.dx, f.pos.dy);
    canvas.rotate(f.aim);
    final gun = f.gun;
    final swingPush = f.swingT > 0 ? 10 * sin(f.swingT / 0.2 * pi) : 0.0;
    canvas.translate(_radius + 10 + swingPush, 6);
    if (gun != null) {
      paintWeapon(canvas, gun.look, gun.color, 44);
    } else {
      paintWeapon(
        canvas,
        f.melee.look,
        f.melee.color,
        f.melee.look == WeaponLook.scythe ? 60 : 26,
      );
    }
    canvas.restore();

    canvas.drawCircle(
      f.pos,
      _radius,
      Paint()..color = f.hurtT > 0 ? Colors.white : color,
    );
    canvas.drawCircle(
      f.pos,
      _radius,
      Paint()
        ..color = kOutplayInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );
    // Eyes look where you aim.
    final eye = Offset.fromDirection(f.aim, 6);
    final side = Offset.fromDirection(f.aim + pi / 2, 6);
    for (final o in [side, -side]) {
      canvas.drawCircle(f.pos + eye + o, 3.5, Paint()..color = kOutplayInk);
    }

    // Little health bar overhead.
    final bar = Rect.fromLTWH(f.pos.dx - 22, f.pos.dy - _radius - 14, 44, 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar, const Radius.circular(3)),
      Paint()..color = Colors.black45,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bar.left, bar.top, bar.width * f.hp / 100, bar.height),
        const Radius.circular(3),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ArenaPainter oldDelegate) => true;
}
