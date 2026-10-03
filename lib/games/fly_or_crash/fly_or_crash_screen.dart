import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../services/save_service.dart';

part 'cartoon_flight.dart';
part 'world_data.dart';
part 'world_map.dart';
part 'role_attendant.dart';
part 'role_passenger.dart';

enum _Role { pilot, attendant, passenger }

// ---------------------------------------------------------------------------
// Fly or Crash
// Pick a city anywhere in the world, fly there from London, dodge storms and
// other planes, deal with emergencies and land safely. Your passengers must
// always be okay: if their meter hits zero, you crash.
// ---------------------------------------------------------------------------

const Color _ink = Color(0xFF15172A);
const Color _cobalt = Color(0xFF2A3FD4);
const Color _sun = Color(0xFFFFC93C);
const Color _tomato = Color(0xFFFF6B5B);
const Color _grass = Color(0xFF3DDC84);
const Color _sea = Color(0xFF6FD3F7);
const Color _sky = Color(0xFF9ADCFF);

class Destination {
  final String city;
  final String country;
  final double lat;
  final double lon;

  const Destination(this.city, this.country, this.lat, this.lon);
}

const Destination _home = Destination('London', 'United Kingdom', 51.47, -0.45);

const List<Destination> _destinations = [
  Destination('Paris', 'France', 48.86, 2.35),
  Destination('Rome', 'Italy', 41.90, 12.50),
  Destination('Reykjavik', 'Iceland', 64.15, -21.94),
  Destination('Cairo', 'Egypt', 30.04, 31.24),
  Destination('New York', 'USA', 40.71, -74.00),
  Destination('Dubai', 'UAE', 25.20, 55.27),
  Destination('Mumbai', 'India', 19.08, 72.88),
  Destination('Los Angeles', 'USA', 34.05, -118.24),
  Destination('Rio de Janeiro', 'Brazil', -22.91, -43.17),
  Destination('Cape Town', 'South Africa', -33.92, 18.42),
  Destination('Tokyo', 'Japan', 35.68, 139.69),
  Destination('Sydney', 'Australia', -33.87, 151.21),
  Destination('Madrid', 'Spain', 40.42, -3.70),
  Destination('Berlin', 'Germany', 52.52, 13.40),
  Destination('Amsterdam', 'Netherlands', 52.37, 4.90),
  Destination('Athens', 'Greece', 37.98, 23.73),
  Destination('Istanbul', 'Turkey', 41.01, 28.98),
  Destination('Moscow', 'Russia', 55.76, 37.62),
  Destination('Oslo', 'Norway', 59.91, 10.75),
  Destination('Dublin', 'Ireland', 53.35, -6.26),
  Destination('Toronto', 'Canada', 43.65, -79.38),
  Destination('Mexico City', 'Mexico', 19.43, -99.13),
  Destination('Miami', 'USA', 25.76, -80.19),
  Destination('San Francisco', 'USA', 37.77, -122.42),
  Destination('Honolulu', 'USA', 21.31, -157.86),
  Destination('Buenos Aires', 'Argentina', -34.60, -58.38),
  Destination('Lima', 'Peru', -12.05, -77.04),
  Destination('Nairobi', 'Kenya', -1.29, 36.82),
  Destination('Marrakesh', 'Morocco', 31.63, -7.99),
  Destination('Beijing', 'China', 39.90, 116.41),
  Destination('Hong Kong', 'China', 22.32, 114.17),
  Destination('Singapore', 'Singapore', 1.35, 103.82),
  Destination('Bangkok', 'Thailand', 13.76, 100.50),
  Destination('Seoul', 'South Korea', 37.57, 126.98),
  Destination('Delhi', 'India', 28.61, 77.21),
  Destination('Auckland', 'New Zealand', -36.85, 174.76),
  Destination('Bali', 'Indonesia', -8.65, 115.22),
];

double _distanceKm(Destination a, Destination b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLon = rad(b.lon - a.lon);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(a.lat)) *
          math.cos(rad(b.lat)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * r * math.asin(math.sqrt(h));
}

String _flightLength(double km) {
  if (km < 2000) return 'Short hop';
  if (km < 7000) return 'Medium flight';
  return 'Long haul';
}

String _formatKm(double km) {
  final n = km.round();
  if (n < 1000) return '$n km';
  final thousands = n ~/ 1000;
  final rest = (n % 1000).toString().padLeft(3, '0');
  return '$thousands,$rest km';
}

// ===========================================================================
// Screen 1: pick where to fly
// ===========================================================================

class FlyOrCrashScreen extends StatefulWidget {
  const FlyOrCrashScreen({super.key});

  @override
  State<FlyOrCrashScreen> createState() => _FlyOrCrashScreenState();
}

class _FlyOrCrashScreenState extends State<FlyOrCrashScreen> {
  late final List<Destination> _sorted = [..._destinations]
    ..sort((a, b) => _distanceKm(_home, a).compareTo(_distanceKm(_home, b)));
  Destination? _selected;
  bool _cartoon = false;
  _Role _role = _Role.pilot;
  String _mapHint =
      'Zoom in to see countries and cities. Tap a city, or tap anywhere on land!';

  void _takeOff() {
    final dest = _selected;
    if (dest == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) {
          switch (_role) {
            case _Role.attendant:
              return AttendantScreen(destination: dest);
            case _Role.passenger:
              return PassengerScreen(destination: dest);
            case _Role.pilot:
              return _cartoon
                  ? CartoonFlightScreen(destination: dest)
                  : FlightScreen(destination: dest);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Scaffold(
      backgroundColor: _cobalt,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Fly or Crash',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 2, 22, 14),
              child: Text(
                'You\'re at London airport. Where are we flying today?',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _ModeChoice(
                      label: 'Pilot',
                      detail: 'Fly the plane',
                      icon: Icons.flight_rounded,
                      selected: _role == _Role.pilot,
                      onTap: () => setState(() => _role = _Role.pilot),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ModeChoice(
                      label: 'Attendant',
                      detail: 'Serve food',
                      icon: Icons.room_service_rounded,
                      selected: _role == _Role.attendant,
                      onTap: () => setState(() => _role = _Role.attendant),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ModeChoice(
                      label: 'Passenger',
                      detail: 'Travel and explore',
                      icon: Icons.person_rounded,
                      selected: _role == _Role.passenger,
                      onTap: () => setState(() => _role = _Role.passenger),
                    ),
                  ),
                ],
              ),
            ),
            if (_role == _Role.pilot)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: Row(
                children: [
                  Expanded(
                    child: _ModeChoice(
                      label: 'Realistic',
                      detail: 'Fly from the cockpit',
                      icon: Icons.airplanemode_active_rounded,
                      selected: !_cartoon,
                      onTap: () => setState(() => _cartoon = false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeChoice(
                      label: 'Cartoon',
                      detail: 'Bright and side-on',
                      icon: Icons.emoji_emotions_rounded,
                      selected: _cartoon,
                      onTap: () => setState(() => _cartoon = true),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                height: (MediaQuery.of(context).size.height * 0.38)
                    .clamp(200.0, 380.0)
                    .toDouble(),
                decoration: BoxDecoration(
                  color: _mapSea,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _ink, width: 2.5),
                  boxShadow: const [
                    BoxShadow(color: _ink, offset: Offset(0, 5)),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _WorldMap(
                  selected: selected,
                  onPick: (d) => setState(() {
                    _selected = d;
                    _mapHint = d.country == 'Your pin'
                        ? 'Pin dropped in ${d.city}! Press take off when you\'re ready.'
                        : '${d.city}, ${d.country}. Great choice!';
                  }),
                  onSea: () => setState(() {
                    _mapHint = 'That\'s the sea! Planes can\'t land on water. '
                        'Tap on the green land.';
                  }),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
              child: Text(
                _mapHint,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                itemCount: _sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final d = _sorted[i];
                  final km = _distanceKm(_home, d);
                  final isSelected = identical(d, selected);
                  return _DestinationTile(
                    destination: d,
                    km: km,
                    selected: isSelected,
                    onTap: () => setState(() => _selected = d),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              child: _ChunkyButton(
                label: selected == null
                    ? 'Pick a place to fly to'
                    : _role == _Role.passenger
                        ? 'Go to the airport'
                        : _role == _Role.attendant
                            ? 'Start work: flight to ${selected.city}'
                            : 'Take off for ${selected.city}',
                color: selected == null ? Colors.white54 : _sun,
                onPressed: selected == null ? null : _takeOff,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeChoice extends StatelessWidget {
  final String label;
  final String detail;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChoice({
    required this.label,
    required this.detail,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label mode',
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? _sun : Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? _ink : Colors.white.withValues(alpha: 0.5),
                width: 2.5,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: selected ? _ink : Colors.white, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: selected ? _ink : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? _ink.withValues(alpha: 0.75)
                              : Colors.white.withValues(alpha: 0.75),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  final Destination destination;
  final double km;
  final bool selected;
  final VoidCallback onTap;

  const _DestinationTile({
    required this.destination,
    required this.km,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? _sun : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _ink, width: 2.5),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.flight_takeoff_rounded : Icons.place_rounded,
                color: _ink,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.city,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      destination.country,
                      style: TextStyle(
                        color: _ink.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatKm(km),
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    _flightLength(km),
                    style: TextStyle(
                      color: _ink.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChunkyButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _ChunkyButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _ink, width: 2.5),
            boxShadow: const [
              BoxShadow(color: _ink, offset: Offset(0, 5)),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

/// A simple flight map: a grid of lines, a dot for every city and a curved
/// route from London to the chosen city.
class _MapPainter extends CustomPainter {
  final Destination? selected;

  _MapPainter({required this.selected});

  // Show latitudes from 72N down to 48S so the cities fill the card.
  static const double _top = 72;
  static const double _bottom = -48;

  Offset _project(Destination d, Size size) {
    final x = (d.lon + 180) / 360 * size.width;
    final y = (_top - d.lat) / (_top - _bottom) * size.height;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var lon = -150; lon <= 150; lon += 30) {
      final x = (lon + 180) / 360 * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var lat = 60; lat >= -40; lat -= 20) {
      final y = (_top - lat) / (_top - _bottom) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // The equator a little stronger.
    final eqY = (_top - 0) / (_top - _bottom) * size.height;
    canvas.drawLine(
      Offset(0, eqY),
      Offset(size.width, eqY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 1.5,
    );

    final dot = Paint()..color = _ink;
    for (final d in _destinations) {
      canvas.drawCircle(_project(d, size), 3.5, dot);
    }

    final home = _project(_home, size);
    final sel = selected;
    if (sel != null) {
      final target = _project(sel, size);
      final mid = Offset(
        (home.dx + target.dx) / 2,
        math.min(home.dy, target.dy) - size.height * 0.22,
      );
      final path = Path()
        ..moveTo(home.dx, home.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, target.dx, target.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      _marker(canvas, target, _tomato);
      _label(canvas, sel.city, target, size);
    }
    _marker(canvas, home, _sun);
    _label(canvas, 'London', home, size);
  }

  void _marker(Canvas canvas, Offset at, Color color) {
    canvas.drawCircle(at, 8, Paint()..color = _ink);
    canvas.drawCircle(at, 5.5, Paint()..color = color);
  }

  void _label(Canvas canvas, String text, Offset at, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: _ink,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx + 10;
    if (dx + tp.width > size.width - 4) dx = at.dx - 10 - tp.width;
    var dy = at.dy - tp.height - 4;
    if (dy < 2) dy = at.dy + 6;
    final box = RRect.fromRectAndRadius(
      Rect.fromLTWH(dx - 4, dy - 1, tp.width + 8, tp.height + 2),
      const Radius.circular(5),
    );
    canvas.drawRRect(box, Paint()..color = Colors.white);
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) =>
      oldDelegate.selected != selected;
}

class _Emergency {
  final String title;
  final String body;
  final IconData icon;
  const _Emergency(this.title, this.body, this.icon);
}

const List<_Emergency> _emergencies = [
  _Emergency(
    'Engine trouble!',
    'One of the engines is smoking. Land at the nearest airport, or keep flying and hope it holds?',
    Icons.local_fire_department_rounded,
  ),
  _Emergency(
    'A passenger feels poorly!',
    'Someone in row 14 needs a doctor. Make an emergency landing, or keep flying?',
    Icons.medical_services_rounded,
  ),
  _Emergency(
    'Bird strike!',
    'A bird hit the windscreen and there\'s a crack. Land now, or keep flying?',
    Icons.flutter_dash,
  ),
];

// ===========================================================================
// Screen 2: the flight, seen from the cockpit
// ===========================================================================
//
// The world is flat and measured in "units". The plane flies at a steady
// speed, turns by banking and changes height by climbing or descending.
// Heading 0 is north (+y) and 90 is east (+x).

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

double _wrap360(double a) {
  final w = a % 360;
  return w < 0 ? w + 360 : w;
}

double _wrap180(double a) {
  final w = _wrap360(a);
  return w > 180 ? w - 360 : w;
}

/// Repeatable "random" number between 0 and 1 for a whole number.
double _hash(int n) {
  final v = math.sin(n * 12.9898 + 78.233) * 43758.5453;
  return v - v.floorToDouble();
}

class _Storm {
  final double x;
  final double y;
  final double r; // radius in units
  final double topFt; // height of the cloud top
  final double seed;
  bool warned = false;

  _Storm(this.x, this.y, this.r, this.topFt, this.seed);
}

class _Traffic {
  double x;
  double y;
  final double altFt;
  final double hdg;
  final double seed;
  bool warned = false;
  bool dead = false;

  _Traffic(this.x, this.y, this.altFt, this.hdg, this.seed);
}

class _Puff {
  final double x; // position inside a repeating 160 x 160 tile
  final double y;
  final double size;
  final double seed;

  const _Puff(this.x, this.y, this.size, this.seed);
}

enum _Phase { flying, emergencyChoice, landed, crashed }

class FlightScreen extends StatefulWidget {
  final Destination destination;

  const FlightScreen({super.key, required this.destination});

  @override
  State<FlightScreen> createState() => _FlightScreenState();
}

class _FlightScreenState extends State<FlightScreen>
    with SingleTickerProviderStateMixin {
  static const double _cruiseSpeed = 4.0; // units per second
  static const double _approachSpeed = 3.0;
  static const double _ftPerUnit = 2500.0; // feet in one unit of height
  static const double _cloudLayerFt = 6000.0;
  static const double _maxAltFt = 41000.0;
  static const double _approachDistance = 100.0;
  static const double _tile = 160.0;

  final math.Random _rand = math.Random();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final FocusNode _focus = FocusNode();

  late double _km;
  late double _routeLen;
  late double _difficulty;
  late int _paxCount;

  _Phase _phase = _Phase.flying;
  double _time = 0;

  // Our plane.
  double _x = 0;
  double _y = 0;
  double _heading = 90;
  double _roll = 0;
  double _altFt = 30000;
  double _vs = 0; // feet per second
  double _travelled = 0;

  // Controls.
  bool _left = false;
  bool _right = false;
  bool _up = false;
  bool _down = false;
  bool _dragging = false;
  double _dragRoll = 0;
  double _dragPitch = 0;

  // Where we are heading (the destination, or an emergency airport).
  late double _destX;
  final double _destY = 0;
  late double _tx;
  late double _ty;
  bool _toEmergencyAirport = false;
  bool _approach = false;
  double _approachFromX = -1; // unit vector from airport towards our approach
  double _approachFromY = 0;

  // The world.
  final List<_Storm> _storms = [];
  final List<_Traffic> _traffic = [];
  final List<_Puff> _puffs = [];
  late final List<_Feature> _destScenery;
  List<_Feature> _emergencyScenery = const [];
  double _trafficTimer = 14;

  // Cabin.
  double _passengers = 100;
  bool _seatbelt = false;
  double _snackCooldown = 0;
  double _calmWithSeatbelt = 0;
  double _engineTrouble = 0;
  final List<double> _emergencyAt = [];
  _Emergency? _currentEmergency;

  // Ava, the flight attendant.
  String _avaText = '';
  double _avaGlow = 0;
  final Map<String, double> _avaLastSaid = {};

  // Effects (0 to 1).
  double _turbulence = 0;
  double _rain = 0;
  double _fog = 0;
  double _lightning = 0;
  double _hitFlash = 0;
  bool _trafficAlert = false;
  bool _pullUp = false;
  bool _stormAhead = false;

  @override
  void initState() {
    super.initState();
    _km = _distanceKm(_home, widget.destination);
    final seconds = (35 + _km / 160).clamp(40.0, 140.0).toDouble();
    _routeLen = seconds * _cruiseSpeed;
    _difficulty = (_km / 17000).clamp(0.0, 1.0).toDouble();
    _paxCount = 120 + _rand.nextInt(200);
    _destX = _routeLen;
    _tx = _destX;
    _ty = _destY;
    _altFt = (_routeLen * 90).clamp(12000.0, 34000.0).toDouble();

    _destScenery = _sceneryFor(widget.destination.city, _rand);
    _makeWorld();
    if (_km > 2500) _emergencyAt.add(0.3 + _rand.nextDouble() * 0.2);
    if (_km > 9000) _emergencyAt.add(0.6 + _rand.nextDouble() * 0.1);

    _avaText =
        'Hi Captain, I\'m Ava, your flight attendant! $_paxCount passengers '
        'on board for ${widget.destination.city}. Steer with the arrow keys '
        'or drag the windscreen, and follow the pink line on your map.';
    _avaGlow = 1;
    _ticker = createTicker(_tick)..start();
  }

  void _makeWorld() {
    final stormCount = (4 + _routeLen / 45 + _difficulty * 4).round();
    for (var i = 0; i < stormCount; i++) {
      final along = _routeLen * (0.12 + _rand.nextDouble() * 0.72);
      final side = (_rand.nextDouble() * 2 - 1) * 22;
      _storms.add(_Storm(
        along,
        _destY + side,
        5 + _rand.nextDouble() * 5,
        30000 + _rand.nextDouble() * 14000,
        _rand.nextDouble(),
      ));
    }
    for (var i = 0; i < 46; i++) {
      _puffs.add(_Puff(
        _rand.nextDouble() * _tile,
        _rand.nextDouble() * _tile,
        2.0 + _rand.nextDouble() * 3.5,
        _rand.nextDouble(),
      ));
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  double _lerp(double a, double b) => a + (b - a) * _difficulty;

  double get _progress {
    final dx = _destX - _x;
    final dy = _destY - _y;
    final d = math.sqrt(dx * dx + dy * dy);
    return (1 - d / _routeLen).clamp(0.0, 1.0).toDouble();
  }

  double get _speed => _approach ? _approachSpeed : _cruiseSpeed;

  double get _bearingToTarget =>
      _wrap360(_deg(math.atan2(_tx - _x, _ty - _y)));

  double get _distToTarget {
    final dx = _tx - _x;
    final dy = _ty - _y;
    return math.sqrt(dx * dx + dy * dy);
  }

  String get _targetName =>
      _toEmergencyAirport ? 'the nearest airport' : widget.destination.city;

  void _ava(String key, String text, {double cooldown = 12}) {
    final last = _avaLastSaid[key];
    if (last != null && _time - last < cooldown) return;
    _avaLastSaid[key] = _time;
    _avaText = text;
    _avaGlow = 1;
  }

  // ---- game loop ----------------------------------------------------------

  void _tick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt > 0.05) dt = 0.05;
    if (dt <= 0) return;
    if (_phase != _Phase.flying) return;
    setState(() => _update(dt));
  }

  void _update(double dt) {
    _time += dt;
    _avaGlow = math.max(0.0, _avaGlow - dt * 1.5);
    _lightning = math.max(0.0, _lightning - dt * 3);
    _hitFlash = math.max(0.0, _hitFlash - dt * 2);
    if (_snackCooldown > 0) _snackCooldown -= dt;

    _fly(dt);
    _weather(dt);
    _updateTraffic(dt);
    _cabin(dt);
    _navigation();

    _passengers = _passengers.clamp(0.0, 100.0).toDouble();
    if (_passengers <= 0) {
      _phase = _Phase.crashed;
    }
  }

  void _fly(double dt) {
    var rollIn = 0.0;
    var pitchIn = 0.0;
    if (_dragging) {
      rollIn = _dragRoll;
      pitchIn = _dragPitch;
    } else {
      if (_left) rollIn -= 1;
      if (_right) rollIn += 1;
      if (_up) pitchIn += 1;
      if (_down) pitchIn -= 1;
    }

    final targetRoll = rollIn * 30;
    _roll += (targetRoll - _roll) * math.min(1.0, dt * 2.5);
    if (_turbulence > 0.02) {
      _roll += (math.sin(_time * 9.1) + math.sin(_time * 23.7)) *
          _turbulence *
          30 *
          dt;
    }
    _heading = _wrap360(_heading + _roll * 0.25 * dt);

    final targetVs = pitchIn * 1500;
    _vs += (targetVs - _vs) * math.min(1.0, dt * 2.0);
    if (_turbulence > 0.02) {
      _vs += math.sin(_time * 11.3) * _turbulence * 2500 * dt;
    }
    _altFt = (_altFt + _vs * dt).clamp(0.0, _maxAltFt).toDouble();

    final h = _rad(_heading);
    final step = _speed * dt;
    _x += math.sin(h) * step;
    _y += math.cos(h) * step;
    _travelled += step;

    if (_altFt <= 0) {
      _phase = _Phase.crashed;
      return;
    }
    _pullUp = _altFt < 1200 && !(_approach && _distToTarget < 8);
  }

  void _weather(double dt) {
    var turbTarget = 0.0;
    var rainTarget = 0.0;
    var fogTarget = 0.0;
    var inside = false;
    var ahead = false;

    final h = _rad(_heading);
    final sinH = math.sin(h);
    final cosH = math.cos(h);

    for (final s in _storms) {
      final dx = s.x - _x;
      final dy = s.y - _y;
      final d = math.sqrt(dx * dx + dy * dy);
      final below = _altFt < s.topFt;
      if (d < s.r) {
        if (below) {
          inside = true;
          turbTarget = 1;
          rainTarget = 1;
          fogTarget = math.max(fogTarget, 0.85);
        } else {
          turbTarget = math.max(turbTarget, 0.15);
        }
      } else if (d < s.r + 6 && below) {
        final t = 1 - (d - s.r) / 6;
        turbTarget = math.max(turbTarget, t * 0.3);
        rainTarget = math.max(rainTarget, t * 0.7);
        fogTarget = math.max(fogTarget, t * 0.25);
      }

      // Is it in front of us, on our path?
      final fwd = dx * sinH + dy * cosH;
      final side = dx * cosH - dy * sinH;
      if (below && fwd > 0 && fwd < 40 && side.abs() < s.r + 2) {
        ahead = true;
        if (!s.warned) {
          s.warned = true;
          final topK = (s.topFt / 1000).round();
          final canClimb = s.topFt < _maxAltFt - 1000;
          _ava(
            'storm',
            canClimb
                ? 'Captain, there\'s a big storm ahead on the radar! Steer '
                    'around it, or climb over it. Its top is about '
                    '${topK},000 feet.'
                : 'Captain, huge storm ahead, too tall to climb over! '
                    'Turn left or right to go around it.',
            cooldown: 6,
          );
        }
      }
    }
    _stormAhead = ahead;

    final k = math.min(1.0, dt * 3);
    _turbulence += (turbTarget - _turbulence) * k;
    _rain += (rainTarget - _rain) * k;
    _fog += (fogTarget - _fog) * k;

    if (inside && _rand.nextDouble() < dt * 0.8) _lightning = 1;
    if (!inside && rainTarget > 0.3 && _rand.nextDouble() < dt * 0.15) {
      _lightning = 0.6;
    }

    if (inside) {
      if (!_seatbelt) {
        _ava('turb', 'Whoa! Turn the seatbelt sign on, people are '
            'spilling their drinks!', cooldown: 10);
      } else {
        _ava('turb2', 'Bumpy in here! Everyone\'s strapped in. Get us out '
            'of this storm, Captain!', cooldown: 14);
      }
    }
  }

  void _updateTraffic(double dt) {
    if (!_approach) {
      _trafficTimer -= dt;
      if (_trafficTimer <= 0) {
        _trafficTimer = _lerp(26, 12) + _rand.nextDouble() * 8;
        final b = _rad(_heading + (_rand.nextDouble() * 2 - 1) * 5);
        const dist = 48.0;
        _traffic.add(_Traffic(
          _x + math.sin(b) * dist,
          _y + math.cos(b) * dist,
          (_altFt + (_rand.nextDouble() * 2 - 1) * 400)
              .clamp(3000.0, _maxAltFt)
              .toDouble(),
          _wrap360(_heading + 180 + (_rand.nextDouble() * 2 - 1) * 4),
          _rand.nextDouble(),
        ));
      }
    }

    var alert = false;
    for (final t in _traffic) {
      final th = _rad(t.hdg);
      t.x += math.sin(th) * 3 * dt;
      t.y += math.cos(th) * 3 * dt;
      final dx = t.x - _x;
      final dy = t.y - _y;
      final d = math.sqrt(dx * dx + dy * dy);
      final altDiff = (t.altFt - _altFt).abs();
      if (d < 25 && altDiff < 1000) {
        alert = true;
        if (!t.warned) {
          t.warned = true;
          _ava(
            'traffic',
            'TRAFFIC! Another plane is coming straight at us at our height. '
                'Climb or go down, quick!',
            cooldown: 4,
          );
        }
      }
      if (d < 1.4 && altDiff < 700) {
        t.dead = true;
        _passengers -= 25;
        _hitFlash = 1;
        _turbulence = 1;
        _ava('hit', 'AAAH! We clipped that plane! Everyone is terrified!',
            cooldown: 2);
      }
      if (d > 70) t.dead = true;
    }
    _traffic.removeWhere((t) => t.dead);
    _trafficAlert = alert;
  }

  void _cabin(double dt) {
    final seat = _seatbelt;
    if (_turbulence > 0.8) {
      _passengers -= (seat ? 5 : 13) * dt;
    } else if (_turbulence > 0.05) {
      _passengers -= _turbulence * (seat ? 4 : 9) * dt;
    }

    if (_engineTrouble > 0) {
      _engineTrouble -= dt;
      _passengers -= 3 * dt;
      if (_engineTrouble <= 0) {
        _engineTrouble = 0;
        _ava('engineok', 'Phew! That problem has calmed down, Captain.',
            cooldown: 1);
      }
    }

    if (_pullUp) {
      _passengers -= 6 * dt;
      _ava('pullup', 'Captain, we\'re really low! Pull up!', cooldown: 6);
    }

    final calm = _turbulence < 0.05 && _engineTrouble <= 0 && !_pullUp;
    if (calm) _passengers += 1.0 * dt;

    if (seat && calm) {
      _calmWithSeatbelt += dt;
      if (_calmWithSeatbelt > 25) {
        _passengers -= 0.6 * dt;
        _ava('seatoff', 'It\'s smooth now. You could switch the seatbelt '
            'sign off so people can stretch their legs.', cooldown: 25);
      }
    } else {
      _calmWithSeatbelt = 0;
    }

    if (_passengers < 35) {
      _ava('scared', 'The passengers are really scared, Captain! Find some '
          'smooth air, or let me serve snacks when it\'s calm.', cooldown: 15);
    }
  }

  void _navigation() {
    // Emergencies happen part way through longer flights.
    if (!_approach &&
        !_toEmergencyAirport &&
        _emergencyAt.isNotEmpty &&
        _progress >= _emergencyAt.first) {
      _emergencyAt.removeAt(0);
      _currentEmergency = _emergencies[_rand.nextInt(_emergencies.length)];
      _phase = _Phase.emergencyChoice;
      return;
    }

    final dist = _distToTarget;
    final err = _wrap180(_bearingToTarget - _heading);

    if (!_approach && dist < _approachDistance) {
      _approach = true;
      _approachFromX = (_x - _tx) / dist;
      _approachFromY = (_y - _ty) / dist;
      _ava(
        'approach',
        'We\'re getting close to $_targetName! Start going down. You need '
            'to be under 1,500 feet and lined up with the runway to land.',
        cooldown: 1,
      );
    }

    if (err.abs() > 30 && dist > 6) {
      _ava(
        'course',
        'Captain, we\'re off course! Turn ${err > 0 ? 'right' : 'left'} '
            'until the pink line points straight up on the map.',
        cooldown: 12,
      );
    }

    if (_approach && dist < 2.2) {
      if (_altFt < 1500 && err.abs() < 25) {
        _touchDown();
        return;
      }
    }
    if (_approach && dist < 0.7) {
      _goAround(err.abs() >= 25 ? 'We weren\'t lined up with the runway.'
          : 'We were too high to land.');
    }
  }

  void _goAround(String why) {
    _passengers -= 6;
    _x = _tx + _approachFromX * 22;
    _y = _ty + _approachFromY * 22;
    _heading = _bearingToTarget;
    _roll = 0;
    _ava('goaround', '$why Going around for another try! Get lower this '
        'time.', cooldown: 1);
  }

  void _touchDown() {
    if (_toEmergencyAirport) {
      _passengers = math.min(100.0, _passengers + 15);
      _engineTrouble = 0;
      _toEmergencyAirport = false;
      _approach = false;
      _tx = _destX;
      _ty = _destY;
      _altFt = 3000;
      _vs = 0;
      _roll = 0;
      _heading = _bearingToTarget;
      _traffic.clear();
      _ava('fixed', 'Safe emergency landing! Everyone\'s okay and we\'re '
          'all fixed. Back in the air, next stop ${widget.destination.city}!',
          cooldown: 1);
    } else {
      // Roll to a stop on the runway, looking down it towards the city.
      final ax = -_approachFromX;
      final ay = -_approachFromY;
      _x = _tx - ax * 1.2;
      _y = _ty - ay * 1.2;
      _heading = _wrap360(_deg(math.atan2(ax, ay)));
      _altFt = 25;
      _vs = 0;
      _roll = 0;
      _turbulence = 0;
      _rain = 0;
      _fog = 0;
      _lightning = 0;
      _pullUp = false;
      _trafficAlert = false;
      _traffic.clear();
      _ava('arrive', _welcomeLine(widget.destination.city), cooldown: 0);
      _phase = _Phase.landed;
      final save = SaveService.instance;
      save.saveHighScore('fly_or_crash', save.getHighScore('fly_or_crash') + 1);
    }
  }

  void _chooseEmergencyLanding() {
    setState(() {
      final e = _currentEmergency;
      _currentEmergency = null;
      _phase = _Phase.flying;
      final b = _rad(_heading + (_rand.nextDouble() * 2 - 1) * 30);
      _tx = _x + math.sin(b) * 70;
      _ty = _y + math.cos(b) * 70;
      _toEmergencyAirport = true;
      _approach = false;
      _traffic.clear();
      _emergencyScenery = _sceneryFor('', _rand);
      _ava('emerg',
          'Good call, Captain. ${e?.title ?? 'Emergency'} I\'ve found the '
          'nearest airport. Follow the pink line and take us down!',
          cooldown: 1);
    });
    _focus.requestFocus();
  }

  void _chooseKeepFlying() {
    setState(() {
      _currentEmergency = null;
      _phase = _Phase.flying;
      _engineTrouble = 14;
      if (_rand.nextDouble() < 0.35) {
        _passengers -= 12;
        _ava('worse', 'Uh oh, it\'s getting worse! The passengers are scared.',
            cooldown: 1);
      } else {
        _ava('keep', 'Okay Captain, we\'ll keep going. I\'ll tell everyone to '
            'stay calm.', cooldown: 1);
      }
    });
    _focus.requestFocus();
  }

  void _toggleSeatbelt() {
    setState(() {
      _seatbelt = !_seatbelt;
      _calmWithSeatbelt = 0;
      _ava(
        'seat',
        _seatbelt
            ? 'Ding! Seatbelt sign is on. Everyone\'s buckling up.'
            : 'Ding! Seatbelt sign off. People can move around again.',
        cooldown: 0,
      );
    });
    _focus.requestFocus();
  }

  void _serveSnacks() {
    setState(() {
      if (_snackCooldown > 0) {
        _ava('snackwait', 'Give me a moment, I\'m still pushing the trolley '
            'down the aisle!', cooldown: 0);
      } else if (_seatbelt) {
        _ava('snackseat', 'I can\'t serve snacks with the seatbelt sign on, '
            'Captain!', cooldown: 0);
      } else if (_turbulence > 0.3) {
        _passengers -= 6;
        _snackCooldown = 10;
        _ava('spill', 'Oops! Juice everywhere! Wait for smooth air next '
            'time.', cooldown: 0);
      } else {
        _passengers += 10;
        _snackCooldown = 20;
        _ava('snack', 'Snacks served! Crisps, juice and cookies. The '
            'passengers love you!', cooldown: 0);
      }
    });
    _focus.requestFocus();
  }

  void _askAva() {
    setState(() {
      final dist = _distToTarget;
      final err = _wrap180(_bearingToTarget - _heading);
      final turn = err > 0 ? 'right' : 'left';
      final String tip;
      if (_trafficAlert) {
        tip = 'There\'s a plane at our height! Hold the up or down arrow to '
            'change height, fast.';
      } else if (_turbulence > 0.5) {
        tip = 'We\'re inside a storm. Turn out of it, or climb if its top is '
            'low. And switch the seatbelt sign on!';
      } else if (_stormAhead) {
        tip = 'Storm ahead! Look at the red blob on the map and turn away '
            'from it, then turn back towards the pink line.';
      } else if (_approach) {
        final needDown = _altFt > 1500;
        if (needDown) {
          tip = 'We need to go down. We\'re at ${_altFt.round()} feet and '
              'need to be under 1,500. Hold the down arrow.';
        } else if (err.abs() > 10) {
          tip = 'Good height! Now turn $turn a little to line up with the '
              'runway.';
        } else {
          tip = 'Perfect! Keep it steady. ${dist.toStringAsFixed(0)} more '
              'to the runway.';
        }
      } else if (err.abs() > 12) {
        tip = 'Turn $turn by about ${err.abs().round()} degrees to get back '
            'on course.';
      } else if (_passengers < 70 && _turbulence < 0.05 && !_seatbelt) {
        tip = 'It\'s nice and smooth. Want me to serve some snacks?';
      } else {
        tip = 'Everything looks great, Captain! About '
            '${(100 - _progress * 100).round()}% of the way still to go.';
      }
      _ava('ask', tip, cooldown: 0);
    });
    _focus.requestFocus();
  }

  void _restart() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FlightScreen(destination: widget.destination),
      ),
    );
  }

  // ---- input --------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      _left = down;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      _right = down;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      _up = down;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyS) {
      _down = down;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onDrag(Offset delta) {
    _dragRoll = (_dragRoll + delta.dx / 90).clamp(-1.0, 1.0).toDouble();
    _dragPitch = (_dragPitch - delta.dy / 90).clamp(-1.0, 1.0).toDouble();
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15171B),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (context, c) {
            final h = c.maxHeight;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {
                _dragging = true;
                _dragRoll = 0;
                _dragPitch = 0;
              },
              onPanUpdate: (d) => _onDrag(d.delta),
              onPanEnd: (_) => _dragging = false,
              onPanCancel: () => _dragging = false,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _CockpitPainter(this)),
                  ),
                  SafeArea(child: _buildHud()),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: h * 0.5 + 10,
                    child: _buildAva(),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: SafeArea(top: false, child: _buildControls()),
                  ),
                  if (_phase == _Phase.emergencyChoice &&
                      _currentEmergency != null)
                    _buildEmergency(_currentEmergency!),
                  if (_phase == _Phase.landed) _buildLanded(),
                  if (_phase == _Phase.crashed) _buildCrashed(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAva() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFB79BFF),
            shape: BoxShape.circle,
            border: Border.all(color: _ink, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: _sun.withValues(alpha: _avaGlow * 0.9),
                blurRadius: 14 * _avaGlow,
                spreadRadius: 3 * _avaGlow,
              ),
            ],
          ),
          child: const Icon(Icons.support_agent_rounded, color: _ink, size: 28),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _ink, width: 2.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Ava, flight attendant',
                        style: TextStyle(
                          color: Color(0xFF6A4FD8),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _avaText,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _SmallButton(
                  label: 'Ask Ava',
                  icon: Icons.chat_bubble_rounded,
                  color: const Color(0xFFB79BFF),
                  onTap: _askAva,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Row(
      children: [
        _SmallButton(
          label: _seatbelt ? 'Seatbelts on' : 'Seatbelts off',
          icon: Icons.airline_seat_recline_normal_rounded,
          color: _seatbelt ? _sun : Colors.white,
          onTap: _toggleSeatbelt,
        ),
        const Spacer(),
        _SmallButton(
          label: 'Serve snacks',
          icon: Icons.local_cafe_rounded,
          color: _snackCooldown > 0 ? Colors.white54 : Colors.white,
          onTap: _serveSnacks,
        ),
      ],
    );
  }

  Widget _buildHud() {
    final p = _passengers;
    final IconData face;
    final Color meter;
    if (p > 70) {
      face = Icons.sentiment_very_satisfied_rounded;
      meter = _grass;
    } else if (p > 45) {
      face = Icons.sentiment_neutral_rounded;
      meter = _sun;
    } else if (p > 20) {
      face = Icons.sentiment_dissatisfied_rounded;
      meter = const Color(0xFFFF9F43);
    } else {
      face = Icons.sentiment_very_dissatisfied_rounded;
      meter = _tomato;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _RoundIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Leave flight',
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Panel(
                  child: Row(
                    children: [
                      Icon(face, color: _ink, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        '$_paxCount passengers',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: _ink, width: 2),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: (p / 100).clamp(0.0, 1.0).toDouble(),
                            child: Container(
                              decoration: BoxDecoration(
                                color: meter,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 38,
                        child: Text(
                          '${p.round()}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Panel(
            child: Row(
              children: [
                const Text(
                  'London',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      const iconSize = 20.0;
                      final left = (c.maxWidth - iconSize) * _progress;
                      return SizedBox(
                        height: iconSize,
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: iconSize / 2 - 1.5,
                              child: Container(
                                height: 3,
                                color: _ink.withValues(alpha: 0.25),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              top: iconSize / 2 - 1.5,
                              child: Container(
                                width: left + iconSize / 2,
                                height: 3,
                                color: _ink,
                              ),
                            ),
                            Positioned(
                              left: left,
                              top: 0,
                              child: Transform.rotate(
                                angle: math.pi / 2,
                                child: const Icon(
                                  Icons.flight_rounded,
                                  color: _ink,
                                  size: iconSize,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.destination.city,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergency(_Emergency e) {
    return _Overlay(
      color: _tomato,
      icon: e.icon,
      title: e.title,
      body: '${e.body}\n\nAva: "Captain, what do you want to do?"',
      buttons: [
        _ChunkyButton(
          label: 'Emergency landing',
          color: _sun,
          onPressed: _chooseEmergencyLanding,
        ),
        const SizedBox(height: 12),
        _ChunkyButton(
          label: 'Keep flying',
          color: Colors.white,
          onPressed: _chooseKeepFlying,
        ),
      ],
    );
  }

  Widget _buildLanded() {
    final p = _passengers.round();
    final stars = p >= 80 ? 3 : (p >= 50 ? 2 : 1);
    final String message;
    if (stars == 3) {
      message = 'Smooth flight! Your passengers are clapping.';
    } else if (stars == 2) {
      message = 'You made it. A few wobbly tummies, but everyone is okay.';
    } else {
      message = 'That was scary, but everyone got there safely.';
    }
    return _Overlay(
      dim: false,
      align: Alignment.bottomCenter,
      color: _grass,
      icon: Icons.flight_land_rounded,
      title: 'Landed in ${widget.destination.city}!',
      body: '$message\nPassengers okay: $p%',
      extra: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          3,
          (i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              i < stars ? Icons.star_rounded : Icons.star_border_rounded,
              color: _ink,
              size: 44,
            ),
          ),
        ),
      ),
      buttons: [
        _ChunkyButton(
          label: 'Pick a new place',
          color: _sun,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 12),
        _ChunkyButton(
          label: 'Fly here again',
          color: Colors.white,
          onPressed: _restart,
        ),
      ],
    );
  }

  Widget _buildCrashed() {
    final hitGround = _altFt <= 0;
    return _Overlay(
      color: _tomato,
      icon: Icons.warning_rounded,
      title: 'Crash!',
      body: hitGround
          ? 'We flew into the ground! Keep an eye on your height, and only go '
              'low when you\'re lined up with the runway.'
          : 'Your passengers weren\'t okay, so the flight is over. Avoid the '
              'storms and planes, use the seatbelt sign, and serve snacks '
              'when it\'s smooth.',
      buttons: [
        _ChunkyButton(
          label: 'Try again',
          color: _sun,
          onPressed: _restart,
        ),
        const SizedBox(height: 12),
        _ChunkyButton(
          label: 'Pick a new place',
          color: Colors.white,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SmallButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _ink, width: 2.5),
            boxShadow: const [BoxShadow(color: _ink, offset: Offset(0, 3))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _ink, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- small UI pieces ------------------------------------------------------

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _ink, width: 2.5),
      ),
      child: child,
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: _ink, width: 2.5),
          ),
          child: Icon(icon, color: _ink),
        ),
      ),
    );
  }
}

class _Sticker extends StatelessWidget {
  final String text;
  const _Sticker({required this.text});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.03,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _sun,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _ink, width: 2.5),
          boxShadow: const [BoxShadow(color: _ink, offset: Offset(0, 4))],
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _ink,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String body;
  final Widget? extra;
  final List<Widget> buttons;
  final bool dim;
  final Alignment align;

  const _Overlay({
    this.dim = true,
    this.align = Alignment.center,
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
    required this.buttons,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: dim ? _ink.withValues(alpha: 0.55) : Colors.transparent,
        alignment: align,
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _ink, width: 3),
              boxShadow: const [BoxShadow(color: _ink, offset: Offset(0, 6))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(icon, color: _ink, size: 48),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (extra != null) ...[
                  const SizedBox(height: 12),
                  extra!,
                ],
                const SizedBox(height: 18),
                ...buttons,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- what each city looks like when you arrive -----------------------------

enum _Lm {
  box,
  empire,
  liberty,
  eiffel,
  colosseum,
  pyramid,
  burj,
  sail,
  church,
  tokyoTower,
  opera,
  bridge,
  tableMountain,
  sugarloaf,
  christ,
  palm,
  dome,
  hills,
  snowPeak,
  needle,
  gabled,
  temple,
  mosque,
  onion,
  suspension,
  obelisk,
  acacia,
  minaret,
  pagoda,
  marinaBay,
  stupa,
}

enum _Ground { grass, desert, snow }

/// Something standing near an airport. [along] is distance past the airport
/// in the direction of the runway, [across] is to the side. Sizes in units.
class _Feature {
  final _Lm kind;
  final double along;
  final double across;
  final double w;
  final double h;
  final Color color;
  final int seed;

  const _Feature(
      this.kind, this.along, this.across, this.w, this.h, this.color, this.seed);
}

_Ground _groundFor(String city) {
  switch (city) {
    case 'Cairo':
    case 'Dubai':
    case 'Marrakesh':
    case 'Lima':
    case 'Nairobi':
      return _Ground.desert;
    case 'Reykjavik':
      return _Ground.snow;
    default:
      return _Ground.grass;
  }
}

String _welcomeLine(String city) {
  switch (city) {
    case 'New York':
      return 'Welcome to New York! Look at all those skyscrapers, and there\'s '
          'the Statue of Liberty!';
    case 'Paris':
      return 'Bienvenue à Paris! You can see the Eiffel Tower from the runway!';
    case 'Rome':
      return 'Benvenuti a Roma! That\'s the Colosseum over there!';
    case 'Reykjavik':
      return 'Welcome to Iceland! Brrr, snowy mountains everywhere. Wrap up '
          'warm, everyone!';
    case 'Cairo':
      return 'Welcome to Egypt! Look out the window, it\'s the pyramids!';
    case 'Dubai':
      return 'Welcome to Dubai! See that super tall tower? That\'s the Burj '
          'Khalifa!';
    case 'Mumbai':
      return 'Welcome to Mumbai, India! Such a big, busy city!';
    case 'Los Angeles':
      return 'Welcome to Los Angeles! Palm trees, sunshine and hills!';
    case 'Rio de Janeiro':
      return 'Bem-vindos ao Rio! There\'s Sugarloaf Mountain, and the big '
          'statue up on the hill!';
    case 'Cape Town':
      return 'Welcome to Cape Town! That flat mountain is Table Mountain!';
    case 'Tokyo':
      return 'Welcome to Tokyo! Look, the red Tokyo Tower, and Mount Fuji in '
          'the distance!';
    case 'Sydney':
      return 'G\'day and welcome to Sydney! There\'s the Opera House and the '
          'Harbour Bridge!';
    case 'Madrid':
      return '¡Bienvenidos a Madrid! Welcome to Spain!';
    case 'Berlin':
      return 'Willkommen in Berlin! See the TV tower with the big ball?';
    case 'Amsterdam':
      return 'Welkom in Amsterdam! Look at the tall, skinny canal houses!';
    case 'Athens':
      return 'Welcome to Athens! That\'s an ancient temple up on the hill!';
    case 'Istanbul':
      return 'Welcome to Istanbul! Look at the domes and the tall thin towers!';
    case 'Moscow':
      return 'Welcome to Moscow! Look at those colourful onion-shaped domes!';
    case 'Oslo':
      return 'Velkommen til Oslo! Welcome to Norway!';
    case 'Dublin':
      return 'Welcome to Dublin! Look how green the hills are!';
    case 'Toronto':
      return 'Welcome to Toronto, Canada! That super tall tower is the CN Tower!';
    case 'Mexico City':
      return '¡Bienvenidos a México! Look, a pyramid, and a volcano far away!';
    case 'Miami':
      return 'Welcome to Miami! Sunshine, palm trees and tall buildings!';
    case 'San Francisco':
      return 'Welcome to San Francisco! There\'s the big red bridge!';
    case 'Honolulu':
      return 'Aloha! Welcome to Hawaii! Palm trees everywhere!';
    case 'Buenos Aires':
      return '¡Bienvenidos a Buenos Aires! See the tall white obelisk?';
    case 'Lima':
      return '¡Bienvenidos a Lima! Welcome to Peru!';
    case 'Nairobi':
      return 'Karibu! Welcome to Nairobi, Kenya! Look at those flat-topped trees!';
    case 'Marrakesh':
      return 'Welcome to Marrakesh, Morocco! Snowy mountains behind the desert!';
    case 'Beijing':
      return 'Welcome to Beijing, China! Look at the pagoda!';
    case 'Hong Kong':
      return 'Welcome to Hong Kong! So many skyscrapers squeezed in by the hills!';
    case 'Singapore':
      return 'Welcome to Singapore! See the hotel with a ship on top?';
    case 'Bangkok':
      return 'Welcome to Bangkok, Thailand! Look at the pointy golden temples!';
    case 'Seoul':
      return 'Welcome to Seoul, South Korea! There\'s a tower up on the mountain!';
    case 'Delhi':
      return 'Welcome to Delhi, India! Look at the beautiful domes!';
    case 'Auckland':
      return 'Kia ora! Welcome to Auckland, New Zealand! See the Sky Tower?';
    case 'Bali':
      return 'Welcome to Bali! Palm trees, temples and volcanoes!';
    default:
      return 'Welcome! Thank you for flying with us!';
  }
}

List<_Feature> _sceneryFor(String city, math.Random r) {
  final f = <_Feature>[];

  void blocks(int n, double minH, double maxH, List<Color> colors,
      {double from = 3.2,
      double to = 8.0,
      double spread = 2.6,
      double minW = 0.14,
      double maxW = 0.32}) {
    for (var i = 0; i < n; i++) {
      f.add(_Feature(
        _Lm.box,
        from + r.nextDouble() * (to - from),
        (r.nextDouble() * 2 - 1) * spread,
        minW + r.nextDouble() * (maxW - minW),
        minH + r.nextDouble() * (maxH - minH),
        colors[r.nextInt(colors.length)],
        r.nextInt(100000),
      ));
    }
  }

  void palms(int n) {
    for (var i = 0; i < n; i++) {
      final side = r.nextBool() ? 1.0 : -1.0;
      f.add(_Feature(
        _Lm.palm,
        -1.0 + r.nextDouble() * 4.5,
        side * (0.45 + r.nextDouble() * 1.4),
        0.18,
        0.22 + r.nextDouble() * 0.1,
        const Color(0xFF2F8F46),
        r.nextInt(100000),
      ));
    }
  }

  const glass = [Color(0xFF7F95AD), Color(0xFF9AACBF), Color(0xFF5E6E80)];
  const stone = [Color(0xFFB7A994), Color(0xFF9C8F7B), Color(0xFFC9BCA6)];
  const cream = [Color(0xFFE6DCC6), Color(0xFFD8CCB2), Color(0xFFEFE6D2)];
  const terracotta = [Color(0xFFD08A5B), Color(0xFFE0A877), Color(0xFFC57A4D)];
  const sand = [Color(0xFFD9C29A), Color(0xFFCBB287), Color(0xFFE2D0AC)];
  const colourful = [
    Color(0xFFE85D5D),
    Color(0xFF3F7FD6),
    Color(0xFFF2C14E),
    Color(0xFFF2F2F2),
    Color(0xFF4CAF7A),
  ];
  const mixed = [
    Color(0xFFD9CDB8),
    Color(0xFFB8C4CF),
    Color(0xFFE3B88F),
    Color(0xFF9FA8B2),
  ];

  switch (city) {
    case 'New York':
      blocks(55, 0.6, 2.2, glass + stone);
      f.add(const _Feature(_Lm.empire, 5.6, 0.4, 0.5, 3.0, Color(0xFFBDB2A0), 1));
      f.add(const _Feature(_Lm.liberty, 2.6, -2.6, 0.3, 0.9, Color(0xFF6FB3A0), 2));
      break;
    case 'Paris':
      blocks(40, 0.22, 0.4, cream, spread: 3.0);
      f.add(const _Feature(_Lm.eiffel, 4.6, 1.0, 0.9, 2.4, Color(0xFF6B5A48), 3));
      break;
    case 'Rome':
      blocks(35, 0.18, 0.36, terracotta + cream, spread: 3.0);
      f.add(const _Feature(_Lm.colosseum, 4.2, -0.9, 1.3, 0.45, Color(0xFFCDB58E), 4));
      f.add(const _Feature(_Lm.dome, 6.0, 1.3, 0.7, 0.8, Color(0xFFE2D6BE), 5));
      break;
    case 'Reykjavik':
      blocks(22, 0.12, 0.24, colourful, spread: 2.4, maxW: 0.22);
      f.add(const _Feature(_Lm.church, 4.6, 0.3, 0.6, 1.1, Color(0xFFE4E6E8), 6));
      f.add(const _Feature(_Lm.snowPeak, 14, -4, 7, 2.4, Color(0xFF6B7A8C), 7));
      f.add(const _Feature(_Lm.snowPeak, 16, 3, 9, 3.0, Color(0xFF5F6E80), 8));
      break;
    case 'Cairo':
      blocks(30, 0.15, 0.4, sand, spread: 2.8);
      f.add(const _Feature(_Lm.pyramid, 8.0, -3.0, 2.2, 1.4, Color(0xFFD9B26F), 9));
      f.add(const _Feature(_Lm.pyramid, 9.5, -1.4, 2.0, 1.25, Color(0xFFD4AC68), 10));
      f.add(const _Feature(_Lm.pyramid, 10.5, 0.2, 1.1, 0.7, Color(0xFFCFA562), 11));
      palms(6);
      break;
    case 'Dubai':
      blocks(28, 0.6, 1.8, glass, spread: 2.8);
      f.add(const _Feature(_Lm.burj, 6.0, 0.6, 0.55, 5.0, Color(0xFFA9BCCF), 12));
      f.add(const _Feature(_Lm.sail, 3.8, -2.8, 0.5, 1.3, Color(0xFFF4F6F8), 13));
      palms(5);
      break;
    case 'Mumbai':
      blocks(50, 0.25, 1.1, mixed, spread: 3.0);
      f.add(const _Feature(_Lm.dome, 3.6, -1.6, 0.7, 0.6, Color(0xFFD9B98F), 14));
      palms(8);
      break;
    case 'Los Angeles':
      blocks(30, 0.15, 0.3, mixed, spread: 3.0);
      blocks(10, 0.8, 1.6, glass, from: 6.5, to: 7.5, spread: 0.8);
      f.add(const _Feature(_Lm.hills, 13, 0, 14, 1.6, Color(0xFF8C8A5E), 15));
      palms(16);
      break;
    case 'Rio de Janeiro':
      blocks(35, 0.3, 0.8, cream + mixed, spread: 3.0);
      f.add(const _Feature(_Lm.sugarloaf, 6.5, -2.6, 1.6, 2.0, Color(0xFF4F6B4A), 16));
      f.add(const _Feature(_Lm.christ, 11, 2.0, 4.0, 2.8, Color(0xFF3F5E3E), 17));
      palms(10);
      break;
    case 'Cape Town':
      blocks(30, 0.2, 0.6, cream + glass, spread: 2.8);
      f.add(const _Feature(_Lm.tableMountain, 13, 0, 12, 2.6, Color(0xFF6E7466), 18));
      break;
    case 'Tokyo':
      blocks(65, 0.4, 1.6, glass + mixed, spread: 3.0);
      f.add(const _Feature(_Lm.tokyoTower, 4.8, 0.8, 0.8, 2.3, Color(0xFFE8432F), 19));
      f.add(const _Feature(_Lm.snowPeak, 26, -5, 16, 5.0, Color(0xFF7A8BA3), 20));
      break;
    case 'Sydney':
      blocks(35, 0.5, 1.5, glass + cream, from: 5.5, to: 8.5, spread: 2.6);
      f.add(const _Feature(_Lm.opera, 4.0, -1.4, 1.3, 0.55, Color(0xFFF1EFE8), 21));
      f.add(const _Feature(_Lm.bridge, 5.0, 1.6, 2.6, 0.75, Color(0xFF7D8590), 22));
      break;
    case 'Madrid':
      blocks(40, 0.2, 0.5, terracotta + cream, spread: 3.0);
      f.add(const _Feature(_Lm.dome, 4.5, -1.0, 0.9, 0.8, Color(0xFFE8DCC4), 24));
      break;
    case 'Berlin':
      blocks(40, 0.3, 0.7, stone + glass, spread: 3.0);
      f.add(const _Feature(_Lm.needle, 5.5, 0.6, 0.3, 3.0, Color(0xFFB8BEC6), 25));
      break;
    case 'Amsterdam':
      for (var i = 0; i < 40; i++) {
        f.add(_Feature(_Lm.gabled, 3.2 + r.nextDouble() * 4.5,
            (r.nextDouble() * 2 - 1) * 2.8, 0.14 + r.nextDouble() * 0.08,
            0.3 + r.nextDouble() * 0.2, colourful[r.nextInt(colourful.length)],
            r.nextInt(100000)));
      }
      break;
    case 'Athens':
      blocks(40, 0.12, 0.3, cream, spread: 3.0);
      f.add(const _Feature(_Lm.hills, 6.5, -0.8, 3.0, 0.7, Color(0xFFB9A57E), 26));
      f.add(const _Feature(_Lm.temple, 6.5, -0.8, 1.0, 0.55, Color(0xFFEDE3CC), 27));
      break;
    case 'Istanbul':
      blocks(35, 0.2, 0.5, cream + terracotta, spread: 3.0);
      f.add(const _Feature(_Lm.mosque, 5.0, -0.8, 1.4, 1.2, Color(0xFFCFC6B6), 28));
      f.add(const _Feature(_Lm.mosque, 7.0, 1.6, 1.1, 1.0, Color(0xFFD9CDB8), 29));
      break;
    case 'Moscow':
      blocks(40, 0.3, 0.8, stone + mixed, spread: 3.0);
      f.add(const _Feature(_Lm.onion, 4.8, 0.2, 1.2, 1.3, Color(0xFFD2473A), 30));
      break;
    case 'Oslo':
      for (var i = 0; i < 25; i++) {
        f.add(_Feature(_Lm.gabled, 3.2 + r.nextDouble() * 4.0,
            (r.nextDouble() * 2 - 1) * 2.6, 0.18, 0.22 + r.nextDouble() * 0.12,
            colourful[r.nextInt(colourful.length)], r.nextInt(100000)));
      }
      f.add(const _Feature(_Lm.hills, 13, 0, 14, 1.8, Color(0xFF4E6B4E), 31));
      break;
    case 'Dublin':
      for (var i = 0; i < 30; i++) {
        f.add(_Feature(_Lm.gabled, 3.2 + r.nextDouble() * 4.0,
            (r.nextDouble() * 2 - 1) * 2.8, 0.2, 0.22 + r.nextDouble() * 0.12,
            mixed[r.nextInt(mixed.length)], r.nextInt(100000)));
      }
      f.add(const _Feature(_Lm.hills, 12, 0, 14, 1.4, Color(0xFF3F8F4A), 32));
      break;
    case 'Toronto':
      blocks(45, 0.6, 1.8, glass, spread: 2.8);
      f.add(const _Feature(_Lm.needle, 5.0, -1.0, 0.35, 4.2, Color(0xFFB9BDC2), 33));
      break;
    case 'Mexico City':
      blocks(45, 0.2, 0.7, mixed + terracotta, spread: 3.0);
      f.add(const _Feature(_Lm.pyramid, 5.0, -2.2, 1.6, 0.8, Color(0xFF9C8A70), 34));
      f.add(const _Feature(_Lm.snowPeak, 22, 3, 12, 3.5, Color(0xFF6E7A8A), 35));
      break;
    case 'Miami':
      blocks(35, 0.6, 1.6, glass + cream, spread: 2.6);
      palms(18);
      break;
    case 'San Francisco':
      f.add(const _Feature(_Lm.hills, 9, 1.0, 8, 1.2, Color(0xFF8A9A6A), 36));
      blocks(30, 0.3, 1.2, cream + glass, from: 5, to: 8.5, spread: 1.6);
      f.add(const _Feature(_Lm.suspension, 4.5, -2.4, 3.2, 1.2, Color(0xFFC0392B), 37));
      break;
    case 'Honolulu':
      f.add(const _Feature(_Lm.hills, 9, -2.0, 6, 1.4, Color(0xFF6E7F4E), 38));
      blocks(20, 0.4, 1.0, cream + glass, spread: 2.2);
      palms(22);
      break;
    case 'Buenos Aires':
      blocks(50, 0.3, 0.8, stone + cream, spread: 3.0);
      f.add(const _Feature(_Lm.obelisk, 4.8, 0.3, 0.22, 1.6, Color(0xFFEDEBE6), 39));
      break;
    case 'Lima':
      blocks(40, 0.15, 0.5, sand + mixed, spread: 3.0);
      f.add(const _Feature(_Lm.hills, 12, 0, 14, 1.6, Color(0xFFB29E7A), 40));
      break;
    case 'Nairobi':
      blocks(20, 0.4, 1.2, glass + mixed, from: 6, to: 8, spread: 1.4);
      for (var i = 0; i < 12; i++) {
        f.add(_Feature(_Lm.acacia, 0.5 + r.nextDouble() * 5,
            (r.nextBool() ? 1 : -1) * (0.6 + r.nextDouble() * 2.4), 0.5, 0.3,
            const Color(0xFF5E7A34), r.nextInt(100000)));
      }
      break;
    case 'Marrakesh':
      blocks(40, 0.12, 0.28, terracotta + sand, spread: 3.0);
      f.add(const _Feature(_Lm.minaret, 4.6, 0.4, 0.25, 1.1, Color(0xFFC98A5E), 41));
      f.add(const _Feature(_Lm.snowPeak, 18, -2, 16, 3.2, Color(0xFF7D7A86), 42));
      palms(8);
      break;
    case 'Beijing':
      blocks(45, 0.4, 1.2, glass + stone, spread: 3.0);
      f.add(const _Feature(_Lm.pagoda, 4.4, -1.0, 0.8, 1.4, Color(0xFFB8402E), 43));
      break;
    case 'Hong Kong':
      f.add(const _Feature(_Lm.hills, 11, 0, 14, 2.6, Color(0xFF3F6B45), 44));
      blocks(70, 0.9, 2.6, glass, from: 4, to: 8, spread: 2.8, maxW: 0.24);
      break;
    case 'Singapore':
      blocks(40, 0.6, 1.8, glass, spread: 2.8);
      f.add(const _Feature(_Lm.marinaBay, 4.2, -1.2, 1.6, 1.6, Color(0xFFD7DCE1), 45));
      palms(8);
      break;
    case 'Bangkok':
      blocks(40, 0.4, 1.4, glass + mixed, from: 5, to: 8.5, spread: 2.8);
      f.add(const _Feature(_Lm.stupa, 3.6, -1.4, 0.7, 1.4, Color(0xFFE2B547), 46));
      f.add(const _Feature(_Lm.stupa, 3.9, -0.6, 0.5, 1.0, Color(0xFFE8C468), 47));
      palms(8);
      break;
    case 'Seoul':
      f.add(const _Feature(_Lm.hills, 9, 1.5, 5, 1.5, Color(0xFF3F6B45), 48));
      f.add(const _Feature(_Lm.needle, 9, 1.5, 0.25, 2.8, Color(0xFFE8E8E8), 49));
      blocks(50, 0.5, 1.6, glass + mixed, spread: 3.0);
      break;
    case 'Delhi':
      blocks(40, 0.15, 0.5, mixed + sand, spread: 3.0);
      f.add(const _Feature(_Lm.mosque, 4.8, -0.5, 1.4, 1.1, Color(0xFFC0705A), 50));
      f.add(const _Feature(_Lm.dome, 6.5, 1.6, 0.9, 0.8, Color(0xFFEDE6DA), 51));
      break;
    case 'Auckland':
      f.add(const _Feature(_Lm.hills, 10, -1.5, 5, 1.0, Color(0xFF4A7A45), 52));
      blocks(35, 0.4, 1.2, glass + cream, spread: 2.6);
      f.add(const _Feature(_Lm.needle, 5.2, 0.6, 0.3, 3.4, Color(0xFFC8CCD0), 53));
      break;
    case 'Bali':
      f.add(const _Feature(_Lm.snowPeak, 20, -3, 12, 3.4, Color(0xFF5C6E5A), 54));
      blocks(15, 0.12, 0.25, terracotta, spread: 2.6);
      f.add(const _Feature(_Lm.pagoda, 4.2, 1.2, 0.6, 1.0, Color(0xFF4A3B33), 55));
      palms(26);
      break;
    default:
      // A small town next to an emergency airport.
      blocks(14, 0.12, 0.3, mixed, spread: 2.2, maxW: 0.24);
      f.add(const _Feature(_Lm.hills, 12, 0, 12, 1.0, Color(0xFF7D8A63), 23));
  }
  return f;
}

// ---- landmark drawing (shared by the cockpit and the walking scenes) -------

Color _hazed(Color c, double haze) =>
    Color.lerp(c, const Color(0xFFB9C6D2), haze * 0.75)!;

void _drawLandmark(
    Canvas canvas, _Feature f, Offset b, double k, double haze) {
  final w = f.w * k;
  final h = f.h * k;
  if (h < 0.8) return;
  final col = _hazed(f.color, haze);
  final fill = Paint()..color = col;
  final shade = Paint()..color = _hazed(Color.lerp(f.color, Colors.black, 0.3)!, haze);
  final light = Paint()..color = _hazed(Color.lerp(f.color, Colors.white, 0.3)!, haze);

  switch (f.kind) {
    case _Lm.box:
      final rect = Rect.fromLTWH(b.dx - w / 2, b.dy - h, w, h);
      canvas.drawRect(rect, fill);
      canvas.drawRect(
          Rect.fromLTWH(rect.right - w * 0.28, rect.top, w * 0.28, h), shade);
      if (w > 10 && h > 18) {
        final win = Paint()
          ..color = _hazed(
              _hash(f.seed) > 0.5
                  ? const Color(0xFFFFE7A3)
                  : const Color(0xFFCFE3F2),
              haze);
        final rows = math.min(14, (h / 7).floor());
        final cols = math.min(5, (w * 0.72 / 6).floor());
        for (var rI = 0; rI < rows; rI++) {
          for (var cI = 0; cI < cols; cI++) {
            if (_hash(f.seed + rI * 13 + cI * 7) < 0.35) continue;
            canvas.drawRect(
              Rect.fromLTWH(
                rect.left + w * 0.08 + cI * (w * 0.64 / math.max(1, cols)),
                rect.top + h * 0.05 + rI * (h * 0.9 / rows),
                math.max(1.0, w * 0.06),
                math.max(1.0, h * 0.9 / rows * 0.45),
              ),
              win,
            );
          }
        }
      }
      break;

    case _Lm.empire:
      final tiers = [
        [1.0, 0.0, 0.55],
        [0.72, 0.55, 0.72],
        [0.5, 0.72, 0.84],
        [0.3, 0.84, 0.9],
      ];
      for (final t in tiers) {
        final tw = w * t[0];
        canvas.drawRect(
          Rect.fromLTRB(b.dx - tw / 2, b.dy - h * t[2], b.dx + tw / 2,
              b.dy - h * t[1]),
          fill,
        );
        canvas.drawRect(
          Rect.fromLTRB(b.dx + tw * 0.2, b.dy - h * t[2], b.dx + tw / 2,
              b.dy - h * t[1]),
          shade,
        );
      }
      canvas.drawLine(Offset(b.dx, b.dy - h * 0.9), Offset(b.dx, b.dy - h),
          shade..strokeWidth = math.max(1.0, w * 0.06));
      break;

    case _Lm.liberty:
      final ped = Path()
        ..moveTo(b.dx - w * 0.5, b.dy)
        ..lineTo(b.dx + w * 0.5, b.dy)
        ..lineTo(b.dx + w * 0.32, b.dy - h * 0.45)
        ..lineTo(b.dx - w * 0.32, b.dy - h * 0.45)
        ..close();
      canvas.drawPath(ped, Paint()..color = _hazed(const Color(0xFFB9AE98), haze));
      final body = Path()
        ..moveTo(b.dx - w * 0.22, b.dy - h * 0.45)
        ..lineTo(b.dx + w * 0.22, b.dy - h * 0.45)
        ..lineTo(b.dx + w * 0.1, b.dy - h * 0.82)
        ..lineTo(b.dx - w * 0.1, b.dy - h * 0.82)
        ..close();
      canvas.drawPath(body, fill);
      canvas.drawCircle(Offset(b.dx, b.dy - h * 0.85), w * 0.09, fill);
      final arm = Paint()
        ..color = col
        ..strokeWidth = math.max(1.0, w * 0.08)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(b.dx + w * 0.1, b.dy - h * 0.78),
          Offset(b.dx + w * 0.2, b.dy - h * 0.98), arm);
      canvas.drawCircle(Offset(b.dx + w * 0.2, b.dy - h), w * 0.08,
          Paint()..color = const Color(0xFFFFC93C));
      break;

    case _Lm.eiffel:
    case _Lm.tokyoTower:
      final tower = Path()
        ..fillType = PathFillType.evenOdd
        ..moveTo(b.dx - w / 2, b.dy)
        ..quadraticBezierTo(
            b.dx - w * 0.12, b.dy - h * 0.35, b.dx - w * 0.05, b.dy - h * 0.8)
        ..lineTo(b.dx, b.dy - h)
        ..lineTo(b.dx + w * 0.05, b.dy - h * 0.8)
        ..quadraticBezierTo(
            b.dx + w * 0.12, b.dy - h * 0.35, b.dx + w / 2, b.dy)
        ..close()
        ..addOval(Rect.fromCenter(
            center: Offset(b.dx, b.dy),
            width: w * 0.5,
            height: h * 0.3));
      canvas.drawPath(tower, fill);
      final lattice = Paint()
        ..color = _hazed(Color.lerp(f.color, Colors.black, 0.4)!, haze)
        ..strokeWidth = math.max(0.6, w * 0.015);
      for (var i = 1; i < 6; i++) {
        final y = b.dy - h * i / 7;
        final half = w * 0.5 * (1 - i / 7) * 0.9;
        canvas.drawLine(
            Offset(b.dx - half, y), Offset(b.dx + half, y), lattice);
      }
      // Viewing platforms.
      for (final level in [0.28, 0.55]) {
        final half = w * 0.5 * (1 - level) * 0.75;
        canvas.drawRect(
          Rect.fromLTRB(b.dx - half, b.dy - h * level - h * 0.02,
              b.dx + half, b.dy - h * level + h * 0.01),
          f.kind == _Lm.tokyoTower
              ? (Paint()..color = _hazed(Colors.white, haze))
              : shade,
        );
      }
      break;

    case _Lm.colosseum:
      final colBody = Rect.fromLTWH(b.dx - w / 2, b.dy - h, w, h);
      final outline = Path()
        ..moveTo(colBody.left, colBody.bottom)
        ..lineTo(colBody.left, colBody.top + h * 0.25)
        ..lineTo(colBody.left + w * 0.3, colBody.top)
        ..lineTo(colBody.right, colBody.top)
        ..lineTo(colBody.right, colBody.bottom)
        ..close();
      canvas.drawPath(outline, fill);
      final arch = Paint()..color = _hazed(const Color(0xFF6E5A3E), haze);
      for (var row = 0; row < 3; row++) {
        final y = colBody.bottom - h * (0.12 + row * 0.3);
        for (var i = 0; i < 9; i++) {
          final x = colBody.left + w * (0.06 + i * 0.105);
          if (row == 2 && x < colBody.left + w * 0.35) continue;
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTWH(x, y - h * 0.18, w * 0.06, h * 0.18),
              topLeft: Radius.circular(w * 0.03),
              topRight: Radius.circular(w * 0.03),
            ),
            arch,
          );
        }
      }
      break;

    case _Lm.pyramid:
      canvas.drawPath(
        Path()
          ..moveTo(b.dx - w / 2, b.dy)
          ..lineTo(b.dx - w * 0.08, b.dy - h)
          ..lineTo(b.dx + w * 0.12, b.dy)
          ..close(),
        light,
      );
      canvas.drawPath(
        Path()
          ..moveTo(b.dx + w * 0.12, b.dy)
          ..lineTo(b.dx - w * 0.08, b.dy - h)
          ..lineTo(b.dx + w / 2, b.dy)
          ..close(),
        shade,
      );
      break;

    case _Lm.burj:
      final steps = [1.0, 0.8, 0.62, 0.46, 0.32, 0.2, 0.1];
      for (var i = 0; i < steps.length; i++) {
        final tw = w * steps[i];
        final top = h * (0.12 + i * 0.11);
        final bottom = i == 0 ? 0.0 : h * (0.12 + (i - 1) * 0.11);
        canvas.drawRect(
          Rect.fromLTRB(b.dx - tw / 2, b.dy - top, b.dx + tw / 2, b.dy - bottom),
          fill,
        );
        canvas.drawRect(
          Rect.fromLTRB(b.dx, b.dy - top, b.dx + tw / 2, b.dy - bottom),
          light,
        );
      }
      canvas.drawLine(Offset(b.dx, b.dy - h * 0.78), Offset(b.dx, b.dy - h),
          light..strokeWidth = math.max(1.0, w * 0.04));
      break;

    case _Lm.sail:
      final sail = Path()
        ..moveTo(b.dx - w * 0.4, b.dy)
        ..lineTo(b.dx - w * 0.4, b.dy - h)
        ..quadraticBezierTo(b.dx + w * 0.7, b.dy - h * 0.55, b.dx + w * 0.3, b.dy)
        ..close();
      canvas.drawPath(sail, fill);
      canvas.drawLine(Offset(b.dx - w * 0.4, b.dy), Offset(b.dx - w * 0.4, b.dy - h * 1.06),
          shade..strokeWidth = math.max(1.0, w * 0.06));
      break;

    case _Lm.church:
      // Stepped wings rising up to a tall pointed tower.
      for (var i = 0; i < 4; i++) {
        final half = w * (0.5 - i * 0.1);
        final top = h * (0.25 + i * 0.12);
        canvas.drawRect(
            Rect.fromLTRB(b.dx - half, b.dy - top, b.dx + half, b.dy), fill);
      }
      canvas.drawPath(
        Path()
          ..moveTo(b.dx - w * 0.1, b.dy - h * 0.6)
          ..lineTo(b.dx, b.dy - h)
          ..lineTo(b.dx + w * 0.1, b.dy - h * 0.6)
          ..close(),
        fill,
      );
      canvas.drawRect(
          Rect.fromLTRB(b.dx, b.dy - h * 0.6, b.dx + w * 0.1, b.dy), shade);
      break;

    case _Lm.opera:
      canvas.drawRect(
        Rect.fromLTWH(b.dx - w / 2, b.dy - h * 0.18, w, h * 0.18),
        Paint()..color = _hazed(const Color(0xFFC9A98A), haze),
      );
      for (var i = 0; i < 4; i++) {
        final sx = b.dx - w * 0.42 + i * w * 0.24;
        final sh = h * (0.55 + i * 0.15);
        final shell = Path()
          ..moveTo(sx, b.dy - h * 0.18)
          ..quadraticBezierTo(sx + w * 0.02, b.dy - sh, sx + w * 0.2, b.dy - sh)
          ..quadraticBezierTo(sx + w * 0.14, b.dy - h * 0.4, sx + w * 0.24,
              b.dy - h * 0.18)
          ..close();
        canvas.drawPath(shell, fill);
        canvas.drawPath(
          shell,
          Paint()
            ..color = _hazed(const Color(0xFFBFC3C7), haze)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(0.6, w * 0.008),
        );
      }
      break;

    case _Lm.bridge:
      final steel = Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, w * 0.02);
      final deckY = b.dy - h * 0.4;
      canvas.drawPath(
        Path()
          ..moveTo(b.dx - w * 0.42, deckY + h * 0.2)
          ..quadraticBezierTo(b.dx, b.dy - h * 1.35, b.dx + w * 0.42, deckY + h * 0.2),
        steel,
      );
      canvas.drawLine(Offset(b.dx - w / 2, deckY), Offset(b.dx + w / 2, deckY),
          steel..strokeWidth = math.max(1.5, w * 0.025));
      for (final side in [-1.0, 1.0]) {
        canvas.drawRect(
          Rect.fromLTWH(b.dx + side * w * 0.45 - w * 0.03, b.dy - h * 0.7,
              w * 0.06, h * 0.7),
          Paint()..color = _hazed(const Color(0xFFB8AC94), haze),
        );
      }
      for (var i = -6; i <= 6; i++) {
        final x = b.dx + i * w * 0.06;
        final t = x - b.dx;
        final archY = deckY + h * 0.2 -
            (1 - (t / (w * 0.42)) * (t / (w * 0.42))) * (h * 0.875);
        canvas.drawLine(Offset(x, archY), Offset(x, deckY),
            Paint()
              ..color = col
              ..strokeWidth = math.max(0.5, w * 0.006));
      }
      break;

    case _Lm.tableMountain:
      final m = Path()
        ..moveTo(b.dx - w / 2, b.dy)
        ..lineTo(b.dx - w * 0.3, b.dy - h * 0.92)
        ..quadraticBezierTo(b.dx - w * 0.27, b.dy - h, b.dx - w * 0.22, b.dy - h)
        ..lineTo(b.dx + w * 0.24, b.dy - h)
        ..quadraticBezierTo(b.dx + w * 0.29, b.dy - h, b.dx + w * 0.32, b.dy - h * 0.9)
        ..lineTo(b.dx + w / 2, b.dy)
        ..close();
      canvas.drawPath(m, fill);
      // The "tablecloth" cloud that pours over the top.
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(b.dx, b.dy - h * 0.98), width: w * 0.5, height: h * 0.12),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1.0, h * 0.04)),
      );
      break;

    case _Lm.sugarloaf:
      canvas.drawPath(
        Path()
          ..moveTo(b.dx - w / 2, b.dy)
          ..quadraticBezierTo(b.dx - w * 0.45, b.dy - h * 1.15, b.dx + w * 0.05, b.dy - h)
          ..quadraticBezierTo(b.dx + w * 0.45, b.dy - h * 0.8, b.dx + w / 2, b.dy)
          ..close(),
        fill,
      );
      break;

    case _Lm.christ:
      canvas.drawPath(
        Path()
          ..moveTo(b.dx - w / 2, b.dy)
          ..quadraticBezierTo(b.dx - w * 0.1, b.dy - h * 1.05, b.dx, b.dy - h * 0.93)
          ..quadraticBezierTo(b.dx + w * 0.15, b.dy - h * 0.85, b.dx + w / 2, b.dy)
          ..close(),
        fill,
      );
      final white = Paint()
        ..color = _hazed(const Color(0xFFF2F2EE), haze)
        ..strokeWidth = math.max(1.0, h * 0.02)
        ..strokeCap = StrokeCap.round;
      final top = Offset(b.dx, b.dy - h * 0.93);
      canvas.drawLine(top, top.translate(0, -h * 0.12), white);
      canvas.drawLine(top.translate(-h * 0.05, -h * 0.09),
          top.translate(h * 0.05, -h * 0.09), white);
      canvas.drawCircle(top.translate(0, -h * 0.13), h * 0.012, white);
      break;

    case _Lm.palm:
      final trunk = Paint()
        ..color = _hazed(const Color(0xFF7A5A3A), haze)
        ..strokeWidth = math.max(1.0, w * 0.08)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final topP = Offset(b.dx + w * 0.15, b.dy - h);
      canvas.drawPath(
        Path()
          ..moveTo(b.dx, b.dy)
          ..quadraticBezierTo(b.dx - w * 0.1, b.dy - h * 0.5, topP.dx, topP.dy),
        trunk,
      );
      final leaf = Paint()
        ..color = col
        ..strokeWidth = math.max(1.0, w * 0.1)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 6; i++) {
        final a = -math.pi + i * math.pi / 5;
        final end = topP + Offset(math.cos(a), math.sin(a) * 0.5 + 0.35) * w * 1.1;
        canvas.drawPath(
          Path()
            ..moveTo(topP.dx, topP.dy)
            ..quadraticBezierTo(
                (topP.dx + end.dx) / 2, topP.dy - w * 0.25, end.dx, end.dy),
          leaf,
        );
      }
      break;

    case _Lm.dome:
      canvas.drawRect(
          Rect.fromLTWH(b.dx - w / 2, b.dy - h * 0.45, w, h * 0.45), fill);
      canvas.drawRect(
          Rect.fromLTWH(b.dx + w * 0.2, b.dy - h * 0.45, w * 0.3, h * 0.45), shade);
      canvas.drawArc(
        Rect.fromCenter(
            center: Offset(b.dx, b.dy - h * 0.45), width: w * 0.62, height: h * 0.8),
        math.pi,
        math.pi,
        true,
        light,
      );
      canvas.drawRect(
          Rect.fromLTWH(b.dx - w * 0.04, b.dy - h, w * 0.08, h * 0.17), light);
      break;

    case _Lm.hills:
      final hills = Path()..moveTo(b.dx - w / 2, b.dy);
      for (var i = 0; i <= 8; i++) {
        final x = b.dx - w / 2 + w * i / 8;
        final y = b.dy - h * (0.45 + 0.55 * _hash(f.seed + i));
        hills.quadraticBezierTo(x - w / 16, y - h * 0.15, x, y);
      }
      hills
        ..lineTo(b.dx + w / 2, b.dy)
        ..close();
      canvas.drawPath(hills, fill);
      break;

    case _Lm.needle:
      // Tall thin tower with a round pod, like a TV tower.
      canvas.drawRect(
          Rect.fromLTWH(b.dx - w * 0.12, b.dy - h * 0.92, w * 0.24, h * 0.92),
          fill);
      canvas.drawRect(
          Rect.fromLTWH(b.dx, b.dy - h * 0.92, w * 0.12, h * 0.92), shade);
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(b.dx, b.dy - h * 0.68), width: w, height: w * 0.8),
        light,
      );
      canvas.drawRect(
          Rect.fromLTWH(b.dx - w * 0.5, b.dy - h * 0.66, w, w * 0.12), shade);
      canvas.drawLine(Offset(b.dx, b.dy - h * 0.92), Offset(b.dx, b.dy - h),
          shade..strokeWidth = math.max(1.0, w * 0.05));
      break;

    case _Lm.gabled:
      final house = Path()
        ..moveTo(b.dx - w / 2, b.dy)
        ..lineTo(b.dx - w / 2, b.dy - h * 0.78)
        ..lineTo(b.dx, b.dy - h)
        ..lineTo(b.dx + w / 2, b.dy - h * 0.78)
        ..lineTo(b.dx + w / 2, b.dy)
        ..close();
      canvas.drawPath(house, fill);
      if (w > 6) {
        final win = Paint()..color = _hazed(const Color(0xFFF4F1E8), haze);
        for (var rI = 0; rI < 3; rI++) {
          for (var cI = 0; cI < 2; cI++) {
            canvas.drawRect(
              Rect.fromLTWH(b.dx - w * 0.32 + cI * w * 0.38,
                  b.dy - h * (0.22 + rI * 0.2), w * 0.24, h * 0.1),
              win,
            );
          }
        }
      }
      break;

    case _Lm.temple:
      // Columns with a triangle roof, sitting on top of a hill.
      final baseY = b.dy - h * 1.15;
      canvas.drawRect(
          Rect.fromLTWH(b.dx - w / 2, baseY, w, h * 0.12), fill);
      for (var i = 0; i < 8; i++) {
        final x = b.dx - w * 0.45 + i * w * 0.9 / 7;
        canvas.drawRect(
            Rect.fromLTWH(x - w * 0.025, baseY - h * 0.6, w * 0.05, h * 0.6),
            light);
      }
      canvas.drawRect(
          Rect.fromLTWH(b.dx - w / 2, baseY - h * 0.72, w, h * 0.12), fill);
      canvas.drawPath(
        Path()
          ..moveTo(b.dx - w / 2, baseY - h * 0.72)
          ..lineTo(b.dx, baseY - h * 0.95)
          ..lineTo(b.dx + w / 2, baseY - h * 0.72)
          ..close(),
        fill,
      );
      break;

    case _Lm.mosque:
      canvas.drawRect(
          Rect.fromLTWH(b.dx - w * 0.4, b.dy - h * 0.35, w * 0.8, h * 0.35),
          fill);
      canvas.drawArc(
        Rect.fromCenter(
            center: Offset(b.dx, b.dy - h * 0.35),
            width: w * 0.55,
            height: h * 0.6),
        math.pi,
        math.pi,
        true,
        light,
      );
      for (final sx in [-0.3, 0.3]) {
        canvas.drawArc(
          Rect.fromCenter(
              center: Offset(b.dx + w * sx, b.dy - h * 0.35),
              width: w * 0.22,
              height: h * 0.24),
          math.pi,
          math.pi,
          true,
          light,
        );
      }
      for (final mx in [-0.5, -0.42, 0.42, 0.5]) {
        canvas.drawRect(
            Rect.fromLTWH(b.dx + w * mx - w * 0.015, b.dy - h * 0.92,
                w * 0.03, h * 0.92),
            light);
        canvas.drawPath(
          Path()
            ..moveTo(b.dx + w * mx - w * 0.02, b.dy - h * 0.92)
            ..lineTo(b.dx + w * mx, b.dy - h)
            ..lineTo(b.dx + w * mx + w * 0.02, b.dy - h * 0.92)
            ..close(),
          shade,
        );
      }
      break;

    case _Lm.onion:
      const domeColours = [
        Color(0xFF2F9E6E),
        Color(0xFFE3B341),
        Color(0xFF3B6FD1),
        Color(0xFFD2473A),
        Color(0xFF7B4FB8),
      ];
      canvas.drawRect(
          Rect.fromLTWH(b.dx - w / 2, b.dy - h * 0.4, w, h * 0.4), fill);
      for (var i = 0; i < 5; i++) {
        final x = b.dx - w * 0.4 + i * w * 0.2;
        final tall = i == 2 ? 1.0 : 0.72 + (i % 2) * 0.1;
        final towerTop = b.dy - h * 0.4 - h * 0.3 * tall;
        canvas.drawRect(
            Rect.fromLTRB(x - w * 0.05, towerTop, x + w * 0.05, b.dy - h * 0.4),
            light);
        final dw = w * (i == 2 ? 0.16 : 0.12);
        final onion = Path()
          ..moveTo(x - dw / 2, towerTop)
          ..cubicTo(x - dw, towerTop - dw * 0.6, x - dw * 0.1,
              towerTop - dw * 1.1, x, towerTop - dw * 1.5)
          ..cubicTo(x + dw * 0.1, towerTop - dw * 1.1, x + dw,
              towerTop - dw * 0.6, x + dw / 2, towerTop)
          ..close();
        canvas.drawPath(
            onion, Paint()..color = _hazed(domeColours[i], haze));
      }
      break;

    case _Lm.suspension:
      // A long red bridge with two tall towers and sweeping cables.
      final red = Paint()..color = col;
      final susDeckY = b.dy - h * 0.35;
      canvas.drawRect(
          Rect.fromLTWH(b.dx - w / 2, susDeckY, w, math.max(1.5, h * 0.04)), red);
      final towers = [b.dx - w * 0.28, b.dx + w * 0.28];
      for (final tx in towers) {
        canvas.drawRect(
            Rect.fromLTWH(tx - w * 0.015, b.dy - h, w * 0.03, h), red);
      }
      final cable = Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, w * 0.004);
      canvas.drawPath(
        Path()
          ..moveTo(b.dx - w / 2, susDeckY)
          ..quadraticBezierTo(b.dx - w * 0.39, susDeckY - h * 0.1, towers[0], b.dy - h)
          ..quadraticBezierTo(b.dx, susDeckY + h * 0.4, towers[1], b.dy - h)
          ..quadraticBezierTo(b.dx + w * 0.39, susDeckY - h * 0.1, b.dx + w / 2, susDeckY),
        cable,
      );
      break;

    case _Lm.obelisk:
      canvas.drawPath(
        Path()
          ..moveTo(b.dx - w / 2, b.dy)
          ..lineTo(b.dx - w * 0.32, b.dy - h * 0.92)
          ..lineTo(b.dx, b.dy - h)
          ..lineTo(b.dx + w * 0.32, b.dy - h * 0.92)
          ..lineTo(b.dx + w / 2, b.dy)
          ..close(),
        fill,
      );
      canvas.drawPath(
        Path()
          ..moveTo(b.dx, b.dy)
          ..lineTo(b.dx, b.dy - h)
          ..lineTo(b.dx + w * 0.32, b.dy - h * 0.92)
          ..lineTo(b.dx + w / 2, b.dy)
          ..close(),
        shade,
      );
      break;

    case _Lm.acacia:
      canvas.drawLine(
        Offset(b.dx, b.dy),
        Offset(b.dx + w * 0.05, b.dy - h * 0.75),
        Paint()
          ..color = _hazed(const Color(0xFF5A4632), haze)
          ..strokeWidth = math.max(1.0, w * 0.05),
      );
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(b.dx + w * 0.05, b.dy - h * 0.82),
            width: w,
            height: h * 0.3),
        fill,
      );
      break;

    case _Lm.minaret:
      canvas.drawRect(
          Rect.fromLTWH(b.dx - w / 2, b.dy - h * 0.82, w, h * 0.82), fill);
      canvas.drawRect(
          Rect.fromLTWH(b.dx + w * 0.15, b.dy - h * 0.82, w * 0.35, h * 0.82),
          shade);
      canvas.drawRect(
          Rect.fromLTWH(b.dx - w * 0.28, b.dy - h * 0.95, w * 0.56, h * 0.13),
          fill);
      canvas.drawCircle(Offset(b.dx, b.dy - h * 0.98), w * 0.08,
          Paint()..color = _hazed(const Color(0xFFE3B341), haze));
      break;

    case _Lm.pagoda:
      for (var i = 0; i < 5; i++) {
        final level = i / 5;
        final lw = w * (1 - level * 0.6);
        final y = b.dy - h * (0.08 + level * 0.82);
        canvas.drawRect(
            Rect.fromLTWH(b.dx - lw * 0.3, y - h * 0.12, lw * 0.6, h * 0.12),
            shade);
        final roof = Path()
          ..moveTo(b.dx - lw / 2, y - h * 0.1)
          ..quadraticBezierTo(b.dx - lw * 0.3, y - h * 0.13, b.dx, y - h * 0.18)
          ..quadraticBezierTo(b.dx + lw * 0.3, y - h * 0.13, b.dx + lw / 2, y - h * 0.1)
          ..lineTo(b.dx + lw * 0.35, y - h * 0.12)
          ..lineTo(b.dx - lw * 0.35, y - h * 0.12)
          ..close();
        canvas.drawPath(roof, fill);
      }
      canvas.drawLine(Offset(b.dx, b.dy - h * 0.9), Offset(b.dx, b.dy - h),
          fill..strokeWidth = math.max(1.0, w * 0.03));
      break;

    case _Lm.marinaBay:
      // Three towers holding up a long "ship" on top.
      for (var i = 0; i < 3; i++) {
        final x = b.dx - w * 0.3 + i * w * 0.3;
        canvas.drawRect(
            Rect.fromLTWH(x - w * 0.07, b.dy - h * 0.86, w * 0.14, h * 0.86),
            fill);
        canvas.drawRect(
            Rect.fromLTWH(x + w * 0.01, b.dy - h * 0.86, w * 0.06, h * 0.86),
            shade);
      }
      canvas.drawPath(
        Path()
          ..moveTo(b.dx - w * 0.48, b.dy - h * 0.9)
          ..lineTo(b.dx + w * 0.5, b.dy - h * 0.92)
          ..lineTo(b.dx + w * 0.42, b.dy - h)
          ..lineTo(b.dx - w * 0.42, b.dy - h * 0.97)
          ..close(),
        light,
      );
      break;

    case _Lm.stupa:
      // Pointed golden temple spire.
      canvas.drawRect(
          Rect.fromLTWH(b.dx - w / 2, b.dy - h * 0.2, w, h * 0.2), shade);
      final bell = Path()
        ..moveTo(b.dx - w * 0.4, b.dy - h * 0.2)
        ..quadraticBezierTo(b.dx - w * 0.38, b.dy - h * 0.5, b.dx - w * 0.08,
            b.dy - h * 0.6)
        ..lineTo(b.dx, b.dy - h)
        ..lineTo(b.dx + w * 0.08, b.dy - h * 0.6)
        ..quadraticBezierTo(
            b.dx + w * 0.38, b.dy - h * 0.5, b.dx + w * 0.4, b.dy - h * 0.2)
        ..close();
      canvas.drawPath(bell, fill);
      canvas.drawPath(
        Path()
          ..moveTo(b.dx, b.dy - h * 0.2)
          ..lineTo(b.dx, b.dy - h)
          ..lineTo(b.dx + w * 0.08, b.dy - h * 0.6)
          ..quadraticBezierTo(
              b.dx + w * 0.38, b.dy - h * 0.5, b.dx + w * 0.4, b.dy - h * 0.2)
          ..close(),
        light,
      );
      break;

    case _Lm.snowPeak:
      final peak = Path()
        ..moveTo(b.dx - w / 2, b.dy)
        ..lineTo(b.dx - w * 0.06, b.dy - h)
        ..lineTo(b.dx + w * 0.06, b.dy - h * 0.98)
        ..lineTo(b.dx + w / 2, b.dy)
        ..close();
      canvas.drawPath(peak, fill);
      final snow = Path()
        ..moveTo(b.dx - w * 0.06, b.dy - h)
        ..lineTo(b.dx - w * 0.2, b.dy - h * 0.6)
        ..lineTo(b.dx - w * 0.1, b.dy - h * 0.66)
        ..lineTo(b.dx, b.dy - h * 0.58)
        ..lineTo(b.dx + w * 0.09, b.dy - h * 0.67)
        ..lineTo(b.dx + w * 0.2, b.dy - h * 0.6)
        ..lineTo(b.dx + w * 0.06, b.dy - h * 0.98)
        ..close();
      canvas.drawPath(snow, Paint()..color = _hazed(Colors.white, haze * 0.6));
      break;
  }
}


// ---- drawing the cockpit ----------------------------------------------------

class _CockpitPainter extends CustomPainter {
  final _FlightScreenState s;

  _CockpitPainter(this.s);

  // Set at the start of every paint.
  late double _w;
  late double _h;
  late double _cx;
  late double _horizonY;
  late double _focal;
  late double _sinH;
  late double _cosH;
  late double _altU;

  static const double _ftPerUnit = _FlightScreenState._ftPerUnit;

  @override
  void paint(Canvas canvas, Size size) {
    _w = size.width;
    _h = size.height;
    _cx = _w / 2;
    final viewBottom = _h * 0.5;
    final horizonBase = _h * 0.27;
    _focal = (_w / 2) / math.tan(_rad(38));
    final pitchDeg = (s._vs / 1500) * 6;
    _horizonY = horizonBase + math.tan(_rad(pitchDeg)) * _focal;
    final hr = _rad(s._heading);
    _sinH = math.sin(hr);
    _cosH = math.cos(hr);
    _altU = s._altFt / _ftPerUnit;

    // ---- the world outside the windscreen ----
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, _w, viewBottom));
    final shake = s._turbulence * 7 + s._hitFlash * 10;
    if (shake > 0.2) {
      canvas.translate(
        math.sin(s._time * 47) * shake,
        math.cos(s._time * 39) * shake * 0.8,
      );
    }
    canvas.translate(_cx, horizonBase);
    canvas.rotate(-_rad(s._roll));
    canvas.translate(-_cx, -horizonBase);

    _paintSky(canvas);
    _paintGround(canvas);
    _paintRunway(canvas);
    canvas0 = canvas;
    _paintObjects(canvas);
    canvas.restore();

    // Screen-space effects on the glass.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, _w, viewBottom));
    if (s._fog > 0.01) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, _w, viewBottom),
        Paint()
          ..color = const Color(0xFF4A505C).withValues(alpha: s._fog * 0.8),
      );
    }
    _paintRainOnGlass(canvas, viewBottom);
    canvas.restore();

    _paintFrame(canvas, viewBottom);
    _paintPanel(canvas, viewBottom);
    _paintYoke(canvas);

    if (s._lightning > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = const Color(0xFFE8EEFF).withValues(alpha: s._lightning * 0.55),
      );
    }
    if (s._hitFlash > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = _tomato.withValues(alpha: s._hitFlash * 0.35),
      );
    }
  }

  // ---- projection ---------------------------------------------------------

  /// Forward distance and sideways offset of a world point from our plane.
  double _fwdOf(double wx, double wy) =>
      (wx - s._x) * _sinH + (wy - s._y) * _cosH;

  double _sideOf(double wx, double wy) =>
      (wx - s._x) * _cosH - (wy - s._y) * _sinH;

  /// Screen position of a world point at height [hU] (units above ground).
  Offset _project(double wx, double wy, double hU, {double minFwd = 0.2}) {
    final fwd = math.max(minFwd, _fwdOf(wx, wy));
    final side = _sideOf(wx, wy);
    return Offset(
      _cx + side / fwd * _focal,
      _horizonY - (hU - _altU) / fwd * _focal,
    );
  }

  // ---- sky and ground -----------------------------------------------------

  void _paintSky(Canvas canvas) {
    final skyRect = Rect.fromLTRB(-_w, _horizonY - _h * 3, _w * 2, _horizonY);
    final stormy = s._fog;
    final top = Color.lerp(const Color(0xFF1A4A8C), const Color(0xFF3B4250), stormy)!;
    final mid = Color.lerp(const Color(0xFF5C93CC), const Color(0xFF6A717E), stormy)!;
    final low = Color.lerp(const Color(0xFFCFE0EE), const Color(0xFF9097A3), stormy)!;
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, _horizonY - _h * 0.55),
          Offset(0, _horizonY),
          [top, mid, low],
          [0.0, 0.62, 1.0],
        ),
    );

    // High thin cirrus streaks, fixed to the world so they slide as we turn.
    for (var i = 0; i < 7; i++) {
      final bearing = _hash(i * 7 + 3) * 360;
      final rel = _wrap180(bearing - s._heading);
      if (rel.abs() > 60) continue;
      final x = _cx + math.tan(_rad(rel)) * _focal;
      final elev = 8 + _hash(i * 13 + 1) * 18;
      final y = _horizonY - math.tan(_rad(elev)) * _focal;
      final len = 60 + _hash(i * 5 + 2) * 120;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: len, height: 7),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.28 * (1 - stormy))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }

    // The sun.
    const sunBearing = 145.0;
    final rel = _wrap180(sunBearing - s._heading);
    if (rel.abs() < 75) {
      final p = Offset(
        _cx + math.tan(_rad(rel)) * _focal,
        _horizonY - math.tan(_rad(22)) * _focal,
      );
      final glow = (1 - stormy) * 0.9;
      canvas.drawCircle(
        p,
        150,
        Paint()
          ..shader = ui.Gradient.radial(p, 150, [
            const Color(0xFFFFF6D8).withValues(alpha: 0.75 * glow),
            const Color(0xFFFFF6D8).withValues(alpha: 0.0),
          ]),
      );
      canvas.drawCircle(
        p,
        16,
        Paint()..color = Colors.white.withValues(alpha: glow),
      );
    }
  }

  void _paintGround(Canvas canvas) {
    // Sea for most of the trip, land near the airports.
    final dx = s._tx - s._x;
    final dy = s._ty - s._y;
    final distT = math.sqrt(dx * dx + dy * dy);
    final nearStart = math.sqrt(s._x * s._x + s._y * s._y) < 60;
    final land = (nearStart || distT < 110) ? 1.0 : 0.0;
    var style = _Ground.grass;
    if (!nearStart && distT < 110 && !s._toEmergencyAirport) {
      style = _groundFor(s.widget.destination.city);
    }
    var landHaze = const Color(0xFFC2C6B8);
    var landMid = const Color(0xFF6B7B4A);
    var landDeep = const Color(0xFF3F4D2B);
    if (style == _Ground.desert) {
      landHaze = const Color(0xFFE6D6B8);
      landMid = const Color(0xFFD2B47E);
      landDeep = const Color(0xFFB08E58);
    } else if (style == _Ground.snow) {
      landHaze = const Color(0xFFDDE4EA);
      landMid = const Color(0xFFE9EEF2);
      landDeep = const Color(0xFFB9C3CC);
    }
    final haze = Color.lerp(const Color(0xFFB4C4D0), landHaze, land)!;
    final midC = Color.lerp(const Color(0xFF3E6D8C), landMid, land)!;
    final deep = Color.lerp(const Color(0xFF1F3E57), landDeep, land)!;
    final groundRect = Rect.fromLTRB(-_w, _horizonY, _w * 2, _horizonY + _h * 3);
    canvas.drawRect(
      groundRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, _horizonY),
          Offset(0, _horizonY + _h * 0.45),
          [haze, midC, deep],
          [0.0, 0.25, 1.0],
        ),
    );

    // Ground lines rushing past when we're low, so you can feel the speed.
    if (_altU < 4.5) {
      const spacing = 1.2;
      final frac = (s._travelled % spacing) / spacing;
      final strength = (1 - _altU / 4.5).clamp(0.0, 1.0);
      final line = Paint()
        ..color = Colors.black.withValues(alpha: 0.10 * strength)
        ..strokeWidth = 1.2;
      for (var i = 0; i < 26; i++) {
        final d = (i + 1 - frac) * spacing;
        final y = _horizonY + _altU / d * _focal;
        if (y > _h) continue;
        canvas.drawLine(Offset(-_w, y), Offset(_w * 2, y), line);
      }
      // Roads and field edges running away from us.
      for (var i = -6; i <= 6; i++) {
        final side = i * 2.4 + 1.1;
        final near = Offset(_cx + side / 0.3 * _focal, _horizonY + _altU / 0.3 * _focal);
        final far = Offset(_cx + side / 60 * _focal, _horizonY + _altU / 60 * _focal);
        canvas.drawLine(near, far, line);
      }
    }
  }

  void _paintRunway(Canvas canvas) {
    final tx = s._tx;
    final ty = s._ty;
    final fwd = _fwdOf(tx, ty);
    if (fwd > 140 || fwd < -4) return;

    // The runway points from the approach side towards the airport.
    var ax = -s._approachFromX;
    var ay = -s._approachFromY;
    if (!s._approach) {
      // Before the approach starts, point it along our path to it.
      final dx = tx - s._x;
      final dy = ty - s._y;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d > 0.001) {
        ax = dx / d;
        ay = dy / d;
      }
    }
    final px = ay;
    final py = -ax;

    Offset corner(double along, double across) =>
        _project(tx + ax * along + px * across, ty + ay * along + py * across, 0);

    // Airport grass and buildings area.
    final area = Path()
      ..moveTo(corner(-2.6, -0.9).dx, corner(-2.6, -0.9).dy)
      ..lineTo(corner(-2.6, 0.9).dx, corner(-2.6, 0.9).dy)
      ..lineTo(corner(2.6, 0.9).dx, corner(2.6, 0.9).dy)
      ..lineTo(corner(2.6, -0.9).dx, corner(2.6, -0.9).dy)
      ..close();
    canvas.drawPath(area, Paint()..color = const Color(0xFF8C9A6E).withValues(alpha: 0.8));

    final strip = Path()
      ..moveTo(corner(-1.6, -0.09).dx, corner(-1.6, -0.09).dy)
      ..lineTo(corner(-1.6, 0.09).dx, corner(-1.6, 0.09).dy)
      ..lineTo(corner(1.6, 0.09).dx, corner(1.6, 0.09).dy)
      ..lineTo(corner(1.6, -0.09).dx, corner(1.6, -0.09).dy)
      ..close();
    canvas.drawPath(strip, Paint()..color = const Color(0xFF3A3D42));

    final white = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 1.5;
    canvas.drawLine(corner(-1.6, -0.085), corner(1.6, -0.085), white);
    canvas.drawLine(corner(-1.6, 0.085), corner(1.6, 0.085), white);
    for (var a = -1.4; a < 1.5; a += 0.22) {
      canvas.drawLine(corner(a, 0), corner(a + 0.1, 0), white);
    }
    for (var c = -0.07; c <= 0.071; c += 0.02) {
      canvas.drawLine(corner(-1.58, c), corner(-1.46, c), white);
    }

    // Approach lights leading in to the runway.
    final blink = (s._time * 2) % 1;
    for (var k = 1; k <= 9; k++) {
      final p = corner(-1.6 - k * 0.14, 0);
      final f = _fwdOf(tx + ax * (-1.6 - k * 0.14), ty + ay * (-1.6 - k * 0.14));
      if (f < 0.2) continue;
      final r = (0.035 / f * _focal).clamp(1.0, 6.0).toDouble();
      final lit = (blink * 9).floor() == 9 - k;
      canvas.drawCircle(
        p,
        r * (lit ? 2.2 : 1.2),
        Paint()
          ..color = Colors.white.withValues(alpha: lit ? 1.0 : 0.75)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r),
      );
    }
  }

  // ---- clouds, storms and other planes, drawn far to near ----------------

  void _paintObjects(Canvas canvas) {
    final items = <MapEntry<double, void Function()>>[];

    // Fair-weather clouds in a repeating tile around us.
    const tile = _FlightScreenState._tile;
    const cloudU = _FlightScreenState._cloudLayerFt / _ftPerUnit;
    for (final p in s._puffs) {
      var wx = p.x - (s._x % tile);
      var wy = p.y - (s._y % tile);
      if (wx > tile / 2) wx -= tile;
      if (wx < -tile / 2) wx += tile;
      if (wy > tile / 2) wy -= tile;
      if (wy < -tile / 2) wy += tile;
      wx += s._x;
      wy += s._y;
      final fwd = _fwdOf(wx, wy);
      if (fwd < 0.8 || fwd > 80) continue;
      final side = _sideOf(wx, wy);
      if ((side / fwd).abs() > 1.6) continue;
      items.add(MapEntry(fwd, () => _drawCumulus(canvas, wx, wy, cloudU, p.size, p.seed, fwd)));
    }

    for (final st in s._storms) {
      final fwd = _fwdOf(st.x, st.y);
      if (fwd < st.r * 0.5 || fwd > 150) continue;
      final side = _sideOf(st.x, st.y);
      if ((side - st.r).abs() / fwd > 2.2 && (side + st.r).abs() / fwd > 2.2) {
        continue;
      }
      items.add(MapEntry(fwd, () => _drawStorm(canvas, st, fwd)));
    }

    for (final t in s._traffic) {
      final fwd = _fwdOf(t.x, t.y);
      if (fwd < 0.3 || fwd > 60) continue;
      items.add(MapEntry(fwd, () => _drawTraffic(canvas, t, fwd)));
    }

    _addScenery(items);
    items.sort((a, b) => b.key.compareTo(a.key));
    for (final item in items) {
      item.value();
    }
  }

  void _drawCumulus(Canvas canvas, double wx, double wy, double hU, double size,
      double seed, double fwd) {
    final c = _project(wx, wy, hU);
    final px = (size / fwd * _focal).clamp(2.0, _w * 2.5).toDouble();
    final haze = (1 - fwd / 80).clamp(0.0, 1.0).toDouble();
    final below = _altU > hU;
    for (var i = 0; i < 5; i++) {
      final ox = (_hash((seed * 1000).round() + i * 17) - 0.5) * px * 1.1;
      final oy = (_hash((seed * 1000).round() + i * 29) - 0.5) * px * (below ? 0.18 : 0.35);
      final r = px * (0.28 + _hash((seed * 1000).round() + i * 41) * 0.22);
      final center = c.translate(ox, oy);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            center.translate(-r * 0.25, -r * 0.45),
            r * 1.4,
            [
              Colors.white.withValues(alpha: 0.95 * haze),
              const Color(0xFFDCE3EA).withValues(alpha: 0.9 * haze),
              const Color(0xFF9DAAB8).withValues(alpha: 0.85 * haze),
            ],
            [0.0, 0.55, 1.0],
          )
          ..maskFilter = MaskFilter.blur(
              BlurStyle.normal, (r * 0.12).clamp(0.8, 14.0).toDouble()),
      );
    }
  }

  void _drawStorm(Canvas canvas, _Storm st, double fwd) {
    final ground = _project(st.x, st.y, 0);
    final baseU = 4000 / _ftPerUnit;
    final topU = st.topFt / _ftPerUnit;
    final base = _project(st.x, st.y, baseU);
    final top = _project(st.x, st.y, topU);
    final wpx = (2 * st.r / fwd * _focal).toDouble();
    final haze = (1 - fwd / 160).clamp(0.2, 1.0).toDouble();
    final seed = (st.seed * 1000).round();

    // Rain falling from the base of the cloud.
    final rainRect = Rect.fromLTRB(
        base.dx - wpx * 0.38, base.dy, base.dx + wpx * 0.38, ground.dy);
    canvas.drawRect(
      rainRect,
      Paint()
        ..shader = ui.Gradient.linear(
          rainRect.topCenter,
          rainRect.bottomCenter,
          [
            const Color(0xFF5B6270).withValues(alpha: 0.55 * haze),
            const Color(0xFF5B6270).withValues(alpha: 0.12 * haze),
          ],
        )
        ..maskFilter = MaskFilter.blur(
            BlurStyle.normal, (wpx * 0.04).clamp(1.0, 18.0).toDouble()),
    );

    // The tall tower of cloud.
    const n = 9;
    for (var i = 0; i < n; i++) {
      final t = i / (n - 1);
      final y = base.dy + (top.dy - base.dy) * t;
      final r = wpx * (0.46 - 0.16 * t) * (0.85 + _hash(seed + i * 7) * 0.3);
      final x = base.dx + (_hash(seed + i * 11) - 0.5) * wpx * 0.25;
      final center = Offset(x, y);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            center.translate(-r * 0.35, -r * 0.5),
            r * 1.5,
            [
              Color.lerp(const Color(0xFFE4E8EE), const Color(0xFF8E96A3), 1 - t)!
                  .withValues(alpha: haze),
              const Color(0xFF6D7584).withValues(alpha: haze),
              const Color(0xFF353B47).withValues(alpha: haze),
            ],
            [0.0, 0.5, 1.0],
          )
          ..maskFilter = MaskFilter.blur(
              BlurStyle.normal, (r * 0.07).clamp(0.6, 16.0).toDouble()),
      );
    }

    // The flat "anvil" top that big thunderstorms have.
    final anvil = Rect.fromCenter(
      center: top.translate(wpx * 0.15, -wpx * 0.02),
      width: wpx * 1.9,
      height: wpx * 0.32,
    );
    canvas.drawOval(
      anvil,
      Paint()
        ..shader = ui.Gradient.linear(
          anvil.topCenter,
          anvil.bottomCenter,
          [
            const Color(0xFFF1F3F6).withValues(alpha: 0.95 * haze),
            const Color(0xFF8A929F).withValues(alpha: 0.9 * haze),
          ],
        )
        ..maskFilter = MaskFilter.blur(
            BlurStyle.normal, (wpx * 0.05).clamp(1.0, 20.0).toDouble()),
    );

    // Dark, heavy base.
    canvas.drawOval(
      Rect.fromCenter(center: base, width: wpx * 1.05, height: wpx * 0.22),
      Paint()
        ..color = const Color(0xFF2A2F38).withValues(alpha: 0.9 * haze)
        ..maskFilter = MaskFilter.blur(
            BlurStyle.normal, (wpx * 0.04).clamp(1.0, 14.0).toDouble()),
    );

    // Lightning inside the storm now and then.
    final phase = (s._time * 0.55 + st.seed * 13) % 1.0;
    if (phase < 0.05) {
      final mid = Offset(base.dx, (base.dy + top.dy) / 2);
      canvas.drawCircle(
        mid,
        wpx * 0.5,
        Paint()
          ..shader = ui.Gradient.radial(mid, wpx * 0.5, [
            const Color(0xFFDDE6FF).withValues(alpha: 0.7),
            const Color(0xFFDDE6FF).withValues(alpha: 0.0),
          ]),
      );
      final bolt = Path()..moveTo(base.dx, base.dy);
      var bx = base.dx;
      final steps = 7;
      for (var k = 1; k <= steps; k++) {
        final y = base.dy + (ground.dy - base.dy) * k / steps;
        bx += (_hash(seed + k * 3 + (s._time * 10).floor()) - 0.5) * wpx * 0.12;
        bolt.lineTo(bx, y);
      }
      canvas.drawPath(
        bolt,
        Paint()
          ..color = const Color(0xFFEFF3FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (wpx * 0.012).clamp(1.0, 4.0).toDouble()
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
  }

  void _drawTraffic(Canvas canvas, _Traffic t, double fwd) {
    final p = _project(t.x, t.y, t.altFt / _ftPerUnit);
    final span = (0.55 / fwd * _focal).clamp(3.0, _w).toDouble();
    final body = Paint()..color = const Color(0xFFD9DDE3);
    final dark = Paint()
      ..color = const Color(0xFF3A3F47)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (span * 0.02).clamp(0.6, 3.0).toDouble();

    // Seen nose-on: wings, body and tail fin.
    final wing = Path()
      ..moveTo(p.dx - span / 2, p.dy + span * 0.03)
      ..lineTo(p.dx + span / 2, p.dy + span * 0.03)
      ..lineTo(p.dx + span * 0.05, p.dy - span * 0.03)
      ..lineTo(p.dx - span * 0.05, p.dy - span * 0.03)
      ..close();
    canvas.drawPath(wing, body);
    canvas.drawPath(wing, dark);
    final tail = Path()
      ..moveTo(p.dx - span * 0.02, p.dy - span * 0.04)
      ..lineTo(p.dx, p.dy - span * 0.22)
      ..lineTo(p.dx + span * 0.02, p.dy - span * 0.04)
      ..close();
    canvas.drawPath(tail, body);
    canvas.drawCircle(p, span * 0.075, body);
    canvas.drawCircle(p, span * 0.075, dark);
    // Engines.
    canvas.drawCircle(p.translate(-span * 0.18, span * 0.06), span * 0.035, body);
    canvas.drawCircle(p.translate(span * 0.18, span * 0.06), span * 0.035, body);

    // Navigation lights and a flashing white strobe.
    final glow = (span * 0.04).clamp(1.5, 8.0).toDouble();
    canvas.drawCircle(
      p.translate(-span / 2, span * 0.03),
      glow,
      Paint()
        ..color = const Color(0xFF39FF7A)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow),
    );
    canvas.drawCircle(
      p.translate(span / 2, span * 0.03),
      glow,
      Paint()
        ..color = const Color(0xFFFF3B3B)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow),
    );
    if ((s._time * 1.4 + t.seed) % 1 < 0.08) {
      canvas.drawCircle(
        p,
        glow * 3,
        Paint()
          ..color = Colors.white
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow * 2),
      );
    }
  }

  // ---- rain on the windscreen --------------------------------------------

  void _paintRainOnGlass(Canvas canvas, double viewBottom) {
    final rain = s._rain;
    if (rain < 0.02) return;
    final streak = Paint()
      ..color = Colors.white.withValues(alpha: 0.35 * rain)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final count = (90 * rain).round();
    for (var i = 0; i < count; i++) {
      final x = _hash(i * 3 + 1) * _w;
      final speed = 0.9 + _hash(i * 5 + 2) * 1.4;
      final phase = (s._time * speed + _hash(i * 7 + 3)) % 1.0;
      final y = viewBottom * (1 - phase);
      final len = 10 + _hash(i * 11 + 4) * 26;
      // Streaks get blown up and outwards across the glass.
      final dx = (x - _cx) / _w * len * 0.8;
      canvas.drawLine(Offset(x, y), Offset(x + dx, y - len), streak);
    }
    // Drops sitting on the glass.
    final drop = Paint()..color = Colors.white.withValues(alpha: 0.22 * rain);
    final bucket = (s._time * 2).floor();
    for (var i = 0; i < (40 * rain).round(); i++) {
      final seed = i * 31 + bucket * 7;
      final p = Offset(_hash(seed) * _w, _hash(seed + 1) * viewBottom);
      canvas.drawCircle(p, 1.5 + _hash(seed + 2) * 2.5, drop);
    }
  }

  // ---- the cockpit itself ---------------------------------------------------

  void _paintFrame(Canvas canvas, double viewBottom) {
    final frame = Paint()..color = const Color(0xFF1B1D22);
    final edge = Paint()
      ..color = const Color(0xFF3B4049)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Roof.
    final roof = Path()
      ..moveTo(0, 0)
      ..lineTo(_w, 0)
      ..lineTo(_w, _h * 0.02)
      ..quadraticBezierTo(_cx, _h * 0.045, 0, _h * 0.02)
      ..close();
    canvas.drawPath(roof, frame);

    // Centre post between the two front windows.
    final post = Path()
      ..moveTo(_cx - 8, 0)
      ..lineTo(_cx + 8, 0)
      ..lineTo(_cx + 16, viewBottom)
      ..lineTo(_cx - 16, viewBottom)
      ..close();
    canvas.drawPath(post, frame);
    canvas.drawLine(Offset(_cx - 8, _h * 0.03), Offset(_cx - 16, viewBottom), edge);
    canvas.drawLine(Offset(_cx + 8, _h * 0.03), Offset(_cx + 16, viewBottom), edge);

    // Side posts.
    final leftPost = Path()
      ..moveTo(0, 0)
      ..lineTo(_w * 0.06, 0)
      ..lineTo(_w * 0.025, viewBottom)
      ..lineTo(0, viewBottom)
      ..close();
    canvas.drawPath(leftPost, frame);
    final rightPost = Path()
      ..moveTo(_w, 0)
      ..lineTo(_w * 0.94, 0)
      ..lineTo(_w * 0.975, viewBottom)
      ..lineTo(_w, viewBottom)
      ..close();
    canvas.drawPath(rightPost, frame);
    canvas.drawLine(Offset(_w * 0.06, 0), Offset(_w * 0.025, viewBottom), edge);
    canvas.drawLine(Offset(_w * 0.94, 0), Offset(_w * 0.975, viewBottom), edge);

    // Glare shield with its warning lights.
    final shieldTop = viewBottom - 10;
    final shield = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, shieldTop, _w, _h * 0.045),
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
    );
    canvas.drawRRect(
      shield,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, shieldTop),
          Offset(0, shieldTop + _h * 0.045),
          [const Color(0xFF2A2D33), const Color(0xFF111215)],
        ),
    );
    canvas.drawLine(Offset(18, shieldTop + 0.5), Offset(_w - 18, shieldTop + 0.5),
        Paint()
          ..color = const Color(0xFF4A505A)
          ..strokeWidth = 1);

    final lampY = shieldTop + _h * 0.012;
    final blinkOn = (s._time * 3) % 1 < 0.6;
    _lamp(canvas, Offset(_w * 0.06, lampY), 'SEATBELT', s._seatbelt,
        const Color(0xFFFFC93C));
    _lamp(canvas, Offset(_w * 0.31, lampY), 'TRAFFIC',
        s._trafficAlert && blinkOn, const Color(0xFFFF4D4D));
    _lamp(canvas, Offset(_w * 0.535, lampY), 'PULL UP', s._pullUp && blinkOn,
        const Color(0xFFFF4D4D));
    _lamp(canvas, Offset(_w * 0.76, lampY), 'WX AHEAD',
        s._stormAhead || s._turbulence > 0.5, const Color(0xFFFFC93C));
  }

  void _lamp(Canvas canvas, Offset at, String label, bool on, Color color) {
    final rect = Rect.fromLTWH(at.dx, at.dy, _w * 0.18, _h * 0.022);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rr, Paint()..color = on ? color : const Color(0xFF26292E));
    if (on) {
      canvas.drawRRect(
        rr,
        Paint()
          ..color = color.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    _text(canvas, label, rect.center, (rect.height * 0.55).clamp(7.0, 11.0).toDouble(),
        on ? const Color(0xFF15172A) : const Color(0xFF5E636D),
        align: 0);
  }

  void _paintPanel(Canvas canvas, double viewBottom) {
    final top = viewBottom + _h * 0.035;
    canvas.drawRect(
      Rect.fromLTRB(0, top, _w, _h),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, top),
          Offset(0, _h),
          [const Color(0xFF30343B), const Color(0xFF1C1E22)],
        ),
    );

    final size = math.min(_w * 0.44, _h * 0.27);
    final y = top + _h * 0.02;
    final pfd = Rect.fromLTWH(_w * 0.04, y, size, size);
    final nd = Rect.fromLTWH(_w * 0.96 - size, y, size, size);
    _bezel(canvas, pfd);
    _bezel(canvas, nd);
    _paintPfd(canvas, pfd.deflate(6));
    _paintNd(canvas, nd.deflate(6));

    // Screws.
    final screw = Paint()..color = const Color(0xFF4A4F57);
    for (final p in [
      Offset(10, top + 10),
      Offset(_w - 10, top + 10),
      Offset(10, _h - 10),
      Offset(_w - 10, _h - 10),
    ]) {
      canvas.drawCircle(p, 3, screw);
    }
  }

  void _bezel(Canvas canvas, Rect r) {
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(10));
    canvas.drawRRect(rr, Paint()..color = const Color(0xFF0B0C0E));
    canvas.drawRRect(
      rr,
      Paint()
        ..color = const Color(0xFF4B515B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  /// Primary flight display: the tilting horizon, speed, height and heading.
  void _paintPfd(Canvas canvas, Rect r) {
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)));
    final c = r.center;
    final pitchDeg = (s._vs / 1500) * 6;
    final pxPerDeg = r.height / 40;

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-_rad(s._roll));
    final hy = pitchDeg * pxPerDeg;
    canvas.drawRect(Rect.fromLTRB(-r.width * 2, -r.height * 3, r.width * 2, hy),
        Paint()..color = const Color(0xFF2F7FD8));
    canvas.drawRect(Rect.fromLTRB(-r.width * 2, hy, r.width * 2, r.height * 3),
        Paint()..color = const Color(0xFF8A5A2E));
    final white = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(-r.width * 2, hy), Offset(r.width * 2, hy), white);
    for (var k = -4; k <= 4; k++) {
      if (k == 0) continue;
      final y = hy - k * 5 * pxPerDeg;
      final half = k.isEven ? r.width * 0.16 : r.width * 0.08;
      canvas.drawLine(Offset(-half, y), Offset(half, y), white);
    }
    canvas.restore();

    // Fixed yellow aeroplane symbol.
    final yellow = Paint()
      ..color = const Color(0xFFFFC93C)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c.translate(-r.width * 0.3, 0), c.translate(-r.width * 0.1, 0), yellow);
    canvas.drawLine(c.translate(r.width * 0.1, 0), c.translate(r.width * 0.3, 0), yellow);
    canvas.drawRect(Rect.fromCenter(center: c, width: 6, height: 6), yellow);

    // Speed and height boxes.
    final knots = s._approach ? 170 : 480;
    _infoBox(canvas, Offset(r.left + 4, c.dy), '$knots', 'KT', alignLeft: true, r: r);
    final alt = (s._altFt / 10).round() * 10;
    _infoBox(canvas, Offset(r.right - 4, c.dy), '$alt', 'FT', alignLeft: false, r: r);

    // Climb / descend arrow.
    final vsText = s._vs.abs() < 50
        ? 'LEVEL'
        : (s._vs > 0 ? 'CLIMB' : 'DESCEND');
    _text(canvas, vsText, Offset(c.dx, r.top + r.height * 0.1),
        r.height * 0.07, Colors.white,
        align: 0);

    // Heading.
    _text(canvas, 'HDG ${s._heading.round().toString().padLeft(3, '0')}',
        Offset(c.dx, r.bottom - r.height * 0.09), r.height * 0.075,
        const Color(0xFF7CFFB0),
        align: 0);
    canvas.restore();
  }

  void _infoBox(Canvas canvas, Offset at, String value, String unit,
      {required bool alignLeft, required Rect r}) {
    final bw = r.width * 0.26;
    final bh = r.height * 0.13;
    final rect = alignLeft
        ? Rect.fromLTWH(at.dx, at.dy - bh / 2, bw, bh)
        : Rect.fromLTWH(at.dx - bw, at.dy - bh / 2, bw, bh);
    canvas.drawRect(rect, Paint()..color = const Color(0xE6000000));
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    _text(canvas, value, rect.center.translate(0, -bh * 0.05), bh * 0.5,
        Colors.white,
        align: 0);
    _text(canvas, unit, Offset(rect.center.dx, rect.bottom + bh * 0.35),
        bh * 0.32, Colors.white70,
        align: 0);
  }

  /// Navigation display: heading-up map with weather radar and traffic.
  void _paintNd(Canvas canvas, Rect r) {
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)));
    canvas.drawRect(r, Paint()..color = const Color(0xFF05070A));
    final me = Offset(r.center.dx, r.top + r.height * 0.8);
    const range = 60.0;
    final scale = (r.height * 0.7) / range;

    Offset toScreen(double wx, double wy) {
      final fwd = _fwdOf(wx, wy);
      final side = _sideOf(wx, wy);
      return me.translate(side * scale, -fwd * scale);
    }

    // Range rings.
    final ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(me, range * scale * 0.5, ring);
    canvas.drawCircle(me, range * scale, ring);

    // Weather radar.
    for (final st in s._storms) {
      final p = toScreen(st.x, st.y);
      if ((p - me).distance > range * scale * 1.3) continue;
      final rr = st.r * scale;
      final dim = s._altFt > st.topFt ? 0.4 : 1.0;
      canvas.drawCircle(p, rr,
          Paint()..color = const Color(0xFF1DB954).withValues(alpha: 0.75 * dim));
      canvas.drawCircle(p, rr * 0.68,
          Paint()..color = const Color(0xFFFFD43B).withValues(alpha: 0.85 * dim));
      canvas.drawCircle(p, rr * 0.36,
          Paint()..color = const Color(0xFFFF3B30).withValues(alpha: 0.9 * dim));
    }

    // Course line to where we're going.
    final target = toScreen(s._tx, s._ty);
    final magenta = Paint()
      ..color = const Color(0xFFFF4FD8)
      ..strokeWidth = 2.5;
    canvas.drawLine(me, target, magenta);
    canvas.drawCircle(target, 6, magenta..style = PaintingStyle.stroke);
    final label = s._toEmergencyAirport ? 'EMERG' : s.widget.destination.city.toUpperCase();
    final labelPos = Offset(
      target.dx.clamp(r.left + 30, r.right - 30).toDouble(),
      (target.dy - 14).clamp(r.top + 30, r.bottom - 12).toDouble(),
    );
    _text(canvas, label, labelPos, r.height * 0.06, const Color(0xFFFF4FD8),
        align: 0);

    // Other planes (TCAS).
    for (final t in s._traffic) {
      final p = toScreen(t.x, t.y);
      if ((p - me).distance > range * scale) continue;
      final diff = ((t.altFt - s._altFt) / 100).round();
      final danger = diff.abs() < 10;
      final col = danger ? const Color(0xFFFF3B30) : Colors.white;
      final d = Path()
        ..moveTo(p.dx, p.dy - 6)
        ..lineTo(p.dx + 6, p.dy)
        ..lineTo(p.dx, p.dy + 6)
        ..lineTo(p.dx - 6, p.dy)
        ..close();
      canvas.drawPath(d, Paint()..color = col);
      final sign = diff >= 0 ? '+' : '-';
      _text(canvas, '$sign${diff.abs().toString().padLeft(2, '0')}',
          p.translate(0, -14), r.height * 0.05, col,
          align: 0);
    }

    // Our plane.
    final plane = Path()
      ..moveTo(me.dx, me.dy - 10)
      ..lineTo(me.dx + 8, me.dy + 6)
      ..lineTo(me.dx, me.dy + 2)
      ..lineTo(me.dx - 8, me.dy + 6)
      ..close();
    canvas.drawPath(plane, Paint()..color = const Color(0xFFFFC93C));

    // Compass arc along the top.
    final arcR = r.height * 0.72;
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 1.2;
    for (var k = -6; k <= 6; k++) {
      final hdgTick = ((s._heading / 10).round() + k) * 10;
      final rel = _wrap180(hdgTick - s._heading);
      final a = _rad(rel) - math.pi / 2;
      final outer = me + Offset(math.cos(a), math.sin(a)) * arcR;
      final inner = me + Offset(math.cos(a), math.sin(a)) * (arcR - (hdgTick % 30 == 0 ? 10 : 5));
      canvas.drawLine(inner, outer, tick);
      if (hdgTick % 30 == 0) {
        final lbl = (_wrap360(hdgTick.toDouble()) / 10).round() % 36;
        final pos = me + Offset(math.cos(a), math.sin(a)) * (arcR - 20);
        _text(canvas, '$lbl', pos, r.height * 0.05, Colors.white, align: 0);
      }
    }
    final box = Rect.fromCenter(
        center: Offset(me.dx, r.top + 12), width: r.width * 0.26, height: 20);
    canvas.drawRect(box, Paint()..color = Colors.black);
    canvas.drawRect(
        box,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke);
    _text(canvas, s._heading.round().toString().padLeft(3, '0'), box.center,
        13, Colors.white,
        align: 0);

    _text(canvas, 'WX', Offset(r.left + 14, r.bottom - 12), r.height * 0.055,
        const Color(0xFF1DB954),
        align: 0);
    canvas.restore();
  }

  void _paintYoke(Canvas canvas) {
    final pivot = Offset(_cx, _h + 10);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(_rad(s._roll * 1.6));
    final yw = math.min(_w * 0.42, 220.0);
    final dark = Paint()..color = const Color(0xFF26282D);
    final edge = Paint()
      ..color = const Color(0xFF4C515A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // Column.
    final column = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-9, -70, 18, 80), const Radius.circular(5));
    canvas.drawRRect(column, dark);
    canvas.drawRRect(column, edge);
    // The U-shaped yoke.
    final yoke = Path()
      ..moveTo(-yw / 2, -110)
      ..lineTo(-yw / 2 + 22, -110)
      ..lineTo(-yw / 2 + 26, -78)
      ..lineTo(yw / 2 - 26, -78)
      ..lineTo(yw / 2 - 22, -110)
      ..lineTo(yw / 2, -110)
      ..lineTo(yw / 2 - 6, -60)
      ..lineTo(-yw / 2 + 6, -60)
      ..close();
    canvas.drawPath(yoke, dark);
    canvas.drawPath(yoke, edge);
    // Logo plate in the middle.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(-22, -76, 44, 14), const Radius.circular(3)),
      Paint()..color = const Color(0xFF3A3E46),
    );
    _text(canvas, 'OSCAR AIR', const Offset(0, -69), 8, const Color(0xFFB0B6C0),
        align: 0);
    canvas.restore();
  }

  // ---- city scenery -------------------------------------------------------

  /// Direction the runway points (unit vector) for the current target.
  Offset _runwayDir() {
    if (s._approach) return Offset(-s._approachFromX, -s._approachFromY);
    final dx = s._tx - s._x;
    final dy = s._ty - s._y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 0.001) return const Offset(1, 0);
    return Offset(dx / d, dy / d);
  }

  void _addScenery(List<MapEntry<double, void Function()>> items) {
    final features =
        s._toEmergencyAirport ? s._emergencyScenery : s._destScenery;
    if (features.isEmpty) return;
    final toTarget = _fwdOf(s._tx, s._ty);
    if (toTarget > 70) return;
    final a = _runwayDir();
    final px = a.dy;
    final py = -a.dx;
    for (final feat in features) {
      final wx = s._tx + a.dx * feat.along + px * feat.across;
      final wy = s._ty + a.dy * feat.along + py * feat.across;
      final fwd = _fwdOf(wx, wy);
      if (fwd < 0.35 || fwd > 75) continue;
      final side = _sideOf(wx, wy);
      if ((side.abs() - feat.w) / fwd > 2.0) continue;
      items.add(MapEntry(fwd, () {
        final base = _project(wx, wy, 0);
        final k = _focal / fwd; // pixels per unit at this distance
        final haze = (fwd / 75).clamp(0.0, 1.0).toDouble();
        _drawLandmark(canvas0!, feat, base, k, haze);
      }));
    }
  }

  Canvas? canvas0;

  // ---- text ----------------------------------------------------------------

  /// Draws text centred on [at] (align 0) .
  void _text(Canvas canvas, String text, Offset at, double size, Color color,
      {int align = 0}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _CockpitPainter oldDelegate) => true;
}
