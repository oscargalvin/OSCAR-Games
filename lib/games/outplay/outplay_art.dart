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

  switch (look) {
    case WeaponLook.rifle:
      box(-46, -4, 30, 12, dark); // stock
      box(-20, -9, 46, 16, body); // body
      box(22, -5, 28, 7, dark, 2); // barrel
      box(-6, 6, 10, 18, dark); // mag
      box(-26, 6, 8, 12, dark); // grip
      break;
    case WeaponLook.pistol:
      box(-24, -10, 46, 14, body);
      box(-20, 2, 12, 22, dark);
      break;
    case WeaponLook.smg:
      box(-30, -9, 44, 16, body);
      box(12, -5, 22, 7, dark, 2);
      box(-6, 6, 9, 24, dark);
      box(-26, 6, 9, 13, dark);
      break;
    case WeaponLook.shotgun:
      box(-50, -5, 26, 13, dark);
      box(-26, -9, 30, 15, body);
      box(2, -8, 48, 7, dark, 2);
      box(4, 0, 34, 7, body, 2); // pump
      break;
    case WeaponLook.revolver:
      box(-12, -9, 40, 9, dark, 2);
      final c = Offset(-10 * s, -2 * s);
      canvas.drawCircle(c, 10 * s, body);
      canvas.drawCircle(c, 10 * s, ink);
      box(-28, -2, 12, 24, Paint()..color = const Color(0xFF8D6E63), 5);
      break;
    case WeaponLook.burst:
      box(-48, -5, 26, 13, dark);
      box(-24, -11, 48, 18, body);
      box(22, -5, 24, 7, dark, 2);
      box(-20, -18, 26, 7, dark, 2); // sight
      box(-4, 7, 10, 16, dark);
      break;
    case WeaponLook.sniper:
      box(-52, -4, 26, 12, dark);
      box(-28, -7, 40, 13, body);
      box(10, -4, 46, 5, dark, 2);
      box(-20, -20, 30, 9, dark, 4); // scope
      box(-22, 6, 8, 14, dark);
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
    case WeaponLook.minigun:
      box(-34, -14, 30, 28, body, 6);
      for (var i = -1; i <= 1; i++) {
        box(-4, -3 + i * 7.0 - 2, 52, 5, dark, 2);
      }
      box(-28, 12, 12, 12, dark);
      break;
    case WeaponLook.rocket:
      box(-46, -9, 84, 18, body, 8);
      final tip = Path()
        ..moveTo(38 * s, -9 * s)
        ..lineTo(52 * s, 0)
        ..lineTo(38 * s, 9 * s)
        ..close();
      canvas.drawPath(tip, dark);
      canvas.drawPath(tip, ink);
      box(-12, 8, 9, 14, dark);
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
      canvas.drawPath(blade, body);
      canvas.drawPath(blade, ink);
      break;
    case WeaponLook.scythe:
      box(-50, -4, 96, 8, Paint()..color = const Color(0xFF6D4C41), 4);
      final blade = Path()
        ..moveTo(40 * s, -4 * s)
        ..quadraticBezierTo(30 * s, -44 * s, -18 * s, -40 * s)
        ..quadraticBezierTo(14 * s, -30 * s, 30 * s, -4 * s)
        ..close();
      canvas.drawPath(blade, body);
      canvas.drawPath(blade, ink);
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
