import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/rendering.dart' show CustomPainter;

import 'boost_ball_data.dart';
import 'boost_ball_sim.dart';

// A tiny 3D engine for Boost Ball: flat-shaded polygons, sorted back to
// front and drawn with Canvas.drawVertices. x runs across the pitch, y up
// the pitch and z is height.

class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);

  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => sqrt(x * x + y * y + z * z);
  V3 get unit {
    final l = length;
    return l < 1e-9 ? const V3(0, 0, 1) : this * (1 / l);
  }
}

/// What part of a car a face is, so one model can be painted many ways.
enum Part {
  body,
  accent,
  team,
  glass,
  tyre,
  rim,
  dark,
  light,
  tail,
  chrome,
  goat,
  horn,
}

class Face {
  final List<V3> pts;
  final Color colour;
  final Part? part;
  final bool lit;
  const Face(this.pts, this.colour, {this.part, this.lit = true});
}

class Camera {
  final V3 pos, f, r, u;
  final double focal;
  final Offset centre;
  Camera._(this.pos, this.f, this.r, this.u, this.focal, this.centre);

  factory Camera.lookAt(V3 pos, V3 target, double focal, Offset centre) {
    final f = (target - pos).unit;
    var r = f.cross(const V3(0, 0, 1));
    r = r.length < 1e-6 ? const V3(1, 0, 0) : r.unit;
    final u = r.cross(f);
    return Camera._(pos, f, r, u, focal, centre);
  }

  V3 toCam(V3 p) {
    final d = p - pos;
    return V3(d.dot(r), d.dot(u), d.dot(f));
  }

  Offset screen(V3 c) =>
      Offset(centre.dx + c.x / c.z * focal, centre.dy - c.y / c.z * focal);

  /// Where a world point lands on screen, or null if it's behind you.
  Offset? project(V3 world) {
    final c = toCam(world);
    return c.z < 0.3 ? null : screen(c);
  }
}

class _Tri {
  final double depth;
  final Offset a, b, c;
  final int colour;
  _Tri(this.depth, this.a, this.b, this.c, this.colour);
}

class Renderer {
  final Camera cam;
  static const V3 light = V3(0.35, -0.45, 0.82);
  static const near = 0.3;
  final Color fog;
  final List<_Tri> _floor = [];
  final List<_Tri> _tris = [];

  Renderer(this.cam, {this.fog = const Color(0xFF1A2340)});

  /// Adds a flat polygon. Floor polygons are drawn first, in order; the
  /// rest are sorted far to near.
  void add(
    List<V3> world,
    Color colour, {
    bool lit = true,
    bool floor = false,
    double bias = 0,
  }) {
    if (world.length < 3) return;
    var shade = 1.0;
    if (lit) {
      final n = (world[1] - world[0]).cross(world[2] - world[0]).unit;
      shade = 0.5 + 0.5 * n.dot(light).abs();
    }
    // Into camera space, then cut off anything behind the camera.
    var poly = [for (final p in world) cam.toCam(p)];
    if (poly.every((p) => p.z < near)) return;
    if (poly.any((p) => p.z < near)) poly = _clip(poly);
    if (poly.length < 3) return;
    var depth = 0.0;
    for (final p in poly) {
      depth += p.z;
    }
    depth = depth / poly.length + bias;
    final t = ((depth - 60) / 160).clamp(0.0, 0.55);
    final c = Color.lerp(
      Color.fromARGB(
        (colour.a * 255).round(),
        (colour.r * 255 * shade).round().clamp(0, 255),
        (colour.g * 255 * shade).round().clamp(0, 255),
        (colour.b * 255 * shade).round().clamp(0, 255),
      ),
      fog.withValues(alpha: colour.a),
      t,
    )!;
    final argb = c.toARGB32();
    final pts = [for (final p in poly) cam.screen(p)];
    final list = floor ? _floor : _tris;
    for (var i = 1; i < pts.length - 1; i++) {
      list.add(_Tri(depth, pts[0], pts[i], pts[i + 1], argb));
    }
  }

  void addFace(Face f, {Color Function(Part)? paint, bool floor = false}) {
    add(
      f.pts,
      f.part != null && paint != null ? paint(f.part!) : f.colour,
      lit: f.lit,
      floor: floor,
    );
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
    _tris.sort((a, b) => b.depth.compareTo(a.depth));
    _flush(canvas, _tris);
  }

  static void _flush(Canvas canvas, List<_Tri> tris) {
    if (tris.isEmpty) return;
    final pos = Float32List(tris.length * 6);
    final col = Int32List(tris.length * 3);
    for (var i = 0; i < tris.length; i++) {
      final t = tris[i];
      pos[i * 6] = t.a.dx;
      pos[i * 6 + 1] = t.a.dy;
      pos[i * 6 + 2] = t.b.dx;
      pos[i * 6 + 3] = t.b.dy;
      pos[i * 6 + 4] = t.c.dx;
      pos[i * 6 + 5] = t.c.dy;
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
// The stadium.
// ===========================================================================

const Color kBlueTeam3d = Color(0xFF2196F3);
const Color kOrangeTeam3d = Color(0xFFFF7043);

/// The pitch outline (inside the walls), going round anticlockwise.
const List<V3> _outline = [
  V3(kCorner, 0, 0),
  V3(kFieldW / 2 - kGoalW / 2, 0, 0),
  V3(kFieldW / 2 + kGoalW / 2, 0, 0),
  V3(kFieldW - kCorner, 0, 0),
  V3(kFieldW, kCorner, 0),
  V3(kFieldW, kFieldL - kCorner, 0),
  V3(kFieldW - kCorner, kFieldL, 0),
  V3(kFieldW / 2 + kGoalW / 2, kFieldL, 0),
  V3(kFieldW / 2 - kGoalW / 2, kFieldL, 0),
  V3(kCorner, kFieldL, 0),
  V3(0, kFieldL - kCorner, 0),
  V3(0, kCorner, 0),
];

/// Edges 1 and 7 are the goal mouths.
bool _isMouth(int edge) => edge == 1 || edge == 7;

class Stadium {
  final List<Face> floor = [];
  final List<Face> lines = [];
  final List<Face> solid = [];

  static final Stadium instance = Stadium._();

  Stadium._() {
    _buildFloor();
    _buildLines();
    _buildWalls();
    _buildGoals();
    _buildLights();
    _buildRoof();
  }

  /// A see-through roof you can drive along.
  void _buildRoof() {
    const tileX = 12.0, tileY = 14.0;
    for (var j = 0; j < (kFieldL / tileY).ceil(); j++) {
      for (var i = 0; i < (kFieldW / tileX).ceil(); i++) {
        final quad = [
          V3(i * tileX, j * tileY, kCeiling),
          V3((i + 1) * tileX, j * tileY, kCeiling),
          V3((i + 1) * tileX, (j + 1) * tileY, kCeiling),
          V3(i * tileX, (j + 1) * tileY, kCeiling),
        ];
        final poly = _clipToPitch(quad);
        if (poly.length < 3) continue;
        solid.add(
          Face(
            poly,
            (i + j).isEven ? const Color(0x6637474F) : const Color(0x55546E7A),
            lit: false,
          ),
        );
      }
    }
  }

  void _buildFloor() {
    const tileX = 8.0, tileY = 10.0;
    for (var j = 0; j < (kFieldL / tileY).ceil(); j++) {
      for (var i = 0; i < (kFieldW / tileX).ceil(); i++) {
        final quad = [
          V3(i * tileX, j * tileY, 0),
          V3((i + 1) * tileX, j * tileY, 0),
          V3((i + 1) * tileX, (j + 1) * tileY, 0),
          V3(i * tileX, (j + 1) * tileY, 0),
        ];
        final poly = _clipToPitch(quad);
        if (poly.length < 3) continue;
        // Mown stripes, tinted towards each team's end.
        var c = j.isEven ? const Color(0xFF2E7D32) : const Color(0xFF388E3C);
        if (j == 0) c = Color.lerp(c, kBlueTeam3d, 0.25)!;
        if (j == (kFieldL / tileY).ceil() - 1) {
          c = Color.lerp(c, kOrangeTeam3d, 0.25)!;
        }
        floor.add(Face(poly, c, lit: false));
      }
    }
    // The floor inside each goal.
    for (final (y0, c) in [
      (-kGoalDepth, kBlueTeam3d),
      (kFieldL, kOrangeTeam3d),
    ]) {
      floor.add(
        Face(
          [
            V3(kFieldW / 2 - kGoalW / 2, y0, 0),
            V3(kFieldW / 2 + kGoalW / 2, y0, 0),
            V3(kFieldW / 2 + kGoalW / 2, y0 + kGoalDepth, 0),
            V3(kFieldW / 2 - kGoalW / 2, y0 + kGoalDepth, 0),
          ],
          Color.lerp(const Color(0xFF263238), c, 0.35)!,
          lit: false,
        ),
      );
    }
  }

  /// Cuts a floor tile down to the (convex) pitch shape.
  static List<V3> _clipToPitch(List<V3> poly) {
    var out = poly;
    for (var e = 0; e < _outline.length; e++) {
      final a = _outline[e], b = _outline[(e + 1) % _outline.length];
      final n = V3(-(b.y - a.y), b.x - a.x, 0);
      double side(V3 p) => (p - a).dot(n);
      final next = <V3>[];
      for (var i = 0; i < out.length; i++) {
        final p = out[i], q = out[(i + 1) % out.length];
        final sp = side(p), sq = side(q);
        if (sp >= 0) next.add(p);
        if ((sp >= 0) != (sq >= 0)) next.add(p + (q - p) * (sp / (sp - sq)));
      }
      out = next;
      if (out.length < 3) return out;
    }
    return out;
  }

  void _line(V3 a, V3 b, double w) {
    final d = (b - a).unit;
    final s = V3(-d.y, d.x, 0) * (w / 2);
    const up = V3(0, 0, 0.03);
    lines.add(
      Face(
        [a + s + up, b + s + up, b - s + up, a - s + up],
        const Color(0xCCFFFFFF),
        lit: false,
      ),
    );
  }

  void _buildLines() {
    const w = 0.35;
    _line(const V3(0, kFieldL / 2, 0), const V3(kFieldW, kFieldL / 2, 0), w);
    const c = V3(kFieldW / 2, kFieldL / 2, 0);
    for (var i = 0; i < 28; i++) {
      final a = i / 28 * 2 * pi, b = (i + 1) / 28 * 2 * pi;
      _line(c + V3(cos(a), sin(a), 0) * 9, c + V3(cos(b), sin(b), 0) * 9, w);
    }
    for (final (y0, y1) in [(0.0, 14.0), (kFieldL, kFieldL - 14)]) {
      const l = kFieldW / 2 - 16, r = kFieldW / 2 + 16;
      _line(V3(l, y0, 0), V3(l, y1, 0), w);
      _line(V3(r, y0, 0), V3(r, y1, 0), w);
      _line(V3(l, y1, 0), V3(r, y1, 0), w);
    }
  }

  /// Wall profile: the curved ramp, then the straight wall, as
  /// (distance in from the wall, height).
  static List<(double, double)> get _profile => [
    for (var i = 0; i <= 5; i++)
      (
        kRampR - kRampR * sin(i / 5 * pi / 2),
        kRampR - kRampR * cos(i / 5 * pi / 2),
      ),
    (0, kRampR + 2.5),
    // The straight wall, then the curve over into the roof.
    for (var i = 0; i <= 5; i++)
      (
        kTopR - kTopR * cos(i / 5 * pi / 2),
        kCeiling - kTopR + kTopR * sin(i / 5 * pi / 2),
      ),
  ];

  void _buildWalls() {
    final n = _outline.length;
    V3 normal(int e) {
      final a = _outline[e], b = _outline[(e + 1) % n];
      return V3(-(b.y - a.y), b.x - a.x, 0).unit;
    }

    // At each corner, push in along the bisector so the ramps meet up.
    V3 miter(int v) {
      final n1 = normal((v - 1 + n) % n), n2 = normal(v);
      final m = (n1 + n2).unit;
      return m * (1 / m.dot(n1));
    }

    final rnd = Random(7);
    const crowd = [
      Color(0xFF1565C0),
      Color(0xFFE64A19),
      Color(0xFFECEFF1),
      Color(0xFFFFB300),
      Color(0xFF455A64),
      Color(0xFF8E24AA),
      Color(0xFF26A69A),
    ];
    final prof = _profile;
    for (var e = 0; e < n; e++) {
      final a = _outline[e], b = _outline[(e + 1) % n];
      final ma = miter(e), mb = miter((e + 1) % n);
      final len = (b - a).length;
      final segs = max(1, (len / 7).ceil());
      final mouth = _isMouth(e);
      for (var s = 0; s < segs; s++) {
        final t0 = s / segs, t1 = (s + 1) / segs;
        final p0 = a + (b - a) * t0, p1 = a + (b - a) * t1;
        final m0 = ma + (mb - ma) * t0, m1 = mb * t1 + ma * (1 - t1);
        V3 at(V3 p, V3 m, double d, double z) => p + m * d + V3(0, 0, z);
        final mid = (p0 + p1) * 0.5;
        final tint = mid.y < kFieldL / 2 ? kBlueTeam3d : kOrangeTeam3d;
        for (var k = 0; k < prof.length - 1; k++) {
          final (d0, z0) = prof[k];
          final (d1, z1) = prof[k + 1];
          // The goal mouth is open below the crossbar.
          if (mouth && z1 <= kGoalH + 0.01) continue;
          final ramp = k < 5;
          final Color c;
          if (ramp) {
            c = Color.lerp(
              const Color(0xFF37474F),
              tint,
              0.12 + 0.06 * (k % 2),
            )!;
          } else if (k == 5) {
            c = Color.lerp(const Color(0xFF263238), tint, 0.55)!; // boards
          } else if (k == 6) {
            c = Color.lerp(const Color(0x55B3E5FC), tint, 0.1)!; // glass
          } else {
            // The curve into the roof: tinted glass with stripes.
            c = Color.lerp(
              const Color(0x8890A4AE),
              tint,
              0.15 + 0.08 * (k % 2),
            )!;
          }
          final lo = mouth ? max(z0, kGoalH) : z0;
          solid.add(
            Face(
              [
                at(p0, m0, d0, lo),
                at(p1, m1, d0, lo),
                at(p1, m1, d1, z1),
                at(p0, m0, d1, z1),
              ],
              c,
              lit: ramp || k >= 5,
            ),
          );
        }
        // The crowd behind the glass, in rows going up and back.
        for (var row = 0; row < 4; row++) {
          final d0 = -1.0 - row * 7, d1 = d0 - 7;
          final z0 = kRampR + 2.5 + row * 6.0, z1 = z0 + 6;
          solid.add(
            Face(
              [
                at(p0, m0, d0, z0),
                at(p1, m1, d0, z0),
                at(p1, m1, d1, z1),
                at(p0, m0, d1, z1),
              ],
              Color.lerp(
                crowd[rnd.nextInt(crowd.length)],
                const Color(0xFF101828),
                0.35 + rnd.nextDouble() * 0.3,
              )!,
            ),
          );
        }
      }
    }
  }

  void _box(
    List<Face> into,
    double x0,
    double x1,
    double y0,
    double y1,
    double z0,
    double z1,
    Color c, {
    bool lit = true,
  }) {
    final v = [
      V3(x0, y0, z0),
      V3(x1, y0, z0),
      V3(x1, y1, z0),
      V3(x0, y1, z0),
      V3(x0, y0, z1),
      V3(x1, y0, z1),
      V3(x1, y1, z1),
      V3(x0, y1, z1),
    ];
    for (final f in const [
      [4, 5, 6, 7],
      [0, 1, 5, 4],
      [1, 2, 6, 5],
      [2, 3, 7, 6],
      [3, 0, 4, 7],
    ]) {
      into.add(Face([for (final i in f) v[i]], c, lit: lit));
    }
  }

  void _buildGoals() {
    const l = kFieldW / 2 - kGoalW / 2, r = kFieldW / 2 + kGoalW / 2;
    for (final (y, back, c) in [
      (0.0, -kGoalDepth, kBlueTeam3d),
      (kFieldL, kFieldL + kGoalDepth, kOrangeTeam3d),
    ]) {
      final post = Color.lerp(c, const Color(0xFFFFFFFF), 0.45)!;
      const t = 0.5;
      _box(solid, l - t, l, y - t / 2, y + t / 2, 0, kGoalH, post);
      _box(solid, r, r + t, y - t / 2, y + t / 2, 0, kGoalH, post);
      _box(solid, l - t, r + t, y - t / 2, y + t / 2, kGoalH, kGoalH + t, post);
      // The net: see-through sides, back and roof.
      final net = c.withValues(alpha: 0.28);
      solid.add(
        Face(
          [
            V3(l, back, 0),
            V3(r, back, 0),
            V3(r, back, kGoalH),
            V3(l, back, kGoalH),
          ],
          net,
          lit: false,
        ),
      );
      solid.add(
        Face(
          [V3(l, y, 0), V3(l, back, 0), V3(l, back, kGoalH), V3(l, y, kGoalH)],
          net,
          lit: false,
        ),
      );
      solid.add(
        Face(
          [V3(r, y, 0), V3(r, back, 0), V3(r, back, kGoalH), V3(r, y, kGoalH)],
          net,
          lit: false,
        ),
      );
      solid.add(
        Face(
          [
            V3(l, y, kGoalH),
            V3(r, y, kGoalH),
            V3(r, back, kGoalH),
            V3(l, back, kGoalH),
          ],
          net,
          lit: false,
        ),
      );
      // A glowing strip along the goal line.
      lines.add(
        Face(
          [
            V3(l, y - 0.3, 0.04),
            V3(r, y - 0.3, 0.04),
            V3(r, y + 0.3, 0.04),
            V3(l, y + 0.3, 0.04),
          ],
          c,
          lit: false,
        ),
      );
    }
  }

  void _buildLights() {
    // Floodlight towers in the four corners.
    for (final (x, y) in [
      (-34.0, -34.0),
      (kFieldW + 34, -34.0),
      (-34.0, kFieldL + 34),
      (kFieldW + 34, kFieldL + 34),
    ]) {
      _box(
        solid,
        x - 0.8,
        x + 0.8,
        y - 0.8,
        y + 0.8,
        0,
        kWallH + 26,
        const Color(0xFF546E7A),
      );
      final toward = V3(kFieldW / 2 - x, kFieldL / 2 - y, 0).unit;
      final side = V3(-toward.y, toward.x, 0);
      final c = V3(x, y, kWallH + 28) + toward * 0.9;
      solid.add(
        Face(
          [
            c + side * 5,
            c - side * 5,
            c - side * 5 + const V3(0, 0, 5),
            c + side * 5 + const V3(0, 0, 5),
          ],
          const Color(0xFFFFFDE7),
          lit: false,
        ),
      );
    }
  }
}

// ===========================================================================
// Cars and the ball.
// ===========================================================================

/// Builds a car model in its own space: x forward, y left, z up, with the
/// bottom of the tyres at z = 0.
class CarModel {
  final List<Face> faces = [];
  final V3 exhaust;

  static final Map<CarBody, CarModel> _cache = {};
  static CarModel of(CarBody body) =>
      _cache.putIfAbsent(body, () => CarModel._(body));

  CarModel._(CarBody body) : exhaust = _exhaustOf(body) {
    switch (body) {
      case CarBody.sport:
        _wheels(1.45, 1.12, 0.47, 0.42);
        _prism(
          const [
            (-2.2, 0.35),
            (2.15, 0.35),
            (2.35, 0.7),
            (2.05, 1.0),
            (-2.1, 1.08),
            (-2.35, 0.75),
          ],
          1.15,
          1.1,
          0.35,
          1.08,
          (i) => i == 0 ? Part.dark : Part.body,
        );
        _prism(
          const [(-1.45, 1.05), (0.95, 1.0), (0.15, 1.62), (-1.15, 1.62)],
          0.98,
          0.78,
          1.0,
          1.62,
          (i) => i == 2 ? Part.body : (i == 0 ? Part.body : Part.glass),
          sides: Part.glass,
        );
        // Spoiler on two struts.
        _box(-2.35, -1.95, -1.15, 1.15, 1.32, 1.42, Part.accent);
        _box(-2.2, -2.05, -0.75, -0.6, 1.05, 1.32, Part.dark);
        _box(-2.2, -2.05, 0.6, 0.75, 1.05, 1.32, Part.dark);
        // Twin racing stripes over the bonnet and roof.
        for (final y in [-0.3, 0.3]) {
          _strip(
            const [(2.05, 1.0), (0.95, 1.005)],
            y,
            0.16,
            Part.accent,
            0.012,
          );
          _strip(
            const [(0.15, 1.62), (-1.15, 1.62)],
            y,
            0.16,
            Part.accent,
            0.012,
          );
        }
        _sideStripe(-1.9, 1.9, 0.62, 0.78, 1.15, 1.11);
        _lights(2.3, 0.75, 0.82, 0.7, -2.33);
      case CarBody.hornet:
        _wheels(1.5, 1.02, 0.42, 0.36);
        _prism(
          const [
            (-2.2, 0.3),
            (2.6, 0.3),
            (2.65, 0.5),
            (0.0, 1.0),
            (-2.2, 1.05),
          ],
          1.05,
          1.0,
          0.3,
          1.05,
          (i) => i == 0 ? Part.dark : Part.body,
        );
        _prism(
          const [(-1.5, 0.98), (0.4, 0.85), (-0.3, 1.38), (-1.2, 1.42)],
          0.7,
          0.5,
          0.85,
          1.42,
          (i) => i == 0 ? Part.body : Part.glass,
          sides: Part.glass,
        );
        // Wasp stripes.
        for (final x in [-1.95, -1.75]) {
          _strip([(x, 1.05), (x - 0.15, 1.05)], 0, 2.05, Part.accent, 0.012);
        }
        _strip(const [(2.4, 0.55), (0.6, 0.9)], 0, 0.5, Part.accent, 0.012);
        // Fins.
        _box(-2.2, -1.6, 0.85, 0.95, 1.05, 1.55, Part.accent);
        _box(-2.2, -1.6, -0.95, -0.85, 1.05, 1.55, Part.accent);
        _lights(2.55, 0.6, 0.45, 0.55, -2.18);
      case CarBody.truck:
        _wheels(1.6, 1.22, 0.62, 0.5);
        _prism(
          const [(-2.5, 0.5), (2.5, 0.5), (2.6, 1.3), (-2.5, 1.3)],
          1.25,
          1.25,
          0.5,
          1.3,
          (i) => i == 0 ? Part.dark : Part.body,
        );
        _prism(
          const [(0.35, 1.3), (2.2, 1.3), (1.85, 2.35), (0.55, 2.35)],
          1.15,
          1.1,
          1.3,
          2.35,
          (i) => i == 1 ? Part.glass : Part.body,
          sides: Part.glass,
        );
        // Truck bed and roll bar.
        _box(-2.4, 0.2, -1.1, 1.1, 1.3, 1.32, Part.dark);
        _box(-0.1, 0.1, -1.15, 1.15, 1.3, 2.2, Part.chrome);
        _box(-0.1, 0.1, -1.15, 1.15, 2.1, 2.2, Part.chrome);
        // Bull bar.
        _box(2.6, 2.85, -1.2, 1.2, 0.55, 1.35, Part.chrome);
        _sideStripe(-2.3, 2.3, 0.75, 1.0, 1.25, 1.25);
        _lights(2.62, 0.85, 1.05, 0.9, -2.52);
      case CarBody.goatKart:
        _wheels(1.3, 1.02, 0.4, 0.38);
        _prism(
          const [
            (-1.9, 0.25),
            (1.9, 0.25),
            (2.15, 0.5),
            (1.6, 0.6),
            (-1.9, 0.62),
          ],
          0.85,
          0.85,
          0.25,
          0.62,
          (i) => i == 0 ? Part.dark : Part.body,
        );
        _box(-1.3, -1.0, -0.55, 0.55, 0.6, 1.4, Part.accent); // seat back
        _box(-1.0, 0.0, -0.45, 0.45, 0.6, 1.3, Part.goat); // goat body
        _box(0.0, 0.7, -0.32, 0.32, 1.25, 1.85, Part.goat); // head
        _box(0.7, 0.9, -0.2, 0.2, 1.3, 1.55, Part.goat); // snout
        _box(0.72, 0.74, 0.1, 0.24, 1.6, 1.72, Part.dark); // eyes
        _box(0.72, 0.74, -0.24, -0.1, 1.6, 1.72, Part.dark);
        _box(-0.1, 0.1, 0.18, 0.32, 1.85, 2.35, Part.horn); // horns
        _box(-0.1, 0.1, -0.32, -0.18, 1.85, 2.35, Part.horn);
        _box(0.75, 0.85, -0.55, 0.55, 0.9, 1.0, Part.dark); // steering wheel
        _box(-1.9, -1.6, -0.6, 0.6, 0.62, 1.0, Part.accent); // rear wing
        _lights(2.1, 0.5, 0.42, 0.5, -1.88);
      case CarBody.hatchback:
        _everyday(
          wheelX: 1.3,
          wheelY: 1.0,
          wheelR: 0.42,
          body: const [
            (-1.95, 0.35),
            (1.95, 0.35),
            (2.05, 0.75),
            (1.3, 0.95),
            (-1.95, 1.0),
          ],
          bodyW: 1.0,
          bodyLo: 0.35,
          bodyHi: 1.0,
          cabin: const [(-1.95, 0.95), (1.0, 0.95), (0.2, 1.68), (-1.75, 1.68)],
          cabinW: 0.94,
          roof: 1.68,
          front: 2.05,
          back: -1.95,
        );
      case CarBody.saloon:
        _everyday(
          wheelX: 1.55,
          wheelY: 1.05,
          wheelR: 0.44,
          body: const [
            (-2.4, 0.35),
            (2.3, 0.35),
            (2.42, 0.72),
            (1.3, 0.96),
            (-2.4, 1.0),
          ],
          bodyW: 1.05,
          bodyLo: 0.35,
          bodyHi: 1.0,
          cabin: const [(-1.35, 0.95), (1.0, 0.95), (0.2, 1.6), (-0.85, 1.6)],
          cabinW: 0.98,
          roof: 1.6,
          front: 2.42,
          back: -2.4,
        );
      case CarBody.estate:
        _everyday(
          wheelX: 1.55,
          wheelY: 1.05,
          wheelR: 0.44,
          body: const [
            (-2.4, 0.35),
            (2.3, 0.35),
            (2.42, 0.72),
            (1.3, 0.96),
            (-2.4, 1.0),
          ],
          bodyW: 1.05,
          bodyLo: 0.35,
          bodyHi: 1.0,
          cabin: const [(-2.38, 0.95), (1.0, 0.95), (0.2, 1.62), (-2.3, 1.62)],
          cabinW: 0.98,
          roof: 1.62,
          front: 2.42,
          back: -2.4,
        );
        // Roof bars.
        for (final y in [-0.65, 0.65]) {
          _box(-1.9, 0.0, y - 0.06, y + 0.06, 1.62, 1.72, Part.chrome);
        }
      case CarBody.suv:
        _everyday(
          wheelX: 1.5,
          wheelY: 1.15,
          wheelR: 0.55,
          body: const [
            (-2.3, 0.5),
            (2.3, 0.5),
            (2.4, 1.0),
            (1.6, 1.3),
            (-2.3, 1.32),
          ],
          bodyW: 1.2,
          bodyLo: 0.5,
          bodyHi: 1.32,
          cabin: const [(-2.25, 1.27), (1.25, 1.27), (0.7, 2.12), (-2.2, 2.12)],
          cabinW: 1.12,
          roof: 2.12,
          front: 2.4,
          back: -2.3,
        );
        for (final y in [-0.8, 0.8]) {
          _box(-2.0, 0.4, y - 0.06, y + 0.06, 2.12, 2.24, Part.chrome);
        }
        _box(-2.45, -2.3, -0.45, 0.45, 0.8, 1.6, Part.tyre); // spare wheel
      case CarBody.van:
        _everyday(
          wheelX: 1.65,
          wheelY: 1.1,
          wheelR: 0.46,
          body: const [
            (-2.55, 0.4),
            (2.35, 0.4),
            (2.5, 0.85),
            (1.9, 1.15),
            (-2.55, 1.15),
          ],
          bodyW: 1.15,
          bodyLo: 0.4,
          bodyHi: 1.15,
          cabin: const [(-2.55, 1.1), (1.9, 1.1), (1.3, 2.4), (-2.55, 2.45)],
          cabinW: 1.12,
          roof: 2.45,
          front: 2.5,
          back: -2.55,
          cabinSides: Part.body,
        );
        // Windows by the driver; the back is all van.
        for (final y in [1.09, -1.09]) {
          faces.add(
            Face(
              [
                V3(0.6, y, 1.35),
                V3(1.65, y, 1.35),
                V3(1.3, y, 2.05),
                V3(0.6, y, 2.05),
              ],
              const Color(0xFF000000),
              part: Part.glass,
            ),
          );
        }
      case CarBody.monster:
        _wheels(1.45, 1.35, 1.0, 0.75);
        _box(-1.2, 1.2, -0.15, 0.15, 0.9, 1.25, Part.chrome); // axles
        _prism(
          const [
            (-2.1, 1.2),
            (2.15, 1.2),
            (2.25, 1.65),
            (2.0, 1.75),
            (-2.2, 1.78),
          ],
          1.05,
          1.02,
          1.2,
          1.78,
          (i) => i == 0 ? Part.dark : Part.body,
        );
        _prism(
          const [(-1.1, 1.75), (0.9, 1.75), (0.35, 2.45), (-0.85, 2.45)],
          0.95,
          0.8,
          1.75,
          2.45,
          (i) => i == 2 || i == 0 ? Part.body : Part.glass,
          sides: Part.glass,
        );
        // Flames painted down each side.
        for (final s in [1.0, -1.0]) {
          final y = s * 1.06;
          faces.add(
            Face(
              [
                V3(2.1, y, 1.3),
                V3(0.8, y, 1.35),
                V3(1.2, y, 1.48),
                V3(0.2, y, 1.52),
                V3(0.9, y, 1.65),
                V3(2.1, y, 1.7),
              ],
              const Color(0xFFFFC107),
              part: Part.accent,
            ),
          );
        }
        _box(
          -0.6,
          0.6,
          -0.9,
          0.9,
          2.45,
          2.6,
          Part.light,
          lit: false,
        ); // roof lights
        _lights(2.22, 0.75, 1.45, 0.75, -2.18);
    }
  }

  static V3 _exhaustOf(CarBody b) => switch (b) {
    CarBody.sport => const V3(-2.4, 0, 0.6),
    CarBody.hornet => const V3(-2.25, 0, 0.6),
    CarBody.truck => const V3(-2.55, 0, 0.8),
    CarBody.goatKart => const V3(-1.95, 0, 0.45),
    CarBody.monster => const V3(-2.25, 0, 1.45),
    CarBody.hatchback => const V3(-2.0, 0.5, 0.5),
    CarBody.saloon => const V3(-2.45, 0.5, 0.5),
    CarBody.estate => const V3(-2.45, 0.5, 0.5),
    CarBody.suv => const V3(-2.35, 0.6, 0.65),
    CarBody.van => const V3(-2.55, 0.6, 0.55),
  };

  /// An everyday car: a body, a cabin on top with windows, lights and a
  /// coloured stripe down each side.
  void _everyday({
    required double wheelX,
    required double wheelY,
    required double wheelR,
    required List<(double, double)> body,
    required double bodyW,
    required double bodyLo,
    required double bodyHi,
    required List<(double, double)> cabin,
    required double cabinW,
    required double roof,
    required double front,
    required double back,
    Part cabinSides = Part.glass,
  }) {
    _wheels(wheelX, wheelY, wheelR, wheelR * 0.8);
    _prism(
      body,
      bodyW,
      bodyW * 0.95,
      bodyLo,
      bodyHi,
      (i) => i == 0 ? Part.dark : Part.body,
    );
    // Cabin edges: 0 bottom, 1 windscreen, 2 roof, 3 back window.
    _prism(
      cabin,
      cabinW,
      cabinW * 0.88,
      bodyHi - 0.05,
      roof,
      (i) => i == 1 || i == 3 ? Part.glass : Part.body,
      sides: cabinSides,
    );
    _sideStripe(
      back + 0.3,
      front - 0.3,
      bodyLo + 0.25,
      bodyLo + 0.38,
      bodyW,
      bodyW,
    );
    _lights(front, bodyW * 0.7, bodyHi - 0.2, bodyHi - 0.2, back);
    // Bumpers and number plates.
    _box(
      front - 0.05,
      front + 0.12,
      -bodyW,
      bodyW,
      bodyLo,
      bodyLo + 0.22,
      Part.dark,
    );
    _box(
      back - 0.12,
      back + 0.05,
      -bodyW,
      bodyW,
      bodyLo,
      bodyLo + 0.22,
      Part.dark,
    );
    _box(
      front + 0.1,
      front + 0.13,
      -0.3,
      0.3,
      bodyLo + 0.25,
      bodyLo + 0.42,
      Part.light,
    );
  }

  /// Extrudes a side profile (x, z) across the car. The width shrinks from
  /// [w0] at height [z0] to [w1] at [z1], like a real car body.
  void _prism(
    List<(double, double)> profile,
    double w0,
    double w1,
    double z0,
    double z1,
    Part Function(int edge) part, {
    Part? sides,
  }) {
    double w(double z) => w0 + (w1 - w0) * ((z - z0) / (z1 - z0)).clamp(0, 1);
    final left = [for (final (x, z) in profile) V3(x, w(z), z)];
    final right = [for (final (x, z) in profile) V3(x, -w(z), z)];
    faces.add(Face(left, const Color(0xFF000000), part: sides ?? Part.body));
    faces.add(
      Face(
        right.reversed.toList(),
        const Color(0xFF000000),
        part: sides ?? Part.body,
      ),
    );
    for (var i = 0; i < profile.length; i++) {
      final j = (i + 1) % profile.length;
      faces.add(
        Face(
          [left[i], left[j], right[j], right[i]],
          const Color(0xFF000000),
          part: part(i),
        ),
      );
    }
  }

  void _box(
    double x0,
    double x1,
    double y0,
    double y1,
    double z0,
    double z1,
    Part part, {
    bool lit = true,
  }) {
    final v = [
      V3(x0, y0, z0),
      V3(x1, y0, z0),
      V3(x1, y1, z0),
      V3(x0, y1, z0),
      V3(x0, y0, z1),
      V3(x1, y0, z1),
      V3(x1, y1, z1),
      V3(x0, y1, z1),
    ];
    for (final f in const [
      [4, 5, 6, 7],
      [0, 1, 5, 4],
      [1, 2, 6, 5],
      [2, 3, 7, 6],
      [3, 0, 4, 7],
      [0, 3, 2, 1],
    ]) {
      faces.add(
        Face(
          [for (final i in f) v[i]],
          const Color(0xFF000000),
          part: part,
          lit: lit,
        ),
      );
    }
  }

  /// A painted strip lying just on top of a surface.
  void _strip(
    List<(double, double)> path,
    double y,
    double width,
    Part part,
    double lift,
  ) {
    final (xa, za) = path.first;
    final (xb, zb) = path.last;
    faces.add(
      Face(
        [
          V3(xa, y - width / 2, za + lift),
          V3(xb, y - width / 2, zb + lift),
          V3(xb, y + width / 2, zb + lift),
          V3(xa, y + width / 2, za + lift),
        ],
        const Color(0xFF000000),
        part: part,
      ),
    );
  }

  /// A stripe in the team's colour down each side.
  void _sideStripe(
    double x0,
    double x1,
    double z0,
    double z1,
    double w0,
    double w1,
  ) {
    for (final s in [1.0, -1.0]) {
      final y = s * (w0 + 0.015);
      faces.add(
        Face(
          [V3(x0, y, z0), V3(x1, y, z0), V3(x1, y, z1), V3(x0, y, z1)],
          const Color(0xFF000000),
          part: Part.team,
        ),
      );
    }
  }

  void _lights(double front, double y, double z, double tailZ, double back) {
    for (final s in [1.0, -1.0]) {
      faces.add(
        Face(
          [
            V3(front + 0.02, s * y - 0.2, z - 0.1),
            V3(front + 0.02, s * y + 0.2, z - 0.1),
            V3(front + 0.02, s * y + 0.2, z + 0.1),
            V3(front + 0.02, s * y - 0.2, z + 0.1),
          ],
          const Color(0xFF000000),
          part: Part.light,
          lit: false,
        ),
      );
      faces.add(
        Face(
          [
            V3(back - 0.02, s * y - 0.25, tailZ - 0.08),
            V3(back - 0.02, s * y + 0.25, tailZ - 0.08),
            V3(back - 0.02, s * y + 0.25, tailZ + 0.08),
            V3(back - 0.02, s * y - 0.25, tailZ + 0.08),
          ],
          const Color(0xFF000000),
          part: Part.tail,
          lit: false,
        ),
      );
    }
  }

  void _wheels(double x, double y, double r, double w) {
    for (final sx in [x, -x]) {
      for (final sy in [y, -y]) {
        final inner = sy > 0 ? sy - w / 2 : sy + w / 2;
        final outer = sy > 0 ? sy + w / 2 : sy - w / 2;
        const n = 10;
        final ring = [
          for (var i = 0; i < n; i++)
            (sx + cos(i / n * 2 * pi) * r, r + sin(i / n * 2 * pi) * r),
        ];
        for (var i = 0; i < n; i++) {
          final (ax, az) = ring[i];
          final (bx, bz) = ring[(i + 1) % n];
          faces.add(
            Face(
              [
                V3(ax, inner, az),
                V3(bx, inner, bz),
                V3(bx, outer, bz),
                V3(ax, outer, az),
              ],
              const Color(0xFF000000),
              part: Part.tyre,
            ),
          );
        }
        faces.add(
          Face(
            [for (final (px, pz) in ring) V3(px, outer, pz)],
            const Color(0xFF000000),
            part: Part.tyre,
          ),
        );
        // Shiny hub.
        faces.add(
          Face(
            [
              for (final (px, pz) in ring)
                V3(
                  sx + (px - sx) * 0.55,
                  outer + (sy > 0 ? 0.02 : -0.02),
                  r + (pz - r) * 0.55,
                ),
            ],
            const Color(0xFF000000),
            part: Part.rim,
          ),
        );
      }
    }
  }
}

/// Colours for each part of a car.
Color Function(Part) carPaint(Color body, Color team, {Color? accent}) {
  final acc = accent ?? _accentFor(body);
  return (p) => switch (p) {
    Part.body => body,
    Part.accent => acc,
    Part.team => team,
    Part.glass => const Color(0xFF263D57),
    Part.tyre => const Color(0xFF1C1C1C),
    Part.rim => const Color(0xFFB0BEC5),
    Part.dark => const Color(0xFF212121),
    Part.light => const Color(0xFFFFF9C4),
    Part.tail => const Color(0xFFFF1744),
    Part.chrome => const Color(0xFFCFD8DC),
    Part.goat => const Color(0xFFF5F5F5),
    Part.horn => const Color(0xFF8D6E63),
  };
}

Color _accentFor(Color body) {
  final l = body.computeLuminance();
  if (l > 0.6) return const Color(0xFF212121);
  if (l < 0.05) return const Color(0xFFFFD600);
  return const Color(0xFFFFFFFF);
}

/// How a car sits in the world: where it is and which way its nose, left
/// side and roof point.
class Pose {
  final V3 pos, fwd, left, up;
  const Pose(this.pos, this.fwd, this.left, this.up);

  V3 apply(V3 p) => pos + fwd * p.x + left * p.y + up * p.z;

  factory Pose.ofCar(Car c) {
    final up = V3(c.upX, c.upY, c.upZ).unit;
    var f = V3(c.fx, c.fy, c.fz);
    f = (f - up * f.dot(up)).unit;
    var left = up.cross(f).unit;
    var u = up;
    if (c.flipT > 0) {
      // Spin nose over tail during a flip.
      final a = (0.5 - c.flipT) / 0.5 * 2 * pi;
      final f2 = f * cos(a) - u * sin(a);
      u = (u * cos(a) + f * sin(a)).unit;
      f = f2.unit;
      left = u.cross(f).unit;
    }
    return Pose(V3(c.x, c.y, c.z), f, left, u);
  }
}

void drawCar(
  Renderer r,
  CarModel model,
  Pose pose,
  Color Function(Part) paint, {
  bool boosting = false,
  Random? rnd,
}) {
  for (final f in model.faces) {
    r.add([for (final p in f.pts) pose.apply(p)], paint(f.part!), lit: f.lit);
  }
  if (boosting) {
    // A flickering cone of fire out of the exhaust.
    final rng = rnd ?? Random();
    final len = 1.4 + rng.nextDouble() * 1.2;
    final base = model.exhaust;
    final tip = base + V3(-len, 0, 0);
    const n = 6;
    for (var i = 0; i < n; i++) {
      final a = i / n * 2 * pi, b = (i + 1) / n * 2 * pi;
      final pa = base + V3(0, cos(a) * 0.38, sin(a) * 0.38);
      final pb = base + V3(0, cos(b) * 0.38, sin(b) * 0.38);
      r.add(
        [pose.apply(pa), pose.apply(pb), pose.apply(tip)],
        i.isEven ? const Color(0xFFFF6D00) : const Color(0xFFFFC400),
        lit: false,
      );
    }
  }
}

/// A football made of a subdivided icosahedron, with dark patches.
class BallModel {
  final List<List<V3>> tris = [];
  final List<bool> dark = [];

  static final BallModel instance = BallModel._();

  BallModel._() {
    final t = (1 + sqrt(5)) / 2;
    final verts = [
      for (final v in [
        V3(-1, t, 0),
        V3(1, t, 0),
        V3(-1, -t, 0),
        V3(1, -t, 0),
        V3(0, -1, t),
        V3(0, 1, t),
        V3(0, -1, -t),
        V3(0, 1, -t),
        V3(t, 0, -1),
        V3(t, 0, 1),
        V3(-t, 0, -1),
        V3(-t, 0, 1),
      ])
        v.unit,
    ];
    const faces = [
      [0, 11, 5],
      [0, 5, 1],
      [0, 1, 7],
      [0, 7, 10],
      [0, 10, 11],
      [1, 5, 9],
      [5, 11, 4],
      [11, 10, 2],
      [10, 7, 6],
      [7, 1, 8],
      [3, 9, 4],
      [3, 4, 2],
      [3, 2, 6],
      [3, 6, 8],
      [3, 8, 9],
      [4, 9, 5],
      [2, 4, 11],
      [6, 2, 10],
      [8, 6, 7],
      [9, 8, 1],
    ];
    var list = [
      for (final f in faces) [verts[f[0]], verts[f[1]], verts[f[2]]],
    ];
    for (var s = 0; s < 2; s++) {
      final next = <List<V3>>[];
      for (final f in list) {
        final ab = (f[0] + f[1]).unit,
            bc = (f[1] + f[2]).unit,
            ca = (f[2] + f[0]).unit;
        next
          ..add([f[0], ab, ca])
          ..add([f[1], bc, ab])
          ..add([f[2], ca, bc])
          ..add([ab, bc, ca]);
      }
      list = next;
    }
    for (final f in list) {
      tris.add(f);
      final c = (f[0] + f[1] + f[2]).unit;
      dark.add(verts.any((v) => v.dot(c) > 0.94));
    }
  }
}

/// A 3x3 rotation, kept as rows.
class Rot {
  final List<double> m;
  Rot([List<double>? m]) : m = m ?? [1, 0, 0, 0, 1, 0, 0, 0, 1];

  V3 apply(V3 v) => V3(
    m[0] * v.x + m[1] * v.y + m[2] * v.z,
    m[3] * v.x + m[4] * v.y + m[5] * v.z,
    m[6] * v.x + m[7] * v.y + m[8] * v.z,
  );

  /// Turns this rotation by [angle] round [axis] (in world space).
  Rot turned(V3 axis, double angle) {
    final a = axis.unit;
    final c = cos(angle), s = sin(angle), t = 1 - c;
    final r = [
      t * a.x * a.x + c,
      t * a.x * a.y - s * a.z,
      t * a.x * a.z + s * a.y,
      t * a.x * a.y + s * a.z,
      t * a.y * a.y + c,
      t * a.y * a.z - s * a.x,
      t * a.x * a.z - s * a.y,
      t * a.y * a.z + s * a.x,
      t * a.z * a.z + c,
    ];
    final out = List<double>.filled(9, 0);
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        var sum = 0.0;
        for (var k = 0; k < 3; k++) {
          sum += r[i * 3 + k] * m[k * 3 + j];
        }
        out[i * 3 + j] = sum;
      }
    }
    return Rot(out);
  }
}

void drawBall(Renderer r, Ball b, Rot spin) {
  final model = BallModel.instance;
  final centre = V3(b.x, b.y, b.z);
  for (var i = 0; i < model.tris.length; i++) {
    final t = model.tris[i];
    r.add([
      for (final p in t) centre + spin.apply(p) * kBallR,
    ], model.dark[i] ? const Color(0xFF37474F) : const Color(0xFFF5F5F5));
  }
}

/// A soft dark blob on the ground under something.
void drawShadow(Renderer r, double x, double y, double radius, double height) {
  final k = (1 - height / 25).clamp(0.3, 1.0);
  const n = 10;
  final gz = BoostBallMatch.floorHeight(x, y) + 0.05;
  r.add(
    [
      for (var i = 0; i < n; i++)
        V3(
          x + cos(i / n * 2 * pi) * radius * k,
          y + sin(i / n * 2 * pi) * radius * k,
          gz,
        ),
    ],
    Color.fromARGB((90 * k).round(), 0, 0, 0),
    lit: false,
    floor: gz < 0.1,
  );
}

/// A car on a little stand, for the garage. [angle] turns the camera
/// round it.
class CarShowcase extends CustomPainter {
  final CarBody body;
  final Color colour;
  final double angle;
  final Color team;

  CarShowcase(
    this.body,
    this.colour, {
    this.angle = 0.7,
    this.team = kBlueTeam3d,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final focal = min(size.width * 0.95, size.height * 1.5);
    final cam = Camera.lookAt(
      V3(cos(angle) * 8, sin(angle) * 8, 3.4),
      const V3(0, 0, 0.9),
      focal,
      Offset(size.width / 2, size.height * 0.52),
    );
    final r = Renderer(cam);
    const n = 24;
    r.add(
      [
        for (var i = 0; i < n; i++)
          V3(cos(i / n * 2 * pi) * 3.4, sin(i / n * 2 * pi) * 3.4, 0),
      ],
      const Color(0x55000000),
      lit: false,
      floor: true,
    );
    drawCar(
      r,
      CarModel.of(body),
      const Pose(V3(0, 0, 0), V3(1, 0, 0), V3(0, 1, 0), V3(0, 0, 1)),
      carPaint(colour, team),
    );
    r.draw(canvas);
  }

  @override
  bool shouldRepaint(covariant CarShowcase old) =>
      old.body != body || old.colour != colour || old.angle != angle;
}
