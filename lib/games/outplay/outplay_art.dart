import 'dart:math';

import 'package:flutter/material.dart';

import 'outplay_data.dart';

const Color kOutplayInk = Color(0xFF15172A);

/// Draws a weapon pointing right, centred on the origin, about [size] long.
/// A [skin] repaints it (gold, camo, galaxy...).
void paintWeapon(
  Canvas canvas,
  WeaponLook look,
  Color color,
  double size, {
  Skin? skin,
}) {
  _paintReal(canvas, look, color, size / 100, skin);
}

/// Deterministic 0..1 noise, so a skin's pattern doesn't flicker.
double _hash(int a, int b) {
  final v = sin(a * 127.1 + b * 311.7) * 43758.5453;
  return v - v.floorToDouble();
}

/// Paints a skin's pattern inside [shape].
void _paintSkinPattern(Canvas canvas, Path shape, Skin skin, double s) {
  if (skin.pattern == SkinPattern.none) return;
  final b = shape.getBounds();
  final cols = skin.patternColours;
  canvas.save();
  canvas.clipPath(shape);
  final cell = 8 * s;
  int gx(double x) => (x / cell).floor();
  void eachCell(void Function(int i, int j, Offset o) f) {
    for (var i = gx(b.left) - 1; i <= gx(b.right); i++) {
      for (var j = gx(b.top) - 1; j <= gx(b.bottom); j++) {
        f(i, j, Offset(i * cell, j * cell));
      }
    }
  }

  switch (skin.pattern) {
    case SkinPattern.camo:
      eachCell((i, j, o) {
        final h = _hash(i, j);
        final c = cols[(h * cols.length).floor() % cols.length];
        canvas.drawOval(
          Rect.fromCenter(
            center: o + Offset(_hash(j, i) * cell, h * cell),
            width: cell * (0.9 + h),
            height: cell * (0.6 + _hash(i + 7, j) * 0.6),
          ),
          Paint()..color = c.withValues(alpha: 0.85),
        );
      });
      break;
    case SkinPattern.neon:
      for (var x = b.left - b.height; x < b.right; x += 12 * s) {
        final k = ((x / (12 * s)).floor()).abs() % cols.length;
        final paint = Paint()
          ..color = cols[k]
          ..strokeWidth = max(0.8, 1.2 * s)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.8 * s);
        canvas.drawLine(
          Offset(x, b.bottom),
          Offset(x + b.height, b.top),
          paint,
        );
      }
      break;
    case SkinPattern.cracks:
      eachCell((i, j, o) {
        if (_hash(i, j) < 0.45) return;
        final path = Path()..moveTo(o.dx, o.dy + _hash(i, j + 3) * cell);
        for (var k = 1; k <= 3; k++) {
          path.lineTo(o.dx + k * cell / 3, o.dy + _hash(i + k, j) * cell);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = cols[0]
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(0.7, 1.1 * s)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.7 * s),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = cols[1]
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(0.4, 0.4 * s),
        );
      });
      break;
    case SkinPattern.stars:
      eachCell((i, j, o) {
        for (var k = 0; k < 2; k++) {
          final h = _hash(i * 3 + k, j * 5 - k);
          canvas.drawCircle(
            o + Offset(_hash(j + k, i) * cell, h * cell),
            (0.35 + h * 0.6) * s,
            Paint()..color = cols[(h * 7).floor() % cols.length],
          );
        }
      });
      break;
    case SkinPattern.shine:
    case SkinPattern.none:
      break;
  }
  if (skin.pattern == SkinPattern.shine || skin.rarity == Rarity.legendary) {
    // A shiny streak across the metal.
    canvas.drawRect(
      b,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.5),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.35, 0.5, 0.65],
        ).createShader(b),
    );
  }
  canvas.restore();
}

// ---- Realistic weapons ---------------------------------------------------
// Drawn in a 100-unit box pointing right: dark gunmetal with shading and
// real parts (rails, sights, grips, magazines). The gun's own colour is
// kept as a small accent so you can still tell them apart.

const Color _metal = Color(0xFF2E333B);
const Color _metalLight = Color(0xFF5B636E);
const Color _metalDark = Color(0xFF15181D);
const Color _polymer = Color(0xFF23262B);
const Color _wood = Color(0xFF7B4A2A);
const Color _woodLight = Color(0xFFA9683C);

void _paintReal(
  Canvas canvas,
  WeaponLook look,
  Color baseAccent,
  double s,
  Skin? skin,
) {
  // Weapons whose own colour is the main part get fully repainted.
  final mainIsAccent =
      look == WeaponLook.fist ||
      look == WeaponLook.slapper ||
      look == WeaponLook.snake;
  final metal = skin?.metal ?? _metal;
  final polymer = skin?.grip ?? _polymer;
  final wood = skin?.grip ?? _wood;
  final accent = skin == null
      ? baseAccent
      : (mainIsAccent ? skin.metal : (skin.accent ?? baseAccent));
  bool skinned(Color c) =>
      skin != null &&
      (c == metal || c == polymer || (mainIsAccent && c == accent));
  void decorate(Path shape) => _paintSkinPattern(canvas, shape, skin!, s);
  // Blades and pans: steel normally, the skin's colour when skinned.
  final steel = skin == null
      ? const [Color(0xFF9EA7B0), Color(0xFFE4E9EE), Color(0xFF7D8690)]
      : [
          Color.lerp(skin.metal, Colors.black, 0.2)!,
          Color.lerp(skin.metal, Colors.white, 0.55)!,
          Color.lerp(skin.metal, Colors.black, 0.4)!,
        ];
  final outline = Paint()
    ..color = const Color(0xFF07080A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(0.8, 1.4 * s)
    ..strokeJoin = StrokeJoin.round;

  // Shaded fill: lighter on top like light from above.
  Paint shade(Rect r, Color base, {double shine = 0.35}) =>
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(base, Colors.white, shine)!,
            base,
            Color.lerp(base, Colors.black, 0.45)!,
          ],
          stops: const [0, 0.45, 1],
        ).createShader(r);

  Rect rr(double l, double t, double w, double h) =>
      Rect.fromLTWH(l * s, t * s, w * s, h * s);

  void part(
    double l,
    double t,
    double w,
    double h,
    Color c, {
    double r = 1.5,
    double shine = 0.35,
  }) {
    final rect = rr(l, t, w, h);
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(r * s));
    canvas.drawRRect(shape, shade(rect, c, shine: shine));
    if (skinned(c)) decorate(Path()..addRRect(shape));
    canvas.drawRRect(shape, outline);
  }

  void poly(List<Offset> pts, Color c, {double shine = 0.3}) {
    final path = Path()..addPolygon([for (final p in pts) p * s], true);
    canvas.drawPath(path, shade(path.getBounds(), c, shine: shine));
    if (skinned(c)) decorate(path);
    canvas.drawPath(path, outline);
  }

  void line(Offset a, Offset b, Color c, [double w = 1]) {
    canvas.drawLine(
      a * s,
      b * s,
      Paint()
        ..color = c
        ..strokeWidth = max(0.6, w * s)
        ..strokeCap = StrokeCap.round,
    );
  }

  // A Picatinny rail: a strip with little teeth along the top.
  void rail(double l, double t, double w) {
    part(l, t, w, 3, _metalDark, r: 0.5, shine: 0.2);
    for (var x = l + 1.5; x < l + w - 1; x += 3) {
      canvas.drawRect(rr(x, t - 1.2, 1.6, 1.4), Paint()..color = metal);
    }
  }

  void grip(double x, double y, Color c) => poly([
    Offset(x, y),
    Offset(x + 8, y),
    Offset(x + 5, y + 16),
    Offset(x - 3, y + 15),
  ], c);

  void triggerGuard(double x, double y) {
    final guard = Path()
      ..moveTo((x - 1) * s, y * s)
      ..quadraticBezierTo((x + 2) * s, (y + 8) * s, (x + 11) * s, y * s);
    canvas.drawPath(
      guard,
      Paint()
        ..color = _metalDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.8, 1.6 * s),
    );
    line(Offset(x + 5, y), Offset(x + 4, y + 4), _metalLight, 1.2);
  }

  void glow(Offset at, double r, Color c) {
    canvas.drawCircle(
      at * s,
      r * 2.2 * s,
      Paint()
        ..color = c.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * s),
    );
    canvas.drawCircle(at * s, r * s, Paint()..color = c);
  }

  // Stroke a path in alternating colours (candy stripes, dragon belly...).
  void stripes(Path path, double width, List<Color> colours, double dash) {
    for (final m in path.computeMetrics()) {
      var i = 0;
      for (var d = 0.0; d < m.length; d += dash * s, i++) {
        canvas.drawPath(
          m.extractPath(d, min(m.length, d + dash * s + 0.5)),
          Paint()
            ..color = colours[i % colours.length]
            ..style = PaintingStyle.stroke
            ..strokeWidth = width * s,
        );
      }
    }
  }

  void stroke(Path path, Color c, double width) => canvas.drawPath(
    path,
    Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width * s,
  );

  Path pathOf(List<Offset> pts) =>
      Path()..addPolygon([for (final p in pts) p * s], false);

  // Mythic skins: a completely different weapon shape.
  switch (skin?.design) {
    case 'fighter_jet':
      glow(const Offset(-50, 0), 4, const Color(0xFFFF9100)); // afterburner
      poly([
        const Offset(-46, -18),
        const Offset(-38, -18),
        const Offset(-28, -4),
        const Offset(-44, -4),
      ], const Color(0xFF546E7A)); // tail fin
      poly(
        [
          const Offset(-48, -4),
          const Offset(-28, -7),
          const Offset(22, -7),
          const Offset(50, 0),
          const Offset(22, 6),
          const Offset(-28, 6),
          const Offset(-48, 4),
        ],
        const Color(0xFF90A4AE),
        shine: 0.5,
      ); // fuselage
      final canopy = Rect.fromCenter(
        center: const Offset(14, -7) * s,
        width: 22 * s,
        height: 9 * s,
      );
      canvas.drawOval(
        canopy,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFB3E5FC), Color(0xFF0277BD)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(canopy),
      );
      canvas.drawOval(canopy, outline);
      poly([
        const Offset(-22, 2),
        const Offset(12, 2),
        const Offset(-8, 20),
        const Offset(-26, 20),
      ], const Color(0xFF607D8B)); // swept wing
      // Rockets under the wing.
      for (final x in [-24.0, -12.0]) {
        part(x, 20, 16, 4, const Color(0xFFECEFF1), r: 2);
        part(x + 13, 20, 4, 4, const Color(0xFFE53935), r: 2);
      }
      // Star roundel and an intake.
      canvas.drawCircle(
        const Offset(-14, 10) * s,
        4 * s,
        Paint()..color = const Color(0xFF1565C0),
      );
      canvas.drawCircle(
        const Offset(-14, 10) * s,
        2 * s,
        Paint()..color = Colors.white,
      );
      part(-6, -2, 10, 6, const Color(0xFF263238), r: 2);
      line(
        const Offset(-40, 0),
        const Offset(30, 0),
        const Color(0xFF607D8B),
        0.6,
      );
      return;
    case 'bomber':
      // A chunky propeller bomber with bombs hanging underneath.
      poly([
        const Offset(-48, -16),
        const Offset(-40, -16),
        const Offset(-32, -4),
        const Offset(-46, -4),
      ], const Color(0xFF556B2F));
      part(-48, -8, 86, 16, const Color(0xFF6B7B3A), r: 8, shine: 0.4);
      final nose = Rect.fromCenter(
        center: const Offset(40, 0) * s,
        width: 16 * s,
        height: 15 * s,
      );
      canvas.drawOval(nose, Paint()..color = const Color(0xCC81D4FA));
      canvas.drawOval(nose, outline);
      for (var i = 0; i < 3; i++) {
        line(
          Offset(36.0 + i * 3, -6),
          Offset(36.0 + i * 3, 6),
          const Color(0xFF455A64),
          0.6,
        );
      }
      part(-30, 4, 52, 6, const Color(0xFF4A5530), r: 3); // wing
      for (final x in [-18.0, 8.0]) {
        part(x, 2, 12, 9, const Color(0xFF37474F), r: 3); // engines
        // Spinning propellers.
        final hub = Offset(x + 13, 6.5) * s;
        canvas.drawOval(
          Rect.fromCenter(center: hub, width: 3 * s, height: 22 * s),
          Paint()..color = const Color(0x8890A4AE),
        );
        canvas.drawCircle(
          hub,
          1.6 * s,
          Paint()..color = const Color(0xFF212121),
        );
      }
      for (final x in [-12.0, 2.0, 16.0]) {
        // Bombs: fat body with tail fins.
        part(x - 4, 12, 10, 6, const Color(0xFF263238), r: 3);
        poly([
          Offset(x - 6, 12),
          Offset(x - 3, 15),
          Offset(x - 6, 18),
        ], const Color(0xFF455A64));
        part(x - 2, 10, 2, 3, _metalDark, r: 0.5);
      }
      // White star on the side.
      canvas.drawCircle(
        const Offset(-26, 0) * s,
        4.5 * s,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        const Offset(-26, 0) * s,
        2 * s,
        Paint()..color = const Color(0xFF1565C0),
      );
      return;
    case 'railgun':
      // A white space railgun with glowing blue rails.
      poly(
        [
          const Offset(-50, -4),
          const Offset(-28, -7),
          const Offset(-26, 6),
          const Offset(-46, 12),
        ],
        const Color(0xFFECEFF1),
        shine: 0.5,
      );
      grip(-18, 5, const Color(0xFF37474F));
      triggerGuard(-11, 5);
      part(-28, -9, 30, 15, const Color(0xFFECEFF1), r: 4, shine: 0.6);
      part(-20, -6, 16, 4, const Color(0xFF29B6F6), r: 2, shine: 0.6);
      // Twin rails with a glowing gap between them.
      canvas.drawRect(
        rr(2, -5, 48, 4),
        Paint()
          ..color = const Color(0xFF80D8FF)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.6 * s),
      );
      part(2, -9, 48, 4, const Color(0xFFCFD8DC), r: 1.5, shine: 0.6);
      part(2, -1, 48, 4, const Color(0xFFCFD8DC), r: 1.5, shine: 0.6);
      for (var i = 0; i < 5; i++) {
        part(
          6.0 + i * 9,
          -11,
          3,
          14,
          const Color(0xFF29B6F6),
          r: 1,
          shine: 0.6,
        );
      }
      // Hologram scope.
      part(-16, -20, 22, 8, const Color(0xFFECEFF1), r: 3);
      canvas.drawRect(
        rr(-12, -18, 14, 4),
        Paint()..color = const Color(0x8840C4FF),
      );
      glow(const Offset(50, -3), 2.5, const Color(0xFF40C4FF));
      return;
    case 'robot_fist':
      // A chunky metal robot fist with glowing knuckles.
      part(-38, -12, 18, 24, const Color(0xFF546E7A), r: 3);
      for (final y in [-8.0, 0.0, 8.0]) {
        line(Offset(-36, y), Offset(-22, y), _metalDark, 1);
      }
      glow(const Offset(-29, 0), 2, const Color(0xFF00E5FF));
      part(-22, -16, 32, 32, const Color(0xFFB0BEC5), r: 5, shine: 0.6);
      for (final p in const [
        Offset(-18, -12),
        Offset(-18, 12),
        Offset(6, -12),
        Offset(6, 12),
      ]) {
        canvas.drawCircle(p * s, 1.4 * s, Paint()..color = _metalDark);
      }
      for (var i = 0; i < 4; i++) {
        final y = -16.0 + i * 8;
        part(8, y, 10, 7.6, const Color(0xFF90A4AE), r: 1.5, shine: 0.6);
        part(17, y, 9, 7.6, const Color(0xFF90A4AE), r: 2.5, shine: 0.6);
        glow(Offset(18, y + 3.8), 1, const Color(0xFF00E5FF));
      }
      part(-6, 4, 22, 8, const Color(0xFF78909C), r: 2.5, shine: 0.6); // thumb
      return;
    case 'candy_cane':
      // A giant candy cane: hook at the back, stripes all the way.
      final cane = Path()
        ..moveTo(50 * s, 2 * s)
        ..lineTo(-30 * s, 2 * s)
        ..arcToPoint(
          Offset(-30 * s, -20 * s),
          radius: Radius.circular(11 * s),
          clockwise: true,
        )
        ..arcToPoint(
          Offset(-20 * s, -12 * s),
          radius: Radius.circular(9 * s),
          clockwise: true,
        );
      stroke(cane, const Color(0xFF07080A), 11);
      stripes(cane, 8.5, const [Colors.white, Color(0xFFE53935)], 4);
      line(
        const Offset(46, -0.5),
        const Offset(-28, -0.5),
        Colors.white.withValues(alpha: 0.6),
        1,
      );
      return;
    case 'guitar':
      // An electric rock guitar (it still bonks people).
      part(-54, -5, 10, 10, const Color(0xFF3E2723), r: 2); // headstock
      for (var i = 0; i < 3; i++) {
        canvas.drawCircle(
          Offset(-52.0 + i * 3, -6.5) * s,
          1 * s,
          Paint()..color = _metalLight,
        );
      }
      part(-45, -2.5, 46, 5, const Color(0xFF6D4C41), r: 1); // neck
      for (var i = 0; i < 8; i++) {
        line(
          Offset(-42.0 + i * 5.5, -2.5),
          Offset(-42.0 + i * 5.5, 2.5),
          const Color(0xFFBDBDBD),
          0.6,
        );
      }
      final body = Path()
        ..addOval(
          Rect.fromCircle(center: const Offset(10, 0) * s, radius: 15 * s),
        )
        ..addOval(
          Rect.fromCircle(center: const Offset(30, 0) * s, radius: 20 * s),
        );
      final bodyFill = Path.combine(PathOperation.union, body, Path());
      canvas.drawPath(
        bodyFill,
        shade(bodyFill.getBounds(), const Color(0xFFD32F2F), shine: 0.5),
      );
      canvas.drawPath(bodyFill, outline);
      poly(
        [
          const Offset(8, 4),
          const Offset(26, 4),
          const Offset(36, 14),
          const Offset(16, 13),
        ],
        Colors.white,
        shine: 0.1,
      ); // pickguard
      for (final x in [16.0, 24.0]) {
        part(x, -5, 4, 10, const Color(0xFF212121), r: 1); // pickups
      }
      part(36, -4, 5, 8, _metalLight, r: 1); // bridge
      for (final y in [-1.5, 0.0, 1.5]) {
        line(Offset(-44, y), Offset(38, y), const Color(0xFFE0E0E0), 0.35);
      }
      return;
    case 'dragon':
      // A red dragon: spiky back, wings and fire coming out of its mouth.
      final body = Path()..moveTo(-50 * s, 4 * s);
      for (var i = 0; i < 4; i++) {
        final x0 = (-50 + i * 18) * s;
        body.quadraticBezierTo(
          x0 + 9 * s,
          (i.isEven ? -12 : 14) * s,
          x0 + 18 * s,
          0,
        );
      }
      poly(
        [
          const Offset(-20, -4),
          const Offset(-30, -30),
          const Offset(-18, -22),
          const Offset(-10, -32),
          const Offset(-6, -20),
          const Offset(2, -26),
          const Offset(0, -4),
        ],
        const Color(0xFFB71C1C),
        shine: 0.3,
      ); // wing
      stroke(body, const Color(0xFF07080A), 13);
      stroke(body, const Color(0xFFC62828), 10.5);
      stripes(body, 3, const [Color(0xFFFFB300), Color(0xFFFF8F00)], 3);
      for (final m in body.computeMetrics()) {
        for (var d = 6.0 * s; d < m.length - 6 * s; d += 7 * s) {
          final t = m.getTangentForOffset(d)!;
          final n = Offset(t.vector.dy, -t.vector.dx);
          final c = t.position;
          final spike = Path()
            ..moveTo(
              c.dx + n.dx * 4 * s - t.vector.dx * 2 * s,
              c.dy + n.dy * 4 * s - t.vector.dy * 2 * s,
            )
            ..lineTo(c.dx + n.dx * 9 * s, c.dy + n.dy * 9 * s)
            ..lineTo(
              c.dx + n.dx * 4 * s + t.vector.dx * 2 * s,
              c.dy + n.dy * 4 * s + t.vector.dy * 2 * s,
            )
            ..close();
          canvas.drawPath(spike, Paint()..color = const Color(0xFFFFB300));
        }
      }
      // Fire breath.
      final fire = Path()
        ..moveTo(42 * s, -1 * s)
        ..quadraticBezierTo(54 * s, -10 * s, 60 * s, -2 * s)
        ..quadraticBezierTo(54 * s, 6 * s, 42 * s, 3 * s)
        ..close();
      canvas.drawPath(
        fire,
        Paint()
          ..color = const Color(0xFFFF6D00)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.2 * s),
      );
      canvas.drawPath(fire, Paint()..color = const Color(0xCCFFD180));
      // Horned head.
      poly(
        [
          const Offset(20, -5),
          const Offset(30, -9),
          const Offset(44, -3),
          const Offset(44, 4),
          const Offset(30, 8),
          const Offset(20, 5),
        ],
        const Color(0xFFC62828),
        shine: 0.35,
      );
      stroke(
        pathOf(const [Offset(26, -7), Offset(20, -16)]),
        const Color(0xFFFFE082),
        2,
      );
      stroke(
        pathOf(const [Offset(31, -8), Offset(29, -17)]),
        const Color(0xFFFFE082),
        2,
      );
      canvas.drawOval(
        rr(32, -5, 5, 3.6),
        Paint()..color = const Color(0xFFFFEB3B),
      );
      canvas.drawOval(
        rr(34, -4.8, 1, 3.2),
        Paint()..color = const Color(0xFF07080A),
      );
      return;
  }

  switch (look) {
    case WeaponLook.rifle:
      // An AR-style assault rifle.
      poly([
        const Offset(-50, -5),
        const Offset(-32, -7),
        const Offset(-32, 5),
        const Offset(-44, 13),
        const Offset(-50, 13),
      ], polymer);
      part(-34, -5, 12, 6, metal, r: 2); // buffer tube
      grip(-15, 6, polymer);
      triggerGuard(-8, 6);
      // Curved magazine.
      final mag = Path()
        ..moveTo(-2 * s, 6 * s)
        ..lineTo(6 * s, 6 * s)
        ..quadraticBezierTo(8 * s, 16 * s, 12 * s, 25 * s)
        ..lineTo(3 * s, 27 * s)
        ..quadraticBezierTo(0, 17 * s, -2 * s, 6 * s)
        ..close();
      canvas.drawPath(mag, shade(mag.getBounds(), polymer));
      canvas.drawPath(mag, outline);
      part(-22, -1, 28, 9, metal); // lower receiver
      part(-24, -10, 31, 10, metal); // upper receiver
      line(const Offset(-14, -5), const Offset(-4, -5), _metalDark, 1.2);
      part(-1, -6, 6, 4, _metalDark, r: 0.6); // ejection port
      rail(-24, -13, 31);
      part(-21, -19, 6, 6, _metalDark, r: 1); // rear sight
      // Handguard with vent holes.
      part(7, -10, 25, 13, polymer, r: 2);
      for (var i = 0; i < 4; i++) {
        part(10.0 + i * 5.5, -6, 3.5, 5, _metalDark, r: 1.2, shine: 0);
      }
      rail(7, -13, 25);
      part(32, -6, 13, 4, metal, r: 1); // barrel
      part(25, -19, 3, 9, _metalDark, r: 0.6); // front sight post
      part(44, -7.5, 7, 7, _metalDark, r: 1); // muzzle brake
      for (var i = 0; i < 2; i++) {
        line(
          Offset(46.0 + i * 2.5, -6.5),
          Offset(46.0 + i * 2.5, -1.5),
          _metalLight,
          0.8,
        );
      }
      // A coloured stripe on the stock so it's still yours.
      part(-47, 4, 10, 3, accent, r: 1, shine: 0.5);
      break;
    case WeaponLook.laser:
      // A sci-fi energy rifle with a scope and a glowing emitter.
      poly([
        const Offset(-48, -8),
        const Offset(-20, -10),
        const Offset(-20, 8),
        const Offset(-44, 12),
      ], polymer);
      grip(-14, 6, polymer);
      triggerGuard(-7, 6);
      part(-22, -10, 44, 17, metal, r: 4);
      part(-2, 7, 12, 9, _metalDark, r: 2); // battery cell
      glow(const Offset(4, 11.5), 2.2, accent);
      // Scope.
      part(-14, -20, 26, 7, _metalDark, r: 3);
      part(10, -21.5, 4, 10, metal, r: 1.5);
      glow(const Offset(13.5, -16.5), 1.6, const Color(0xFF80D8FF));
      part(-6, -13, 3, 4, _metalDark, r: 0.5);
      part(4, -13, 3, 4, _metalDark, r: 0.5);
      // Emitter barrel with coloured coils.
      part(22, -7, 22, 10, _metalDark, r: 2);
      for (var i = 0; i < 4; i++) {
        part(24.0 + i * 5, -8.5, 2.5, 13, accent, r: 1, shine: 0.6);
      }
      glow(const Offset(46, -2), 3, accent);
      line(const Offset(-18, -2), const Offset(18, -2), accent, 1.2);
      break;
    case WeaponLook.confetti:
      // A pump shotgun with a wooden stock and party-coloured shells.
      poly([
        const Offset(-50, -4),
        const Offset(-24, -6),
        const Offset(-22, 5),
        const Offset(-46, 13),
        const Offset(-50, 12),
      ], wood);
      line(const Offset(-46, 2), const Offset(-28, -1), _woodLight, 1);
      grip(-18, 5, wood);
      triggerGuard(-11, 5);
      part(-25, -7, 26, 13, metal, r: 2); // receiver
      for (var i = 0; i < 4; i++) {
        final c = [
          const Color(0xFFE53935),
          accent,
          const Color(0xFF43A047),
          const Color(0xFF1E88E5),
        ][i];
        part(-21.0 + i * 5, -4, 3.6, 7, c, r: 1, shine: 0.5); // side shells
      }
      part(0, -6, 50, 5, metal, r: 1.5); // barrel
      part(0, -1, 40, 4, _metalDark, r: 1.5); // tube magazine
      part(10, -2.5, 18, 8, polymer, r: 2.5); // pump
      for (var i = 0; i < 5; i++) {
        line(
          Offset(12.0 + i * 3.4, -1.5),
          Offset(12.0 + i * 3.4, 4.5),
          _metalDark,
          0.7,
        );
      }
      part(46, -8, 3, 3, _metalLight, r: 1.5); // bead sight
      break;
    case WeaponLook.snowball:
      // A grenade launcher with a wide frosty tube.
      poly([
        const Offset(-50, -3),
        const Offset(-28, -5),
        const Offset(-28, 6),
        const Offset(-46, 12),
        const Offset(-50, 11),
      ], polymer);
      grip(-20, 6, polymer);
      triggerGuard(-13, 6);
      part(-30, -6, 22, 12, metal, r: 2);
      part(-10, -13, 46, 22, metal, r: 4); // the big tube
      for (final x in [-6.0, 30.0]) {
        part(x, -14.5, 3.5, 25, accent, r: 1, shine: 0.6); // frosty rings
      }
      rail(-6, -16.5, 30);
      part(4, 9, 14, 6, polymer, r: 2); // fore grip
      part(36, -11, 6, 18, _metalDark, r: 2);
      // A snowball waiting in the muzzle.
      canvas.drawCircle(
        const Offset(41, -2) * s,
        7 * s,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(const Offset(41, -2) * s, 7 * s, outline);
      canvas.drawCircle(
        const Offset(39, -4) * s,
        2.2 * s,
        Paint()..color = const Color(0xFFE1F5FE),
      );
      break;
    case WeaponLook.zapper:
      // An arc rifle: twin electrodes and a glowing coil.
      poly([
        const Offset(-48, -5),
        const Offset(-26, -7),
        const Offset(-26, 6),
        const Offset(-44, 12),
      ], polymer);
      grip(-18, 5, polymer);
      triggerGuard(-11, 5);
      part(-28, -9, 32, 15, metal, r: 3);
      part(-6, -16, 14, 7, _metalDark, r: 2); // battery pack
      glow(const Offset(5, -12.5), 1.5, accent);
      // Copper coil.
      part(4, -7, 20, 11, _metalDark, r: 2);
      for (var i = 0; i < 6; i++) {
        part(
          5.0 + i * 3.2,
          -8,
          2,
          13,
          const Color(0xFFB87333),
          r: 0.8,
          shine: 0.6,
        );
      }
      for (final y in [-8.0, 2.0]) {
        part(24, y, 18, 3.5, _metalLight, r: 1); // electrodes
      }
      // The spark jumping between the tips.
      final spark = Path()
        ..moveTo(42 * s, -6 * s)
        ..lineTo(46 * s, -3 * s)
        ..lineTo(43 * s, -1 * s)
        ..lineTo(47 * s, 3 * s);
      canvas.drawPath(
        spark,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.8, 1.6 * s)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.6 * s),
      );
      break;
    case WeaponLook.bubble:
      // A launcher with a glass tank of bubble mix on top.
      poly([
        const Offset(-48, -4),
        const Offset(-26, -6),
        const Offset(-26, 6),
        const Offset(-44, 12),
      ], polymer);
      grip(-18, 6, polymer);
      triggerGuard(-11, 6);
      part(-28, -8, 40, 15, metal, r: 3);
      // Glass tank.
      final tank = RRect.fromRectAndRadius(
        rr(-20, -24, 26, 15),
        Radius.circular(5 * s),
      );
      canvas.drawRRect(tank, Paint()..color = accent.withValues(alpha: 0.75));
      canvas.drawRRect(
        RRect.fromRectAndRadius(rr(-18, -22.5, 22, 4), Radius.circular(2 * s)),
        Paint()..color = Colors.white.withValues(alpha: 0.45),
      );
      canvas.drawRRect(tank, outline);
      part(-10, -10, 4, 3, _metalDark, r: 0.5);
      // Flared muzzle.
      part(12, -6, 18, 10, _metalDark, r: 2);
      poly([
        const Offset(30, -6),
        const Offset(44, -12),
        const Offset(44, 10),
        const Offset(30, 4),
      ], metal);
      canvas.drawCircle(
        const Offset(48, -1) * s,
        5 * s,
        Paint()..color = const Color(0x88E1F5FE),
      );
      canvas.drawCircle(const Offset(48, -1) * s, 5 * s, outline);
      break;
    case WeaponLook.sniper:
      // A long bolt-action sniper rifle with a big scope and a bipod.
      poly([
        const Offset(-52, -4),
        const Offset(-30, -6),
        const Offset(-22, -2),
        const Offset(-24, 6),
        const Offset(-36, 4),
        const Offset(-48, 13),
        const Offset(-52, 12),
      ], wood);
      line(const Offset(-48, 2), const Offset(-32, -2), _woodLight, 1);
      part(-46, -9, 14, 4, wood, r: 2); // cheek rest
      grip(-22, 3, wood);
      triggerGuard(-15, 4);
      part(-24, -7, 30, 10, metal, r: 2); // action
      part(-6, -10, 3, 4, _metalLight, r: 1); // bolt
      canvas.drawCircle(
        const Offset(-4.5, -11) * s,
        2 * s,
        Paint()..color = _metalLight,
      );
      part(6, -5, 46, 4, metal, r: 1); // long barrel
      part(44, -6.5, 10, 7, _metalDark, r: 2); // muzzle brake
      part(-4, -3, 30, 7, wood, r: 2); // forend
      // Scope with a shiny lens.
      part(-18, -20, 34, 8, _metalDark, r: 4);
      part(-22, -21.5, 7, 11, metal, r: 3);
      part(12, -22, 8, 12, metal, r: 3);
      canvas.drawOval(
        rr(17, -20, 3, 8),
        Paint()..color = const Color(0xFF4FC3F7),
      );
      canvas.drawCircle(
        const Offset(18.5, -18) * s,
        1 * s,
        Paint()..color = Colors.white,
      );
      part(-10, -12, 4, 5, _metalDark, r: 0.5);
      part(4, -12, 4, 5, _metalDark, r: 0.5);
      // Folded bipod.
      line(const Offset(22, 2), const Offset(30, 14), _metalLight, 1.6);
      line(const Offset(24, 2), const Offset(34, 13), _metalLight, 1.6);
      part(-36, 0, 8, 2.5, accent, r: 1, shine: 0.5);
      break;
    case WeaponLook.rpgMini:
      // A mini rocket launcher built like a minigun: a spinning cluster of
      // short tubes, each with a rocket poking out.
      part(-44, -11, 30, 21, metal, r: 4); // motor housing
      for (var i = 0; i < 3; i++) {
        line(
          Offset(-40.0 + i * 7, -8),
          Offset(-40.0 + i * 7, 7),
          _metalDark,
          1.2,
        );
      }
      part(-36, -19, 20, 5, _metalDark, r: 2); // carry handle
      part(-34, -15, 3, 5, _metalDark, r: 0.5);
      part(-22, -15, 3, 5, _metalDark, r: 0.5);
      grip(-26, 9, polymer);
      triggerGuard(-19, 9);
      part(-12, 8, 18, 14, accent, r: 2, shine: 0.4); // rocket box
      line(const Offset(-10, 15), const Offset(4, 15), _metalDark, 0.8);
      part(-14, -9, 6, 17, _metalDark, r: 2); // spinning hub
      for (final y in [-12.0, -4.5, 3.0]) {
        part(-8, y, 40, 7, metal, r: 3); // launch tubes
        // Rocket nose: orange warhead with a dark tip.
        final nose = Path()
          ..moveTo(32 * s, (y + 0.8) * s)
          ..lineTo(38 * s, (y + 0.8) * s)
          ..quadraticBezierTo(44 * s, (y + 3.5) * s, 38 * s, (y + 6.2) * s)
          ..lineTo(32 * s, (y + 6.2) * s)
          ..close();
        canvas.drawPath(nose, shade(nose.getBounds(), const Color(0xFFE65100)));
        canvas.drawPath(nose, outline);
      }
      for (final x in [2.0, 24.0]) {
        part(x, -13.5, 3, 25, _metalDark, r: 1); // clamps
      }
      break;
    case WeaponLook.flamer:
      // A flamethrower: fuel tank underneath, long nozzle, pilot flame.
      part(-46, 4, 36, 14, const Color(0xFFB71C1C), r: 7, shine: 0.45);
      for (final x in [-38.0, -20.0]) {
        part(x, 3, 3, 16, _metalLight, r: 1); // tank straps
      }
      final hose = Path()
        ..moveTo(-10 * s, 10 * s)
        ..quadraticBezierTo(2 * s, 20 * s, 8 * s, 6 * s);
      canvas.drawPath(
        hose,
        Paint()
          ..color = _metalDark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5 * s,
      );
      grip(-26, -2, polymer);
      triggerGuard(-19, -2);
      part(-30, -10, 36, 10, metal, r: 2);
      part(6, -8, 34, 6, metal, r: 1.5); // nozzle tube
      part(14, -11, 3, 12, _metalDark, r: 0.8);
      part(26, -11, 3, 12, _metalDark, r: 0.8);
      part(38, -10, 9, 10, _metalDark, r: 2); // nozzle tip
      // Little pilot flame.
      final flame = Path()
        ..moveTo(47 * s, -8 * s)
        ..quadraticBezierTo(54 * s, -10 * s, 52 * s, -16 * s)
        ..quadraticBezierTo(50 * s, -11 * s, 47 * s, -12 * s)
        ..close();
      canvas.drawPath(flame, Paint()..color = const Color(0xFFFFA000));
      canvas.drawPath(
        flame,
        Paint()
          ..color = accent.withValues(alpha: 0.6)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.5 * s),
      );
      break;
    case WeaponLook.fist:
      // A real clenched fist: sleeve, back of the hand, curled fingers and
      // the thumb wrapped across the front.
      part(-36, -12, 16, 24, const Color(0xFF37474F), r: 3); // sleeve
      part(-24, -10, 8, 20, Color.lerp(accent, Colors.brown, 0.2)!, r: 4);
      part(-20, -17, 32, 34, accent, r: 10, shine: 0.25);
      for (var i = 0; i < 4; i++) {
        final y = -17.0 + i * 8.6;
        part(8, y, 16, 8.4, accent, r: 4, shine: 0.3);
        // Knuckle shine and the crease between fingers.
        canvas.drawOval(
          rr(9.5, y + 1.5, 5, 3),
          Paint()..color = Colors.white.withValues(alpha: 0.35),
        );
        line(
          Offset(18, y + 2),
          Offset(22, y + 4),
          Color.lerp(accent, Colors.black, 0.35)!,
          0.8,
        );
      }
      part(-8, 4, 24, 8.5, Color.lerp(accent, Colors.white, 0.08)!, r: 4.2);
      part(
        11,
        5.5,
        4.5,
        5.5,
        Color.lerp(accent, Colors.white, 0.55)!,
        r: 1.6,
      ); // thumbnail
      line(
        const Offset(-12, -6),
        const Offset(-2, -8),
        Color.lerp(accent, Colors.black, 0.25)!,
        0.8,
      );
      break;
    case WeaponLook.knife:
      // A combat knife: rubber grip, steel guard, sharpened blade.
      part(-40, -5, 4, 10, _metalLight, r: 1.5); // pommel
      part(-37, -5.5, 28, 11, polymer, r: 3);
      for (var i = 0; i < 6; i++) {
        line(
          Offset(-33.0 + i * 4, -4),
          Offset(-33.0 + i * 4, 4),
          _metalDark,
          0.9,
        );
      }
      part(-10, -10, 4, 20, _metalLight, r: 1.2); // guard
      final blade = Path()
        ..moveTo(-6 * s, -6 * s)
        ..lineTo(30 * s, -6 * s)
        ..quadraticBezierTo(42 * s, -4 * s, 50 * s, 2 * s)
        ..quadraticBezierTo(30 * s, 6 * s, -6 * s, 6 * s)
        ..close();
      canvas.drawPath(
        blade,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: steel,
          ).createShader(blade.getBounds()),
      );
      if (skin != null) decorate(blade);
      canvas.drawPath(blade, outline);
      line(
        const Offset(-2, -1),
        const Offset(28, -1),
        const Color(0xFF7D8690),
        1.2,
      ); // fuller
      for (var x = 0.0; x < 16; x += 3) {
        line(Offset(x, -6), Offset(x + 1.5, -8), _metalLight, 0.9); // saw teeth
      }
      line(
        const Offset(0, 5),
        const Offset(44, 2.5),
        Colors.white,
        0.6,
      ); // edge
      break;
    case WeaponLook.pan:
      // A heavy cast-iron frying pan.
      part(-52, -4, 40, 8, _metalDark, r: 4);
      canvas.drawCircle(
        const Offset(-46, 0) * s,
        2 * s,
        Paint()..color = const Color(0xFF07080A),
      );
      final c = const Offset(18, 0) * s;
      final outer = Rect.fromCircle(center: c, radius: 27 * s);
      final iron = skin?.metal ?? const Color(0xFF3A3F45);
      canvas.drawOval(outer, shade(outer, iron, shine: 0.3));
      if (skin != null) decorate(Path()..addOval(outer));
      canvas.drawOval(outer, outline);
      final inner = Rect.fromCircle(center: c, radius: 21 * s);
      canvas.drawOval(
        inner,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            colors: [
              Color.lerp(iron, Colors.white, 0.12)!,
              Color.lerp(iron, Colors.black, 0.5)!,
            ],
          ).createShader(inner),
      );
      canvas.drawOval(inner, outline);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 15 * s),
        -2.6,
        1.1,
        false,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * s
          ..strokeCap = StrokeCap.round,
      );
      break;
    case WeaponLook.slapper:
      // A motor with bolts, a chrome piston and a big rubber glove.
      part(-52, -15, 34, 30, metal, r: 4);
      for (final p in const [
        Offset(-48, -11),
        Offset(-22, -11),
        Offset(-48, 11),
        Offset(-22, 11),
      ]) {
        canvas.drawCircle(p * s, 1.6 * s, Paint()..color = _metalLight);
      }
      for (var i = 0; i < 4; i++) {
        line(
          Offset(-44.0 + i * 5, -8),
          Offset(-44.0 + i * 5, 8),
          _metalDark,
          1.2,
        ); // cooling fins
      }
      glow(const Offset(-26, -9), 1.5, const Color(0xFF76FF03));
      part(-18, -4, 26, 8, const Color(0xFFB0BEC5), r: 3, shine: 0.7); // piston
      part(-6, -6, 4, 12, _metalDark, r: 1);
      // Rubber glove: palm, four fingers and a thumb.
      part(6, -14, 20, 28, accent, r: 7, shine: 0.3);
      for (var i = 0; i < 4; i++) {
        part(
          24,
          -15.0 + i * 7.6,
          17 - (i - 1.5).abs() * 2,
          6.6,
          accent,
          r: 3.3,
          shine: 0.35,
        );
      }
      part(10, -22, 7, 12, accent, r: 3.5, shine: 0.35); // thumb
      part(4, -10, 4, 20, Color.lerp(accent, Colors.black, 0.3)!, r: 2); // cuff
      break;
    case WeaponLook.scythe:
      // A long wooden handle and a curved steel blade.
      part(-52, -3.5, 98, 7, wood, r: 3.5, shine: 0.3);
      for (var i = 0; i < 6; i++) {
        line(
          Offset(-48.0 + i * 15, -1),
          Offset(-40.0 + i * 15, -1.5),
          _woodLight,
          0.7,
        );
      }
      part(-22, -3, 4, 14, wood, r: 2); // hand grip peg
      part(38, -6, 8, 12, _metalDark, r: 2); // collar
      final blade = Path()
        ..moveTo(44 * s, -5 * s)
        ..quadraticBezierTo(32 * s, -48 * s, -20 * s, -42 * s)
        ..quadraticBezierTo(14 * s, -34 * s, 36 * s, -5 * s)
        ..close();
      canvas.drawPath(
        blade,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: skin == null
                ? [
                    const Color(0xFFE4E9EE),
                    Color.lerp(const Color(0xFF8E979F), accent, 0.25)!,
                    const Color(0xFF4E565E),
                  ]
                : [steel[1], steel[0], steel[2]],
          ).createShader(blade.getBounds()),
      );
      if (skin != null) decorate(blade);
      canvas.drawPath(blade, outline);
      final edge = Path()
        ..moveTo(36 * s, -6 * s)
        ..quadraticBezierTo(14 * s, -34 * s, -18 * s, -41 * s);
      canvas.drawPath(
        edge,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.6, 1 * s),
      );
      canvas.drawCircle(
        const Offset(41, -3) * s,
        1.6 * s,
        Paint()..color = _metalLight,
      );
      break;
    case WeaponLook.snake:
      // A real-looking snake with scales, a viper head and a forked tongue.
      final body = Path()..moveTo(-50 * s, 2 * s);
      for (var i = 0; i < 4; i++) {
        final x0 = (-50 + i * 20) * s;
        body.quadraticBezierTo(
          x0 + 10 * s,
          (i.isEven ? -15 : 15) * s,
          x0 + 20 * s,
          0,
        );
      }
      canvas.drawPath(
        body,
        Paint()
          ..color = const Color(0xFF07080A)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 13 * s,
      );
      canvas.drawPath(
        body,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(accent, Colors.white, 0.25)!,
              Color.lerp(accent, Colors.black, 0.35)!,
            ],
          ).createShader(Rect.fromLTRB(-50 * s, -15 * s, 40 * s, 15 * s))
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 10.5 * s,
      );
      // Diamond scale pattern down its back.
      for (final m in body.computeMetrics()) {
        for (var d = 4.0 * s; d < m.length - 2 * s; d += 5 * s) {
          final t = m.getTangentForOffset(d)!;
          final n = Offset(-t.vector.dy, t.vector.dx);
          final c = t.position;
          final dia = Path()
            ..moveTo(c.dx + t.vector.dx * 2.2 * s, c.dy + t.vector.dy * 2.2 * s)
            ..lineTo(c.dx + n.dx * 2.4 * s, c.dy + n.dy * 2.4 * s)
            ..lineTo(c.dx - t.vector.dx * 2.2 * s, c.dy - t.vector.dy * 2.2 * s)
            ..lineTo(c.dx - n.dx * 2.4 * s, c.dy - n.dy * 2.4 * s)
            ..close();
          canvas.drawPath(
            dia,
            Paint()
              ..color = Color.lerp(
                accent,
                Colors.black,
                0.5,
              )!.withValues(alpha: 0.75),
          );
        }
      }
      final tongue = Paint()
        ..color = const Color(0xFFD32F2F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.8, 1.6 * s);
      canvas.drawLine(Offset(44 * s, 0), Offset(54 * s, 0), tongue);
      canvas.drawLine(Offset(54 * s, 0), Offset(58 * s, -3 * s), tongue);
      canvas.drawLine(Offset(54 * s, 0), Offset(58 * s, 3 * s), tongue);
      // Wide viper head.
      poly(
        [
          const Offset(26, -6),
          const Offset(36, -9),
          const Offset(46, -3),
          const Offset(46, 3),
          const Offset(36, 9),
          const Offset(26, 6),
        ],
        accent,
        shine: 0.3,
      );
      for (final ey in [-4.5, 4.5]) {
        canvas.drawOval(
          rr(36, ey - 1.8, 4.4, 3.6),
          Paint()..color = const Color(0xFFFFC107),
        );
        canvas.drawOval(
          rr(37.8, ey - 1.6, 0.9, 3.2),
          Paint()..color = const Color(0xFF07080A),
        );
      }
      canvas.drawCircle(
        const Offset(45, -1.5) * s,
        0.6 * s,
        Paint()..color = const Color(0xFF07080A),
      );
      canvas.drawCircle(
        const Offset(45, 1.5) * s,
        0.6 * s,
        Paint()..color = const Color(0xFF07080A),
      );
      break;
  }
}

/// A weapon picture for menus.
class WeaponIcon extends StatelessWidget {
  final WeaponLook look;
  final Color color;
  final double size;
  final Skin? skin;

  const WeaponIcon({
    super.key,
    required this.look,
    required this.color,
    this.size = 64,
    this.skin,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.62,
      child: CustomPaint(painter: _WeaponIconPainter(look, color, skin)),
    );
  }
}

class _WeaponIconPainter extends CustomPainter {
  final WeaponLook look;
  final Color color;
  final Skin? skin;
  _WeaponIconPainter(this.look, this.color, this.skin);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    final rotate = look == WeaponLook.scythe;
    if (rotate) canvas.translate(0, size.height * 0.2);
    paintWeapon(canvas, look, color, size.width * 0.9, skin: skin);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WeaponIconPainter old) =>
      old.look != look || old.color != color || old.skin != skin;
}
