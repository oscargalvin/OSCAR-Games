part of 'fly_or_crash_screen.dart';

// ===========================================================================
// Cartoon mode: the bright, side-on version of Fly or Crash.
// ===========================================================================

enum _Kind { storm, plane, snack }

class _Thing {
  final _Kind kind;
  double x; // fraction of the play area's width
  final double y; // fraction of the play area's height
  final double size; // pixels
  final double speed; // extra speed, fraction of width per second
  final double seed;
  bool touched = false;
  bool dead = false;

  _Thing(this.kind, this.x, this.y, this.size, this.speed, this.seed);
}

enum _CPhase { cruising, emergencyChoice, approach, landed, crashed }


class CartoonFlightScreen extends StatefulWidget {
  final Destination destination;

  const CartoonFlightScreen({super.key, required this.destination});

  @override
  State<CartoonFlightScreen> createState() => _CartoonFlightState();
}

class _CartoonFlightState extends State<CartoonFlightScreen>
    with SingleTickerProviderStateMixin {
  static const double _planeX = 0.22; // where our plane sits across the screen
  static const double _minY = 0.10;
  static const double _maxY = 0.86;
  static const double _landingY = 0.74; // fly below this to land
  static const double _worldSpeed = 0.32; // screen widths per second
  static const double _runwayLength = 0.9; // screen widths

  final math.Random _rand = math.Random();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final FocusNode _focus = FocusNode();

  late double _km;
  late double _flightSeconds;
  late double _difficulty; // 0 = easy, 1 = hardest

  _CPhase _phase = _CPhase.cruising;
  double _time = 0;
  double _progress = 0;
  double _passengers = 100;

  double _planeY = 0.45;
  double _velocity = 0;
  double? _dragTargetY;
  bool _upHeld = false;
  bool _downHeld = false;

  final List<_Thing> _things = [];
  double _stormTimer = 3;
  double _planeTimer = 5;
  double _snackTimer = 7;

  final List<double> _emergencyAt = [];
  _Emergency? _currentEmergency;
  bool _emergencyLanding = false;
  double _engineTrouble = 0;

  double? _runwayX;
  bool _runwayChecked = false;
  double _runwayRespawn = 0;

  String? _banner;
  double _bannerTime = 0;
  double _shake = 0;
  double _flash = 0;

  Size _playSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _km = _distanceKm(_home, widget.destination);
    _flightSeconds = (25 + _km / 220).clamp(30, 100).toDouble();
    _difficulty = (_km / 17000).clamp(0.0, 1.0).toDouble();
    if (_km > 2500) _emergencyAt.add(0.3 + _rand.nextDouble() * 0.25);
    if (_km > 9000) _emergencyAt.add(0.65 + _rand.nextDouble() * 0.1);
    _say('Drag up and down, or use the arrow keys, to fly.', 4);
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _say(String text, [double seconds = 2.5]) {
    _banner = text;
    _bannerTime = seconds;
  }

  double _lerp(double a, double b) => a + (b - a) * _difficulty;

  // ---- game loop ----------------------------------------------------------

  void _tick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt > 0.05) dt = 0.05;
    if (dt <= 0) return;
    if (_phase == _CPhase.emergencyChoice ||
        _phase == _CPhase.landed ||
        _phase == _CPhase.crashed) {
      return;
    }
    setState(() => _update(dt));
  }

  void _update(double dt) {
    _time += dt;
    if (_bannerTime > 0) {
      _bannerTime -= dt;
      if (_bannerTime <= 0) _banner = null;
    }
    if (_shake > 0) _shake = math.max(0.0, _shake - dt);
    if (_flash > 0) _flash = math.max(0.0, _flash - dt * 2);

    _movePlane(dt);

    if (_phase == _CPhase.cruising) {
      _progress += dt / _flightSeconds;
      _spawn(dt);
      if (_emergencyAt.isNotEmpty && _progress >= _emergencyAt.first) {
        _emergencyAt.removeAt(0);
        _currentEmergency = _emergencies[_rand.nextInt(_emergencies.length)];
        _phase = _CPhase.emergencyChoice;
        return;
      }
      if (_progress >= 1) {
        _progress = 1;
        _startApproach(emergency: false);
      }
    }

    // Engine trouble slowly upsets the passengers.
    if (_engineTrouble > 0) {
      _engineTrouble -= dt;
      _passengers -= 3 * dt;
      if (_engineTrouble <= 0) {
        _engineTrouble = 0;
        _say('Phew, that problem has calmed down.');
      }
    }

    _moveThings(dt);
    _checkHits(dt);

    if (_phase == _CPhase.approach) _updateRunway(dt);

    // Calm skies slowly make passengers happier again.
    final inStorm = _things.any((t) => t.kind == _Kind.storm && t.touched);
    if (!inStorm && _engineTrouble <= 0) _passengers += 1.2 * dt;
    _passengers = _passengers.clamp(0, 100).toDouble();

    if (_passengers <= 0) {
      _phase = _CPhase.crashed;
      _banner = null;
    }
  }

  void _movePlane(double dt) {
    final target = _dragTargetY;
    if (target != null) {
      final diff = target - _planeY;
      _velocity = (diff * 6).clamp(-0.9, 0.9).toDouble();
    } else if (_upHeld != _downHeld) {
      final want = _upHeld ? -0.7 : 0.7;
      _velocity += (want - _velocity) * math.min(1, dt * 8);
    } else {
      _velocity += (0 - _velocity) * math.min(1, dt * 6);
    }
    _planeY = (_planeY + _velocity * dt).clamp(_minY, _maxY).toDouble();
  }

  void _spawn(double dt) {
    // Keep the last stretch clear so the runway isn't covered in storms.
    if (_progress > 0.93) return;
    _stormTimer -= dt;
    _planeTimer -= dt;
    _snackTimer -= dt;
    if (_stormTimer <= 0) {
      _stormTimer = _lerp(6.5, 2.6) + _rand.nextDouble() * 2;
      final double h = _playSize.height == 0 ? 600.0 : _playSize.height;
      _things.add(_Thing(
        _Kind.storm,
        1.25,
        0.15 + _rand.nextDouble() * 0.5,
        h * (0.07 + _rand.nextDouble() * 0.04),
        0,
        _rand.nextDouble(),
      ));
    }
    if (_planeTimer <= 0) {
      _planeTimer = _lerp(8, 3.4) + _rand.nextDouble() * 2.5;
      _things.add(_Thing(
        _Kind.plane,
        1.2,
        0.12 + _rand.nextDouble() * 0.6,
        30,
        _lerp(0.12, 0.3),
        _rand.nextDouble(),
      ));
      _say('Plane ahead! Steer around it.', 1.8);
    }
    if (_snackTimer <= 0) {
      _snackTimer = 7 + _rand.nextDouble() * 5;
      _things.add(_Thing(
        _Kind.snack,
        1.15,
        0.15 + _rand.nextDouble() * 0.55,
        16,
        0,
        _rand.nextDouble(),
      ));
    }
  }

  void _moveThings(double dt) {
    for (final t in _things) {
      t.x -= (_worldSpeed + t.speed) * dt;
    }
    _things.removeWhere((t) => t.dead || t.x < -0.35);
  }

  void _checkHits(double dt) {
    final w = _playSize.width;
    final h = _playSize.height;
    if (w == 0 || h == 0) return;
    final px = _planeX * w;
    final py = _planeY * h;

    for (final t in _things) {
      final dx = t.x * w - px;
      final dy = t.y * h - py;
      switch (t.kind) {
        case _Kind.storm:
          final nx = dx / (t.size + 28);
          final ny = dy / (t.size * 0.6 + 10);
          final hit = nx * nx + ny * ny < 1;
          if (hit) {
            if (!t.touched) _say('Turbulence! Hold on, everyone!', 1.6);
            t.touched = true;
            _passengers -= 14 * dt;
            _shake = 0.35;
          } else {
            t.touched = false;
          }
          break;
        case _Kind.plane:
          final nx = dx / (t.size + 30);
          final ny = dy / 22;
          if (nx * nx + ny * ny < 1) {
            t.dead = true;
            _passengers -= 25;
            _shake = 0.7;
            _flash = 1;
            _say('Ouch! You clipped another plane!', 2);
          }
          break;
        case _Kind.snack:
          final nx = dx / (t.size + 30);
          final ny = dy / (t.size + 12);
          if (nx * nx + ny * ny < 1) {
            t.dead = true;
            _passengers += 8;
            _say('Snacks served! Passengers are happier.', 1.8);
          }
          break;
      }
    }
  }

  // ---- landing ------------------------------------------------------------

  void _startApproach({required bool emergency}) {
    _phase = _CPhase.approach;
    _emergencyLanding = emergency;
    _runwayX = 1.4;
    _runwayChecked = false;
    _say(
      emergency
          ? 'Nearest airport ahead! Fly low over the runway to land.'
          : 'There\'s ${widget.destination.city}! Fly low over the runway to land.',
      4,
    );
  }

  void _updateRunway(double dt) {
    final x = _runwayX;
    if (x == null) {
      _runwayRespawn -= dt;
      if (_runwayRespawn <= 0) {
        _runwayX = 1.3;
        _runwayChecked = false;
        _say('Coming round again. Get low!', 2.5);
      }
      return;
    }
    final newX = x - _worldSpeed * dt;
    _runwayX = newX;
    // The moment the start of the runway reaches our plane, check our height.
    if (!_runwayChecked && newX <= _planeX) {
      _runwayChecked = true;
      if (_planeY >= _landingY) {
        _touchDown();
      } else {
        _passengers -= 6;
        _say('Too high to land! Go around.', 2.5);
      }
    }
    if (newX + _runwayLength < -0.1) {
      _runwayX = null;
      _runwayRespawn = 2.5;
    }
  }

  void _touchDown() {
    if (_emergencyLanding) {
      _passengers = math.min(100, _passengers + 15);
      _engineTrouble = 0;
      _emergencyLanding = false;
      _runwayX = null;
      _phase = _CPhase.cruising;
      _planeY = 0.5;
      _say('Safe emergency landing! All fixed, taking off again.', 3.5);
    } else {
      _phase = _CPhase.landed;
      _banner = null;
      final save = SaveService.instance;
      save.saveHighScore('fly_or_crash', save.getHighScore('fly_or_crash') + 1);
    }
  }

  void _chooseEmergencyLanding() {
    setState(() {
      _currentEmergency = null;
      _things.removeWhere((t) => t.x > 0.6);
      _startApproach(emergency: true);
    });
    _focus.requestFocus();
  }

  void _chooseKeepFlying() {
    setState(() {
      _currentEmergency = null;
      _phase = _CPhase.cruising;
      _engineTrouble = 12;
      if (_rand.nextDouble() < 0.35) {
        _passengers -= 12;
        _say('Uh oh, it\'s getting worse! Passengers are scared.', 3);
      } else {
        _say('Keep calm and fly on. Passengers are a bit nervous.', 3);
      }
    });
    _focus.requestFocus();
  }

  void _restart() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CartoonFlightScreen(destination: widget.destination),
      ),
    );
  }

  // ---- input --------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      _upHeld = down;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyS) {
      _downHeld = down;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _sky,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _playSize = Size(constraints.maxWidth, constraints.maxHeight);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _dragTargetY =
                  (d.localPosition.dy / constraints.maxHeight)
                      .clamp(_minY, _maxY)
                      .toDouble(),
              onPanUpdate: (d) => _dragTargetY =
                  (d.localPosition.dy / constraints.maxHeight)
                      .clamp(_minY, _maxY)
                      .toDouble(),
              onPanEnd: (_) => _dragTargetY = null,
              onPanCancel: () => _dragTargetY = null,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _FlightPainter(
                        time: _time,
                        planeX: _planeX,
                        planeY: _planeY,
                        tilt: (_velocity * 0.45).clamp(-0.35, 0.35).toDouble(),
                        things: _things,
                        runwayX: _runwayX,
                        runwayLength: _runwayLength,
                        showLandingZone: _phase == _CPhase.approach,
                        landingY: _landingY,
                        shake: _shake,
                        flash: _flash,
                        smoking: _engineTrouble > 0,
                      ),
                    ),
                  ),
                  SafeArea(child: _buildHud()),
                  if (_banner != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 90,
                      child: Center(child: _Sticker(text: _banner!)),
                    ),
                  if (_phase == _CPhase.emergencyChoice &&
                      _currentEmergency != null)
                    _buildEmergency(_currentEmergency!),
                  if (_phase == _CPhase.landed) _buildLanded(),
                  if (_phase == _CPhase.crashed) _buildCrashed(),
                ],
              ),
            );
          },
        ),
      ),
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
                      const Text(
                        'Passengers',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 13,
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
                        width: 40,
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
                      final left =
                          (c.maxWidth - iconSize) * _progress.clamp(0.0, 1.0);
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
      body: e.body,
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
    return _Overlay(
      color: _tomato,
      icon: Icons.warning_rounded,
      title: 'Crash!',
      body: 'Your passengers weren\'t okay, so the flight is over. '
          'Dodge the storms and planes, and grab snacks to keep everyone happy.',
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


// ---- drawing the sky --------------------------------------------------------

class _FlightPainter extends CustomPainter {
  final double time;
  final double planeX;
  final double planeY;
  final double tilt;
  final List<_Thing> things;
  final double? runwayX;
  final double runwayLength;
  final bool showLandingZone;
  final double landingY;
  final double shake;
  final double flash;
  final bool smoking;

  _FlightPainter({
    required this.time,
    required this.planeX,
    required this.planeY,
    required this.tilt,
    required this.things,
    required this.runwayX,
    required this.runwayLength,
    required this.showLandingZone,
    required this.landingY,
    required this.shake,
    required this.flash,
    required this.smoking,
  });

  static final Paint _inkStroke = Paint()
    ..color = _ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = _sky);

    canvas.save();
    if (shake > 0) {
      canvas.translate(
        math.sin(time * 70) * shake * 8,
        math.cos(time * 55) * shake * 6,
      );
    }

    // Far-away fluffy clouds drifting slowly.
    final cloudPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (var i = 0; i < 6; i++) {
      final speed = 0.03 + i * 0.008;
      final x = ((i * 0.41 + 1.2 - (time * speed) % 1.2) % 1.2 - 0.1) * w;
      final y = (0.12 + (i * 0.13) % 0.6) * h;
      final s = 18.0 + (i % 3) * 8;
      canvas.drawCircle(Offset(x, y), s, cloudPaint);
      canvas.drawCircle(Offset(x + s * 1.1, y + 4), s * 0.8, cloudPaint);
      canvas.drawCircle(Offset(x - s * 1.0, y + 6), s * 0.7, cloudPaint);
    }

    // Ground.
    final groundTop = h * 0.92;
    canvas.drawRect(
      Rect.fromLTRB(-20, groundTop, w + 20, h + 20),
      Paint()..color = _grass,
    );
    canvas.drawLine(
      Offset(-20, groundTop),
      Offset(w + 20, groundTop),
      _inkStroke,
    );

    if (showLandingZone) {
      canvas.drawRect(
        Rect.fromLTRB(0, landingY * h, w, groundTop),
        Paint()..color = Colors.white.withValues(alpha: 0.22),
      );
      _text(canvas, 'Fly low here to land', Offset(12, landingY * h + 6), 13,
          Colors.white);
    }

    final rx = runwayX;
    if (rx != null) {
      final left = rx * w;
      final right = (rx + runwayLength) * w;
      final rect = Rect.fromLTRB(left, groundTop - 4, right, groundTop + 14);
      canvas.drawRect(rect, Paint()..color = const Color(0xFF3A3D4F));
      canvas.drawRect(rect, _inkStroke);
      final dash = Paint()..color = Colors.white;
      for (var x = left + 14; x < right - 20; x += 34) {
        canvas.drawRect(Rect.fromLTWH(x, groundTop + 3, 18, 3), dash);
      }
      // Flags at the start of the runway.
      final flagPaint = Paint()..color = _tomato;
      canvas.drawLine(
          Offset(left, groundTop - 4), Offset(left, groundTop - 30), _inkStroke);
      canvas.drawPath(
        Path()
          ..moveTo(left, groundTop - 30)
          ..lineTo(left + 18, groundTop - 25)
          ..lineTo(left, groundTop - 20)
          ..close(),
        flagPaint,
      );
    }

    for (final t in things) {
      final c = Offset(t.x * w, t.y * h);
      switch (t.kind) {
        case _Kind.storm:
          _drawStorm(canvas, c, t.size, t.seed);
          break;
        case _Kind.plane:
          _drawPlane(canvas, c, 0.75, false, _tomato, 0);
          break;
        case _Kind.snack:
          _drawSnack(canvas, c, t.size);
          break;
      }
    }

    final me = Offset(planeX * w, planeY * h);
    if (smoking) {
      final smoke = Paint()..color = const Color(0xFF6B6F80).withValues(alpha: 0.6);
      for (var i = 0; i < 6; i++) {
        final age = ((time * 2.5 + i / 6) % 1);
        canvas.drawCircle(
          Offset(me.dx - 30 - age * 90, me.dy - 4 - age * 18),
          5 + age * 10,
          smoke,
        );
      }
    }
    _drawPlane(canvas, me, 1.0, true, Colors.white, tilt);

    canvas.restore();

    if (flash > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = _tomato.withValues(alpha: 0.35 * flash),
      );
    }
  }

  void _drawStorm(Canvas canvas, Offset c, double r, double seed) {
    // Rain.
    final rain = Paint()
      ..color = const Color(0xFF3B5BDB)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var i = -3; i <= 3; i++) {
      final fall = (time * 3 + i * 0.37 + seed) % 1;
      final x = c.dx + i * r * 0.28 - fall * 8;
      final y = c.dy + r * 0.45 + fall * r * 0.9;
      canvas.drawLine(Offset(x, y), Offset(x - 4, y + 10), rain);
    }

    // Lightning now and then.
    final flicker = (time * 1.3 + seed * 7) % 1;
    if (flicker < 0.12) {
      final bolt = Path()
        ..moveTo(c.dx, c.dy + r * 0.3)
        ..lineTo(c.dx - r * 0.18, c.dy + r * 0.8)
        ..lineTo(c.dx + r * 0.05, c.dy + r * 0.8)
        ..lineTo(c.dx - r * 0.12, c.dy + r * 1.35)
        ..lineTo(c.dx + r * 0.25, c.dy + r * 0.65)
        ..lineTo(c.dx + r * 0.02, c.dy + r * 0.65)
        ..lineTo(c.dx + r * 0.15, c.dy + r * 0.3)
        ..close();
      canvas.drawPath(bolt, Paint()..color = _sun);
      canvas.drawPath(bolt, _inkStroke);
    }

    // The cloud itself: a few overlapping puffs merged into one shape.
    final merged = Path.combine(
      PathOperation.union,
      Path.combine(
        PathOperation.union,
        Path()
          ..addOval(Rect.fromCircle(center: c, radius: r * 0.75)),
        Path()
          ..addOval(Rect.fromCircle(
              center: c.translate(-r * 0.7, r * 0.15), radius: r * 0.55)),
      ),
      Path.combine(
        PathOperation.union,
        Path()
          ..addOval(Rect.fromCircle(
              center: c.translate(r * 0.7, r * 0.12), radius: r * 0.6)),
        Path()
          ..addOval(Rect.fromCircle(
              center: c.translate(r * 0.2, -r * 0.35), radius: r * 0.55)),
      ),
    );
    canvas.drawPath(merged, Paint()..color = const Color(0xFF555A75));
    canvas.drawPath(merged, _inkStroke);
  }

  void _drawSnack(Canvas canvas, Offset c, double r) {
    // A little cup of juice with a straw.
    final cup = Path()
      ..moveTo(c.dx - r * 0.7, c.dy - r * 0.6)
      ..lineTo(c.dx + r * 0.7, c.dy - r * 0.6)
      ..lineTo(c.dx + r * 0.5, c.dy + r * 0.9)
      ..lineTo(c.dx - r * 0.5, c.dy + r * 0.9)
      ..close();
    canvas.drawCircle(c, r * 1.5, Paint()..color = Colors.white);
    canvas.drawCircle(c, r * 1.5, _inkStroke);
    canvas.drawPath(cup, Paint()..color = const Color(0xFFFF9F43));
    canvas.drawPath(cup, _inkStroke);
    canvas.drawLine(
      Offset(c.dx + r * 0.1, c.dy - r * 0.6),
      Offset(c.dx + r * 0.45, c.dy - r * 1.15),
      _inkStroke,
    );
  }

  /// Draws a side-on plane. [facingRight] false mirrors it.
  void _drawPlane(Canvas canvas, Offset c, double scale, bool facingRight,
      Color body, double angle) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    canvas.scale(facingRight ? scale : -scale, scale);

    final fill = Paint()..color = body;
    final accent = Paint()..color = facingRight ? _cobalt : _ink;

    // Tail fin.
    final tail = Path()
      ..moveTo(-30, -4)
      ..lineTo(-40, -24)
      ..lineTo(-30, -24)
      ..lineTo(-16, -6)
      ..close();
    canvas.drawPath(tail, accent);
    canvas.drawPath(tail, _inkStroke);

    // Body.
    final bodyRect = RRect.fromRectAndCorners(
      const Rect.fromLTRB(-40, -9, 40, 9),
      topLeft: const Radius.circular(6),
      bottomLeft: const Radius.circular(6),
      topRight: const Radius.circular(16),
      bottomRight: const Radius.circular(12),
    );
    canvas.drawRRect(bodyRect, fill);
    canvas.drawRRect(bodyRect, _inkStroke);

    // Windows.
    final window = Paint()..color = _ink;
    for (var x = -22.0; x <= 18; x += 8) {
      canvas.drawCircle(Offset(x, -2), 2, window);
    }
    // Cockpit.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(26, -6, 9, 5), const Radius.circular(2)),
      window,
    );

    // Wing.
    final wing = Path()
      ..moveTo(-4, 2)
      ..lineTo(10, 2)
      ..lineTo(-10, 22)
      ..lineTo(-20, 22)
      ..close();
    canvas.drawPath(wing, accent);
    canvas.drawPath(wing, _inkStroke);

    canvas.restore();
  }

  void _text(Canvas canvas, String text, Offset at, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _FlightPainter oldDelegate) => true;
}
