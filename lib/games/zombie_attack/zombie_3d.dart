import 'dart:math';

import 'package:flutter/material.dart';

import '../boost_ball/boost_ball_3d.dart' show V3, Camera, Renderer;
import 'zombie_data.dart';
import 'zombie_sim.dart';

// Zombie Attack in 3D, drawn with Boost Ball's little polygon engine.
// The sim works on a flat map with y pointing down the screen; in 3D that
// becomes V3(x, -y, height) so left and right stay the same way round.

V3 _w(Offset p, [double z = 0]) => V3(p.dx, -p.dy, z);

/// A sim angle (y down) as a 3D angle (y up).
double _yaw(double simAngle) => -simAngle;

/// Where the 3D camera is: behind you, looking the way [yaw] points.
class ZombieView {
  final double yaw; // sim angle you are looking along
  final double pitch; // how far above you the camera sits (radians)
  const ZombieView(this.yaw, this.pitch);

  Camera camera(Offset player, Size size) {
    final f = V3(cos(yaw), -sin(yaw), 0);
    final p = _w(player);
    // Pull the camera in rather than letting it go out past the fence.
    var back = 7.5 * cos(pitch);
    const edge = 0.2;
    if (f.x > 0.01) back = min(back, (p.x + edge) / f.x);
    if (f.x < -0.01) back = min(back, (kWorldW + edge - p.x) / -f.x);
    if (f.y < -0.01) back = min(back, (edge - p.y) / -f.y);
    if (f.y > 0.01) back = min(back, (p.y + kWorldH + edge) / f.y);
    back = max(back, 3.5);
    final pos = p - f * back + V3(0, 0, 7.5 * sin(pitch) + 1.3);
    final target = p + f * 3 + const V3(0, 0, 1.1);
    final focal = min(size.width, size.height) * 0.95;
    return Camera.lookAt(pos, target, focal, size.center(Offset.zero));
  }
}

class Zombie3dPainter extends CustomPainter {
  final ZombieWorld w;
  final ZombieView view;
  final double shake;
  Zombie3dPainter(this.w, this.view, {this.shake = 0});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (shake > 0) {
      final r = Random();
      canvas.translate(
        (r.nextDouble() - 0.5) * 12 * shake,
        (r.nextDouble() - 0.5) * 12 * shake,
      );
    }
    final dark = w.map == ZombieMap.graveyard;
    // Sky.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: switch (w.map) {
            ZombieMap.graveyard => const [Color(0xFF0B1026), Color(0xFF2B2F4A)],
            ZombieMap.snow => const [Color(0xFF9FB3C8), Color(0xFFEFF4F8)],
            ZombieMap.beach => const [Color(0xFF29B6F6), Color(0xFFE1F5FE)],
            _ => const [Color(0xFF64B5F6), Color(0xFFD7ECFF)],
          },
        ).createShader(Offset.zero & size),
    );

    final cam = view.camera(w.player, size);
    final r = Renderer(
      cam,
      fog: dark ? const Color(0xFF2B2F4A) : const Color(0xFFD7ECFF),
    );
    _ground(r);
    for (final b in w.blocks) {
      _block(r, b);
    }
    _fence(r);
    _safeZones(r);
    for (final p in w.pickups) {
      _pickup(r, p);
    }
    for (final z in w.zombies) {
      _zombie(r, z);
    }
    _player(r);
    for (final g in w.thrown) {
      final k = (g.t / Grenade.fuse * 1.4).clamp(0.0, 1.0);
      final at = _w(g.pos, 0.3 + sin(k * pi) * 2.2);
      _box(r, at, 0.2, 0.2, 0, 0.4, 0, const Color(0xFF33691E));
    }
    r.draw(canvas);

    // Effects on top: bullets, explosions, smoke, health bars.
    for (final b in w.bullets) {
      final tail = b.vel / b.vel.distance * (b.gun.pierce ? 1.6 : 0.8);
      final a = cam.project(_w(b.pos - tail, 1.25));
      final c = cam.project(_w(b.pos, 1.25));
      if (a == null || c == null) continue;
      final depth = cam.toCam(_w(b.pos, 1.25)).z;
      canvas.drawLine(
        a,
        c,
        Paint()
          ..color = b.gun.colour
          ..strokeWidth = (cam.focal * (b.gun.blast > 0 ? 0.3 : 0.12) / depth)
              .clamp(1.5, 14)
          ..strokeCap = StrokeCap.round,
      );
    }
    for (final p in w.poofs) {
      _ball(
        canvas,
        cam,
        _w(p.pos, 1),
        p.size * (0.6 + p.t / 0.6),
        Color.fromRGBO(225, 235, 225, 0.6 * (1 - p.t / 0.6)),
      );
    }
    for (final b in w.booms) {
      final k = b.t / 0.5;
      _ball(
        canvas,
        cam,
        _w(b.pos, 0.8),
        b.radius * (0.4 + 0.6 * k),
        Color.fromRGBO(255, 152, 0, 0.55 * (1 - k)),
      );
      _ball(
        canvas,
        cam,
        _w(b.pos, 0.8),
        b.radius * 0.5 * (1 - k),
        Color.fromRGBO(255, 241, 118, 0.8 * (1 - k)),
      );
    }
    for (final z in w.zombies) {
      if (z.hp >= z.maxHp && z.kind != ZombieKind.king) continue;
      final s = z.r / 0.85;
      final top = cam.project(_w(z.pos, 2.3 * s));
      if (top == null) continue;
      final depth = cam.toCam(_w(z.pos, 2.3 * s)).z;
      final wide = (cam.focal * 1.2 * s / depth).clamp(14.0, 120.0);
      final bar = Rect.fromCenter(center: top, width: wide, height: 5);
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
    if (dark) {
      // Only a pool of light round you in the graveyard.
      final me = cam.project(_w(w.player, 1)) ?? size.center(Offset.zero);
      final radius = size.longestSide * 0.75;
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: const [
              Color(0x00000000),
              Color(0x00000000),
              Color(0xA0000814),
            ],
            stops: const [0, 0.35, 1],
          ).createShader(Rect.fromCircle(center: me, radius: radius)),
      );
    }
    _crosshair(canvas, size, cam);
    canvas.restore();
  }

  void _ball(Canvas canvas, Camera cam, V3 at, double radius, Color c) {
    final cc = cam.toCam(at);
    if (cc.z < 0.5) return;
    canvas.drawCircle(
      cam.screen(cc),
      radius * cam.focal / cc.z,
      Paint()..color = c,
    );
  }

  /// A small ring where your gun is pointing.
  void _crosshair(Canvas canvas, Size size, Camera cam) {
    final at = w.player + Offset.fromDirection(w.aimAngle, 9);
    final p = cam.project(_w(at, 1.2));
    if (p == null) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(p, 9, paint);
    canvas.drawCircle(p, 2, paint..style = PaintingStyle.fill);
  }

  // ---- the world ---------------------------------------------------------

  void _ground(Renderer r) {
    final g = w.map.ground;
    // Grass beyond the fence, then the play area in tiles.
    r.add(
      const [
        V3(-80, 80, 0),
        V3(-80, -150, 0),
        V3(150, -150, 0),
        V3(150, 80, 0),
      ],
      switch (w.map) {
        ZombieMap.beach => const Color(0xFF4FC3F7), // the sea
        ZombieMap.snow => const Color(0xFFF5F9FC),
        _ => Color.lerp(g, Colors.black, 0.25)!,
      },
      floor: true,
    );
    final light = Color.lerp(g, Colors.white, 0.07)!;
    for (var x = 0.0; x < kWorldW; x += 4) {
      for (var y = 0.0; y < kWorldH; y += 4) {
        final odd = ((x + y) / 4).round().isOdd;
        r.add(
          [
            _w(Offset(x, y)),
            _w(Offset(x, y + 4)),
            _w(Offset(x + 4, y + 4)),
            _w(Offset(x + 4, y)),
          ],
          odd ? light : g,
          floor: true,
        );
      }
    }
    if (w.map == ZombieMap.town) {
      _flat(
        r,
        const Rect.fromLTWH(0, kWorldH / 2 - 3, kWorldW, 6),
        const Color(0xFF546E7A),
      );
      for (var x = 1.0; x < kWorldW; x += 4) {
        _flat(
          r,
          Rect.fromLTWH(x, kWorldH / 2 - 0.12, 2, 0.24),
          const Color(0xFFFFF59D),
        );
      }
    } else if (w.map == ZombieMap.school) {
      final line = Colors.white.withValues(alpha: 0.6);
      _flat(r, const Rect.fromLTWH(6, 6, kWorldW - 12, 0.2), line);
      _flat(r, const Rect.fromLTWH(6, kWorldH - 6.2, kWorldW - 12, 0.2), line);
      _flat(r, const Rect.fromLTWH(6, 6, 0.2, kWorldH - 12), line);
      _flat(r, const Rect.fromLTWH(kWorldW - 6.2, 6, 0.2, kWorldH - 12), line);
      _flat(
        r,
        const Rect.fromLTWH(kWorldW / 2 - 0.1, 6, 0.2, kWorldH - 12),
        line,
      );
    }
  }

  void _flat(Renderer r, Rect b, Color c, [double z = 0.01]) => r.add(
    [
      _w(b.topLeft, z),
      _w(b.bottomLeft, z),
      _w(b.bottomRight, z),
      _w(b.topRight, z),
    ],
    c,
    lit: false,
    floor: true,
  );

  /// The four corner safe zones: a green glow on the floor and posts
  /// along the sides zombies can't cross.
  void _safeZones(Renderer r) {
    final glow = const Color(0xFF69F0AE).withValues(alpha: 0.35);
    const post = Color(0xFF00E676);
    for (final z in kSafeZones) {
      _flat(r, z, glow, 0.02);
      final x = z.left == 0 ? z.right : z.left;
      final y = z.top == 0 ? z.bottom : z.top;
      for (var t = 0.0; t <= kSafeSize + 0.01; t += 2) {
        final ax = z.left == 0 ? t : kWorldW - t;
        final ay = z.top == 0 ? t : kWorldH - t;
        _rect(
          r,
          Rect.fromCenter(center: Offset(x, ay), width: 0.25, height: 0.25),
          0,
          1,
          post,
        );
        _rect(
          r,
          Rect.fromCenter(center: Offset(ax, y), width: 0.25, height: 0.25),
          0,
          1,
          post,
        );
      }
      // A flag on the inside corner so you can spot it.
      final c = Offset(x, y);
      _rect(
        r,
        Rect.fromCenter(center: c, width: 0.2, height: 0.2),
        0,
        4,
        Colors.white,
      );
      _box(
        r,
        _w(c) + const V3(0.6, 0, 0),
        0.6,
        0.04,
        3.2,
        0.8,
        0,
        post,
        lit: false,
      );
    }
  }

  void _fence(Renderer r) {
    const brown = Color(0xFF6D4C41);
    const h = 1.1, t = 0.3;
    _rect(r, const Rect.fromLTWH(-t, -t, kWorldW + 2 * t, t), 0, h, brown);
    _rect(r, const Rect.fromLTWH(-t, kWorldH, kWorldW + 2 * t, t), 0, h, brown);
    _rect(r, const Rect.fromLTWH(-t, 0, t, kWorldH), 0, h, brown);
    _rect(r, const Rect.fromLTWH(kWorldW, 0, t, kWorldH), 0, h, brown);
  }

  void _block(Renderer r, Rect b) {
    switch (w.map) {
      case ZombieMap.farm:
        if (max(b.width, b.height) >= 6) {
          _house(
            r,
            b,
            wall: const Color(0xFFC62828),
            roof: const Color(0xFF616161),
            h: 3.6,
            ridge: 5.6,
            windows: false,
          );
        } else {
          const hay = Color(0xFFFFD54F);
          _rect(r, b, 0, 1.2, hay);
          final strap = b.width > b.height
              ? Rect.fromCenter(
                  center: b.center,
                  width: 0.15,
                  height: b.height + 0.04,
                )
              : Rect.fromCenter(
                  center: b.center,
                  width: b.width + 0.04,
                  height: 0.15,
                );
          _rect(r, strap, 0, 1.22, const Color(0xFF8D6E63));
        }
      case ZombieMap.beach:
        if (b.width >= 3.5) {
          // A beach hut with a straw roof.
          _rect(r, b, 0, 2.4, const Color(0xFF4DD0E1));
          final c = _w(b.center, 4);
          final cs = [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft];
          for (var i = 0; i < 4; i++) {
            r.add([
              _w(cs[i], 2.4),
              _w(cs[(i + 1) % 4], 2.4),
              c,
            ], const Color(0xFFD4B26A));
          }
          final y = b.bottom + 0.02;
          _upright(
            r,
            Offset(b.center.dx - 0.5, y),
            Offset(b.center.dx + 0.5, y),
            0,
            1.9,
            const Color(0xFFFFFFFF),
          );
        } else if (b.width >= 1.5) {
          _rect(r, b, 0, 1.0, const Color(0xFF8D8D8D));
          _rect(r, b.deflate(0.4), 1.0, 1.5, const Color(0xFF9E9E9E));
        } else {
          // A palm tree.
          _rect(r, b.deflate(0.25), 0, 4.6, const Color(0xFF8D6E63));
          for (var i = 0; i < 5; i++) {
            final a = i * 2 * pi / 5;
            _box(
              r,
              _w(b.center + Offset.fromDirection(-a, 0.9)),
              0.9,
              0.3,
              4.4,
              0.12,
              a,
              const Color(0xFF43A047),
            );
          }
        }
      case ZombieMap.snow:
        if (b.width >= 1.2) {
          // A snowman.
          const snow = Color(0xFFFFFFFF);
          final c = _w(b.center);
          _box(r, c, 0.65, 0.65, 0, 0.95, 0, snow);
          _box(r, c, 0.47, 0.47, 0.95, 0.75, 0, snow);
          _box(r, c, 0.33, 0.33, 1.7, 0.6, 0, snow);
          _box(r, c, 0.2, 0.2, 2.3, 0.45, 0, const Color(0xFF212121));
          _box(
            r,
            c + const V3(0, -0.45, 0),
            0.06,
            0.2,
            1.95,
            0.1,
            pi / 2,
            const Color(0xFFFF7043),
            lit: false,
          );
        } else {
          // A pine tree with snow on top.
          final c = _w(b.center);
          _box(r, c, 0.2, 0.2, 0, 1, 0, const Color(0xFF5D4037));
          const green = Color(0xFF2E7D32);
          var z = 1.0;
          for (final half in [1.3, 0.95, 0.62, 0.32]) {
            _box(r, c, half, half, z, 1.0, 0.4, green);
            z += 0.9;
          }
          _box(r, c, 0.2, 0.2, z, 0.25, 0.4, Colors.white);
        }
      case ZombieMap.town:
        if (min(b.width, b.height) < 2.5) {
          _car(r, b);
        } else {
          _house(
            r,
            b,
            wall: const Color(0xFFF3E5AB),
            roof: const Color(0xFFB0453A),
            h: 3.0,
            ridge: 4.8,
          );
        }
      case ZombieMap.graveyard:
        if (b.width > 3) {
          _rect(r, b, 0, 1.1, const Color(0xFF78909C));
          _rect(r, b.deflate(0.3), 1.1, 1.3, const Color(0xFF90A4AE));
        } else {
          // A gravestone stands up across its short side.
          final stone = b.width > b.height
              ? Rect.fromCenter(center: b.center, width: b.width, height: 0.35)
              : Rect.fromCenter(
                  center: b.center,
                  width: 0.35,
                  height: b.height,
                );
          _rect(r, stone, 0, 1.5, const Color(0xFFB0BEC5));
          _rect(r, b, 0, 0.12, const Color(0xFF4E5B47));
        }
      case ZombieMap.school:
        if (b.height > 2) {
          // Climbing frame: posts and a top.
          const blue = Color(0xFF1565C0), yellow = Color(0xFFFFCA28);
          for (final c in [
            b.topLeft,
            b.topRight,
            b.bottomLeft,
            b.bottomRight,
          ]) {
            final p = Offset(
              c.dx.clamp(b.left + 0.2, b.right - 0.2),
              c.dy.clamp(b.top + 0.2, b.bottom - 0.2),
            );
            _rect(
              r,
              Rect.fromCenter(center: p, width: 0.3, height: 0.3),
              0,
              2.4,
              blue,
            );
          }
          _rect(r, b, 2.4, 2.6, yellow);
          _rect(r, b.deflate(0.6), 1.2, 1.35, yellow);
          // Underneath is blocked for zombies and you, so fill it softly.
          _rect(r, b.deflate(0.25), 0, 1.2, const Color(0xFF1E88E5));
        } else {
          _rect(r, b, 0.45, 0.6, const Color(0xFF8D6E63));
          _rect(r, b.deflate(0.25), 0, 0.45, const Color(0xFF5D4037));
        }
    }
  }

  void _house(
    Renderer r,
    Rect b, {
    required Color wall,
    required Color roof,
    required double h,
    required double ridge,
    bool windows = true,
  }) {
    _rect(r, b, 0, h, wall);
    final along = b.width >= b.height; // ridge runs along the long side
    if (along) {
      final y = b.center.dy;
      final a = _w(Offset(b.left, y), ridge), c = _w(Offset(b.right, y), ridge);
      r.add([_w(b.topLeft, h), a, c, _w(b.topRight, h)], roof);
      r.add([_w(b.bottomLeft, h), _w(b.bottomRight, h), c, a], roof);
      r.add([_w(b.topLeft, h), _w(b.bottomLeft, h), a], wall);
      r.add([_w(b.topRight, h), _w(b.bottomRight, h), c], wall);
    } else {
      final x = b.center.dx;
      final a = _w(Offset(x, b.top), ridge), c = _w(Offset(x, b.bottom), ridge);
      r.add([_w(b.topLeft, h), a, c, _w(b.bottomLeft, h)], roof);
      r.add([_w(b.topRight, h), _w(b.bottomRight, h), c, a], roof);
      r.add([_w(b.topLeft, h), _w(b.topRight, h), a], wall);
      r.add([_w(b.bottomLeft, h), _w(b.bottomRight, h), c], wall);
    }
    // A door and windows on the side facing down the map.
    const door = Color(0xFF6D4C41), glass = Color(0xFF81D4FA);
    final y = b.bottom + 0.02;
    _upright(
      r,
      Offset(b.center.dx - 0.5, y),
      Offset(b.center.dx + 0.5, y),
      0,
      2,
      door,
    );
    if (!windows) {
      // A big barn door.
      _upright(
        r,
        Offset(b.center.dx - 1.4, y),
        Offset(b.center.dx + 1.4, y),
        0,
        2.8,
        const Color(0xFFFFFFFF),
      );
      return;
    }
    _upright(
      r,
      Offset(b.left + 0.8, y),
      Offset(b.left + 2, y),
      1.2,
      2.2,
      glass,
    );
    _upright(
      r,
      Offset(b.right - 2, y),
      Offset(b.right - 0.8, y),
      1.2,
      2.2,
      glass,
    );
  }

  void _car(Renderer r, Rect b) {
    const colours = [
      Color(0xFFE53935),
      Color(0xFF1E88E5),
      Color(0xFFFDD835),
      Color(0xFFECEFF1),
    ];
    final c = colours[(b.left * 7 + b.top).floor() % colours.length];
    _rect(r, b, 0.25, 0.95, c);
    final long = b.width > b.height;
    final cab = long
        ? Rect.fromLTRB(
            b.left + 1,
            b.top + 0.15,
            b.right - 1.2,
            b.bottom - 0.15,
          )
        : Rect.fromLTRB(
            b.left + 0.15,
            b.top + 1,
            b.right - 0.15,
            b.bottom - 1.2,
          );
    _rect(r, cab, 0.95, 1.55, const Color(0xFF90CAF9));
    _rect(r, cab.deflate(0.05), 1.55, 1.6, c);
    // Wheels.
    const tyre = Color(0xFF212121);
    for (final f in [0.22, 0.78]) {
      final p = long
          ? Offset(b.left + b.width * f, b.center.dy)
          : Offset(b.center.dx, b.top + b.height * f);
      final wheel = long
          ? Rect.fromCenter(center: p, width: 0.7, height: b.height + 0.1)
          : Rect.fromCenter(center: p, width: b.width + 0.1, height: 0.7);
      _rect(r, wheel, 0, 0.6, tyre);
    }
  }

  void _pickup(Renderer r, Pickup p) {
    if (p.life < 3 && (w.time * 6).floor().isEven) return; // blinking out
    final z = 0.3 + sin(w.time * 4) * 0.12;
    final spin = w.time * 2;
    switch (p.kind) {
      case PickupKind.health:
        _box(r, _w(p.pos, z), 0.45, 0.45, 0, 0.6, spin, Colors.white);
        _box(
          r,
          _w(p.pos, z + 0.6),
          0.32,
          0.09,
          0,
          0.02,
          spin,
          const Color(0xFFE53935),
          lit: false,
        );
        _box(
          r,
          _w(p.pos, z + 0.6),
          0.09,
          0.32,
          0,
          0.02,
          spin,
          const Color(0xFFE53935),
          lit: false,
        );
      case PickupKind.grenade:
        _box(r, _w(p.pos, z), 0.3, 0.3, 0, 0.6, spin, const Color(0xFF558B2F));
        _box(
          r,
          _w(p.pos, z + 0.6),
          0.1,
          0.1,
          0,
          0.15,
          spin,
          const Color(0xFF9E9E9E),
        );
      case PickupKind.sword:
        // A sword standing up, spinning, with a gold glow under it.
        _shadow(r, p.pos, 0.9, const Color(0x80FFD54F));
        _box(
          r,
          _w(p.pos),
          0.05,
          0.12,
          z + 0.55,
          1.4,
          spin,
          const Color(0xFFECEFF1),
        );
        _box(
          r,
          _w(p.pos),
          0.08,
          0.4,
          z + 0.45,
          0.1,
          spin,
          const Color(0xFFFFC107),
        );
        _box(r, _w(p.pos), 0.07, 0.07, z, 0.45, spin, const Color(0xFF6D4C41));
    }
  }

  // ---- people ------------------------------------------------------------

  void _shadow(
    Renderer r,
    Offset p,
    double radius, [
    Color colour = const Color(0x50000000),
  ]) {
    const n = 10;
    r.add(
      [
        for (var i = 0; i < n; i++)
          _w(p + Offset.fromDirection(i / n * 2 * pi, radius), 0.02),
      ],
      colour,
      lit: false,
      floor: true,
    );
  }

  void _zombie(Renderer r, Zombie z) {
    final s = z.r / 0.85;
    final skin = z.flash > 0
        ? Colors.white
        : switch (z.kind) {
            ZombieKind.walker => const Color(0xFF8BC34A),
            ZombieKind.runner => const Color(0xFFC0CA33),
            ZombieKind.tank => const Color(0xFF558B2F),
            ZombieKind.king => const Color(0xFF7CB342),
          };
    final shirt = z.flash > 0
        ? Colors.white
        : switch (z.kind) {
            ZombieKind.walker => const Color(0xFF6D4C41),
            ZombieKind.runner => const Color(0xFF5C6BC0),
            ZombieKind.tank => const Color(0xFF37474F),
            ZombieKind.king => const Color(0xFF6A1B9A),
          };
    _shadow(r, z.pos, z.r * 0.8);
    _body(
      r,
      z.pos,
      _yaw(z.facing),
      s,
      skin: skin,
      shirt: shirt,
      trousers: const Color(0xFF455A64),
      walk: z.wobble,
      armsOut: true,
    );
    final at = _w(z.pos);
    final yaw = _yaw(z.facing);
    final f = V3(cos(yaw), sin(yaw), 0), side = V3(-sin(yaw), cos(yaw), 0);
    // Glowing yellow eyes.
    for (final k in [-1.0, 1.0]) {
      _box(
        r,
        at + f * (0.23 * s) + side * (0.1 * k * s),
        0.02 * s,
        0.05 * s,
        1.72 * s,
        0.08 * s,
        yaw,
        const Color(0xFFFFEB3B),
        lit: false,
      );
    }
    if (z.sword) {
      // A sword held up in its right hand.
      final hand = at + f * (0.8 * s) - side * (0.37 * s);
      _box(
        r,
        hand,
        0.06 * s,
        0.06 * s,
        1.2 * s,
        0.3 * s,
        yaw,
        const Color(0xFF6D4C41),
      );
      _box(
        r,
        hand,
        0.08 * s,
        0.25 * s,
        1.5 * s,
        0.08 * s,
        yaw,
        const Color(0xFFFFC107),
      );
      _box(
        r,
        hand,
        0.04 * s,
        0.1 * s,
        1.58 * s,
        1.1 * s,
        yaw,
        const Color(0xFFCFD8DC),
      );
    }
    if (z.kind == ZombieKind.king) {
      // A gold crown with points.
      const gold = Color(0xFFFFC107);
      _box(r, at, 0.24 * s, 0.24 * s, 1.95 * s, 0.12 * s, yaw, gold);
      for (final dx in [-1.0, 1.0]) {
        for (final dy in [-1.0, 1.0]) {
          _box(
            r,
            at + f * (0.18 * dx * s) + side * (0.18 * dy * s),
            0.05 * s,
            0.05 * s,
            2.07 * s,
            0.12 * s,
            yaw,
            gold,
          );
        }
      }
    }
  }

  void _player(Renderer r) {
    final yaw = _yaw(w.aimAngle);
    _shadow(r, w.player, kPlayerR * 0.8);
    final moving = w.input.move.distance > 0.1;
    _body(
      r,
      w.player,
      yaw,
      1,
      skin: const Color(0xFFFFCC80),
      shirt: w.hurtT > 0 ? const Color(0xFFFF5252) : const Color(0xFF1E88E5),
      trousers: const Color(0xFF283593),
      walk: moving ? w.time * 10 : 0,
      armsOut: false,
    );
    final at = _w(w.player);
    final f = V3(cos(yaw), sin(yaw), 0), side = V3(-sin(yaw), cos(yaw), 0);
    // Hair, then the gun held out in front.
    _box(r, at - f * 0.03, 0.24, 0.24, 1.87, 0.1, yaw, const Color(0xFF5D4037));
    if (w.gun.melee) {
      _sword(r, at, yaw, side);
    } else {
      _gun(r, at, yaw, f, side);
    }
    // Arms reaching forwards.
    for (final k in [-1.0, 1.0]) {
      _box(
        r,
        at + f * 0.25 + side * (0.25 * k - 0.05),
        0.25,
        0.08,
        1.2,
        0.16,
        yaw,
        const Color(0xFF1E88E5),
      );
    }
  }

  /// Your sword: held out to the right, sweeping across when you swing.
  void _sword(Renderer r, V3 at, double yaw, V3 side) {
    final k = w.swingT > 0 ? 1 - w.swingT / kSwingTime : 0.0;
    final a = w.swingT > 0 ? yaw + 1.2 - 2.4 * k : yaw - 0.35;
    final dir = V3(cos(a), sin(a), 0);
    final hand = at + V3(cos(yaw), sin(yaw), 0) * 0.45 - side * 0.12;
    _box(
      r,
      hand + dir * 0.12,
      0.14,
      0.05,
      1.12,
      0.1,
      a,
      const Color(0xFF6D4C41),
    );
    _box(
      r,
      hand + dir * 0.3,
      0.04,
      0.22,
      1.08,
      0.18,
      a,
      const Color(0xFFFFC107),
    );
    _box(r, hand + dir * 1.0, 0.68, 0.06, 1.13, 0.08, a, w.gun.colour);
  }

  void _gun(Renderer r, V3 at, double yaw, V3 f, V3 side) {
    final gunAt = at + f * 0.55 + side * -0.2;
    _box(r, gunAt, 0.42, 0.08, 1.15, 0.18, yaw, const Color(0xFF263238));
    _box(
      r,
      gunAt + f * 0.42,
      0.04,
      0.09,
      1.14,
      0.2,
      yaw,
      w.gun.colour,
      lit: false,
    );
  }

  /// A blocky person facing [yaw] (3D angle), [s] times normal size.
  void _body(
    Renderer r,
    Offset pos,
    double yaw,
    double s, {
    required Color skin,
    required Color shirt,
    required Color trousers,
    required double walk,
    required bool armsOut,
  }) {
    final at = _w(pos);
    final f = V3(cos(yaw), sin(yaw), 0), side = V3(-sin(yaw), cos(yaw), 0);
    final step = sin(walk) * 0.18 * s;
    for (final k in [-1.0, 1.0]) {
      _box(
        r,
        at + side * (0.13 * k * s) + f * (step * k),
        0.11 * s,
        0.11 * s,
        0,
        0.85 * s,
        yaw,
        trousers,
      );
    }
    _box(r, at, 0.17 * s, 0.3 * s, 0.85 * s, 0.7 * s, yaw, shirt);
    _box(r, at, 0.22 * s, 0.22 * s, 1.55 * s, 0.42 * s, yaw, skin);
    if (armsOut) {
      // Zombie arms stretched out in front, swaying.
      for (final k in [-1.0, 1.0]) {
        final sway = sin(walk + k) * 0.06 * s;
        _box(
          r,
          at + f * (0.42 * s) + side * (0.37 * k * s),
          0.38 * s,
          0.08 * s,
          1.3 * s + sway,
          0.16 * s,
          yaw,
          skin,
        );
      }
    }
  }

  /// A box centred on [c] (ground point) from height [z0] to [z0]+[h],
  /// [hf] long forwards and [hs] wide sideways, turned by [yaw].
  void _box(
    Renderer r,
    V3 c,
    double hf,
    double hs,
    double z0,
    double h,
    double yaw,
    Color colour, {
    bool lit = true,
  }) {
    final f = V3(cos(yaw), sin(yaw), 0) * hf;
    final s = V3(-sin(yaw), cos(yaw), 0) * hs;
    final base = V3(c.x, c.y, c.z + z0);
    final up = V3(0, 0, h);
    final a = base + f + s,
        b = base + f - s,
        d = base - f + s,
        e = base - f - s;
    r.add([a + up, b + up, e + up, d + up], colour, lit: lit);
    r.add([a, b, b + up, a + up], colour, lit: lit);
    r.add([b, e, e + up, b + up], colour, lit: lit);
    r.add([e, d, d + up, e + up], colour, lit: lit);
    r.add([d, a, a + up, d + up], colour, lit: lit);
  }

  /// A box over a map rectangle, from height [z0] to [z1].
  void _rect(Renderer r, Rect b, double z0, double z1, Color colour) {
    _box(r, _w(b.center), b.width / 2, b.height / 2, z0, z1 - z0, 0, colour);
  }

  /// A flat upright panel (a door or window) between two map points.
  void _upright(Renderer r, Offset a, Offset b, double z0, double z1, Color c) {
    r.add(
      [_w(a, z0), _w(b, z0), _w(b, z1), _w(a, z1)],
      c,
      lit: false,
      bias: -0.6,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
