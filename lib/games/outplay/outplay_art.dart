import 'dart:math';

import 'package:flutter/material.dart';

import 'outplay_data.dart';

const Color kOutplayInk = Color(0xFF15172A);

/// Draws a weapon pointing right, centred on the origin, about [size] long.
void paintWeapon(Canvas canvas, WeaponLook look, Color color, double size) {
  _paintReal(canvas, look, color, size / 100);
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

void _paintReal(Canvas canvas, WeaponLook look, Color accent, double s) {
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
    canvas.drawRRect(shape, outline);
  }

  void poly(List<Offset> pts, Color c, {double shine = 0.3}) {
    final path = Path()..addPolygon([for (final p in pts) p * s], true);
    canvas.drawPath(path, shade(path.getBounds(), c, shine: shine));
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
      canvas.drawRect(rr(x, t - 1.2, 1.6, 1.4), Paint()..color = _metal);
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

  switch (look) {
    case WeaponLook.rifle:
      // An AR-style assault rifle.
      poly([
        const Offset(-50, -5),
        const Offset(-32, -7),
        const Offset(-32, 5),
        const Offset(-44, 13),
        const Offset(-50, 13),
      ], _polymer);
      part(-34, -5, 12, 6, _metal, r: 2); // buffer tube
      grip(-15, 6, _polymer);
      triggerGuard(-8, 6);
      // Curved magazine.
      final mag = Path()
        ..moveTo(-2 * s, 6 * s)
        ..lineTo(6 * s, 6 * s)
        ..quadraticBezierTo(8 * s, 16 * s, 12 * s, 25 * s)
        ..lineTo(3 * s, 27 * s)
        ..quadraticBezierTo(0, 17 * s, -2 * s, 6 * s)
        ..close();
      canvas.drawPath(mag, shade(mag.getBounds(), _polymer));
      canvas.drawPath(mag, outline);
      part(-22, -1, 28, 9, _metal); // lower receiver
      part(-24, -10, 31, 10, _metal); // upper receiver
      line(const Offset(-14, -5), const Offset(-4, -5), _metalDark, 1.2);
      part(-1, -6, 6, 4, _metalDark, r: 0.6); // ejection port
      rail(-24, -13, 31);
      part(-21, -19, 6, 6, _metalDark, r: 1); // rear sight
      // Handguard with vent holes.
      part(7, -10, 25, 13, _polymer, r: 2);
      for (var i = 0; i < 4; i++) {
        part(10.0 + i * 5.5, -6, 3.5, 5, _metalDark, r: 1.2, shine: 0);
      }
      rail(7, -13, 25);
      part(32, -6, 13, 4, _metal, r: 1); // barrel
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
      ], _polymer);
      grip(-14, 6, _polymer);
      triggerGuard(-7, 6);
      part(-22, -10, 44, 17, _metal, r: 4);
      part(-2, 7, 12, 9, _metalDark, r: 2); // battery cell
      glow(const Offset(4, 11.5), 2.2, accent);
      // Scope.
      part(-14, -20, 26, 7, _metalDark, r: 3);
      part(10, -21.5, 4, 10, _metal, r: 1.5);
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
      ], _wood);
      line(const Offset(-46, 2), const Offset(-28, -1), _woodLight, 1);
      grip(-18, 5, _wood);
      triggerGuard(-11, 5);
      part(-25, -7, 26, 13, _metal, r: 2); // receiver
      for (var i = 0; i < 4; i++) {
        final c = [
          const Color(0xFFE53935),
          accent,
          const Color(0xFF43A047),
          const Color(0xFF1E88E5),
        ][i];
        part(-21.0 + i * 5, -4, 3.6, 7, c, r: 1, shine: 0.5); // side shells
      }
      part(0, -6, 50, 5, _metal, r: 1.5); // barrel
      part(0, -1, 40, 4, _metalDark, r: 1.5); // tube magazine
      part(10, -2.5, 18, 8, _polymer, r: 2.5); // pump
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
      ], _polymer);
      grip(-20, 6, _polymer);
      triggerGuard(-13, 6);
      part(-30, -6, 22, 12, _metal, r: 2);
      part(-10, -13, 46, 22, _metal, r: 4); // the big tube
      for (final x in [-6.0, 30.0]) {
        part(x, -14.5, 3.5, 25, accent, r: 1, shine: 0.6); // frosty rings
      }
      rail(-6, -16.5, 30);
      part(4, 9, 14, 6, _polymer, r: 2); // fore grip
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
      ], _polymer);
      grip(-18, 5, _polymer);
      triggerGuard(-11, 5);
      part(-28, -9, 32, 15, _metal, r: 3);
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
      ], _polymer);
      grip(-18, 6, _polymer);
      triggerGuard(-11, 6);
      part(-28, -8, 40, 15, _metal, r: 3);
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
      ], _metal);
      canvas.drawCircle(
        const Offset(48, -1) * s,
        5 * s,
        Paint()..color = const Color(0x88E1F5FE),
      );
      canvas.drawCircle(const Offset(48, -1) * s, 5 * s, outline);
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
      grip(-26, -2, _polymer);
      triggerGuard(-19, -2);
      part(-30, -10, 36, 10, _metal, r: 2);
      part(6, -8, 34, 6, _metal, r: 1.5); // nozzle tube
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
      part(-37, -5.5, 28, 11, _polymer, r: 3);
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
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF9EA7B0), Color(0xFFE4E9EE), Color(0xFF7D8690)],
          ).createShader(blade.getBounds()),
      );
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
      canvas.drawOval(outer, shade(outer, const Color(0xFF3A3F45), shine: 0.3));
      canvas.drawOval(outer, outline);
      final inner = Rect.fromCircle(center: c, radius: 21 * s);
      canvas.drawOval(
        inner,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.3, -0.4),
            colors: [Color(0xFF4A5058), Color(0xFF1C1F23)],
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
      part(-52, -15, 34, 30, _metal, r: 4);
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
      part(-52, -3.5, 98, 7, _wood, r: 3.5, shine: 0.3);
      for (var i = 0; i < 6; i++) {
        line(
          Offset(-48.0 + i * 15, -1),
          Offset(-40.0 + i * 15, -1.5),
          _woodLight,
          0.7,
        );
      }
      part(-22, -3, 4, 14, _wood, r: 2); // hand grip peg
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
            colors: [
              const Color(0xFFE4E9EE),
              Color.lerp(const Color(0xFF8E979F), accent, 0.25)!,
              const Color(0xFF4E565E),
            ],
          ).createShader(blade.getBounds()),
      );
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

  const WeaponIcon({
    super.key,
    required this.look,
    required this.color,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.62,
      child: CustomPaint(painter: _WeaponIconPainter(look, color)),
    );
  }
}

class _WeaponIconPainter extends CustomPainter {
  final WeaponLook look;
  final Color color;
  _WeaponIconPainter(this.look, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    final rotate = look == WeaponLook.scythe;
    if (rotate) canvas.translate(0, size.height * 0.2);
    paintWeapon(canvas, look, color, size.width * 0.9);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WeaponIconPainter old) =>
      old.look != look || old.color != color;
}
