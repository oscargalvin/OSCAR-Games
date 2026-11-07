import 'dart:math';

import 'package:flutter/material.dart';

import '../boost_ball/boost_ball_3d.dart' show V3;
import '../outplay/outplay_3d.dart' show Scene3D, kUp;

// Pie Splat Party in 3D. The world: x goes right, y goes away from the
// camera and z is height. A person is about 1.8 tall.

/// Everyone at the party. The first ones are pie fighters; the rest are
/// guests who just came for the cake.
enum Kind {
  chef,
  snooty,
  moustache,
  clown,
  robot,
  baby,
  granny,
  waiter,
  puppy,
  stranger,
  dad,
}

/// The goofs that fight, in the order bots are handed out.
const List<Kind> kGoofs = [
  Kind.snooty,
  Kind.moustache,
  Kind.clown,
  Kind.robot,
  Kind.baby,
];

extension KindInfo on Kind {
  /// Guests wander about and don't throw pies.
  bool get bystander =>
      this == Kind.granny ||
      this == Kind.waiter ||
      this == Kind.puppy ||
      this == Kind.stranger ||
      this == Kind.dad;

  /// Guests you must NOT splat. (The waiter is fair game!)
  bool get protected => bystander && this != Kind.waiter && this != Kind.dad;

  String get title => switch (this) {
    Kind.chef => 'You (the Chef)',
    Kind.snooty => 'Lord Snootypants',
    Kind.moustache => 'Mr Moustachio',
    Kind.clown => 'Bonko the Clown',
    Kind.robot => 'Robo-Bob',
    Kind.baby => 'Baby Burp',
    Kind.granny => 'Granny',
    Kind.waiter => 'The Waiter',
    Kind.puppy => 'Biscuit the Puppy',
    Kind.stranger => 'The Stranger',
    Kind.dad => 'Dad',
  };

  String get short => switch (this) {
    Kind.chef => 'You',
    Kind.snooty => 'Snootypants',
    Kind.moustache => 'Moustachio',
    Kind.clown => 'Bonko',
    Kind.robot => 'Robo-Bob',
    Kind.baby => 'Baby Burp',
    Kind.granny => 'Granny',
    Kind.waiter => 'Waiter',
    Kind.puppy => 'Biscuit',
    Kind.stranger => 'Stranger',
    Kind.dad => 'Dad',
  };

  /// How tall they are compared with a grown-up.
  double get size => switch (this) {
    Kind.baby => 0.7,
    Kind.puppy => 1.0,
    Kind.granny => 0.92,
    Kind.dad => 1.05,
    _ => 1.0,
  };

  double get height => this == Kind.puppy ? 0.75 : 1.95 * size;

  /// Shouted when they throw a pie.
  List<String> get throwLines => switch (this) {
    Kind.snooty => ['Pie for you, peasant!', 'Tally ho!', 'Catch, you scoundrel!'],
    Kind.moustache => ['Taste the tash!', 'Moustache ATTACK!', 'Hiyaaa!'],
    Kind.clown => ['Honk honk!', 'Pie delivery!', 'Special clown pie!'],
    Kind.robot => ['PIE LAUNCHED.', 'TARGET LOCKED.', 'BEEP BOOP. YUM.'],
    Kind.baby => ['Goo goo PIE!', 'Wheee!', 'Ha ha ha!'],
    _ => const ['Pie!'],
  };

  /// Said after a pie in the face.
  List<String> get splatLines => switch (this) {
    Kind.chef => ['Bleurgh!', 'My lovely hat!', 'Not the face!'],
    Kind.snooty => ['How DARE you!', 'My monocle is creamed!', 'Mother will hear of this!'],
    Kind.moustache => ['My MOUSTACHE!', 'It took 30 years to grow!', 'Mmm, moustache custard.'],
    Kind.clown => ["Hey! That's MY joke!", 'Honk... honk...', 'I deserved that.'],
    Kind.robot => ['ERROR: PIE IN FACE.', 'SYSTEM... STICKY.', 'REBOOTING DIGNITY...'],
    Kind.baby => ['Waaah! ...yum!', 'Again! AGAIN!', 'BLEURGH!'],
    Kind.granny => ['YOUNG MAN!!', 'I am telling your MUM!', 'Back in my day pies were for EATING!'],
    Kind.waiter => ['My CAKE!', 'I am just the waiter!', 'That is NOT on the menu!', 'I quit!'],
    Kind.puppy => ['*licks it all up*', 'Woof?!', '*happy wiggle*'],
    Kind.stranger => ['You have made a powerful enemy.', 'My disguise is RUINED!', 'Hmph. Rude.', 'I was never here...'],
    Kind.dad => ['MY HEAD! My lovely shiny head!', 'Not AGAIN!', 'That is it. No more pocket money!', "I'm not angry. I'm just... sticky.", 'Who did that?! ...was it you?'],
  };

  /// Things strangers say while they wander about.
  List<String> get chatter => switch (this) {
    Kind.granny => ['Lovely party!', 'Who wants a biscuit?', "I'm knitting a jumper!", 'Ooh, cake!'],
    Kind.waiter => ['Cake, anyone?', 'Mind the cake please!', 'Excuse me, coming through!'],
    Kind.puppy => ['Woof!', '*wags tail*', 'Is it walkies?', '*sniff sniff*'],
    Kind.stranger => ['...', 'Nothing to see here.', 'I am a totally normal guest.', 'Have we met?', '*mysterious whistling*'],
    Kind.dad => ["Hi Hungry, I'm Dad!", 'Has anyone seen the remote?', 'Back in MY day...', 'Do NOT get pie on my head.', '*shiny head sparkles*', 'Who turned the heating on?!'],
    _ => const [],
  };
}

const Color kInk3 = Color(0xFF1A1A2E);
const Color kCream3 = Color(0xFFFFF6DC);
const Color kCrust3 = Color(0xFFC98A3E);
const Color _skin = Color(0xFFFFD2AE);

/// Draws one person at ([x], [y]) facing [angle].
void addGuy(
  Scene3D s,
  Kind k,
  double x,
  double y,
  double angle, {
  double walk = 0,
  double throwT = 0,
  double splat = -1,
  double z = 0,
  double time = 0,
}) {
  if (k == Kind.puppy) {
    _addPuppy(s, x, y, angle, walk: walk, splat: splat, time: time);
    return;
  }
  final sc = k.size;
  final base = V3(x, y, z);
  final f = V3(cos(angle), sin(angle), 0);
  final r = f.cross(kUp).unit;
  V3 at(double fw, double rt, double up) =>
      base + f * (fw * sc) + r * (rt * sc) + kUp * (up * sc);
  void b(V3 c, double hf, double hr, double hz, Color col, {Color? top, Color? front}) =>
      s.box(c, f, r, kUp, hf * sc, hr * sc, hz * sc, col, top: top, front: front);
  void decal(V3 c, double hr, double hz, Color col) =>
      s.quad(c, r * (hr * sc), kUp * (hz * sc), col, normal: f, decal: true, lit: false);

  final (shirt, pants, skin) = switch (k) {
    Kind.chef => (Colors.white, const Color(0xFF263238), _skin),
    Kind.snooty => (const Color(0xFF222233), const Color(0xFF222233), _skin),
    Kind.moustache => (const Color(0xFFE53935), const Color(0xFF1E88E5), const Color(0xFFE8B48A)),
    Kind.clown => (const Color(0xFFFFEB3B), const Color(0xFF7C4DFF), Colors.white),
    Kind.robot => (const Color(0xFF90A4AE), const Color(0xFF607D8B), const Color(0xFFB0BEC5)),
    Kind.baby => (const Color(0xFF81D4FA), Colors.white, const Color(0xFFFFE3CC)),
    Kind.granny => (const Color(0xFFE995B5), const Color(0xFF9E9E9E), const Color(0xFFFFDCC7)),
    Kind.waiter => (const Color(0xFF212121), const Color(0xFF212121), _skin),
    Kind.puppy => (Colors.brown, Colors.brown, Colors.brown),
    Kind.stranger => (const Color(0xFFC8A165), const Color(0xFF37474F), _skin),
    Kind.dad => (const Color(0xFF43A047), const Color(0xFFD7B98E), _skin),
  };

  s.group(() {
    // Legs and shoes.
    for (final side in [-1.0, 1.0]) {
      final step = sin(walk) * 0.22 * side;
      b(at(step, side * 0.13, 0.42), 0.1, 0.09, 0.4, pants);
      final shoe = k == Kind.clown ? const Color(0xFFE53935) : kInk3;
      final long = k == Kind.clown ? 0.28 : 0.14;
      b(at(step + 0.06, side * 0.13, 0.04), long, 0.1, 0.05, shoe);
    }
    if (k == Kind.granny) {
      // A long skirt.
      b(at(0, 0, 0.55), 0.22, 0.27, 0.3, pants);
    }
    // Body.
    b(at(0, 0, 1.12), 0.17, 0.3, 0.32, shirt);
    switch (k) {
      case Kind.snooty:
        decal(at(0.171, 0, 1.25), 0.08, 0.17, Colors.white);
        decal(at(0.19, 0, 1.38), 0.09, 0.04, const Color(0xFFD32F2F));
      case Kind.waiter:
        decal(at(0.171, 0, 1.2), 0.1, 0.24, Colors.white);
        decal(at(0.19, 0, 1.38), 0.08, 0.035, kInk3);
      case Kind.chef:
        for (final zz in [1.0, 1.15, 1.3]) {
          decal(at(0.171, 0.09, zz), 0.025, 0.025, kInk3);
        }
      case Kind.moustache:
        for (final zz in [0.95, 1.12, 1.29]) {
          decal(at(0.171, 0, zz), 0.3, 0.04, Colors.white);
        }
      case Kind.clown:
        decal(at(0.171, -0.12, 1.25), 0.05, 0.05, const Color(0xFFE53935));
        decal(at(0.171, 0.1, 1.05), 0.05, 0.05, const Color(0xFF1E88E5));
        decal(at(0.171, -0.05, 0.92), 0.05, 0.05, const Color(0xFF43A047));
      case Kind.stranger:
        // Trench coat: long, with the collar turned up.
        b(at(0, 0, 0.72), 0.18, 0.31, 0.2, shirt);
        decal(at(0.19, 0, 1.0), 0.015, 0.4, const Color(0xFF8D6E43));
        b(at(-0.02, 0, 1.47), 0.14, 0.27, 0.06, shirt);
      case Kind.granny:
        for (var i = -2; i <= 2; i++) {
          decal(at(0.171, i * 0.06, 1.38 - i.abs() * 0.025), 0.022, 0.022, Colors.white);
        }
      case Kind.dad:
        // A big round dad belly and a little collar.
        b(at(0.1, 0, 1.0), 0.12, 0.26, 0.2, shirt);
        b(at(0.02, 0, 1.43), 0.16, 0.2, 0.03, const Color(0xFF2E7D32));
      default:
        break;
    }
    if (k == Kind.dad) {
      // Socks with sandals, of course.
      for (final side in [-1.0, 1.0]) {
        final step = sin(walk) * 0.22 * side;
        b(at(step, side * 0.13, 0.14), 0.095, 0.095, 0.12, Colors.white);
      }
    }
    // Arms: the throwing arm swings up and over.
    for (final side in [-1.0, 1.0]) {
      final throwing = side > 0 && throwT > 0;
      final lift = throwing ? sin(throwT * pi) : 0.0;
      final swing = sin(walk) * 0.18 * -side;
      final hand = throwing
          ? at(0.05 + lift * 0.25, side * 0.4, 1.35 + lift * 0.45)
          : at(swing, side * 0.4, 1.0);
      final shoulder = at(0, side * 0.4, 1.36);
      final mid = (hand + shoulder) * 0.5;
      final len = (hand - shoulder).length / sc;
      b(mid, 0.08, 0.08, len / 2 + 0.04, shirt);
      b(hand - kUp * (0.04 * sc), 0.07, 0.07, 0.07, k == Kind.robot ? const Color(0xFF607D8B) : skin);
    }
    if (k == Kind.waiter) {
      // Holding a tray up with a big cake on it.
      final tray = at(0.15, -0.55, 1.62);
      b(at(0.05, -0.45, 1.45), 0.06, 0.06, 0.16, shirt);
      b(tray, 0.3, 0.3, 0.025, const Color(0xFFB0BEC5));
      b(tray + kUp * (0.16 * sc), 0.2, 0.2, 0.13, const Color(0xFFF48FB1), top: kCream3);
      b(tray + kUp * (0.36 * sc), 0.015, 0.015, 0.07, const Color(0xFF64B5F6));
      b(tray + kUp * (0.45 * sc), 0.02, 0.02, 0.03, const Color(0xFFFFC107));
    }

    // Head.
    final head = k == Kind.baby ? 0.32 : 0.25;
    final hz = 1.48 + head;
    if (k == Kind.robot) {
      b(at(0, 0, hz), head, head + 0.03, head, skin);
    } else {
      b(at(0, 0, hz), head, head, head, skin);
    }
    final front = head + 0.002;
    // Eyes and mouth.
    for (final side in [-1.0, 1.0]) {
      final e = at(front, side * 0.1, hz + 0.05);
      if (k == Kind.robot) {
        decal(e, 0.07, 0.04, const Color(0xFF00E5FF));
      } else {
        decal(e, 0.045, 0.055, Colors.white);
        final look = sin(time * 1.7 + side) * 0.015;
        decal(at(front + 0.02, side * 0.1 + look, hz + 0.04), 0.028, 0.032, kInk3);
      }
    }
    if (k == Kind.robot) {
      decal(at(front, 0, hz - 0.12), 0.12, 0.035, const Color(0xFF37474F));
    } else if (k != Kind.moustache) {
      decal(at(front, 0, hz - 0.12), 0.08, 0.02, const Color(0xFFB71C1C));
    }

    switch (k) {
      case Kind.chef:
        b(at(0, 0, hz + head + 0.15), 0.2, 0.2, 0.15, Colors.white);
        b(at(0, 0, hz + head + 0.36), 0.28, 0.28, 0.1, Colors.white);
      case Kind.snooty:
        b(at(0, 0, hz + head + 0.03), 0.36, 0.36, 0.025, kInk3);
        b(at(0, 0, hz + head + 0.27), 0.2, 0.2, 0.23, kInk3);
        b(at(0, 0, hz + head + 0.1), 0.205, 0.205, 0.05, const Color(0xFFD32F2F));
        // Monocle.
        s.quad(at(front + 0.004, 0.1, hz + 0.05), r * (0.07 * sc), kUp * (0.07 * sc),
            const Color(0xFFFFC107), normal: f, decal: true, lit: false);
        decal(at(front + 0.025, 0.1, hz + 0.05), 0.045, 0.045, Colors.white);
        decal(at(front + 0.045, 0.1, hz + 0.04), 0.028, 0.032, kInk3);
      case Kind.moustache:
        final wig = sin(time * 5) * 0.03;
        b(at(head + 0.04, 0, hz - 0.07), 0.04, 0.2, 0.045, const Color(0xFF5A3A1E));
        for (final side in [-1.0, 1.0]) {
          b(at(head + 0.04, side * 0.26, hz - 0.01 + wig), 0.04, 0.07, 0.06, const Color(0xFF5A3A1E));
        }
        for (final side in [-1.0, 1.0]) {
          b(at(head + 0.01, side * 0.1, hz + 0.15), 0.02, 0.08, 0.025, const Color(0xFF5A3A1E));
        }
      case Kind.clown:
        b(at(head + 0.05, 0, hz - 0.03), 0.06, 0.06, 0.06, const Color(0xFFE53935));
        decal(at(front, 0, hz - 0.15), 0.14, 0.035, const Color(0xFFE53935));
        const puffs = [Color(0xFFFF5252), Color(0xFFFF9800), Color(0xFF7C4DFF)];
        for (final side in [-1.0, 1.0]) {
          for (var i = 0; i < 3; i++) {
            b(at(-0.05, side * (head + 0.1), hz + 0.2 - i * 0.16), 0.13, 0.1, 0.09, puffs[i]);
          }
        }
      case Kind.robot:
        b(at(0, 0, hz + head + 0.15), 0.02, 0.02, 0.15, kInk3);
        final blink = (sin(time * 8) + 1) / 2;
        b(at(0, 0, hz + head + 0.33), 0.06, 0.06, 0.06,
            Color.lerp(const Color(0xFF8B0000), const Color(0xFFFF5252), blink)!);
      case Kind.baby:
        b(at(0, 0, hz + head + 0.05), 0.04, 0.04, 0.05, const Color(0xFF8D6E63));
        decal(at(front, 0, hz - 0.14), 0.08, 0.05, const Color(0xFF4FC3F7));
      case Kind.granny:
        b(at(-0.05, 0, hz + head + 0.02), head + 0.02, head + 0.02, 0.06, const Color(0xFFCFD8DC));
        b(at(-0.12, 0, hz + head + 0.16), 0.12, 0.12, 0.1, const Color(0xFFCFD8DC));
        for (final side in [-1.0, 1.0]) {
          s.quad(at(front + 0.004, side * 0.1, hz + 0.05), r * (0.08 * sc), kUp * (0.075 * sc),
              const Color(0xFF6D4C41), normal: f, decal: true, lit: false);
          decal(at(front + 0.025, side * 0.1, hz + 0.05), 0.055, 0.05, Colors.white);
          decal(at(front + 0.045, side * 0.1, hz + 0.045), 0.028, 0.032, kInk3);
        }
      case Kind.waiter:
        b(at(-0.02, 0, hz + head + 0.02), head + 0.01, head + 0.01, 0.04, kInk3);
      case Kind.stranger:
        // Sunglasses and a big hat pulled down low.
        decal(at(front + 0.03, 0, hz + 0.05), 0.2, 0.06, kInk3);
        b(at(0, 0, hz + head + 0.02), 0.4, 0.4, 0.025, const Color(0xFF5D4037));
        b(at(0, 0, hz + head + 0.15), 0.24, 0.24, 0.12, const Color(0xFF5D4037));
        b(at(0, 0, hz + head + 0.06), 0.245, 0.245, 0.03, kInk3);
      case Kind.dad:
        // Totally bald on top, with a shiny spot and two grey tufts.
        s.quad(at(0.02, -0.06, hz + head + 0.004), f * (0.06 * sc), r * (0.09 * sc), Colors.white,
            normal: kUp, decal: true, lit: false);
        for (final side in [-1.0, 1.0]) {
          b(at(-0.04, side * (head + 0.02), hz + 0.04), 0.16, 0.03, 0.09, const Color(0xFF9E9E9E));
        }
        b(at(-head - 0.02, 0, hz + 0.02), 0.03, head, 0.08, const Color(0xFF9E9E9E));
        // A big bushy dad beard (with a grin poking through).
        const beard = Color(0xFF8D6E63);
        b(at(0.17, 0, hz - 0.22), 0.13, head + 0.02, 0.14, beard);
        b(at(0.2, 0, hz - 0.4), 0.1, 0.16, 0.06, beard);
        for (final side in [-1.0, 1.0]) {
          b(at(0, side * (head + 0.015), hz - 0.04), 0.1, 0.03, 0.12, beard);
        }
        decal(at(0.302, 0, hz - 0.14), 0.08, 0.022, const Color(0xFFB71C1C));
        // Big bushy eyebrows.
        for (final side in [-1.0, 1.0]) {
          decal(at(front + 0.03, side * 0.1, hz + 0.13), 0.06, 0.018, const Color(0xFF616161));
        }
      case Kind.puppy:
        break;
    }

    if (splat >= 0) _custardHead(s, at, b, head, hz, splat);
  });
}

void _custardHead(
  Scene3D s,
  V3 Function(double, double, double) at,
  void Function(V3, double, double, double, Color, {Color? top, Color? front}) b,
  double head,
  double hz,
  double age,
) {
  final grow = min(1.0, age / 0.12);
  final h = head + 0.06;
  b(at(0.03, 0, hz + 0.05), h * grow, h * grow, (h - 0.02) * grow, kCream3);
  b(at(0.03, 0, hz + head + 0.08), 0.18 * grow, 0.18 * grow, 0.06, kCrust3, top: kCream3);
  b(at(0.05, 0.05, hz + head + 0.2), 0.05, 0.05, 0.05, const Color(0xFFD50000));
  // Drips sliding down.
  final drip = min(1.0, age / 1.4) * 0.35;
  for (final side in [-0.7, -0.1, 0.5]) {
    b(at(h + 0.02, side * head, hz - head - drip / 2), 0.025, 0.04, 0.05 + drip / 2, kCream3);
  }
}

void _addPuppy(
  Scene3D s,
  double x,
  double y,
  double angle, {
  double walk = 0,
  double splat = -1,
  double time = 0,
}) {
  final base = V3(x, y, 0);
  final f = V3(cos(angle), sin(angle), 0);
  final r = f.cross(kUp).unit;
  V3 at(double fw, double rt, double up) => base + f * fw + r * rt + kUp * up;
  void b(V3 c, double hf, double hr, double hz, Color col, {Color? top, Color? front}) =>
      s.box(c, f, r, kUp, hf, hr, hz, col, top: top, front: front);
  const fur = Color(0xFFC68B59), dark = Color(0xFF6D4C2E);
  s.group(() {
    for (final fw in [-0.2, 0.2]) {
      for (final side in [-1.0, 1.0]) {
        final step = sin(walk + (fw > 0 ? 0 : pi)) * 0.06 * side;
        b(at(fw + step, side * 0.12, 0.13), 0.05, 0.05, 0.13, fur);
      }
    }
    b(at(0, 0, 0.36), 0.3, 0.16, 0.12, fur);
    b(at(-0.22, 0, 0.37), 0.02, 0.165, 0.04, const Color(0xFFE53935));
    final wag = sin(time * 14) * 0.08;
    b(at(-0.36, wag, 0.48), 0.04, 0.03, 0.1, fur);
    b(at(0.36, 0, 0.55), 0.15, 0.15, 0.14, fur);
    b(at(0.52, 0, 0.5), 0.07, 0.09, 0.06, const Color(0xFFE8C9A0));
    b(at(0.59, 0, 0.53), 0.02, 0.04, 0.025, kInk3);
    s.quad(at(0.592, 0, 0.44 + sin(time * 10) * 0.01), r * 0.03, kUp * 0.05,
        const Color(0xFFFF7FA0), normal: f, decal: true, lit: false);
    for (final side in [-1.0, 1.0]) {
      b(at(0.33, side * 0.18, 0.5), 0.05, 0.03, 0.12, dark);
      s.quad(at(0.512, side * 0.07, 0.6), r * 0.025, kUp * 0.03, kInk3,
          normal: f, decal: true, lit: false);
    }
    if (splat >= 0) {
      final g = min(1.0, splat / 0.12);
      b(at(0.38, 0, 0.6), 0.2 * g, 0.18 * g, 0.12 * g, kCream3);
    }
  });
}

/// A custard pie flying through the air.
void addPie(Scene3D s, V3 p, double spin, {bool mega = false}) {
  final sc = mega ? 1.6 : 1.0;
  final f = V3(cos(spin), sin(spin), 0);
  final r = f.cross(kUp).unit;
  s.group(() {
    s.box(p, f, r, kUp, 0.2 * sc, 0.2 * sc, 0.05 * sc, mega ? const Color(0xFFFFC107) : kCrust3,
        top: kCream3);
    s.box(p + kUp * (0.07 * sc), f, r, kUp, 0.05 * sc, 0.05 * sc, 0.04 * sc, const Color(0xFFD50000));
  });
}

/// A flat splodge of custard on the ground.
void addFloorSplat(Scene3D s, double x, double y, double radius, double seed) {
  final rnd = Random(seed.toInt());
  final pts = <V3>[];
  for (var i = 0; i < 9; i++) {
    final a = i * pi * 2 / 9;
    final d = radius * (0.7 + rnd.nextDouble() * 0.5);
    pts.add(V3(x + cos(a) * d, y + sin(a) * d, 0.01));
  }
  s.poly(pts, kCream3, floor: true, lit: false);
}

/// A close-up of one character, for the menu.
void paintPortrait(Canvas canvas, Size size, Kind k, double time, {double splat = -1}) {
  final h = k.height;
  final look = V3(0, 0, k == Kind.puppy ? 0.45 : h * 0.72);
  final eye = look + V3(sin(time * 0.8) * 0.6, -2.6 * (k == Kind.puppy ? 0.55 : max(0.75, k.size)), 0.5);
  final s = Scene3D(
    eye,
    look - eye,
    size.width * 1.5,
    Offset(size.width / 2, size.height * 0.55),
    fog: const Color(0xFFFFFFFF),
    fogFar: 100,
    fogMax: 0,
  );
  addGuy(s, k, 0, 0, k == Kind.puppy ? -pi / 2 + 0.5 : -pi / 2, time: time, splat: splat);
  s.draw(canvas);
}
