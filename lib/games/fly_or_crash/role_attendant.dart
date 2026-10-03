part of 'fly_or_crash_screen.dart';

// ===========================================================================
// Flight attendant mode: you work in the cabin. Serve passengers what they
// ask for, but only when the seatbelt sign is off. When it comes on, get back
// to your seat in the galley!
// ===========================================================================

enum _Item { juice, water, tea, crisps, sandwich, cookie }

const Map<_Item, String> _itemNames = {
  _Item.juice: 'Orange juice',
  _Item.water: 'Water',
  _Item.tea: 'Cup of tea',
  _Item.crisps: 'Crisps',
  _Item.sandwich: 'Sandwich',
  _Item.cookie: 'Cookie',
};

const Map<_Item, IconData> _itemIcons = {
  _Item.juice: Icons.local_drink_rounded,
  _Item.water: Icons.water_drop_rounded,
  _Item.tea: Icons.emoji_food_beverage_rounded,
  _Item.crisps: Icons.fastfood_rounded,
  _Item.sandwich: Icons.lunch_dining_rounded,
  _Item.cookie: Icons.bakery_dining_rounded,
};

const Map<_Item, Color> _itemColors = {
  _Item.juice: Color(0xFFFF9F43),
  _Item.water: Color(0xFF6FD3F7),
  _Item.tea: Color(0xFFC08A5B),
  _Item.crisps: Color(0xFFFFC93C),
  _Item.sandwich: Color(0xFFB6E34A),
  _Item.cookie: Color(0xFFD9A066),
};

class _Request {
  final int seat; // row * 6 + column
  final _Item item;
  double patience; // seconds left

  _Request(this.seat, this.item, this.patience);
}

class AttendantScreen extends StatefulWidget {
  final Destination destination;

  const AttendantScreen({super.key, required this.destination});

  @override
  State<AttendantScreen> createState() => _AttendantScreenState();
}

class _AttendantScreenState extends State<AttendantScreen>
    with SingleTickerProviderStateMixin {
  static const int rows = 14;
  static const double rowH = 70; // pixels per row
  static const double galleyH = 120; // space at the front of the plane

  final math.Random _rand = math.Random();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final FocusNode _focus = FocusNode();

  late double _flightSeconds;
  double _time = 0;
  double get _progress => (_time / _flightSeconds).clamp(0.0, 1.0).toDouble();

  // Who is sitting where (null = empty seat). Value is a look number.
  final List<int?> _seats = List<int?>.filled(rows * 6, null);

  double _y = 30; // our position along the aisle in pixels from the top
  double? _walkTo;
  bool _up = false;
  bool _down = false;

  final List<_Request> _requests = [];
  int? _chosenSeat;
  double _spawnTimer = 3;

  // Turbulence windows, as [start, end] fractions of the flight.
  final List<List<double>> _bumps = [];
  bool _seatbeltWasOn = true;
  double _seatbeltOnFor = 0;

  double _happy = 80;
  int _served = 0;
  int _missed = 0;
  bool _finished = false;
  bool _seatedForLanding = false;

  String _banner = '';
  double _bannerTime = 0;
  double _shake = 0;

  @override
  void initState() {
    super.initState();
    final km = _distanceKm(_home, widget.destination);
    _flightSeconds = (60 + km / 300).clamp(60.0, 110.0).toDouble();
    for (var i = 0; i < _seats.length; i++) {
      if (_rand.nextDouble() < 0.82) _seats[i] = _rand.nextInt(1000);
    }
    final bumpCount = km > 6000 ? 3 : 2;
    for (var i = 0; i < bumpCount; i++) {
      final start = 0.2 + (i + _rand.nextDouble() * 0.6) * (0.6 / bumpCount);
      _bumps.add([start, start + 8 / _flightSeconds]);
    }
    _say('Welcome aboard! The seatbelt sign is on for take-off, so stay in '
        'your seat in the galley for now.', 5);
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _seatbeltOn {
    final p = _progress;
    if (p < 0.1 || p > 0.88) return true;
    for (final b in _bumps) {
      if (p >= b[0] && p <= b[1]) return true;
    }
    return false;
  }

  bool get _turbulent {
    final p = _progress;
    for (final b in _bumps) {
      if (p >= b[0] && p <= b[1]) return true;
    }
    return false;
  }

  bool get _inGalley => _y < galleyH * 0.6;

  int _rowOfSeat(int seat) => seat ~/ 6;
  double _rowCentre(int row) => galleyH + row * rowH + rowH / 2;
  double get _aisleRow => (_y - galleyH) / rowH - 0.5;

  void _say(String text, [double seconds = 3]) {
    _banner = text;
    _bannerTime = seconds;
  }

  void _tick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt > 0.05) dt = 0.05;
    if (dt <= 0 || _finished) return;
    setState(() => _update(dt));
  }

  void _update(double dt) {
    _time += dt;
    if (_bannerTime > 0) _bannerTime -= dt;
    _shake = _turbulent ? 1 : math.max(0.0, _shake - dt * 2);

    // Walking.
    final maxY = galleyH + rows * rowH - 20;
    const speed = 210.0;
    if (_up != _down) {
      _walkTo = null;
      _y += (_down ? speed : -speed) * dt;
    } else if (_walkTo != null) {
      final d = _walkTo! - _y;
      if (d.abs() < 4) {
        _walkTo = null;
      } else {
        _y += d.sign * math.min(d.abs(), speed * dt);
      }
    }
    _y = _y.clamp(24.0, maxY).toDouble();

    // Seatbelt sign.
    final on = _seatbeltOn;
    if (on != _seatbeltWasOn) {
      _seatbeltWasOn = on;
      _seatbeltOnFor = 0;
      if (on) {
        _chosenSeat = null;
        if (_progress > 0.85) {
          _say('Ding! We\'re about to land. Seatbelt sign ON. Get back to '
              'the galley and sit down!', 4);
        } else {
          _say('Ding! Turbulence ahead, seatbelt sign ON! Stop serving and '
              'get back to the galley!', 4);
        }
      } else {
        _say('Ding! Seatbelt sign OFF. Passengers are pressing their call '
            'buttons. Go and serve them!', 4);
      }
    }
    if (on) {
      _seatbeltOnFor += dt;
      if (_seatbeltOnFor > 5 && !_inGalley) {
        _happy -= 3 * dt;
        if (_bannerTime <= 0) {
          _say('The seatbelt sign is on! Go back to the galley at the front '
              'and sit down!', 2);
        }
      }
    }

    // New requests only when people are allowed to ask.
    if (!on) {
      _spawnTimer -= dt;
      if (_spawnTimer <= 0 && _requests.length < 5) {
        _spawnTimer = 2.2 + _rand.nextDouble() * 2.5;
        final free = <int>[];
        for (var i = 0; i < _seats.length; i++) {
          if (_seats[i] != null && !_requests.any((r) => r.seat == i)) {
            free.add(i);
          }
        }
        if (free.isNotEmpty) {
          final seat = free[_rand.nextInt(free.length)];
          _requests.add(_Request(
              seat, _Item.values[_rand.nextInt(_Item.values.length)], 24));
        }
      }
    }

    // Waiting passengers lose patience.
    for (final r in _requests) {
      if (!on) r.patience -= dt;
    }
    final expired = _requests.where((r) => r.patience <= 0).toList();
    for (final r in expired) {
      _requests.remove(r);
      _missed++;
      _happy -= 7;
      if (_chosenSeat == r.seat) _chosenSeat = null;
      _say('Row ${_rowOfSeat(r.seat) + 1} waited too long and gave up. '
          'They\'re grumpy now!', 2.5);
    }

    if (_progress >= 1) {
      _finished = true;
      _seatedForLanding = _inGalley;
      if (!_seatedForLanding) _happy -= 10;
      _happy = _happy.clamp(0.0, 100.0).toDouble();
      final save = SaveService.instance;
      save.saveHighScore('fly_or_crash', save.getHighScore('fly_or_crash') + 1);
    }
    _happy = _happy.clamp(0.0, 100.0).toDouble();
  }

  void _tapCabin(Offset local, double scrollY, double width) {
    _focus.requestFocus();
    final y = local.dy + scrollY;
    if (y < galleyH) {
      setState(() => _walkTo = 30);
      return;
    }
    final row = ((y - galleyH) / rowH).floor();
    if (row < 0 || row >= rows) return;
    final layout = _CabinLayout(width);
    final col = layout.columnAt(local.dx);
    if (col == null) {
      setState(() => _walkTo = _rowCentre(row));
      return;
    }
    final seat = row * 6 + col;
    final req = _requests.where((r) => r.seat == seat).toList();
    setState(() {
      if (req.isEmpty) {
        _walkTo = _rowCentre(row);
        return;
      }
      if ((_aisleRow - row).abs() > 1.2) {
        _walkTo = _rowCentre(row);
        _say('Walking to row ${row + 1}...', 1.5);
        return;
      }
      _chosenSeat = seat;
    });
  }

  void _give(_Item item) {
    final seat = _chosenSeat;
    if (seat == null) return;
    setState(() {
      final matches = _requests.where((r) => r.seat == seat).toList();
      _chosenSeat = null;
      if (matches.isEmpty) return;
      final r = matches.first;
      if (_seatbeltOn) {
        _requests.remove(r);
        _happy -= 8;
        _say('Whoops! You served during turbulence and it spilled '
            'everywhere!', 2.5);
        return;
      }
      _requests.remove(r);
      if (r.item == item) {
        _served++;
        _happy += 6;
        _say('"Thank you so much!" Row ${_rowOfSeat(seat) + 1} is happy.', 2);
      } else {
        _happy -= 4;
        _say('"Um, I asked for ${_itemNames[r.item]!.toLowerCase()}..." '
            'Wrong one!', 2.5);
      }
      _happy = _happy.clamp(0.0, 100.0).toDouble();
    });
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      _up = down;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) {
      _down = down;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1F26),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: Column(
            children: [
              _buildTop(),
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  final viewH = c.maxHeight;
                  final total = galleyH + rows * rowH + 30;
                  final scrollY =
                      (_y - viewH * 0.4).clamp(0.0, math.max(0.0, total - viewH)).toDouble();
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _tapCabin(d.localPosition, scrollY, c.maxWidth),
                    onVerticalDragUpdate: (d) => setState(() {
                      _walkTo = null;
                      _y += d.delta.dy;
                    }),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _CabinPainter(this, scrollY),
                          ),
                        ),
                        if (_bannerTime > 0)
                          Positioned(
                            left: 14,
                            right: 14,
                            top: 10,
                            child: Center(child: _Sticker(text: _banner)),
                          ),
                      ],
                    ),
                  );
                }),
              ),
              _buildTray(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTop() {
    final on = _seatbeltOn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      child: Row(
        children: [
          _RoundIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Leave',
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: on ? _sun : const Color(0xFF3A3F49),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _ink, width: 2.5),
            ),
            child: Row(
              children: [
                Icon(Icons.airline_seat_recline_normal_rounded,
                    size: 18, color: on ? _ink : Colors.white54),
                const SizedBox(width: 4),
                Text(
                  on ? 'BELTS ON' : 'Belts off',
                  style: TextStyle(
                    color: on ? _ink : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Panel(
              child: Row(
                children: [
                  Icon(
                    _happy > 60
                        ? Icons.sentiment_very_satisfied_rounded
                        : _happy > 30
                            ? Icons.sentiment_neutral_rounded
                            : Icons.sentiment_very_dissatisfied_rounded,
                    color: _ink,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: _happy / 100,
                        minHeight: 10,
                        backgroundColor: const Color(0xFFE6E6E6),
                        color: _happy > 60
                            ? _grass
                            : _happy > 30
                                ? _sun
                                : _tomato,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${(_progress * 100).round()}% to ${widget.destination.city}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTray() {
    if (_finished) return _buildEnd();
    final seat = _chosenSeat;
    if (seat == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        color: const Color(0xFF2A2E37),
        child: Text(
          _seatbeltOn
              ? 'Seatbelt sign is on. Wait in the galley at the front.'
              : 'Walk along the aisle (drag, arrow keys or tap a row). Tap a '
                  'passenger with a speech bubble to serve them.',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    final row = _rowOfSeat(seat) + 1;
    final letter = 'ABCDEF'[seat % 6];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      color: const Color(0xFF2A2E37),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Seat $row$letter. What did they ask for?',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in _Item.values)
                _SmallButton(
                  label: _itemNames[item]!,
                  icon: _itemIcons[item]!,
                  color: _itemColors[item]!,
                  onTap: () => _give(item),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnd() {
    final h = _happy.round();
    final stars = h >= 75 ? 3 : (h >= 45 ? 2 : 1);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      color: _grass,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Landed in ${widget.destination.city}!',
            style: const TextStyle(
                color: _ink, fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              3,
              (i) => Icon(
                i < stars ? Icons.star_rounded : Icons.star_border_rounded,
                color: _ink,
                size: 36,
              ),
            ),
          ),
          Text(
            'You served $_served passengers. $_missed gave up waiting. '
            'Happy passengers: $h%.'
            '${_seatedForLanding ? '' : '\nYou weren\'t in your seat for landing!'}',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: _ink, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _ChunkyButton(
            label: 'Back to the map',
            color: _sun,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Where the seats sit across the cabin, for drawing and for taps.
class _CabinLayout {
  final double width;
  late final double wall;
  late final double seatW;
  late final double aisleW;

  _CabinLayout(this.width) {
    wall = width * 0.07;
    aisleW = width * 0.16;
    seatW = (width - wall * 2 - aisleW) / 6;
  }

  double seatLeft(int col) {
    if (col < 3) return wall + col * seatW;
    return wall + 3 * seatW + aisleW + (col - 3) * seatW;
  }

  double get aisleCentre => wall + 3 * seatW + aisleW / 2;

  int? columnAt(double x) {
    for (var c = 0; c < 6; c++) {
      final l = seatLeft(c);
      if (x >= l && x < l + seatW) return c;
    }
    return null;
  }
}

class _CabinPainter extends CustomPainter {
  final _AttendantScreenState s;
  final double scrollY;

  _CabinPainter(this.s, this.scrollY);

  static const List<Color> _skins = [
    Color(0xFFF3D2B3),
    Color(0xFFE0B48F),
    Color(0xFFB98563),
    Color(0xFF8D5A3B),
    Color(0xFF5E3A24),
  ];
  static const List<Color> _hairs = [
    Color(0xFF2B1D14),
    Color(0xFF5A3A22),
    Color(0xFFC9A15A),
    Color(0xFF8E3B1F),
    Color(0xFF1A1A1A),
    Color(0xFFB0B0B0),
  ];
  static const List<Color> _tops = [
    Color(0xFF3F6FD1),
    Color(0xFFE85D5D),
    Color(0xFF4CAF7A),
    Color(0xFFF2C14E),
    Color(0xFF7B4FB8),
    Color(0xFF555B66),
    Color(0xFFF2F2F2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final layout = _CabinLayout(w);
    final shakeX = s._shake > 0 ? math.sin(s._time * 40) * 3 * s._shake : 0.0;
    canvas.save();
    canvas.translate(shakeX, -scrollY);

    final totalH = _AttendantScreenState.galleyH +
        _AttendantScreenState.rows * _AttendantScreenState.rowH +
        30;

    // Floor and walls of the cabin.
    canvas.drawRect(Rect.fromLTWH(0, 0, w, totalH),
        Paint()..color = const Color(0xFFD9D4CA));
    final wallPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(layout.wall, 0),
        [const Color(0xFF9EA4AD), const Color(0xFFE9E6E0)],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, layout.wall, totalH), wallPaint);
    canvas.save();
    canvas.translate(w, 0);
    canvas.scale(-1, 1);
    canvas.drawRect(Rect.fromLTWH(0, 0, layout.wall, totalH), wallPaint);
    canvas.restore();

    // Windows along the walls, with a peek of sky.
    for (var r = 0; r < _AttendantScreenState.rows; r++) {
      final y = _AttendantScreenState.galleyH + r * _AttendantScreenState.rowH + 16;
      for (final x in [layout.wall * 0.35, w - layout.wall * 0.65]) {
        final win = RRect.fromRectAndRadius(
            Rect.fromLTWH(x - 2, y, layout.wall * 0.35, 30), const Radius.circular(8));
        canvas.drawRRect(win, Paint()..color = const Color(0xFF9FD3F5));
      }
    }

    // Aisle carpet.
    canvas.drawRect(
      Rect.fromLTWH(layout.aisleCentre - layout.aisleW / 2, 0, layout.aisleW, totalH),
      Paint()..color = const Color(0xFF34407A),
    );
    final stripe = Paint()
      ..color = const Color(0xFF4A57A0)
      ..strokeWidth = 2;
    for (var y = 10.0; y < totalH; y += 24) {
      canvas.drawLine(Offset(layout.aisleCentre - layout.aisleW / 2 + 4, y),
          Offset(layout.aisleCentre + layout.aisleW / 2 - 4, y + 8), stripe);
    }

    // Galley at the front.
    final galley = Rect.fromLTWH(layout.wall, 0, w - layout.wall * 2,
        _AttendantScreenState.galleyH - 12);
    canvas.drawRect(galley, Paint()..color = const Color(0xFFC3C8CF));
    for (var i = 0; i < 5; i++) {
      final box = Rect.fromLTWH(galley.left + 10 + i * (galley.width - 20) / 5,
          8, (galley.width - 20) / 5 - 6, 34);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)),
          Paint()..color = const Color(0xFF9CA3AD));
      canvas.drawCircle(box.center, 3, Paint()..color = const Color(0xFF5A616B));
    }
    _text(canvas, 'GALLEY  (your seat when the seatbelt sign is on)',
        Offset(w / 2, 62), 11, const Color(0xFF3B414B));
    // Jump seat.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(layout.aisleCentre - 22, 76, 44, 22), const Radius.circular(6)),
      Paint()..color = s._seatbeltOn ? _sun : const Color(0xFF7C838E),
    );

    // Seats and passengers.
    for (var r = 0; r < _AttendantScreenState.rows; r++) {
      final top = _AttendantScreenState.galleyH + r * _AttendantScreenState.rowH;
      if (top - scrollY > size.height + 80 || top - scrollY < -100) continue;
      _text(canvas, '${r + 1}', Offset(layout.aisleCentre, top + 10), 10,
          Colors.white.withValues(alpha: 0.7));
      for (var c = 0; c < 6; c++) {
        final seat = r * 6 + c;
        final x = layout.seatLeft(c);
        final rect = Rect.fromLTWH(x + 3, top + 8, layout.seatW - 6,
            _AttendantScreenState.rowH - 14);
        _drawSeat(canvas, rect, s._chosenSeat == seat);
        final look = s._seats[seat];
        if (look != null) _drawPassenger(canvas, rect, look);
      }
    }

    // Requests as speech bubbles.
    for (final req in s._requests) {
      final r = req.seat ~/ 6;
      final c = req.seat % 6;
      final x = layout.seatLeft(c) + layout.seatW / 2;
      final y = _AttendantScreenState.galleyH + r * _AttendantScreenState.rowH + 6;
      _bubble(canvas, Offset(x, y), req);
    }

    // You, pushing the trolley.
    _drawAttendant(canvas, Offset(layout.aisleCentre, s._y), layout.aisleW);

    canvas.restore();

    if (s._seatbeltOn) {
      canvas.drawRect(Offset.zero & size,
          Paint()..color = const Color(0xFFFFC93C).withValues(alpha: 0.06));
    }
  }

  void _drawSeat(Canvas canvas, Rect r, bool chosen) {
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(8));
    canvas.drawRRect(
      rr.shift(const Offset(0, 3)),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = ui.Gradient.linear(
          r.topCenter,
          r.bottomCenter,
          [const Color(0xFF3550A8), const Color(0xFF243A82)],
        ),
    );
    // Headrest cover.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(r.left + 3, r.bottom - 14, r.width - 6, 10),
          const Radius.circular(4)),
      Paint()..color = const Color(0xFFE9E6DF),
    );
    if (chosen) {
      canvas.drawRRect(
        rr,
        Paint()
          ..color = _sun
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  /// A passenger seen from above, facing the front of the plane.
  void _drawPassenger(Canvas canvas, Rect seat, int look) {
    final skin = _skins[look % _skins.length];
    final hair = _hairs[(look ~/ 5) % _hairs.length];
    final top = _tops[(look ~/ 30) % _tops.length];
    final c = Offset(seat.center.dx, seat.center.dy - 2);
    final shoulders = Rect.fromCenter(
        center: c.translate(0, 8), width: seat.width * 0.86, height: 18);
    canvas.drawRRect(
        RRect.fromRectAndRadius(shoulders, const Radius.circular(9)),
        Paint()..color = top);
    final headR = seat.width * 0.22;
    canvas.drawCircle(c.translate(0, -2), headR, Paint()..color = skin);
    // Hair covers the back of the head (we see it from behind/above).
    canvas.drawArc(
      Rect.fromCircle(center: c.translate(0, -2), radius: headR),
      0.15,
      math.pi - 0.3,
      true,
      Paint()..color = hair,
    );
    if (s._turbulent && look % 3 == 0) {
      _text(canvas, '!', c.translate(headR + 4, -headR), 12, _tomato);
    }
  }

  void _bubble(Canvas canvas, Offset at, _Request req) {
    final urgent = req.patience < 8;
    final rect = Rect.fromCenter(center: at.translate(0, -2), width: 34, height: 26);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(9));
    canvas.drawRRect(rr, Paint()..color = urgent ? const Color(0xFFFFE1DC) : Colors.white);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = urgent ? _tomato : _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final icon = _itemIcons[req.item]!;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 17,
          color: _itemColors[req.item],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
    // Patience bar.
    final frac = (req.patience / 24).clamp(0.0, 1.0).toDouble();
    canvas.drawRect(
      Rect.fromLTWH(rect.left + 3, rect.bottom - 4, (rect.width - 6) * frac, 2.5),
      Paint()..color = urgent ? _tomato : _grass,
    );
  }

  void _drawAttendant(Canvas canvas, Offset c, double aisleW) {
    // Trolley in front (towards the back of the plane = down the screen).
    final trolley = Rect.fromCenter(
        center: c.translate(0, 34), width: aisleW * 0.78, height: 34);
    canvas.drawRRect(
        RRect.fromRectAndRadius(trolley, const Radius.circular(4)),
        Paint()..color = const Color(0xFFB9BFC8));
    canvas.drawRect(
        Rect.fromLTWH(trolley.left + 3, trolley.top + 4, trolley.width - 6, 6),
        Paint()..color = const Color(0xFF8A919B));
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(
        Offset(trolley.left + 8 + i * (trolley.width - 16) / 3, trolley.top + 22),
        4,
        Paint()..color = _itemColors.values.elementAt(i),
      );
    }
    // Body in uniform.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: c.translate(0, 6), width: aisleW * 0.7, height: 20),
          const Radius.circular(10)),
      Paint()..color = const Color(0xFF6A4FD8),
    );
    canvas.drawCircle(c, 11, Paint()..color = const Color(0xFFE0B48F));
    canvas.drawArc(Rect.fromCircle(center: c, radius: 11), math.pi * 1.05,
        math.pi * 0.9, true, Paint()..color = const Color(0xFF2B1D14));
    canvas.drawCircle(c.translate(0, -12), 5, Paint()..color = const Color(0xFF2B1D14));
    _text(canvas, 'YOU', c.translate(0, -26), 10, _ink);
  }

  void _text(Canvas canvas, String text, Offset at, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _CabinPainter oldDelegate) => true;
}
