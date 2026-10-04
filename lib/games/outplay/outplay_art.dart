import 'dart:math';

import 'package:flutter/material.dart';

import 'outplay_data.dart';

const Color kOutplayInk = Color(0xFF15172A);

/// Draws a weapon pointing right, centred on the origin, about [size] long.
void paintWeapon(Canvas canvas, WeaponLook look, Color color, double size) {
  final s = size / 100;
  final body = Paint()..color = color;
  final dark = Paint()..color = Color.lerp(color, kOutplayInk, 0.55)!;
  final ink = Paint()
    ..color = kOutplayInk
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.2, 3 * s)
    ..strokeJoin = StrokeJoin.round;

  void box(double l, double t, double w, double h, Paint p, [double r = 3]) {
    final rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(l * s, t * s, w * s, h * s),
      Radius.circular(r * s),
    );
    canvas.drawRRect(rr, p);
    canvas.drawRRect(rr, ink);
  }

  void path(Path p, Paint fill) {
    canvas.drawPath(p, fill);
    canvas.drawPath(p, ink);
  }

  switch (look) {
    case WeaponLook.rifle:
      box(-46, -4, 30, 12, dark); // stock
      box(-20, -9, 46, 16, body); // body
      box(22, -5, 28, 7, dark, 2); // barrel
      box(-6, 6, 10, 18, dark); // mag
      box(-26, 6, 8, 12, dark); // grip
      break;
    case WeaponLook.laser:
      box(-36, -10, 50, 20, body, 10);
      box(10, -6, 26, 12, dark, 6);
      canvas.drawCircle(
        Offset(40 * s, 0),
        6 * s,
        Paint()..color = const Color(0xFFFFFFFF),
      );
      canvas.drawCircle(Offset(40 * s, 0), 6 * s, ink);
      for (var i = 0; i < 3; i++) {
        box(-28.0 + i * 12, -15, 6, 6, dark, 3); // fins
      }
      box(-24, 8, 10, 16, dark, 4);
      break;
    case WeaponLook.confetti:
      final cone = Path()
        ..moveTo(-30 * s, -6 * s)
        ..lineTo(36 * s, -20 * s)
        ..lineTo(36 * s, 20 * s)
        ..lineTo(-30 * s, 6 * s)
        ..close();
      path(cone, body);
      for (var i = 0; i < 4; i++) {
        canvas.drawLine(
          Offset((-14 + i * 14) * s, -12 * s + i * s),
          Offset((-8 + i * 14) * s, 12 * s - i * s),
          ink,
        );
      }
      box(-40, -5, 12, 22, dark, 4);
      break;
    case WeaponLook.snowball:
      box(-44, -12, 70, 24, body, 12);
      box(20, -14, 18, 28, dark, 6);
      canvas.drawCircle(
        Offset(-14 * s, -16 * s),
        10 * s,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(Offset(-14 * s, -16 * s), 10 * s, ink);
      box(-30, 10, 10, 16, dark, 4);
      break;
    case WeaponLook.zapper:
      box(-34, -9, 40, 18, body, 6);
      for (var i = 0; i < 2; i++) {
        box(4, -12.0 + i * 16, 26, 7, dark, 3); // prongs
      }
      final bolt = Path()
        ..moveTo(32 * s, -8 * s)
        ..lineTo(44 * s, -2 * s)
        ..lineTo(38 * s, 0)
        ..lineTo(50 * s, 8 * s)
        ..lineTo(36 * s, 3 * s)
        ..lineTo(42 * s, 1 * s)
        ..close();
      path(bolt, Paint()..color = const Color(0xFFFFEB3B));
      box(-28, 8, 10, 16, dark, 4);
      break;
    case WeaponLook.bubble:
      box(-40, -8, 50, 16, body, 8);
      box(8, -12, 10, 24, dark, 4);
      canvas.drawCircle(
        Offset(34 * s, 0),
        16 * s,
        Paint()..color = const Color(0x88E1F5FE),
      );
      canvas.drawCircle(Offset(34 * s, 0), 16 * s, ink);
      canvas.drawCircle(
        Offset(28 * s, -6 * s),
        4 * s,
        Paint()..color = Colors.white,
      );
      box(-30, 8, 10, 16, dark, 4);
      break;
    case WeaponLook.flamer:
      box(
        -40,
        -10,
        22,
        30,
        Paint()..color = const Color(0xFFFF8A65),
        8,
      ); // tank
      box(-16, -7, 40, 13, body);
      box(22, -9, 14, 17, dark, 4);
      break;
    case WeaponLook.fist:
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 44 * s, height: 38 * s),
        Radius.circular(14 * s),
      );
      canvas.drawRRect(r, body);
      canvas.drawRRect(r, ink);
      for (var i = -1; i <= 1; i++) {
        canvas.drawLine(
          Offset(8 * s, i * 9 * s),
          Offset(22 * s, i * 9 * s),
          ink,
        );
      }
      break;
    case WeaponLook.knife:
      box(-34, -6, 26, 12, Paint()..color = const Color(0xFF6D4C41), 4);
      box(-10, -10, 5, 20, dark, 2);
      final blade = Path()
        ..moveTo(-5 * s, -6 * s)
        ..lineTo(30 * s, -6 * s)
        ..quadraticBezierTo(42 * s, -2 * s, 46 * s, 2 * s)
        ..lineTo(-5 * s, 6 * s)
        ..close();
      path(blade, body);
      break;
    case WeaponLook.pan:
      box(-48, -5, 44, 10, Paint()..color = const Color(0xFF5D4037), 4);
      final c = Offset(18 * s, 0);
      canvas.drawCircle(c, 26 * s, dark);
      canvas.drawCircle(c, 26 * s, ink);
      canvas.drawCircle(c, 19 * s, body);
      break;
    case WeaponLook.slapper:
      box(
        -50,
        -14,
        34,
        28,
        Paint()..color = const Color(0xFF78909C),
        6,
      ); // motor
      canvas.drawCircle(
        Offset(-33 * s, 0),
        7 * s,
        Paint()..color = const Color(0xFFFFEB3B),
      );
      canvas.drawCircle(Offset(-33 * s, 0), 7 * s, ink);
      box(-18, -4, 30, 8, dark, 3); // arm
      final hand = RRect.fromRectAndRadius(
        Rect.fromLTWH(10 * s, -22 * s, 30 * s, 44 * s),
        Radius.circular(12 * s),
      );
      canvas.drawRRect(hand, body);
      canvas.drawRRect(hand, ink);
      for (var i = 0; i < 4; i++) {
        box(36, -20.0 + i * 11, 14, 8, body, 4); // fingers
      }
      break;
    case WeaponLook.scythe:
      box(-50, -4, 96, 8, Paint()..color = const Color(0xFF6D4C41), 4);
      final blade = Path()
        ..moveTo(40 * s, -4 * s)
        ..quadraticBezierTo(30 * s, -44 * s, -18 * s, -40 * s)
        ..quadraticBezierTo(14 * s, -30 * s, 30 * s, -4 * s)
        ..close();
      path(blade, body);
      break;
    case WeaponLook.snake:
      // A wiggly green snake: tail on the left, head on the right.
      final wiggle = Path()..moveTo(-50 * s, 0);
      for (var i = 0; i < 4; i++) {
        final x0 = (-50 + i * 20) * s;
        wiggle.quadraticBezierTo(
          x0 + 10 * s,
          (i.isEven ? -16 : 16) * s,
          x0 + 20 * s,
          0,
        );
      }
      canvas.drawPath(
        wiggle,
        Paint()
          ..color = kOutplayInk
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 15 * s,
      );
      canvas.drawPath(
        wiggle,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 10 * s,
      );
      // Yellow stripes down its back.
      for (var i = 0; i < 4; i++) {
        canvas.drawCircle(
          Offset((-40 + i * 20) * s, (i.isEven ? -8 : 8) * s),
          2.5 * s,
          Paint()..color = const Color(0xFFFFEB3B),
        );
      }
      // Forked red tongue.
      final tongue = Paint()
        ..color = const Color(0xFFE53935)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, 2.5 * s);
      canvas.drawLine(Offset(44 * s, 0), Offset(54 * s, 0), tongue);
      canvas.drawLine(Offset(54 * s, 0), Offset(58 * s, -4 * s), tongue);
      canvas.drawLine(Offset(54 * s, 0), Offset(58 * s, 4 * s), tongue);
      final head = Rect.fromCenter(
        center: Offset(36 * s, 0),
        width: 22 * s,
        height: 17 * s,
      );
      canvas.drawOval(head, body);
      canvas.drawOval(head, ink);
      for (final ey in [-4.0, 4.0]) {
        canvas.drawCircle(
          Offset(39 * s, ey * s),
          2.6 * s,
          Paint()..color = const Color(0xFFFFEB3B),
        );
        canvas.drawCircle(
          Offset(39.5 * s, ey * s),
          1.2 * s,
          Paint()..color = kOutplayInk,
        );
      }
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
