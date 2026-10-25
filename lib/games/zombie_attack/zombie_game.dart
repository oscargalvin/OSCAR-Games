import 'dart:math';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/sound_service.dart';
import '../../widgets/full_screen_game.dart';
import 'zombie_3d.dart';
import 'zombie_data.dart';
import 'zombie_sim.dart';

/// One game of Zombie Attack: survive as many waves as you can.
class ZombieGameScreen extends StatefulWidget {
  final ZombieMap map;
  final int level;
  final String gunId;

  const ZombieGameScreen({
    super.key,
    this.map = ZombieMap.town,
    this.level = 1,
    this.gunId = 'pistol',
  });

  @override
  State<ZombieGameScreen> createState() => _ZombieGameScreenState();
}

class _ZombieGameScreenState extends State<ZombieGameScreen>
    with SingleTickerProviderStateMixin, FullScreenGame {
  late ZombieWorld _w;
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

  @override
  void initState() {
    super.initState();
    _start();
    _ticker = createTicker(_tick)..start();
  }

  void _start() {
    _w = ZombieWorld(
      map: widget.map,
      level: widget.level,
      gun: gunById(widget.gunId),
    );
    _paid = false;
    _yaw = -pi / 2;
    _shooting = false;
    _banner = 'GET READY!';
    _bannerT = 1.5;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.25);
    _last = now;
    _readControls(dt);
    // Slow frames take a few small steps so nothing jumps through walls.
    final steps = (dt * 60).ceil().clamp(1, 15);
    for (var i = 0; i < steps; i++) {
      _w.step(dt / steps);
    }
    _bannerT = max(0, _bannerT - dt);
    _shake = max(0, _shake - dt * 3);
    _soundT = max(0, _soundT - dt);
    for (final e in _w.events) {
      switch (e) {
        case ZombieEvent.shoot:
          if (_soundT <= 0) {
            SoundService.instance.play(GameSound.shoot);
            _soundT = 0.09;
          }
        case ZombieEvent.kill:
          SoundService.instance.play(GameSound.hit);
        case ZombieEvent.hurt:
          _shake = 0.5;
          SoundService.instance.play(GameSound.noMatch);
        case ZombieEvent.boom:
          _shake = max(_shake, 0.7);
        case ZombieEvent.pickup:
          SoundService.instance.play(GameSound.eat);
        case ZombieEvent.waveStart:
          _say(
            _w.bossWave ? 'WAVE ${_w.wave}: ZOMBIE KING!' : 'WAVE ${_w.wave}',
          );
          SoundService.instance.play(GameSound.countdown);
        case ZombieEvent.waveClear:
          _say('WAVE ${_w.wave} CLEARED!');
          SoundService.instance.play(GameSound.levelComplete);
        case ZombieEvent.dead:
          SoundService.instance.play(GameSound.gameOver);
        case ZombieEvent.hit:
          break;
      }
    }
    if (_w.phase == ZombiePhase.over && !_paid) _finish();
    setState(() {});
  }

  void _say(String text) {
    _banner = text;
    _bannerT = 2;
  }

  void _finish() {
    _paid = true;
    _save.coins += _w.coinsEarned;
    _save.kills += _w.kills;
    _save.bestWave = max(_save.bestWave, _w.wavesCleared);
    _save.save();
  }

  // ---- controls ----------------------------------------------------------

  void _readControls(double dt) {
    final inp = _w.input;
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
      ..aim = _aimHelp(ahead) ?? ahead
      ..fire = _shooting || _keys.contains(LogicalKeyboardKey.space)
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
      if (e.logicalKey == LogicalKeyboardKey.keyG) _w.input.grenade = true;
    } else if (e is KeyUpEvent) {
      _keys.remove(e.logicalKey);
    }
    return KeyEventResult.handled;
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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _grenadeButton(),
                        const SizedBox(width: 14),
                        _shootButton(),
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
                      Row(
                        children: [
                          const Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFFF5252),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: w.hp / kMaxHp,
                                minHeight: 12,
                                backgroundColor: Colors.black45,
                                color: w.hp > 35
                                    ? const Color(0xFF66BB6A)
                                    : const Color(0xFFFF5252),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        w.phase == ZombiePhase.rest && w.wave > 0
                            ? 'Next wave in ${w.phaseT.ceil()}...'
                            : 'Zombies left: ${w.zombiesLeft}',
                        style: _shadowed(13, FontWeight.w700),
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

  Widget _grenadeButton() {
    final left = _w.grenades;
    return GestureDetector(
      onTap: () => _w.input.grenade = true,
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

  /// Hold to keep shooting.
  Widget _shootButton() => Listener(
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
        color: _shooting ? const Color(0xEEFF5252) : const Color(0xBBE53935),
        border: Border.all(color: Colors.white, width: 3),
      ),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gps_fixed_rounded, color: Colors.white, size: 28),
          Text(
            'SHOOT',
            style: TextStyle(
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
    final best = w.wavesCleared >= _save.bestWave && w.wavesCleared > 0;
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
            const Text(
              'THE ZOMBIES GOT YOU!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFFF8A80),
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
            if (w.coinsEarned > 0) ...[
              const SizedBox(height: 10),
              Text(
                '+${w.coinsEarned} coins',
                style: const TextStyle(
                  color: Color(0xFFFFD54F),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
            const SizedBox(height: 18),
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
