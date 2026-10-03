part of 'fly_or_crash_screen.dart';

// ===========================================================================
// The big zoomable world map on the "where are we flying?" screen.
// Blue sea, green land, continents in big bold letters. Zoom in to see
// countries and cities. Tap a city, or anywhere on land, to fly there.
// ===========================================================================

const Color _mapSea = Color(0xFF3F97DB);
const Color _mapSeaDeep = Color(0xFF2F7FC4);
const Color _mapLand = Color(0xFF5DBB63);
const Color _mapBorder = Color(0xFF2E7A35);

class _ParsedCountry {
  final _CountryShape shape;
  final Path path; // in map degrees: x = lon + 180, y = 90 - lat
  final List<List<Offset>> rings;

  _ParsedCountry(this.shape, this.path, this.rings);
}

List<_ParsedCountry>? _parsedCountriesCache;

List<_ParsedCountry> get _parsedCountries {
  final cached = _parsedCountriesCache;
  if (cached != null) return cached;
  final list = <_ParsedCountry>[];
  for (final c in _countryShapes) {
    final path = Path();
    final rings = <List<Offset>>[];
    for (final ring in c.rings.split('|')) {
      final nums = ring.split(',');
      final pts = <Offset>[];
      for (var i = 0; i + 1 < nums.length; i += 2) {
        final lon = int.parse(nums[i]) / 10.0;
        final lat = int.parse(nums[i + 1]) / 10.0;
        pts.add(Offset(lon + 180, 90 - lat));
      }
      if (pts.length < 3) continue;
      rings.add(pts);
      path.addPolygon(pts, true);
    }
    list.add(_ParsedCountry(c, path, rings));
  }
  _parsedCountriesCache = list;
  return list;
}

bool _pointInRing(Offset p, List<Offset> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i];
    final b = ring[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// Which country is at this spot (in map degrees), or null for the sea.
String? _countryAt(Offset deg) {
  for (final c in _parsedCountries) {
    for (final ring in c.rings) {
      if (_pointInRing(deg, ring)) return c.shape.name;
    }
  }
  return null;
}

class _Continent {
  final String name;
  final double lon;
  final double lat;
  const _Continent(this.name, this.lon, this.lat);
}

const List<_Continent> _continents = [
  _Continent('NORTH AMERICA', -102, 47),
  _Continent('SOUTH AMERICA', -60, -14),
  _Continent('EUROPE', 18, 54),
  _Continent('AFRICA', 20, 6),
  _Continent('ASIA', 92, 52),
  _Continent('AUSTRALIA', 134, -25),
  _Continent('ANTARCTICA', 20, -80),
];

class _WorldMap extends StatefulWidget {
  final Destination? selected;
  final ValueChanged<Destination> onPick;
  final VoidCallback onSea;

  const _WorldMap({
    required this.selected,
    required this.onPick,
    required this.onSea,
  });

  @override
  State<_WorldMap> createState() => _WorldMapState();
}

class _WorldMapState extends State<_WorldMap> {
  static const double _minScale = 1.0;
  static const double _maxScale = 14.0;

  final TransformationController _controller = TransformationController();
  Size _viewport = Size.zero;
  Size _mapSize = Size.zero;
  bool _placed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onZoom);
  }

  @override
  void dispose() {
    _controller.removeListener(_onZoom);
    _controller.dispose();
    super.dispose();
  }

  void _onZoom() => setState(() {});

  double get _scale => _controller.value.getMaxScaleOnAxis();

  void _setView(double scale, double tx, double ty) {
    final s = scale.clamp(_minScale, _maxScale).toDouble();
    final minX = _viewport.width - _mapSize.width * s;
    final minY = _viewport.height - _mapSize.height * s;
    final x = tx.clamp(math.min(minX, 0.0), 0.0).toDouble();
    final y = ty.clamp(math.min(minY, 0.0), 0.0).toDouble();
    _controller.value = Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s)
      ..setEntry(0, 3, x)
      ..setEntry(1, 3, y);
  }

  /// Zoom in or out around the middle of the map box.
  void _zoomBy(double factor) {
    final s = _scale;
    final t = _controller.value.getTranslation();
    final cx = _viewport.width / 2;
    final cy = _viewport.height / 2;
    final sceneX = (cx - t.x) / s;
    final sceneY = (cy - t.y) / s;
    final s2 = (s * factor).clamp(_minScale, _maxScale).toDouble();
    _setView(s2, cx - sceneX * s2, cy - sceneY * s2);
  }

  Offset _toDeg(Offset local) => Offset(
        local.dx / _mapSize.width * 360,
        local.dy / _mapSize.height * 180,
      );

  Offset _cityPx(Destination d) => Offset(
        (d.lon + 180) / 360 * _mapSize.width,
        (90 - d.lat) / 180 * _mapSize.height,
      );

  void _onTap(Offset local) {
    final s = _scale;
    // A city close to the tap?
    Destination? best;
    var bestDist = 22.0 / s;
    for (final d in [_home, ..._destinations]) {
      final dist = (_cityPx(d) - local).distance;
      if (dist < bestDist) {
        bestDist = dist;
        best = d;
      }
    }
    if (best != null) {
      if (!identical(best, _home)) widget.onPick(best);
      return;
    }
    // Otherwise, drop a pin wherever they tapped (if it's land).
    final deg = _toDeg(local);
    final country = _countryAt(deg);
    if (country == null) {
      widget.onSea();
      return;
    }
    final lon = deg.dx - 180;
    final lat = 90 - deg.dy;
    widget.onPick(Destination(country, 'Your pin', lat, lon));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _viewport = Size(c.maxWidth, c.maxHeight);
      // The map is twice as wide as it is tall; make it fill the box.
      final h = math.max(c.maxHeight, c.maxWidth / 2);
      _mapSize = Size(h * 2, h);
      if (!_placed && c.maxWidth > 0) {
        _placed = true;
        // Start centred on London.
        final london = _cityPx(_home);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _setView(1.6, c.maxWidth / 2 - london.dx * 1.6, c.maxHeight / 2 - london.dy * 1.6);
        });
      }
      return Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _controller,
              constrained: false,
              minScale: _minScale,
              maxScale: _maxScale,
              boundaryMargin: EdgeInsets.zero,
              child: GestureDetector(
                onTapUp: (d) => _onTap(d.localPosition),
                child: CustomPaint(
                  size: _mapSize,
                  painter: _WorldMapPainter(
                    scale: _scale,
                    selected: widget.selected,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Column(
              children: [
                _MapButton(icon: Icons.add_rounded, tooltip: 'Zoom in', onTap: () => _zoomBy(1.6)),
                const SizedBox(height: 6),
                _MapButton(icon: Icons.remove_rounded, tooltip: 'Zoom out', onTap: () => _zoomBy(1 / 1.6)),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MapButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _ink, width: 2.5),
            ),
            child: Icon(icon, color: _ink, size: 22),
          ),
        ),
      ),
    );
  }
}

class _WorldMapPainter extends CustomPainter {
  final double scale;
  final Destination? selected;

  _WorldMapPainter({required this.scale, required this.selected});

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 360; // pixels per degree before zooming
    final px = 1 / scale; // one screen pixel, in canvas units

    // Sea.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [_mapSea, _mapSeaDeep, _mapSea],
          [0.0, 0.5, 1.0],
        ),
    );
    // Faint lines of longitude and latitude.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = px;
    for (var lon = 30; lon < 360; lon += 30) {
      canvas.drawLine(Offset(lon * k, 0), Offset(lon * k, size.height), grid);
    }
    for (var lat = 30; lat < 180; lat += 30) {
      canvas.drawLine(Offset(0, lat * k), Offset(size.width, lat * k), grid);
    }

    // Land.
    canvas.save();
    canvas.scale(k, k);
    final land = Paint()..color = _mapLand;
    final border = Paint()
      ..color = _mapBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = px / k * (scale > 2 ? 1.2 : 0.8)
      ..strokeJoin = StrokeJoin.round;
    final countries = _parsedCountries;
    for (final c in countries) {
      canvas.drawPath(c.path, land);
    }
    for (final c in countries) {
      canvas.drawPath(c.path, border);
    }
    canvas.restore();

    // Country names when zoomed in enough.
    for (final c in countries) {
      final s = c.shape;
      final needed = s.size > 150
          ? 2.2
          : s.size > 40
              ? 3.2
              : s.size > 8
                  ? 5.0
                  : 8.0;
      if (scale < needed) continue;
      _label(
        canvas,
        s.name,
        Offset((s.labelLon + 180) * k, (90 - s.labelLat) * k),
        11 * px,
        const Color(0xFF173A1B),
        px,
        weight: FontWeight.w700,
        outline: const Color(0xCCFFFFFF),
      );
    }

    // Continents in big bold black letters (fade away when zoomed right in).
    final continentAlpha = (1.0 - (scale - 3.5) / 2.5).clamp(0.0, 1.0).toDouble();
    if (continentAlpha > 0) {
      for (final ct in _continents) {
        _label(
          canvas,
          ct.name,
          Offset((ct.lon + 180) * k, (90 - ct.lat) * k),
          (17 + 5 * math.min(scale, 2.0)) * px,
          Colors.black.withValues(alpha: continentAlpha),
          px,
          weight: FontWeight.w900,
          outline: Colors.white.withValues(alpha: 0.85 * continentAlpha),
          spacing: 2,
        );
      }
    }

    // Route to the chosen place.
    Offset cityPos(Destination d) => Offset((d.lon + 180) * k, (90 - d.lat) * k);
    final home = cityPos(_home);
    final sel = selected;
    if (sel != null) {
      final target = cityPos(sel);
      final mid = Offset(
        (home.dx + target.dx) / 2,
        math.min(home.dy, target.dy) - (target - home).distance * 0.2,
      );
      canvas.drawPath(
        Path()
          ..moveTo(home.dx, home.dy)
          ..quadraticBezierTo(mid.dx, mid.dy, target.dx, target.dy),
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * px
          ..strokeCap = StrokeCap.round,
      );
    }

    // Cities you can fly to.
    final showNames = scale >= 1.5;
    for (final d in _destinations) {
      final p = cityPos(d);
      final isSel = identical(d, sel);
      canvas.drawCircle(p, (isSel ? 6 : 4.5) * px, Paint()..color = _ink);
      canvas.drawCircle(p, (isSel ? 4 : 2.8) * px,
          Paint()..color = isSel ? _tomato : Colors.white);
      if (showNames || isSel) {
        _label(canvas, d.city, p.translate(0, -12 * px), 11.5 * px, _ink, px,
            weight: FontWeight.w800, outline: Colors.white);
      }
    }

    // A pin dropped on a spot that isn't one of the cities.
    if (sel != null && !_destinations.contains(sel)) {
      final p = cityPos(sel);
      _pin(canvas, p, px);
      _label(canvas, sel.city, p.translate(0, -30 * px), 12 * px, _ink, px,
          weight: FontWeight.w900, outline: Colors.white);
    } else if (sel != null) {
      _pin(canvas, cityPos(sel), px);
    }

    // London, where every flight starts.
    canvas.drawCircle(home, 6 * px, Paint()..color = _ink);
    canvas.drawCircle(home, 4 * px, Paint()..color = _sun);
    _label(canvas, 'London', home.translate(0, 13 * px), 11.5 * px, _ink, px,
        weight: FontWeight.w900, outline: _sun);
  }

  void _pin(Canvas canvas, Offset p, double px) {
    final pin = Path()
      ..moveTo(p.dx, p.dy)
      ..quadraticBezierTo(p.dx - 9 * px, p.dy - 14 * px, p.dx - 9 * px, p.dy - 20 * px)
      ..arcToPoint(Offset(p.dx + 9 * px, p.dy - 20 * px),
          radius: Radius.circular(9 * px))
      ..quadraticBezierTo(p.dx + 9 * px, p.dy - 14 * px, p.dx, p.dy)
      ..close();
    canvas.drawPath(pin, Paint()..color = _tomato);
    canvas.drawPath(
      pin,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * px,
    );
    canvas.drawCircle(p.translate(0, -20 * px), 3.5 * px, Paint()..color = Colors.white);
  }

  void _label(Canvas canvas, String text, Offset at, double size, Color color,
      double px,
      {FontWeight weight = FontWeight.w700, Color? outline, double spacing = 0}) {
    if (outline != null) {
      final back = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: size,
            fontWeight: weight,
            letterSpacing: spacing * px,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3 * px
              ..strokeJoin = StrokeJoin.round
              ..color = outline,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      back.paint(canvas, Offset(at.dx - back.width / 2, at.dy - back.height / 2));
    }
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing * px,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _WorldMapPainter old) =>
      old.scale != scale || old.selected != selected;
}
