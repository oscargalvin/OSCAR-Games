import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/sound_service.dart';
import '../../widgets/full_screen_game.dart';
import 'sky_tower_sim.dart';

/// The block colour for a floor in a theme.
Color towerColour(String theme, int floor) {
  switch (theme) {
    case 'candy':
      return Color.lerp(
        const Color(0xFFFF8FC7),
        const Color(0xFF7FE7C4),
        0.5 + 0.5 * sin(floor * 0.7),
      )!;
    case 'ice':
      return Color.lerp(
        const Color(0xFFB3E5FC),
        const Color(0xFF4FC3F7),
        0.5 + 0.5 * sin(floor * 0.5),
      )!;
    case 'lava':
      return Color.lerp(
        const Color(0xFF8E2400),
        const Color(0xFFFFA000),
        0.5 + 0.5 * sin(floor * 0.6),
      )!;
    case 'gold':
      return Color.lerp(
        const Color(0xFFC79100),
        const Color(0xFFFFE082),
        0.5 + 0.5 * sin(floor * 0.8),
      )!;
    default:
      return HSVColor.fromAHSV(1, (floor * 9.0) % 360, 0.55, 0.97).toColor();
  }
}

class SkyTowerGameScreen extends StatefulWidget {
  final String theme;
  final void Function(int floors, int coins)? onFinish;

  /// A game already under way (for tests).
  final TowerGame? startWith;
  const SkyTowerGameScreen({
    super.key,
    this.theme = 'rainbow',
    this.onFinish,
    @visibleForTesting this.startWith,
  });

  @override
  State<SkyTowerGameScreen> createState() => _SkyTowerGameScreenState();
}

class _SkyTowerGameScreenState extends State<SkyTowerGameScreen>
    with SingleTickerProviderStateMixin, FullScreenGame {
  late TowerGame game = widget.startWith ?? TowerGame();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _camY = 0;
  String? _pop; // PERFECT! and friends
  double _popT = 0;
  bool _started = false;
  bool _finished = false;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
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
        : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    if (_started) game.step(dt);
    for (final e in game.events) {
      switch (e) {
        case TowerEvent.drop:
          SoundService.instance.play(GameSound.place);
        case TowerEvent.perfect:
          SoundService.instance.play(GameSound.match);
          _say(game.perfects > 1 ? 'PERFECT x${game.perfects}!' : 'PERFECT!');
        case TowerEvent.grow:
          _say('PERFECT x${game.perfects}! BIGGER!');
        case TowerEvent.miss:
          SoundService.instance.play(GameSound.gameOver);
          _finish();
        case TowerEvent.newSky:
          SoundService.instance.play(GameSound.levelComplete);
          _say('WELCOME TO ${skyName(game.floors).toUpperCase()}!');
      }
    }
    game.events.clear();
    final target = max(0.0, game.floors * kBlockH - 2.2);
    _camY += (target - _camY) * min(1.0, dt * 4);
    _popT = max(0, _popT - dt);
    setState(() {});
  }

  void _say(String text) {
    _pop = text;
    _popT = 1.1;
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinish?.call(game.floors, game.coins);
  }

  void _tap() {
    if (game.over) return;
    if (!_started) {
      _started = true;
      return;
    }
    game.drop();
  }

  void _again() {
    setState(() {
      game = TowerGame();
      _camY = 0;
      _finished = false;
      _started = true;
      _pop = null;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.space ||
        e.logicalKey == LogicalKeyboardKey.enter) {
      if (game.over) {
        _again();
      } else {
        _tap();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _tap(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _TowerPainter(game, _camY, widget.theme)),
              SafeArea(child: _hud()),
              if (game.over) _overCard(),
            ],
          ),
        ),
      ),
    );
  }

  static const _shadow = [Shadow(blurRadius: 6, color: Colors.black54)];

  Widget _hud() {
    return Stack(
      children: [
        Positioned(
          left: 8,
          top: 4,
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            style: IconButton.styleFrom(backgroundColor: Colors.black26),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 10,
          child: Column(
            children: [
              Text(
                '${game.floors}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 54,
                  fontWeight: FontWeight.w900,
                  shadows: _shadow,
                ),
              ),
              Text(
                skyName(game.floors),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  shadows: _shadow,
                ),
              ),
            ],
          ),
        ),
        if (_popT > 0 && _pop != null)
          Positioned(
            left: 0,
            right: 0,
            top: 130,
            child: Opacity(
              opacity: _popT.clamp(0.0, 1.0),
              child: Text(
                _pop!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFFEB3B),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  shadows: _shadow,
                ),
              ),
            ),
          ),
        if (!_started)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 60,
            child: Text(
              'TAP TO DROP THE BLOCK\nStack it right on top!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                shadows: _shadow,
              ),
            ),
          ),
      ],
    );
  }

  Widget _overCard() {
    return Container(
      color: Colors.black45,
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(22),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2A5C),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'TOWER DONE!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${game.floors} floors high',
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
            Text(
              '${game.perfectTotal} perfect drops',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              '+${game.coins} coins',
              style: const TextStyle(
                color: Color(0xFFFFD54F),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _again,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF43A047),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'PLAY AGAIN',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('BACK'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TowerPainter extends CustomPainter {
  final TowerGame g;
  final double camY;
  final String theme;
  _TowerPainter(this.g, this.camY, this.theme);

  late double _s, _cx, _cy;

  // Looking down at the tower from a corner.
  Offset _p(double x, double y, double z) => Offset(
    _cx + (x - z) * 0.866 * _s,
    _cy + ((x + z) * 0.5 - (y - camY)) * _s,
  );

  @override
  void paint(Canvas canvas, Size size) {
    _s = min(size.width, size.height) / 10.5;
    _cx = size.width / 2;
    _cy = size.height * 0.62;
    final height = camY + 2.2;
    _sky(canvas, size, height);
    // The ground the tower stands on.
    final base = g.stack.first;
    _box(
      canvas,
      base.x,
      -40,
      base.z,
      base.w,
      40,
      base.d,
      const Color(0xFF78909C),
    );
    final behind = g.chunks.where((c) => c.x + c.z < 0).toList();
    for (final c in behind) {
      _chunk(canvas, c);
    }
    for (final s in g.stack.skip(1)) {
      _box(
        canvas,
        s.x,
        (s.floor - 1) * kBlockH,
        s.z,
        s.w,
        kBlockH,
        s.d,
        towerColour(theme, s.floor),
      );
    }
    final m = g.moving;
    if (m != null) {
      _box(
        canvas,
        m.x,
        (m.floor - 1) * kBlockH,
        m.z,
        m.w,
        kBlockH,
        m.d,
        towerColour(theme, m.floor),
      );
    }
    for (final c in g.chunks.where((c) => c.x + c.z >= 0)) {
      _chunk(canvas, c);
    }
  }

  void _chunk(Canvas canvas, Chunk c) {
    _box(
      canvas,
      c.x,
      c.y - kBlockH,
      c.z,
      c.w,
      kBlockH,
      c.d,
      towerColour(theme, c.floor),
    );
  }

  /// A block with its bottom at height [y].
  void _box(
    Canvas canvas,
    double x,
    double y,
    double z,
    double w,
    double h,
    double d,
    Color c,
  ) {
    final x0 = x - w / 2, x1 = x + w / 2, z0 = z - d / 2, z1 = z + d / 2;
    final y1 = y + h;
    Path quad(List<Offset> pts) => Path()..addPolygon(pts, true);
    final top = quad([
      _p(x0, y1, z0),
      _p(x1, y1, z0),
      _p(x1, y1, z1),
      _p(x0, y1, z1),
    ]);
    final left = quad([
      _p(x0, y1, z1),
      _p(x1, y1, z1),
      _p(x1, y, z1),
      _p(x0, y, z1),
    ]);
    final right = quad([
      _p(x1, y1, z0),
      _p(x1, y1, z1),
      _p(x1, y, z1),
      _p(x1, y, z0),
    ]);
    canvas.drawPath(left, Paint()..color = Color.lerp(c, Colors.black, 0.18)!);
    canvas.drawPath(right, Paint()..color = Color.lerp(c, Colors.black, 0.35)!);
    canvas.drawPath(top, Paint()..color = Color.lerp(c, Colors.white, 0.15)!);
    final edge = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(top, edge);
  }

  void _sky(Canvas canvas, Size size, double height) {
    final floors = height / kBlockH;
    // City blue, up through the clouds, into space.
    const stops = [
      (0.0, Color(0xFF7EC8F7), Color(0xFFD7F0FF)),
      (25.0, Color(0xFF4A90E2), Color(0xFFBFE3FF)),
      (50.0, Color(0xFF0B1442), Color(0xFF2A3F8F)),
      (75.0, Color(0xFF05060F), Color(0xFF1A1A3A)),
      (100.0, Color(0xFF1A0530), Color(0xFF4A1A6A)),
    ];
    var top = stops.last.$2, bottom = stops.last.$3;
    for (var i = 0; i < stops.length - 1; i++) {
      final a = stops[i], b = stops[i + 1];
      if (floors < b.$1) {
        final t = ((floors - a.$1) / (b.$1 - a.$1)).clamp(0.0, 1.0);
        top = Color.lerp(a.$2, b.$2, t)!;
        bottom = Color.lerp(a.$3, b.$3, t)!;
        break;
      }
    }
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ).createShader(rect),
    );
    final w = size.width, h = size.height;
    final t = g.clock;
    // Stars come out as you get higher.
    final starAlpha = ((floors - 35) / 20).clamp(0.0, 1.0);
    if (starAlpha > 0) {
      final star = Paint()..color = Colors.white.withValues(alpha: starAlpha);
      for (var i = 0; i < 70; i++) {
        final sx = (i * 97.3 % 1000) / 1000 * w;
        final sy = ((i * 61.7 + height * 6) % 1000) / 1000 * h;
        canvas.drawCircle(Offset(sx, sy), i % 5 == 0 ? 1.8 : 1.0, star);
      }
    }
    // The city far below at the start.
    final cityY = h * 0.62 + camY * _s + 2 * _s;
    if (cityY < h + 200) {
      final city = Paint()..color = const Color(0xFF90A4AE);
      for (var i = 0; i < 14; i++) {
        final bw = w / 12;
        final bh = 40 + (i * 53 % 7) * 18.0;
        canvas.drawRect(
          Rect.fromLTWH(i * bw - 10, cityY - bh, bw - 4, bh + 400),
          city,
        );
        final win = Paint()..color = const Color(0x55FFFFFF);
        for (var r = 0; r < bh / 16 - 1; r++) {
          canvas.drawRect(
            Rect.fromLTWH(i * bw, cityY - bh + 8 + r * 16, bw * 0.3, 7),
            win,
          );
        }
      }
    }
    // Birds near the ground, clouds in the middle.
    if (floors < 30) {
      final bird = Paint()
        ..color = const Color(0xFF37474F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (var i = 0; i < 3; i++) {
        final bx = ((t * 40 + i * 230) % (w + 100)) - 50;
        final by = h * (0.2 + i * 0.1) + sin(t * 2 + i) * 10;
        final flap = sin(t * 10 + i) * 5;
        canvas.drawPath(
          Path()
            ..moveTo(bx - 9, by - flap)
            ..lineTo(bx, by)
            ..lineTo(bx + 9, by - flap),
          bird,
        );
      }
    }
    final cloudAlpha = (1 - ((floors - 37) / 15).abs()).clamp(0.0, 1.0);
    if (cloudAlpha > 0) {
      final cloud = Paint()
        ..color = Colors.white.withValues(alpha: 0.8 * cloudAlpha);
      for (var i = 0; i < 5; i++) {
        final x = ((t * 18 * (1 + i % 2) + i * 170) % (w + 240)) - 120;
        final y = ((i * 173 + height * 30) % (h + 200)) - 100;
        for (final (dx, dy, r) in const [
          (0.0, 0.0, 34.0),
          (30.0, 8.0, 26.0),
          (-30.0, 8.0, 24.0),
          (55.0, 14.0, 18.0),
        ]) {
          canvas.drawCircle(Offset(x + dx, y + dy), r, cloud);
        }
      }
    }
    // A plane flies past on the way up.
    if (floors > 12 && floors < 35) {
      final px = w - ((t * 70) % (w + 200)) + 100;
      final py = h * 0.18;
      final plane = Paint()..color = Colors.white;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(px, py), width: 60, height: 12),
          const Radius.circular(6),
        ),
        plane,
      );
      canvas.drawPath(
        Path()
          ..moveTo(px - 4, py)
          ..lineTo(px + 10, py + 20)
          ..lineTo(px + 16, py)
          ..close(),
        plane,
      );
      canvas.drawPath(
        Path()
          ..moveTo(px + 22, py - 2)
          ..lineTo(px + 32, py - 16)
          ..lineTo(px + 30, py)
          ..close(),
        Paint()..color = const Color(0xFFE53935),
      );
    }
    // Up in space: a planet, a rocket and the odd friendly UFO.
    if (floors > 45) {
      final a = ((floors - 45) / 10).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(w * 0.82, h * 0.2),
        34,
        Paint()..color = const Color(0xFFFF8A65).withValues(alpha: a),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * 0.82, h * 0.2),
          width: 100,
          height: 18,
        ),
        Paint()
          ..color = const Color(0xFFFFE0B2).withValues(alpha: a)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
    if (floors > 70) {
      final moon = Offset(w * 0.18, h * 0.25);
      canvas.drawCircle(moon, 40, Paint()..color = const Color(0xFFECEFF1));
      for (final (dx, dy, r) in const [(-12.0, -8.0, 7.0), (14.0, 10.0, 9.0)]) {
        canvas.drawCircle(
          moon + Offset(dx, dy),
          r,
          Paint()..color = const Color(0xFFCFD8DC),
        );
      }
    }
    if (floors > 55) {
      final ux = ((t * 55) % (w + 160)) - 80;
      final uy = h * 0.32 + sin(t * 3) * 14;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(ux, uy), width: 64, height: 18),
        Paint()..color = const Color(0xFFB0BEC5),
      );
      canvas.drawCircle(
        Offset(ux, uy - 8),
        12,
        Paint()..color = const Color(0xAA80DEEA),
      );
      canvas.drawCircle(
        Offset(ux, uy - 9),
        5,
        Paint()..color = const Color(0xFF76FF03),
      );
    }
  }

  @override
  bool shouldRepaint(_TowerPainter old) => true;
}
