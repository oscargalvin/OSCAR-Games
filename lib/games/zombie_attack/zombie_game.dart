import 'dart:math';

import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/sound_service.dart';
import '../../widgets/full_screen_game.dart';
import 'zombie_data.dart';
import 'zombie_sim.dart';

/// How many metres you can see across the short side of the screen.
const double kViewMetres = 18;

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

  // Touch sticks: left drives, right aims and shoots.
  int? _movePointer, _aimPointer;
  Offset? _moveStart, _aimStart;
  Offset _moveNow = Offset.zero, _aimNow = Offset.zero;
  bool _touch = false; // playing on a touch screen
  Offset? _mouse; // where the mouse is pointing (PC)
  bool _mouseDown = false;

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
    _readControls();
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

  void _readControls() {
    final inp = _w.input;
    var move = Offset.zero;
    if (_moveStart != null) {
      final d = _moveNow - _moveStart!;
      if (d.distance > 6) move = d / 45;
    }
    if (_keys.contains(LogicalKeyboardKey.keyA) ||
        _keys.contains(LogicalKeyboardKey.arrowLeft)) {
      move += const Offset(-1, 0);
    }
    if (_keys.contains(LogicalKeyboardKey.keyD) ||
        _keys.contains(LogicalKeyboardKey.arrowRight)) {
      move += const Offset(1, 0);
    }
    if (_keys.contains(LogicalKeyboardKey.keyW) ||
        _keys.contains(LogicalKeyboardKey.arrowUp)) {
      move += const Offset(0, -1);
    }
    if (_keys.contains(LogicalKeyboardKey.keyS) ||
        _keys.contains(LogicalKeyboardKey.arrowDown)) {
      move += const Offset(0, 1);
    }
    inp.move = move;

    Offset? aim;
    var fire = false;
    if (_aimStart != null) {
      final d = _aimNow - _aimStart!;
      if (d.distance > 8) aim = d;
      fire = true; // holding the right side shoots
    } else if (_mouse != null && !_touch) {
      aim = _toWorld(_mouse!) - _w.player;
      fire = _mouseDown;
    }
    inp
      ..aim = aim
      ..fire = fire
      // On a touch screen your gun aims and fires by itself.
      ..autoAim = _touch;
  }

  double get _scale =>
      _size.shortestSide <= 0 ? 20 : _size.shortestSide / kViewMetres;

  /// The world point in the middle of the screen.
  Offset get _camera {
    final halfW = _size.width / _scale / 2, halfH = _size.height / _scale / 2;
    double fit(double v, double half, double world) =>
        half * 2 >= world ? world / 2 : v.clamp(half, world - half);
    return Offset(
      fit(_w.player.dx, halfW, kWorldW),
      fit(_w.player.dy, halfH, kWorldH),
    );
  }

  Offset _toWorld(Offset screen) =>
      _camera + (screen - _size.center(Offset.zero)) / _scale;

  void _down(PointerDownEvent e) {
    _focus.requestFocus();
    if (e.kind == PointerDeviceKind.touch) _touch = true;
    if (e.kind == PointerDeviceKind.mouse) {
      _touch = false;
      _mouse = e.localPosition;
      if (e.buttons & kPrimaryButton != 0) _mouseDown = true;
      return;
    }
    if (e.localPosition.dx < _size.width / 2) {
      if (_movePointer == null) {
        _movePointer = e.pointer;
        _moveStart = _moveNow = e.localPosition;
      }
    } else if (_aimPointer == null) {
      _aimPointer = e.pointer;
      _aimStart = _aimNow = e.localPosition;
    }
  }

  void _move(PointerEvent e) {
    if (e.kind == PointerDeviceKind.mouse) {
      _mouse = e.localPosition;
      return;
    }
    if (e.pointer == _movePointer) _moveNow = e.localPosition;
    if (e.pointer == _aimPointer) _aimNow = e.localPosition;
  }

  void _up(PointerEvent e) {
    if (e.kind == PointerDeviceKind.mouse) _mouseDown = false;
    if (e.pointer == _movePointer) {
      _movePointer = null;
      _moveStart = null;
    }
    if (e.pointer == _aimPointer) {
      _aimPointer = null;
      _aimStart = null;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent) {
      _keys.add(e.logicalKey);
      if (e.logicalKey == LogicalKeyboardKey.space ||
          e.logicalKey == LogicalKeyboardKey.keyG) {
        _w.input.grenade = true;
      }
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
                    onPointerHover: _move,
                    onPointerUp: _up,
                    onPointerCancel: _up,
                    child: CustomPaint(painter: _ZombiePainter(this)),
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
                  child: SafeArea(child: _grenadeButton()),
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
        width: 66,
        height: 66,
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

// ===========================================================================
// Drawing.
// ===========================================================================

class _ZombiePainter extends CustomPainter {
  final _ZombieGameScreenState s;
  _ZombiePainter(this.s);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = s._w;
    final scale = s._scale;
    final cam = s._camera;
    canvas.save();
    if (s._shake > 0) {
      final r = Random();
      canvas.translate(
        (r.nextDouble() - 0.5) * 12 * s._shake,
        (r.nextDouble() - 0.5) * 12 * s._shake,
      );
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-cam.dx, -cam.dy);

    _ground(canvas, w);
    for (final p in w.pickups) {
      _pickup(canvas, p, w.time);
    }
    for (final b in w.blocks) {
      _block(canvas, w.map, b);
    }
    for (final p in w.poofs) {
      final k = p.t / 0.6;
      canvas.drawCircle(
        p.pos,
        p.size * (0.6 + k),
        Paint()..color = Color.fromRGBO(220, 230, 220, 0.6 * (1 - k)),
      );
    }
    for (final z in w.zombies) {
      _zombie(canvas, z);
    }
    _player(canvas, w);
    for (final b in w.bullets) {
      final tail = b.vel / b.vel.distance * (b.gun.pierce ? 1.6 : 0.7);
      canvas.drawLine(
        b.pos - tail,
        b.pos,
        Paint()
          ..color = b.gun.colour
          ..strokeWidth = b.gun.blast > 0 ? 0.45 : 0.22
          ..strokeCap = StrokeCap.round,
      );
    }
    for (final g in w.thrown) {
      canvas.drawCircle(g.pos, 0.35, Paint()..color = const Color(0xFF33691E));
      canvas.drawCircle(
        g.pos,
        0.35,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.08,
      );
    }
    for (final b in w.booms) {
      final k = b.t / 0.5;
      canvas.drawCircle(
        b.pos,
        b.radius * (0.4 + 0.6 * k),
        Paint()..color = Color.fromRGBO(255, 152, 0, 0.55 * (1 - k)),
      );
      canvas.drawCircle(
        b.pos,
        b.radius * 0.5 * (1 - k),
        Paint()..color = Color.fromRGBO(255, 241, 118, 0.8 * (1 - k)),
      );
    }
    if (w.map == ZombieMap.graveyard) _darkness(canvas, w, size, scale, cam);
    canvas.restore();
    _sticks(canvas);
  }

  void _ground(Canvas canvas, ZombieWorld w) {
    final world = const Offset(0, 0) & const Size(kWorldW, kWorldH);
    canvas.drawRect(world, Paint()..color = w.map.ground);
    // Patchy tiles so you can see yourself moving.
    final light = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (var x = 0; x < kWorldW; x += 4) {
      for (var y = 0; y < kWorldH; y += 4) {
        if ((x ~/ 4 + y ~/ 4).isEven) {
          canvas.drawRect(
            Rect.fromLTWH(x.toDouble(), y.toDouble(), 4, 4),
            light,
          );
        }
      }
    }
    if (w.map == ZombieMap.town) {
      // A road across the middle.
      canvas.drawRect(
        const Rect.fromLTWH(0, kWorldH / 2 - 3, kWorldW, 6),
        Paint()..color = const Color(0xFF546E7A),
      );
      final dash = Paint()..color = const Color(0xFFFFF59D);
      for (var x = 1.0; x < kWorldW; x += 4) {
        canvas.drawRect(Rect.fromLTWH(x, kWorldH / 2 - 0.12, 2, 0.24), dash);
      }
    } else if (w.map == ZombieMap.school) {
      // Playground lines.
      final line = Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.15;
      canvas.drawCircle(const Offset(kWorldW / 2, kWorldH / 2), 6, line);
      canvas.drawRect(Rect.fromLTWH(6, 6, kWorldW - 12, kWorldH - 12), line);
    }
    // A fence round the edge.
    canvas.drawRect(
      world,
      Paint()
        ..color = const Color(0xFF3E2723)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  void _block(Canvas canvas, ZombieMap map, Rect b) {
    final shadow = Paint()..color = Colors.black.withValues(alpha: 0.25);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        b.shift(const Offset(0.3, 0.4)),
        const Radius.circular(0.3),
      ),
      shadow,
    );
    switch (map) {
      case ZombieMap.town:
        final car = min(b.width, b.height) < 2.5;
        if (car) {
          final colours = [
            const Color(0xFFE53935),
            const Color(0xFF1E88E5),
            const Color(0xFFFDD835),
            const Color(0xFFECEFF1),
          ];
          final c = colours[(b.left * 7 + b.top).floor() % colours.length];
          canvas.drawRRect(
            RRect.fromRectAndRadius(b, const Radius.circular(0.5)),
            Paint()..color = c,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              b.deflate(0.45),
              const Radius.circular(0.3),
            ),
            Paint()..color = const Color(0xFF263238).withValues(alpha: 0.7),
          );
        } else {
          // A house seen from above: roof with a ridge line.
          canvas.drawRect(b, Paint()..color = const Color(0xFFB0453A));
          final ridge = Paint()
            ..color = const Color(0xFF7F2D25)
            ..strokeWidth = 0.25;
          if (b.width > b.height) {
            canvas.drawLine(b.centerLeft, b.centerRight, ridge);
          } else {
            canvas.drawLine(b.topCenter, b.bottomCenter, ridge);
          }
          canvas.drawRect(
            Rect.fromLTWH(b.right - 1.6, b.top + 0.5, 0.9, 0.9),
            Paint()..color = const Color(0xFF5D4037),
          );
        }
      case ZombieMap.graveyard:
        final tomb = b.width > 3;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            b,
            topLeft: Radius.circular(tomb ? 0.3 : 0.6),
            topRight: Radius.circular(tomb ? 0.3 : 0.6),
          ),
          Paint()
            ..color = tomb ? const Color(0xFF78909C) : const Color(0xFFB0BEC5),
        );
        if (!tomb) {
          final cross = Paint()
            ..color = const Color(0xFF546E7A)
            ..strokeWidth = 0.12;
          final c = b.center;
          canvas.drawLine(
            c + const Offset(0, -0.3),
            c + const Offset(0, 0.3),
            cross,
          );
          canvas.drawLine(
            c + const Offset(-0.25, -0.1),
            c + const Offset(0.25, -0.1),
            cross,
          );
        }
      case ZombieMap.school:
        final frame = b.height > 2;
        if (frame) {
          // Climbing frame: a grid of bars.
          canvas.drawRect(b, Paint()..color = const Color(0xFF1565C0));
          final bar = Paint()
            ..color = const Color(0xFFFFCA28)
            ..strokeWidth = 0.18;
          for (var x = b.left; x <= b.right + 0.01; x += b.width / 4) {
            canvas.drawLine(Offset(x, b.top), Offset(x, b.bottom), bar);
          }
          for (var y = b.top; y <= b.bottom + 0.01; y += b.height / 3) {
            canvas.drawLine(Offset(b.left, y), Offset(b.right, y), bar);
          }
        } else {
          // A bench.
          canvas.drawRRect(
            RRect.fromRectAndRadius(b, const Radius.circular(0.2)),
            Paint()..color = const Color(0xFF8D6E63),
          );
          final plank = Paint()
            ..color = const Color(0xFF6D4C41)
            ..strokeWidth = 0.08;
          canvas.drawLine(b.centerLeft, b.centerRight, plank);
        }
    }
  }

  void _pickup(Canvas canvas, Pickup p, double time) {
    final bob = sin(time * 4) * 0.12;
    final at = p.pos + Offset(0, bob);
    if (p.life < 3 && (time * 6).floor().isEven) return; // blink out
    switch (p.kind) {
      case PickupKind.health:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: at, width: 1.2, height: 1.2),
            const Radius.circular(0.2),
          ),
          Paint()..color = Colors.white,
        );
        final red = Paint()..color = const Color(0xFFE53935);
        canvas.drawRect(
          Rect.fromCenter(center: at, width: 0.8, height: 0.26),
          red,
        );
        canvas.drawRect(
          Rect.fromCenter(center: at, width: 0.26, height: 0.8),
          red,
        );
      case PickupKind.grenade:
        canvas.drawCircle(at, 0.45, Paint()..color = const Color(0xFF558B2F));
        canvas.drawRect(
          Rect.fromCenter(
            center: at + const Offset(0, -0.45),
            width: 0.3,
            height: 0.2,
          ),
          Paint()..color = const Color(0xFF9E9E9E),
        );
    }
  }

  void _zombie(Canvas canvas, Zombie z) {
    final r = z.r;
    final skin = switch (z.kind) {
      ZombieKind.walker => const Color(0xFF8BC34A),
      ZombieKind.runner => const Color(0xFFC0CA33),
      ZombieKind.tank => const Color(0xFF558B2F),
      ZombieKind.king => const Color(0xFF7CB342),
    };
    final shirt = switch (z.kind) {
      ZombieKind.walker => const Color(0xFF6D4C41),
      ZombieKind.runner => const Color(0xFF5C6BC0),
      ZombieKind.tank => const Color(0xFF37474F),
      ZombieKind.king => const Color(0xFF6A1B9A),
    };
    canvas.save();
    canvas.translate(z.pos.dx, z.pos.dy);
    canvas.drawCircle(
      const Offset(0.15, 0.2),
      r,
      Paint()..color = Colors.black26,
    );
    canvas.rotate(z.facing);
    // Arms stretched out in front, swinging as it shuffles.
    final arm = Paint()
      ..color = skin
      ..strokeWidth = r * 0.32
      ..strokeCap = StrokeCap.round;
    final swing = sin(z.wobble) * r * 0.2;
    canvas.drawLine(
      Offset(0, -r * 0.6),
      Offset(r * 1.25, -r * 0.55 + swing),
      arm,
    );
    canvas.drawLine(
      Offset(0, r * 0.6),
      Offset(r * 1.25, r * 0.55 - swing),
      arm,
    );
    // Body (shoulders) then head.
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 1.3, height: r * 2),
      Paint()..color = z.flash > 0 ? Colors.white : shirt,
    );
    canvas.drawCircle(
      Offset(r * 0.1, 0),
      r * 0.62,
      Paint()..color = z.flash > 0 ? Colors.white : skin,
    );
    // Glowing eyes.
    final eye = Paint()..color = const Color(0xFFFFEB3B);
    canvas.drawCircle(Offset(r * 0.48, -r * 0.22), r * 0.12, eye);
    canvas.drawCircle(Offset(r * 0.48, r * 0.22), r * 0.12, eye);
    if (z.kind == ZombieKind.king) {
      // A gold crown.
      final crown = Path()
        ..moveTo(-r * 0.4, -r * 0.45)
        ..lineTo(-r * 0.4, r * 0.45)
        ..lineTo(-r * 0.05, r * 0.3)
        ..lineTo(-r * 0.15, 0)
        ..lineTo(-r * 0.05, -r * 0.3)
        ..close();
      canvas.drawPath(crown, Paint()..color = const Color(0xFFFFC107));
    }
    canvas.restore();
    // Health bar for zombies that have been hit (always for the king).
    if (z.hp < z.maxHp || z.kind == ZombieKind.king) {
      final bar = Rect.fromLTWH(z.pos.dx - r, z.pos.dy - r - 0.6, r * 2, 0.22);
      canvas.drawRect(bar, Paint()..color = Colors.black54);
      canvas.drawRect(
        Rect.fromLTWH(
          bar.left,
          bar.top,
          bar.width * (z.hp / z.maxHp).clamp(0, 1),
          bar.height,
        ),
        Paint()..color = const Color(0xFFFF5252),
      );
    }
  }

  void _player(Canvas canvas, ZombieWorld w) {
    canvas.save();
    canvas.translate(w.player.dx, w.player.dy);
    canvas.drawCircle(
      const Offset(0.15, 0.2),
      kPlayerR,
      Paint()..color = Colors.black26,
    );
    canvas.rotate(w.aimAngle);
    // The gun sticks out the way you aim.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.3, 0.15, 1.3, 0.32),
        const Radius.circular(0.08),
      ),
      Paint()..color = const Color(0xFF263238),
    );
    canvas.drawRect(
      Rect.fromLTWH(1.4, 0.18, 0.2, 0.26),
      Paint()..color = w.gun.colour,
    );
    final hurt = w.hurtT > 0;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: kPlayerR * 1.3,
        height: kPlayerR * 2.1,
      ),
      Paint()..color = hurt ? const Color(0xFFFF5252) : const Color(0xFF1E88E5),
    );
    canvas.drawCircle(
      const Offset(0.05, 0),
      kPlayerR * 0.6,
      Paint()..color = const Color(0xFFFFCC80),
    );
    // Hair.
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(0.05, 0), radius: kPlayerR * 0.6),
      pi / 2,
      pi,
      true,
      Paint()..color = const Color(0xFF5D4037),
    );
    canvas.restore();
  }

  /// The graveyard is dark except near you.
  void _darkness(
    Canvas canvas,
    ZombieWorld w,
    Size size,
    double scale,
    Offset cam,
  ) {
    final view = Rect.fromCenter(
      center: cam,
      width: size.width / scale + 4,
      height: size.height / scale + 4,
    );
    canvas.drawRect(
      view,
      Paint()
        ..shader = RadialGradient(
          colors: const [
            Color(0x00000000),
            Color(0x00000000),
            Color(0xB0000814),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: w.player, radius: 16)),
    );
  }

  void _sticks(Canvas canvas) {
    void stick(Offset? start, Offset now, Color c) {
      if (start == null) return;
      canvas.drawCircle(
        start,
        48,
        Paint()..color = Colors.white.withValues(alpha: 0.15),
      );
      var d = now - start;
      if (d.distance > 48) d = d / d.distance * 48;
      canvas.drawCircle(
        start + d,
        22,
        Paint()..color = c.withValues(alpha: 0.6),
      );
    }

    stick(s._moveStart, s._moveNow, Colors.white);
    stick(s._aimStart, s._aimNow, const Color(0xFFFF5252));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
