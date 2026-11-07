import 'dart:math';
import 'package:flutter/material.dart';

/// The silly characters who pop out of the windows.
enum Goof { snooty, moustache, baby, clown, robot, granny, puppy, chicken }

extension GoofInfo on Goof {
  /// Granny and the puppy must NOT be splatted.
  bool get noSplat => this == Goof.granny || this == Goof.puppy;

  String get title => switch (this) {
    Goof.snooty => 'Lord Snootypants',
    Goof.moustache => 'Mr Moustachio',
    Goof.baby => 'Baby Burp',
    Goof.clown => 'Bonko the Clown',
    Goof.robot => 'Robo-Bob',
    Goof.granny => 'Granny',
    Goof.puppy => 'Biscuit the Puppy',
    Goof.chicken => 'Golden Chicken',
  };

  /// What they shout when they pop up.
  List<String> get popLines => switch (this) {
    Goof.snooty => [
      'I say! Pie is for peasants!',
      "Don't you DARE.",
      'My hat cost a million pounds!',
      'Butler! Fetch my umbrella!',
    ],
    Goof.moustache => [
      'Not the moustache!',
      'Pie? Never heard of it.',
      'Behold my magnificent tash!',
      'I comb it 400 times a day.',
    ],
    Goof.baby => [
      'Goo goo ha ha!',
      "Can't catch me!",
      'I just did a stinky!',
      'Wah wah... JUST KIDDING!',
    ],
    Goof.clown => [
      'Honk honk!',
      "I'm the funny one here!",
      'Want to see a trick?',
      'My shoes are size 97!',
    ],
    Goof.robot => [
      'PIE NOT DETECTED.',
      'BEEP BOOP. MISS ME.',
      'I AM 100% PIE PROOF.',
      'LOADING SMUGNESS...',
    ],
    Goof.granny => [
      'Hello dearie!',
      'Who wants a biscuit?',
      "I'm knitting you a jumper!",
      'Lovely weather!',
    ],
    Goof.puppy => ['Woof!', 'Woof woof?', '*wags tail*', 'Is it walkies?'],
    Goof.chicken => ['BAWK!', 'BAWK BAWK!', 'Squeak!'],
  };

  /// What they say after getting a pie in the face.
  List<String> get splatLines => switch (this) {
    Goof.snooty => [
      'How DARE you!',
      'My monocle! It is creamed!',
      "Mother will hear of this!",
      '...is this lemon? Rather nice.',
    ],
    Goof.moustache => [
      'My MOUSTACHE!',
      'It took 30 years to grow!',
      'Mmm... moustache custard.',
    ],
    Goof.baby => ['Waaah! ...yum!', 'Again! AGAIN!', 'BLEURGH!'],
    Goof.clown => [
      "Hey! That's MY joke!",
      'Honk... honk...',
      'I deserved that.',
    ],
    Goof.robot => [
      'ERROR: PIE IN FACE.',
      'SYSTEM... STICKY.',
      'REBOOTING DIGNITY...',
    ],
    Goof.granny => [
      'YOUNG MAN!!',
      'Back in my day pies were for EATING!',
      "I'm telling your mum!",
    ],
    Goof.puppy => ['*licks it all up*', 'Whimper... tasty?'],
    Goof.chicken => ['MEGA PIE!!!'],
  };
}

const Color kPieInk = Color(0xFF1A1A2E);
const Color kCream = Color(0xFFFFF6DC);
const Color kCrust = Color(0xFFC98A3E);

Paint _fill(Color c) => Paint()..color = c;
Paint _line(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// Draws a goof with their head at [o] and head radius [r]. The body hangs
/// down below the head. [splat] > 0 means they have been pied (it is how
/// long ago, in seconds, so the cream can drip).
void paintGoof(
  Canvas c,
  Goof g,
  Offset o,
  double r, {
  double time = 0,
  double? splat,
}) {
  final ink = _line(kPieInk, max(1.5, r * 0.07));
  // Body / shoulders.
  final bodyColor = switch (g) {
    Goof.snooty => const Color(0xFF222233),
    Goof.moustache => const Color(0xFFE53935),
    Goof.baby => const Color(0xFF81D4FA),
    Goof.clown => const Color(0xFFFFEB3B),
    Goof.robot => const Color(0xFF607D8B),
    Goof.granny => const Color(0xFFE995B5),
    Goof.puppy => const Color(0xFFC68B59),
    Goof.chicken => const Color(0xFFFFC107),
  };
  final body = RRect.fromRectAndRadius(
    Rect.fromLTRB(o.dx - r * 1.15, o.dy + r * 0.7, o.dx + r * 1.15, o.dy + r * 3),
    Radius.circular(r * 0.6),
  );
  c.drawRRect(body, _fill(bodyColor));
  c.drawRRect(body, ink);
  _bodyDetails(c, g, o, r, ink);

  switch (g) {
    case Goof.snooty:
      _head(c, o, r, const Color(0xFFFFD9B8), ink);
      _eyes(c, o, r, ink, time: time, squint: true);
      // Monocle and its chain.
      final mono = o + Offset(r * 0.36, -r * 0.1);
      c.drawCircle(mono, r * 0.25, _line(const Color(0xFFFFC107), r * 0.07));
      c.drawPath(
        Path()
          ..moveTo(mono.dx + r * 0.2, mono.dy + r * 0.15)
          ..quadraticBezierTo(o.dx + r * 0.9, o.dy + r * 0.5, o.dx + r * 0.75, o.dy + r * 0.9),
        _line(const Color(0xFFFFC107), r * 0.04),
      );
      // Nose in the air.
      c.drawCircle(o + Offset(0, r * 0.15), r * 0.12, _fill(const Color(0xFFF4B393)));
      // Smug little mouth.
      c.drawPath(
        Path()
          ..moveTo(o.dx - r * 0.2, o.dy + r * 0.48)
          ..quadraticBezierTo(o.dx + r * 0.05, o.dy + r * 0.42, o.dx + r * 0.25, o.dy + r * 0.38),
        ink,
      );
      // Top hat.
      final brimY = o.dy - r * 0.78;
      final hat = Rect.fromLTRB(o.dx - r * 0.6, brimY - r * 1.1, o.dx + r * 0.6, brimY);
      c.drawRect(hat, _fill(const Color(0xFF111118)));
      c.drawRect(hat, ink);
      c.drawRect(
        Rect.fromLTRB(hat.left, brimY - r * 0.3, hat.right, brimY - r * 0.12),
        _fill(const Color(0xFFD32F2F)),
      );
      final brim = RRect.fromRectAndRadius(
        Rect.fromLTRB(o.dx - r * 0.95, brimY - r * 0.1, o.dx + r * 0.95, brimY + r * 0.1),
        Radius.circular(r * 0.1),
      );
      c.drawRRect(brim, _fill(const Color(0xFF111118)));
      c.drawRRect(brim, ink);
    case Goof.moustache:
      _head(c, o, r, const Color(0xFFE8B48A), ink);
      // Three lonely hairs.
      for (var i = -1; i <= 1; i++) {
        c.drawPath(
          Path()
            ..moveTo(o.dx + i * r * 0.2, o.dy - r * 0.97)
            ..quadraticBezierTo(
              o.dx + i * r * 0.2 + r * 0.25 * sin(time * 3 + i),
              o.dy - r * 1.3,
              o.dx + i * r * 0.3,
              o.dy - r * 1.45,
            ),
          _line(kPieInk, r * 0.05),
        );
      }
      _eyes(c, o, r, ink, time: time);
      // Bushy eyebrows.
      for (final s in [-1, 1]) {
        c.drawLine(
          o + Offset(s * r * 0.55, -r * 0.42),
          o + Offset(s * r * 0.15, -r * 0.38 + sin(time * 5) * r * 0.05),
          _line(const Color(0xFF5A3A1E), r * 0.14),
        );
      }
      c.drawCircle(o + Offset(0, r * 0.18), r * 0.2, _fill(const Color(0xFFD9925F)));
      // The magnificent moustache, curling up at the ends.
      final m = Paint()..color = const Color(0xFF5A3A1E);
      final wig = sin(time * 4) * r * 0.06;
      for (final s in [-1.0, 1.0]) {
        final p = Path()
          ..moveTo(o.dx, o.dy + r * 0.32)
          ..cubicTo(
            o.dx + s * r * 0.5, o.dy + r * 0.2,
            o.dx + s * r * 0.8, o.dy + r * 0.65,
            o.dx + s * r * 1.2, o.dy + r * 0.05 + wig,
          )
          ..cubicTo(
            o.dx + s * r * 1.0, o.dy + r * 0.25,
            o.dx + s * r * 0.95, o.dy + r * 0.85,
            o.dx + s * r * 0.4, o.dy + r * 0.6,
          )
          ..quadraticBezierTo(o.dx + s * r * 0.2, o.dy + r * 0.55, o.dx, o.dy + r * 0.45)
          ..close();
        c.drawPath(p, m);
      }
    case Goof.baby:
      _head(c, o, r * 1.05, const Color(0xFFFFE3CC), ink);
      // The single curl.
      c.drawArc(
        Rect.fromCircle(center: o + Offset(0, -r * 1.12), radius: r * 0.16),
        0.5,
        5,
        false,
        _line(const Color(0xFF8D6E63), r * 0.07),
      );
      _cheeks(c, o, r);
      _eyes(c, o, r, ink, time: time, big: true);
      // Dummy.
      c.drawOval(
        Rect.fromCenter(center: o + Offset(0, r * 0.5), width: r * 0.6, height: r * 0.28),
        _fill(const Color(0xFF4FC3F7)),
      );
      c.drawCircle(o + Offset(0, r * 0.5), r * 0.12, _fill(const Color(0xFFF06292)));
    case Goof.clown:
      // Rainbow hair puffs.
      const puffs = [Color(0xFFFF5252), Color(0xFFFF9800), Color(0xFF7C4DFF)];
      for (final s in [-1.0, 1.0]) {
        for (var i = 0; i < 3; i++) {
          c.drawCircle(
            o + Offset(s * r * (0.95 + 0.1 * i), -r * (0.55 - 0.4 * i)),
            r * 0.32,
            _fill(puffs[i]),
          );
        }
      }
      _head(c, o, r, Colors.white, ink);
      _eyes(c, o, r, ink, time: time);
      // Big red smile and red nose.
      c.drawArc(
        Rect.fromCenter(center: o + Offset(0, r * 0.2), width: r * 1.2, height: r * 0.8),
        0.2,
        pi - 0.4,
        false,
        _line(const Color(0xFFE53935), r * 0.14),
      );
      c.drawCircle(o + Offset(0, r * 0.15), r * 0.2, _fill(const Color(0xFFE53935)));
      c.drawCircle(o + Offset(-r * 0.06, r * 0.08), r * 0.06, _fill(Colors.white70));
    case Goof.robot:
      c.drawLine(o + Offset(0, -r * 0.9), o + Offset(0, -r * 1.35), _line(kPieInk, r * 0.06));
      final blink = (sin(time * 8) + 1) / 2;
      c.drawCircle(
        o + Offset(0, -r * 1.4),
        r * 0.13,
        _fill(Color.lerp(const Color(0xFF8B0000), const Color(0xFFFF5252), blink)!),
      );
      final head = RRect.fromRectAndRadius(
        Rect.fromCenter(center: o, width: r * 1.85, height: r * 1.8),
        Radius.circular(r * 0.25),
      );
      c.drawRRect(head, _fill(const Color(0xFFB0BEC5)));
      c.drawRRect(head, ink);
      for (final s in [-1.0, 1.0]) {
        c.drawRect(
          Rect.fromCenter(center: o + Offset(s * r * 0.4, -r * 0.2), width: r * 0.45, height: r * 0.28),
          _fill(const Color(0xFF00E5FF)),
        );
        c.drawCircle(o + Offset(s * r * 0.75, r * 0.6), r * 0.06, _fill(const Color(0xFF78909C)));
      }
      final grille = Rect.fromCenter(center: o + Offset(0, r * 0.4), width: r * 0.9, height: r * 0.3);
      c.drawRect(grille, _fill(const Color(0xFF37474F)));
      for (var i = 1; i < 5; i++) {
        final x = grille.left + grille.width * i / 5;
        c.drawLine(Offset(x, grille.top), Offset(x, grille.bottom), _line(const Color(0xFF90A4AE), r * 0.04));
      }
    case Goof.granny:
      c.drawCircle(o + Offset(0, -r * 1.0), r * 0.38, _fill(const Color(0xFFCFD8DC)));
      c.drawCircle(o + Offset(0, -r * 1.0), r * 0.38, ink);
      _head(c, o, r, const Color(0xFFFFDCC7), ink);
      c.drawArc(
        Rect.fromCircle(center: o, radius: r),
        pi * 1.02,
        pi * 0.96,
        true,
        _fill(const Color(0xFFCFD8DC)),
      );
      _cheeks(c, o, r);
      _eyes(c, o + Offset(0, r * 0.08), r, ink, time: time, small: true);
      for (final s in [-1.0, 1.0]) {
        c.drawCircle(o + Offset(s * r * 0.36, -r * 0.02), r * 0.24, _line(const Color(0xFF6D4C41), r * 0.06));
      }
      c.drawLine(o + Offset(-r * 0.12, -r * 0.02), o + Offset(r * 0.12, -r * 0.02), _line(const Color(0xFF6D4C41), r * 0.06));
      c.drawArc(
        Rect.fromCenter(center: o + Offset(0, r * 0.38), width: r * 0.6, height: r * 0.3),
        0.2,
        pi - 0.4,
        false,
        ink,
      );
    case Goof.puppy:
      _head(c, o, r, const Color(0xFFC68B59), ink);
      // Floppy ears.
      for (final s in [-1.0, 1.0]) {
        c.save();
        c.translate(o.dx + s * r * 0.85, o.dy - r * 0.2);
        c.rotate(s * (0.25 + 0.12 * sin(time * 6)));
        final ear = Rect.fromCenter(center: Offset(0, r * 0.35), width: r * 0.55, height: r * 1.1);
        c.drawOval(ear, _fill(const Color(0xFF6D4C2E)));
        c.drawOval(ear, ink);
        c.restore();
      }
      _eyes(c, o + Offset(0, -r * 0.08), r, ink, time: time, big: true, dark: true);
      c.drawOval(
        Rect.fromCenter(center: o + Offset(0, r * 0.42), width: r * 1.1, height: r * 0.7),
        _fill(const Color(0xFFE8C9A0)),
      );
      // Tongue out, panting.
      final pant = sin(time * 10) * r * 0.05;
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: o + Offset(0, r * 0.75 + pant), width: r * 0.3, height: r * 0.4),
          Radius.circular(r * 0.15),
        ),
        _fill(const Color(0xFFFF7FA0)),
      );
      c.drawOval(
        Rect.fromCenter(center: o + Offset(0, r * 0.28), width: r * 0.36, height: r * 0.24),
        _fill(kPieInk),
      );
    case Goof.chicken:
      // Golden sparkles.
      for (var i = 0; i < 5; i++) {
        final a = time * 2 + i * pi * 2 / 5;
        _star(c, o + Offset(cos(a) * r * 1.5, sin(a) * r * 1.3), r * 0.16, const Color(0xFFFFF59D));
      }
      for (var i = -1; i <= 1; i++) {
        c.drawCircle(o + Offset(i * r * 0.22, -r * 1.05 + i.abs() * r * 0.06), r * 0.2, _fill(const Color(0xFFE53935)));
      }
      final head = Rect.fromCenter(center: o, width: r * 1.6, height: r * 2.0);
      c.drawOval(head, _fill(const Color(0xFFFFD54F)));
      c.drawOval(head, ink);
      _eyes(c, o + Offset(0, -r * 0.3), r * 0.8, ink, time: time, dark: true);
      final open = (sin(time * 9) + 1) * r * 0.08;
      c.drawPath(
        Path()
          ..moveTo(o.dx - r * 0.3, o.dy + r * 0.1)
          ..lineTo(o.dx + r * 0.3, o.dy + r * 0.1)
          ..lineTo(o.dx, o.dy + r * 0.5 + open)
          ..close(),
        _fill(const Color(0xFFFF9800)),
      );
      c.drawCircle(o + Offset(r * 0.05, r * 0.65 + open), r * 0.12, _fill(const Color(0xFFE53935)));
  }

  if (splat != null) {
    _splatFace(c, g, o, r, splat, time);
  }
}

void _head(Canvas c, Offset o, double r, Color skin, Paint ink) {
  c.drawCircle(o, r, _fill(skin));
  c.drawCircle(o, r, ink);
}

void _cheeks(Canvas c, Offset o, double r) {
  for (final s in [-1.0, 1.0]) {
    c.drawCircle(
      o + Offset(s * r * 0.58, r * 0.25),
      r * 0.16,
      _fill(const Color(0x66FF6F91)),
    );
  }
}

void _eyes(
  Canvas c,
  Offset o,
  double r,
  Paint ink, {
  double time = 0,
  bool big = false,
  bool small = false,
  bool squint = false,
  bool dark = false,
}) {
  final size = r * (big ? 0.22 : small ? 0.12 : 0.17);
  // Pupils wander about, googly-eye style.
  final look = Offset(cos(time * 1.7), sin(time * 2.3)) * size * 0.35;
  final blink = (time % 3.2) > 3.05;
  for (final s in [-1.0, 1.0]) {
    final e = o + Offset(s * r * 0.36, -r * 0.1);
    if (blink) {
      c.drawLine(e - Offset(size, 0), e + Offset(size, 0), ink);
      continue;
    }
    if (dark) {
      c.drawCircle(e, size * 0.8, _fill(kPieInk));
      c.drawCircle(e + Offset(-size * 0.25, -size * 0.25), size * 0.25, _fill(Colors.white));
      continue;
    }
    c.drawCircle(e, size, _fill(Colors.white));
    c.drawCircle(e, size, ink);
    c.drawCircle(e + look, size * 0.5, _fill(kPieInk));
    if (squint) {
      // Snooty half-closed lids.
      c.drawArc(Rect.fromCircle(center: e, radius: size), pi, pi, true, _fill(const Color(0xFFF4C7A3)));
      c.drawLine(e - Offset(size, 0), e + Offset(size, 0), ink);
    }
  }
}

void _bodyDetails(Canvas c, Goof g, Offset o, double r, Paint ink) {
  final top = o.dy + r * 0.75;
  switch (g) {
    case Goof.snooty:
      c.drawPath(
        Path()
          ..moveTo(o.dx - r * 0.35, top)
          ..lineTo(o.dx + r * 0.35, top)
          ..lineTo(o.dx, top + r * 0.9)
          ..close(),
        _fill(Colors.white),
      );
      c.drawPath(
        Path()
          ..moveTo(o.dx, top + r * 0.2)
          ..lineTo(o.dx - r * 0.3, top + r * 0.05)
          ..lineTo(o.dx - r * 0.3, top + r * 0.35)
          ..close()
          ..moveTo(o.dx, top + r * 0.2)
          ..lineTo(o.dx + r * 0.3, top + r * 0.05)
          ..lineTo(o.dx + r * 0.3, top + r * 0.35)
          ..close(),
        _fill(const Color(0xFFD32F2F)),
      );
    case Goof.moustache:
      for (var i = 0; i < 3; i++) {
        c.drawRect(
          Rect.fromLTWH(o.dx - r * 1.1, top + r * (0.15 + i * 0.4), r * 2.2, r * 0.18),
          _fill(Colors.white),
        );
      }
    case Goof.baby:
      c.drawOval(
        Rect.fromCenter(center: Offset(o.dx, top + r * 0.35), width: r * 1.1, height: r * 0.8),
        _fill(Colors.white),
      );
    case Goof.clown:
      final rnd = Random(3);
      for (var i = 0; i < 6; i++) {
        c.drawCircle(
          Offset(o.dx + (rnd.nextDouble() - 0.5) * r * 1.8, top + rnd.nextDouble() * r * 1.4),
          r * 0.12,
          _fill([Colors.red, Colors.blue, Colors.green][i % 3]),
        );
      }
    case Goof.granny:
      for (var i = -3; i <= 3; i++) {
        c.drawCircle(
          Offset(o.dx + i * r * 0.17, top + r * 0.1 + (i * i) * r * 0.025),
          r * 0.08,
          _fill(Colors.white),
        );
      }
    case Goof.puppy:
      c.drawRect(
        Rect.fromLTWH(o.dx - r * 0.7, top - r * 0.02, r * 1.4, r * 0.18),
        _fill(const Color(0xFFE53935)),
      );
      c.drawCircle(Offset(o.dx, top + r * 0.25), r * 0.12, _fill(const Color(0xFFFFC107)));
    case Goof.robot:
    case Goof.chicken:
      break;
  }
}

void _star(Canvas c, Offset o, double r, Color color) {
  final p = Path();
  for (var i = 0; i < 8; i++) {
    final a = i * pi / 4;
    final d = i.isEven ? r : r * 0.35;
    final pt = o + Offset(cos(a) * d, sin(a) * d);
    i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
  }
  p.close();
  c.drawPath(p, _fill(color));
}

/// A face full of custard, with eyes blinking out of it and a tongue
/// licking it off.
void _splatFace(Canvas c, Goof g, Offset o, double r, double age, double time) {
  final cream = _fill(kCream);
  final edge = _line(const Color(0xFFD9C38A), r * 0.1);
  final grow = Curves.easeOutBack.transform(min(1, age / 0.18).toDouble());
  final blob = Path()
    ..addOval(Rect.fromCircle(center: o + Offset(0, -r * 0.2), radius: r * 0.9 * grow));
  const bumps = [
    Offset(-0.85, -0.6),
    Offset(0.8, -0.7),
    Offset(-0.95, 0.15),
    Offset(0.95, 0.1),
    Offset(0.1, -1.05),
    Offset(-0.45, 0.5),
    Offset(0.5, 0.45),
  ];
  for (final b in bumps) {
    blob.addOval(Rect.fromCircle(center: o + b * r * grow, radius: r * 0.3 * grow));
  }
  // Drips that slowly slide down.
  final drip = r * (0.2 + 0.7 * min(1.0, age / 1.2));
  for (final x in [-0.6, -0.15, 0.35, 0.7]) {
    final len = drip * (0.7 + (x * 7).abs() % 0.6);
    blob.addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(o.dx + x * r - r * 0.09, o.dy + r * 0.2, r * 0.18, len + r * 0.3),
        Radius.circular(r * 0.09),
      ),
    );
  }
  // Outline first, then fill over it, so only the outer edge shows.
  c.drawPath(blob, edge);
  c.drawPath(blob, cream);
  // Bits of pie crust.
  for (final b in [const Offset(-0.6, -0.5), const Offset(0.55, -0.15), const Offset(-0.1, 0.25)]) {
    c.drawArc(
      Rect.fromCircle(center: o + b * r, radius: r * 0.2),
      0.3,
      2.2,
      false,
      _line(kCrust, r * 0.1),
    );
  }
  // A cherry on top.
  c.drawLine(o + Offset(r * 0.1, -r * 1.05), o + Offset(r * 0.3, -r * 1.35), _line(const Color(0xFF2E7D32), r * 0.05));
  c.drawCircle(o + Offset(r * 0.08, -r * 0.98), r * 0.16, _fill(const Color(0xFFD50000)));

  if (age > 0.2) {
    // Eyes blinking out of the custard.
    final blinkClosed = ((age * 3) % 2) > 1.8;
    for (final s in [-1.0, 1.0]) {
      final e = o + Offset(s * r * 0.33, -r * 0.15);
      if (blinkClosed) {
        c.drawLine(e - Offset(r * 0.1, 0), e + Offset(r * 0.1, 0), _line(kPieInk, r * 0.06));
      } else {
        c.drawCircle(e, r * 0.13, _fill(Colors.white));
        c.drawCircle(e, r * 0.13, _line(kPieInk, r * 0.04));
        c.drawCircle(e + Offset(sin(time * 6) * r * 0.04, 0), r * 0.06, _fill(kPieInk));
      }
    }
    if (g != Goof.robot) {
      // Tongue licking the custard off.
      final lick = sin(age * 9) * r * 0.25;
      c.drawOval(
        Rect.fromCenter(center: o + Offset(lick, r * 0.62), width: r * 0.32, height: r * 0.22),
        _fill(const Color(0xFFFF7FA0)),
      );
    } else {
      // Robots fizz instead.
      final rnd = Random((age * 12).floor());
      for (var i = 0; i < 3; i++) {
        final p = o + Offset((rnd.nextDouble() - 0.5) * r * 2, (rnd.nextDouble() - 0.5) * r * 2);
        _star(c, p, r * 0.15, const Color(0xFFFFEB3B));
      }
    }
  }
}

/// A custard pie, seen from slightly above.
void paintPie(Canvas c, Offset o, double r, {double spin = 0}) {
  c.save();
  c.translate(o.dx, o.dy);
  c.rotate(spin);
  final tin = Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 1.5);
  c.drawOval(tin.shift(Offset(0, r * 0.12)), _fill(const Color(0xFF9E9E9E)));
  c.drawOval(tin, _fill(kCrust));
  c.drawOval(tin, _line(kPieInk, max(1, r * 0.08)));
  c.drawOval(tin.deflate(r * 0.18).shift(Offset(0, -r * 0.08)), _fill(kCream));
  for (var i = 0; i < 5; i++) {
    final a = i * pi * 2 / 5;
    c.drawCircle(Offset(cos(a) * r * 0.45, sin(a) * r * 0.3 - r * 0.12), r * 0.16, _fill(Colors.white));
  }
  c.drawCircle(Offset(0, -r * 0.2), r * 0.17, _fill(const Color(0xFFD50000)));
  c.restore();
}

/// A blob of custard stuck on the wall where a pie missed.
void paintWallSplat(Canvas c, Offset o, double r, double seed, double alpha) {
  final p = _fill(kCream.withValues(alpha: alpha));
  final rnd = Random(seed.toInt());
  final path = Path()..addOval(Rect.fromCircle(center: o, radius: r * 0.6));
  for (var i = 0; i < 8; i++) {
    final a = i * pi / 4 + rnd.nextDouble() * 0.4;
    final d = r * (0.55 + rnd.nextDouble() * 0.4);
    path.addOval(Rect.fromCircle(center: o + Offset(cos(a) * d, sin(a) * d), radius: r * (0.15 + rnd.nextDouble() * 0.15)));
  }
  path.addRRect(RRect.fromRectAndRadius(
    Rect.fromLTWH(o.dx - r * 0.1, o.dy, r * 0.2, r * 1.2),
    Radius.circular(r * 0.1),
  ));
  c.drawPath(path, p);
  c.drawCircle(o + Offset(r * 0.1, -r * 0.1), r * 0.15, _fill(const Color(0xFFD50000).withValues(alpha: alpha)));
}

/// A whoopee cushion. [squash] goes 0..1 when it has been sat on.
void paintWhoopee(Canvas c, Offset o, double r, double squash, double time) {
  final wob = 1 + sin(time * 7) * 0.05;
  final w = r * 2.2 * (1 + squash * 0.3);
  final h = r * 1.4 * wob * (1 - squash * 0.6);
  final body = Rect.fromCenter(center: o, width: w, height: h);
  c.drawOval(body, _fill(const Color(0xFFFF4081)));
  c.drawOval(body, _line(kPieInk, 2.5));
  c.drawOval(
    Rect.fromCenter(center: o + Offset(-w * 0.18, -h * 0.2), width: w * 0.3, height: h * 0.2),
    _fill(Colors.white.withValues(alpha: 0.5)),
  );
  final neck = RRect.fromRectAndRadius(
    Rect.fromLTWH(o.dx + w * 0.42, o.dy - r * 0.15, r * 0.6, r * 0.3),
    Radius.circular(r * 0.1),
  );
  c.drawRRect(neck, _fill(const Color(0xFFF50057)));
  c.drawRRect(neck, _line(kPieInk, 2));
}
