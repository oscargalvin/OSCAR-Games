import 'dart:math';
import 'dart:typed_data';

import 'dart:ui' show Vertices, VertexMode;

import 'package:flutter/material.dart';

import '../boost_ball/boost_ball_3d.dart' show V3;
import 'outplay_art.dart';
import 'outplay_avatar.dart';
import 'outplay_data.dart';

// Outplay in real 3D: flat-shaded blocks sorted far to near and drawn with
// Canvas.drawVertices. Map points (x, y) sit at V3(x, -y, z) so the map
// isn't mirrored, and z is height (1 is a normal wall).

/// A point on the map at height [z].
V3 op3(Offset p, double z) => V3(p.dx, -p.dy, z);

/// Which way an angle on the map points, in 3D.
V3 opDir(double angle) => V3(cos(angle), -sin(angle), 0);

const V3 kUp = V3(0, 0, 1);

class _Tri {
  final double depth;
  final double ax, ay, bx, by, cx, cy;
  final int colour;
  _Tri(
    this.depth,
    this.ax,
    this.ay,
    this.bx,
    this.by,
    this.cx,
    this.cy,
    this.colour,
  );
}

class _Item {
  final double depth;
  final List<_Tri>? tris;
  final void Function(Canvas)? draw;
  _Item(this.depth, {this.tris, this.draw});
}

/// One frame of a 3D scene seen from [eye].
class Scene3D {
  final V3 eye, f, r, u;
  final double focal;
  final Offset centre;
  final Color fog;
  final double fogFar;
  final double fogMax;
  static const near = 0.05;
  static final V3 light = const V3(0.35, -0.45, 0.82).unit;

  final List<_Tri> _floor = [];
  final List<_Item> _items = [];
  List<_Tri>? _group;
  double _groupSum = 0;
  int _groupN = 0;

  Scene3D._(
    this.eye,
    this.f,
    this.r,
    this.u,
    this.focal,
    this.centre,
    this.fog,
    this.fogFar,
    this.fogMax,
  );

  /// A camera at [eye] looking towards [forward].
  factory Scene3D(
    V3 eye,
    V3 forward,
    double focal,
    Offset centre, {
    Color fog = const Color(0xFF90A4AE),
    double fogFar = 16,
    double fogMax = 0.65,
  }) {
    final f = forward.unit;
    var r = f.cross(kUp);
    r = r.length < 1e-6 ? const V3(1, 0, 0) : r.unit;
    final u = r.cross(f);
    return Scene3D._(eye, f, r, u, focal, centre, fog, fogFar, fogMax);
  }

  V3 toCam(V3 p) {
    final d = p - eye;
    return V3(d.dot(r), d.dot(u), d.dot(f));
  }

  /// A direction in camera space (right, up, forward) as a world direction.
  V3 fromCamDir(double x, double y, double z) => r * x + u * y + f * z;

  V3 camToWorld(V3 c) => eye + fromCamDir(c.x, c.y, c.z);

  double depthOf(V3 p) => (p - eye).dot(f);

  Offset? project(V3 p) {
    final c = toCam(p);
    if (c.z < 0.1) return null;
    return Offset(centre.dx + c.x / c.z * focal, centre.dy - c.y / c.z * focal);
  }

  int _shade(Color colour, double shade, double depth) {
    final t = min(fogMax, max(0.0, depth / fogFar));
    final a = (colour.a * 255).round();
    double ch(double c, double fc) => (c * shade) * (1 - t) + fc * t;
    final rr = (ch(colour.r, fog.r) * 255).round().clamp(0, 255);
    final gg = (ch(colour.g, fog.g) * 255).round().clamp(0, 255);
    final bb = (ch(colour.b, fog.b) * 255).round().clamp(0, 255);
    return a << 24 | rr << 16 | gg << 8 | bb;
  }

  /// A flat polygon. With [normal] it's only drawn from the side it faces.
  /// Floor polygons are drawn first, in the order they're added.
  void poly(
    List<V3> pts,
    Color colour, {
    V3? normal,
    bool lit = true,
    bool floor = false,
    bool decal = false,
  }) {
    if (pts.length < 3) return;
    if (normal != null && normal.dot(eye - pts[0]) <= 0) return;
    var shade = 1.0;
    if (lit) {
      final n = normal ?? (pts[1] - pts[0]).cross(pts[2] - pts[0]).unit;
      shade = 0.55 + 0.45 * n.dot(light).abs();
    }
    var cam = [for (final p in pts) toCam(p)];
    if (cam.every((p) => p.z < near)) return;
    if (cam.any((p) => p.z < near)) cam = _clip(cam);
    if (cam.length < 3) return;
    var depth = 0.0;
    for (final p in cam) {
      depth += p.z;
    }
    depth /= cam.length;
    // Fog by real distance, so it doesn't swing as you turn.
    var dist = 0.0;
    for (final p in cam) {
      dist += p.length;
    }
    final c = _shade(colour, shade, dist / cam.length);
    final xs = [for (final p in cam) centre.dx + p.x / p.z * focal];
    final ys = [for (final p in cam) centre.dy - p.y / p.z * focal];
    final out = floor ? _floor : (_group ?? <_Tri>[]);
    // Decals (eyes, bricks) go on top of everything else in their group.
    final sortDepth = decal && _group != null ? depth - 1e6 : depth;
    for (var i = 1; i < cam.length - 1; i++) {
      out.add(
        _Tri(sortDepth, xs[0], ys[0], xs[i], ys[i], xs[i + 1], ys[i + 1], c),
      );
    }
    if (floor) return;
    if (_group != null) {
      if (!decal) {
        _groupSum += depth * (cam.length - 2);
        _groupN += cam.length - 2;
      }
    } else {
      _items.add(_Item(depth, tris: out));
    }
  }

  /// Everything [build] adds is sorted as one thing (a person, a wall face
  /// and its bricks...), so its parts never poke through something else.
  void group(void Function() build, {double? depth, double bias = 0}) {
    final tris = _group = <_Tri>[];
    _groupSum = 0;
    _groupN = 0;
    build();
    _group = null;
    if (tris.isEmpty) return;
    tris.sort((a, b) => b.depth.compareTo(a.depth));
    _items.add(
      _Item((depth ?? _groupSum / max(1, _groupN)) + bias, tris: tris),
    );
  }

  /// Flat drawing (a name tag, a picture) done in its place in the sort.
  void later(double depth, void Function(Canvas) draw) =>
      _items.add(_Item(depth, draw: draw));

  /// A four-sided face: [c] is its middle, [a] and [b] go half way across.
  void quad(
    V3 c,
    V3 a,
    V3 b,
    Color colour, {
    V3? normal,
    bool lit = true,
    bool decal = false,
  }) => poly(
    [c - a - b, c + a - b, c + a + b, c - a + b],
    colour,
    normal: normal,
    lit: lit,
    decal: decal,
  );

  /// A block centred at [c] lined up with [ax], [ay] and [az], reaching
  /// [hx], [hy] and [hz] out from the middle each way.
  void box(
    V3 c,
    V3 ax,
    V3 ay,
    V3 az,
    double hx,
    double hy,
    double hz,
    Color colour, {
    Color? top,
    Color? front,
  }) {
    final x = ax * hx, y = ay * hy, z = az * hz;
    quad(c + x, y, z, front ?? colour, normal: ax);
    quad(c - x, y, z, colour, normal: ax * -1);
    quad(c + y, x, z, colour, normal: ay);
    quad(c - y, x, z, colour, normal: ay * -1);
    quad(c + z, x, y, top ?? colour, normal: az);
    quad(c - z, x, y, colour, normal: az * -1);
  }

  static List<V3> _clip(List<V3> poly) {
    final out = <V3>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final ain = a.z >= near, bin = b.z >= near;
      if (ain) out.add(a);
      if (ain != bin) {
        final t = (near - a.z) / (b.z - a.z);
        out.add(a + (b - a) * t);
      }
    }
    return out;
  }

  void draw(Canvas canvas) {
    _flush(canvas, _floor);
    _items.sort((a, b) => b.depth.compareTo(a.depth));
    final batch = <_Tri>[];
    for (final it in _items) {
      if (it.tris != null) {
        batch.addAll(it.tris!);
      } else {
        _flush(canvas, batch);
        batch.clear();
        it.draw!(canvas);
      }
    }
    _flush(canvas, batch);
  }

  static void _flush(Canvas canvas, List<_Tri> tris) {
    if (tris.isEmpty) return;
    final pos = Float32List(tris.length * 6);
    final col = Int32List(tris.length * 3);
    for (var i = 0; i < tris.length; i++) {
      final t = tris[i];
      pos[i * 6] = t.ax;
      pos[i * 6 + 1] = t.ay;
      pos[i * 6 + 2] = t.bx;
      pos[i * 6 + 3] = t.by;
      pos[i * 6 + 4] = t.cx;
      pos[i * 6 + 5] = t.cy;
      col[i * 3] = t.colour;
      col[i * 3 + 1] = t.colour;
      col[i * 3 + 2] = t.colour;
    }
    canvas.drawVertices(
      Vertices.raw(VertexMode.triangles, pos, colors: col),
      BlendMode.dst,
      Paint(),
    );
  }
}

// ===========================================================================
// People.
// ===========================================================================

const Color _ink = Color(0xFF15172A);

/// A blocky 3D person standing at [pos] (feet at height [z]) facing
/// [angle]. [walk] swings their legs; [held] is what's in their hands.
void addPerson(
  Scene3D s,
  Avatar look,
  Offset pos,
  double z,
  double angle, {
  double walk = 0,
  bool hurt = false,
  bool slow = false,
  WeaponLook? held,
  Color heldColour = Colors.grey,
  Skin? skin,
  double swing = 0,
}) {
  final base = op3(pos, z);
  final f = opDir(angle);
  final r = f.cross(kUp).unit;
  V3 at(double fw, double rt, double up) => base + f * fw + r * rt + kUp * up;
  Color c(Color col) => hurt ? Colors.white : col;
  final skinC = c(look.skinColour);
  var shirt = c(look.shirtColour);
  if (slow) shirt = Color.lerp(shirt, const Color(0xFF81D4FA), 0.6)!;
  final pants = c(look.pantsColour);
  final hair = c(look.hairPaint);
  void b(V3 at, double hx, double hy, double hz, Color col, {Color? top}) =>
      s.box(at, f, r, kUp, hx, hy, hz, col, top: top);

  s.group(() {
    // Legs and shoes.
    for (final side in [-1.0, 1.0]) {
      final step = sin(walk) * 0.07 * side;
      b(at(step, side * 0.085, 0.19), 0.065, 0.065, 0.15, pants);
      b(at(step + 0.02, side * 0.085, 0.03), 0.085, 0.07, 0.03, c(_ink));
    }
    // Body, with a belt.
    b(at(0, 0, 0.5), 0.1, 0.18, 0.16, shirt);
    b(at(0, 0, 0.355), 0.105, 0.185, 0.02, c(const Color(0xFF3E2723)));
    // Arms out in front, holding what they've got.
    final lift = swing * 0.12;
    for (final side in [-1.0, 1.0]) {
      b(at(0.09, side * 0.21, 0.59 + lift), 0.13, 0.05, 0.05, shirt);
      b(at(0.24, side * 0.15, 0.58 + lift), 0.045, 0.045, 0.045, skinC);
    }
    _head(s, at, f, r, look, skinC, hair, c);
    if (held != null) {
      _heldWeapon(
        s,
        at(0.27, 0.06, 0.58 + lift),
        f,
        r,
        held,
        hurt ? Colors.white : heldColour,
        skin,
        swing,
      );
    }
  });
}

void _head(
  Scene3D s,
  V3 Function(double, double, double) at,
  V3 f,
  V3 r,
  Avatar look,
  Color skinC,
  Color hair,
  Color Function(Color) c,
) {
  void b(V3 p, double hx, double hy, double hz, Color col) =>
      s.box(p, f, r, kUp, hx, hy, hz, col);
  void face(double rt, double up, double hw, double hh, Color col) => s.quad(
    at(0.133, rt, up),
    r * hw,
    kUp * hh,
    col,
    normal: f,
    lit: false,
    decal: true,
  );

  b(at(0, 0, 0.79), 0.13, 0.13, 0.13, skinC);
  // The face, on the front of the head.
  final eye = c(_ink);
  switch (look.face) {
    case 2: // shades
      face(0, 0.815, 0.11, 0.03, c(const Color(0xFF111111)));
    case 3: // angry
      for (final side in [-1.0, 1.0]) {
        face(side * 0.05, 0.81, 0.022, 0.022, eye);
        face(side * 0.05, 0.85, 0.035, 0.008, eye);
      }
    default:
      for (final side in [-1.0, 1.0]) {
        face(side * 0.05, 0.815, 0.022, 0.027, eye);
      }
  }
  switch (look.face) {
    case 1: // grin
      face(0, 0.74, 0.06, 0.02, c(Colors.white));
    case 3:
      face(0, 0.735, 0.04, 0.008, c(const Color(0xFF6D1B1B)));
    case 4: // wow
      face(0, 0.735, 0.022, 0.025, c(const Color(0xFF6D1B1B)));
    default:
      face(0, 0.74, 0.045, 0.012, c(const Color(0xFFB71C1C)));
  }
  // Hair.
  switch (look.hair) {
    case 1: // short
      b(at(-0.01, 0, 0.93), 0.14, 0.14, 0.02, hair);
      b(at(-0.13, 0, 0.84), 0.015, 0.14, 0.08, hair);
    case 2: // spiky
      b(at(-0.01, 0, 0.93), 0.14, 0.14, 0.02, hair);
      for (var i = 0; i < 4; i++) {
        b(
          at(0.06 - i * 0.06, (i.isEven ? 1 : -1) * 0.05, 0.98),
          0.03,
          0.03,
          0.04,
          hair,
        );
      }
    case 3: // long
      b(at(-0.01, 0, 0.93), 0.14, 0.14, 0.02, hair);
      b(at(-0.13, 0, 0.76), 0.02, 0.15, 0.17, hair);
      for (final side in [-1.0, 1.0]) {
        b(at(-0.04, side * 0.14, 0.8), 0.09, 0.015, 0.12, hair);
      }
    case 4: // mohawk
      b(at(-0.02, 0, 0.97), 0.13, 0.025, 0.06, hair);
  }
  // Hats.
  switch (look.hat) {
    case 1: // cap
      final red = c(const Color(0xFFE53935));
      b(at(0, 0, 0.95), 0.135, 0.135, 0.035, red);
      b(at(0.18, 0, 0.925), 0.06, 0.12, 0.01, red);
    case 2: // beanie
      b(at(0, 0, 0.96), 0.14, 0.14, 0.05, c(const Color(0xFF3949AB)));
      b(at(0, 0, 0.9), 0.142, 0.142, 0.015, c(const Color(0xFF5C6BC0)));
    case 3: // crown
      final gold = c(const Color(0xFFFFC93C));
      b(at(0, 0, 0.94), 0.12, 0.12, 0.02, gold);
      for (final (x, y) in [(1, 1), (1, -1), (-1, 1), (-1, -1), (1, 0)]) {
        b(at(x * 0.1, y * 0.1, 0.99), 0.02, 0.02, 0.035, gold);
      }
    case 4: // top hat
      final black = c(const Color(0xFF212121));
      b(at(0, 0, 0.93), 0.17, 0.17, 0.01, black);
      b(at(0, 0, 1.04), 0.1, 0.1, 0.1, black);
      b(at(0, 0, 0.965), 0.102, 0.102, 0.02, c(const Color(0xFFE53935)));
    case 5: // horns
      for (final side in [-1.0, 1.0]) {
        b(at(0.03, side * 0.1, 0.96), 0.025, 0.025, 0.04, c(Colors.white));
        b(at(0.05, side * 0.12, 1.01), 0.018, 0.018, 0.025, c(Colors.white));
      }
    case 6: // headphones
      b(at(0, 0, 0.94), 0.025, 0.15, 0.015, c(const Color(0xFF212121)));
      for (final side in [-1.0, 1.0]) {
        b(
          at(0, side * 0.145, 0.8),
          0.05,
          0.02,
          0.06,
          c(const Color(0xFFE53935)),
        );
      }
  }
}

/// What someone else is holding, as blocks.
void _heldWeapon(
  Scene3D s,
  V3 hand,
  V3 f0,
  V3 r0,
  WeaponLook look,
  Color colour,
  Skin? skin,
  double swing,
) {
  // Swinging tips a melee weapon across in front of them.
  final f = (f0 * cos(swing * 1.2) - r0 * sin(swing * 1.2)).unit;
  final r = f.cross(kUp).unit;
  final metal = skin?.metal ?? const Color(0xFF2E333B);
  final grip = skin?.grip ?? const Color(0xFF23262B);
  final accent = skin?.accent ?? colour;
  V3 at(double fw, double rt, double up) => hand + f * fw + r * rt + kUp * up;
  void b(V3 p, double hx, double hy, double hz, Color col) =>
      s.box(p, f, r, kUp, hx, hy, hz, col);
  const steel = Color(0xFFB0BEC5);
  switch (look) {
    case WeaponLook.fist:
      b(at(0.03, 0, 0), 0.06, 0.06, 0.06, skin?.metal ?? colour);
    case WeaponLook.knife:
      b(at(0, 0, 0), 0.05, 0.02, 0.025, grip);
      b(at(0.12, 0, 0.005), 0.08, 0.008, 0.025, skin?.metal ?? steel);
    case WeaponLook.pan:
      b(at(0.06, 0, 0), 0.08, 0.015, 0.015, grip);
      b(
        at(0.24, 0, 0),
        0.11,
        0.11,
        0.015,
        skin?.metal ?? const Color(0xFF37474F),
      );
    case WeaponLook.slapper:
      b(at(0.1, 0, 0), 0.12, 0.02, 0.02, metal);
      b(at(0.27, 0, 0.02), 0.05, 0.02, 0.07, skin?.metal ?? colour);
    case WeaponLook.scythe:
      b(at(0.05, 0, 0.12), 0.02, 0.02, 0.3, grip);
      b(at(0.15, 0, 0.42), 0.14, 0.01, 0.035, skin?.metal ?? steel);
    case WeaponLook.snake:
      for (var i = 0; i < 5; i++) {
        b(
          at(0.04 + i * 0.06, sin(i * 1.4) * 0.03, 0),
          0.03,
          0.03,
          0.03,
          i.isEven ? skin?.metal ?? colour : const Color(0xFFFFEB3B),
        );
      }
    default:
      // A gun: body, barrel, grip, magazine and a coloured stripe.
      final len = switch (look) {
        WeaponLook.sniper => 0.24,
        WeaponLook.rpgMini => 0.2,
        WeaponLook.rifle || WeaponLook.flamer => 0.18,
        _ => 0.15,
      };
      final fat = look == WeaponLook.rpgMini || look == WeaponLook.flamer
          ? 0.045
          : 0.03;
      b(at(len * 0.5, 0, 0.03), len * 0.6, fat * 0.8, fat, metal);
      b(at(len * 1.2, 0, 0.04), len * 0.25, 0.012, 0.012, metal);
      b(at(len * 0.6, 0, 0.03 + fat), len * 0.4, fat * 0.5, 0.008, accent);
      b(at(-0.01, 0, -0.03), 0.02, 0.02, 0.04, grip);
      b(at(len * 0.4, 0, -0.03), 0.02, 0.018, 0.04, grip);
  }
}

// ===========================================================================
// The weapon pictures, made solid.
// ===========================================================================

/// Paints a weapon's picture as a solid object in 3D: [mid] is its middle,
/// [along] points from its back to its tip, [down] points from its top to
/// its grip, and it's [length] long. Returns where the tip ended up on
/// screen, or null if it's behind the camera.
Offset? paintWeapon3D(
  Canvas canvas,
  Scene3D s,
  WeaponLook look,
  Color colour,
  V3 mid,
  V3 along,
  V3 down,
  double length, {
  Skin? skin,
  double thick = 0.035,
  int layers = 10,
}) {
  final a = along.unit;
  final d = (down - a * down.dot(a)).unit;
  final n = a.cross(d).unit;
  // The picture is 100 units long, so this is one unit in 3D.
  final k = length / 100;
  Float64List matrix(V3 o) => _planeMatrix(s, o, a * k, d * k);

  // Everything has to be in front of the camera.
  for (final x in [-55.0, 55.0]) {
    for (final y in [-30.0, 30.0]) {
      if (s.toCam(mid + a * (x * k) + d * (y * k)).z < 0.06) return null;
    }
  }
  final steps = [
    for (var i = 0; i < layers; i++) n * (thick * (i / (layers - 1) - 0.5)),
  ];
  // Back layers first.
  steps.sort(
    (p, q) => s.toCam(mid + q).length.compareTo(s.toCam(mid + p).length),
  );
  void layer(V3 off) {
    canvas.save();
    canvas.transform(matrix(mid + off));
    paintWeapon(canvas, look, colour, 100, skin: skin);
    canvas.restore();
  }

  // The sides are the picture in shadow.
  canvas.saveLayer(
    null,
    Paint()
      ..colorFilter = const ColorFilter.matrix([
        0.5, 0, 0, 0, 0, //
        0, 0.5, 0, 0, 0,
        0, 0, 0.55, 0, 0,
        0, 0, 0, 1, 0,
      ]),
  );
  for (final off in steps.take(layers - 1)) {
    layer(off);
  }
  canvas.restore();
  layer(steps.last);
  return s.project(mid + a * (length / 2));
}

// ===========================================================================
// Menu pictures.
// ===========================================================================

/// A person seen in 3D, for menus. [turn] spins them (0 faces you).
void paintAvatar3D(
  Canvas canvas,
  Size size,
  Avatar avatar, {
  double turn = 0.3,
}) {
  final h = size.height;
  final focal = h * 2.1;
  // Stand them at the origin and back the camera off to fit them in.
  final s = Scene3D(
    const V3(-2.8, 0, 0.62),
    const V3(1, 0, -0.02),
    focal,
    Offset(size.width / 2, h * 0.5),
    fogFar: 1e9,
    fogMax: 0,
  );
  addPerson(s, avatar, Offset.zero, 0, pi + turn);
  s.draw(canvas);
}

/// A weapon tipped so you can see it's solid, for menus.
void paintWeaponIcon3D(
  Canvas canvas,
  Size size,
  WeaponLook look,
  Color colour, {
  Skin? skin,
}) {
  final s = Scene3D(
    const V3(0, -2, 0.35),
    const V3(0, 1, -0.17),
    size.width * 1.75,
    Offset(size.width / 2, size.height / 2),
    fogFar: 1e9,
    fogMax: 0,
  );
  paintWeapon3D(
    canvas,
    s,
    look,
    colour,
    const V3(0, 0, 0),
    const V3(1, 0.32, 0),
    const V3(0, 0.25, -1),
    0.9,
    skin: skin,
    thick: 0.045,
    layers: 5,
  );
}

/// Paints a flat picture onto a rectangle in 3D: [centre] is its middle,
/// [x] and [y] point along its width and down its height, and it's [w] by
/// [h] big. [draw] paints into a picture 200 wide.
void paintOnPlane(
  Canvas canvas,
  Scene3D s,
  V3 centre,
  V3 x,
  V3 y,
  double w,
  double h,
  void Function(Canvas c, double pw, double ph) draw,
) {
  const pw = 200.0;
  final ph = pw * h / w;
  final xu = x.unit, yu = y.unit;
  final o = centre - xu * (w / 2) - yu * (h / 2);
  for (final p in [o, o + xu * w, o + yu * h, o + xu * w + yu * h]) {
    if (s.toCam(p).z < 0.06) return;
  }
  canvas.save();
  canvas.transform(_planeMatrix(s, o, xu * (w / pw), yu * (h / ph)));
  draw(canvas, pw, ph);
  canvas.restore();
}

/// Sends picture point (px, py) to where o + ua*px + va*py lands on screen.
Float64List _planeMatrix(Scene3D s, V3 o, V3 ua, V3 va) {
  V3 dir(V3 v) => V3(v.dot(s.r), v.dot(s.u), v.dot(s.f));
  final a = dir(ua), b = dir(va), c = s.toCam(o);
  final f = s.focal, cx = s.centre.dx, cy = s.centre.dy;
  return Float64List.fromList([
    cx * a.z + f * a.x, cy * a.z - f * a.y, 0, a.z, //
    cx * b.z + f * b.x, cy * b.z - f * b.y, 0, b.z,
    0, 0, 1, 0,
    cx * c.z + f * c.x, cy * c.z - f * c.y, 0, c.z,
  ]);
}
