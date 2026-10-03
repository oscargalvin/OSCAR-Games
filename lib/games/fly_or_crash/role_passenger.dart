part of 'fly_or_crash_screen.dart';

// ===========================================================================
// Passenger mode: check in, go through security, walk onto the plane, enjoy
// the flight from your seat, then get off and explore the city, see the
// famous landmarks and stay in a hotel.
// ===========================================================================

enum _Stage { departAirport, flight, arriveAirport, city, hotel }

class _Spot {
  final String id;
  final double x;
  final String sign;
  final String action;
  final IconData icon;
  final bool barrier;
  bool done = false;

  _Spot(this.id, this.x, this.sign, this.action, this.icon,
      {this.barrier = false});
}

class _Npc {
  double x;
  double dir;
  final double speed;
  final int look;
  _Npc(this.x, this.dir, this.speed, this.look);
}

class _LandmarkInfo {
  final String name;
  final String fact;
  const _LandmarkInfo(this.name, this.fact);
}

const Map<String, _LandmarkInfo> _landmarkInfo = {
  'New York|empire': _LandmarkInfo('Empire State Building',
      'It has 102 floors and is 443 metres tall to the tip of its spire!'),
  'New York|liberty': _LandmarkInfo('Statue of Liberty',
      'A present from France in 1886. Her torch is 93 metres above the ground!'),
  'Paris|eiffel': _LandmarkInfo('Eiffel Tower',
      'Built in 1889. It grows about 15 cm taller in summer because the hot metal stretches!'),
  'Rome|colosseum': _LandmarkInfo('Colosseum',
      'Nearly 2,000 years old! About 50,000 people could watch the games here.'),
  'Rome|dome': _LandmarkInfo('St Peter\'s Basilica',
      'One of the biggest churches in the world, with a gigantic dome.'),
  'Reykjavik|church': _LandmarkInfo('Hallgrímskirkja',
      'This church was designed to look like the lava rock columns you find in Iceland.'),
  'Reykjavik|snowPeak': _LandmarkInfo('Mount Esja',
      'A snowy mountain across the bay that Icelanders love to hike up.'),
  'Cairo|pyramid': _LandmarkInfo('Pyramids of Giza',
      'Over 4,500 years old! The biggest one was the tallest thing ever built for almost 4,000 years.'),
  'Dubai|burj': _LandmarkInfo('Burj Khalifa',
      'The tallest building in the world: 828 metres, with 163 floors!'),
  'Dubai|sail': _LandmarkInfo('Burj Al Arab',
      'A hotel shaped like a sail, built on its own little island.'),
  'Mumbai|dome': _LandmarkInfo('Gateway of India',
      'A giant stone arch by the sea, finished in 1924.'),
  'Los Angeles|hills': _LandmarkInfo('Hollywood Hills',
      'Home of the famous HOLLYWOOD sign and lots of film stars!'),
  'Los Angeles|palm': _LandmarkInfo('Palm tree avenue',
      'LA is famous for its long roads lined with super tall palm trees.'),
  'Rio de Janeiro|sugarloaf': _LandmarkInfo('Sugarloaf Mountain',
      'You can ride a cable car all the way to the top!'),
  'Rio de Janeiro|christ': _LandmarkInfo('Christ the Redeemer',
      'A 30-metre statue on top of a mountain, with its arms stretched over the city.'),
  'Cape Town|tableMountain': _LandmarkInfo('Table Mountain',
      'It\'s flat like a table, and clouds pour over the top like a tablecloth!'),
  'Tokyo|tokyoTower': _LandmarkInfo('Tokyo Tower',
      'Painted orange and white so planes can see it. 333 metres tall!'),
  'Tokyo|snowPeak': _LandmarkInfo('Mount Fuji',
      'Japan\'s tallest mountain at 3,776 metres. It\'s actually a volcano!'),
  'Sydney|opera': _LandmarkInfo('Sydney Opera House',
      'Its roof looks like sails and is covered in over a million tiles!'),
  'Sydney|bridge': _LandmarkInfo('Sydney Harbour Bridge',
      'Locals call it "The Coathanger" because of its shape.'),
  'Madrid|dome': _LandmarkInfo('Royal Palace',
      'The biggest royal palace in Western Europe, with more than 3,000 rooms!'),
  'Berlin|needle': _LandmarkInfo('Berlin TV Tower',
      '368 metres tall, and the restaurant inside the ball slowly spins round!'),
  'Amsterdam|gabled': _LandmarkInfo('Canal houses',
      'They\'re tall and skinny because people used to pay tax by how wide their house was!'),
  'Athens|temple': _LandmarkInfo('Parthenon',
      'A temple built about 2,500 years ago on a hill called the Acropolis.'),
  'Istanbul|mosque': _LandmarkInfo('Blue Mosque',
      'It has six tall towers called minarets and over 20,000 blue tiles inside.'),
  'Moscow|onion': _LandmarkInfo('St Basil\'s Cathedral',
      'Famous for its colourful onion-shaped domes. Built in the 1500s!'),
  'Oslo|hills': _LandmarkInfo('Holmenkollen',
      'A giant ski jump on the hill above the city!'),
  'Dublin|hills': _LandmarkInfo('Wicklow Mountains',
      'Green hills just outside Dublin where lots of films have been made.'),
  'Toronto|needle': _LandmarkInfo('CN Tower',
      '553 metres tall, with a glass floor you can stand on and look straight down!'),
  'Mexico City|pyramid': _LandmarkInfo('Teotihuacan',
      'Ancient pyramids almost 2,000 years old, just outside the city.'),
  'Mexico City|snowPeak': _LandmarkInfo('Popocatépetl',
      'An active volcano that still puffs out smoke!'),
  'Miami|palm': _LandmarkInfo('Miami Beach',
      'Sunny beaches and bright, colourful buildings by the sea.'),
  'San Francisco|suspension': _LandmarkInfo('Golden Gate Bridge',
      'Its colour is called "International Orange", and it\'s 2.7 km long!'),
  'Honolulu|hills': _LandmarkInfo('Diamond Head',
      'An old volcano crater you can hike right to the top of.'),
  'Honolulu|palm': _LandmarkInfo('Waikiki Beach',
      'One of the most famous surfing beaches in the world!'),
  'Buenos Aires|obelisk': _LandmarkInfo('The Obelisco',
      'A 67-metre white monument in the middle of one of the widest streets in the world.'),
  'Lima|hills': _LandmarkInfo('Andes foothills',
      'The start of the Andes, the longest mountain range on Earth!'),
  'Nairobi|acacia': _LandmarkInfo('Nairobi National Park',
      'You can see giraffes, lions and zebras with skyscrapers in the background!'),
  'Marrakesh|minaret': _LandmarkInfo('Koutoubia Mosque',
      'Its tower is 77 metres tall and almost 900 years old.'),
  'Marrakesh|snowPeak': _LandmarkInfo('Atlas Mountains',
      'Snowy mountains right next to the desert!'),
  'Beijing|pagoda': _LandmarkInfo('Temple of Heaven',
      'Emperors came here long ago to pray for good harvests.'),
  'Hong Kong|hills': _LandmarkInfo('Victoria Peak',
      'Ride the super steep Peak Tram up to see all the skyscrapers.'),
  'Singapore|marinaBay': _LandmarkInfo('Marina Bay Sands',
      'A hotel with a giant swimming pool on the roof, 200 metres up!'),
  'Bangkok|stupa': _LandmarkInfo('Wat Arun',
      'The Temple of Dawn, decorated with thousands of colourful pieces of china.'),
  'Seoul|needle': _LandmarkInfo('N Seoul Tower',
      'People hang "love locks" on the fence at the top of the mountain.'),
  'Delhi|mosque': _LandmarkInfo('Jama Masjid',
      'One of the biggest mosques in India, with room for 25,000 people.'),
  'Delhi|dome': _LandmarkInfo('Humayun\'s Tomb',
      'A beautiful tomb in a garden. It inspired the Taj Mahal!'),
  'Auckland|needle': _LandmarkInfo('Sky Tower',
      '328 metres tall, and you can bungee jump off it!'),
  'Bali|pagoda': _LandmarkInfo('Bali temple',
      'Bali has thousands of temples with tall, many-roofed towers.'),
  'Bali|snowPeak': _LandmarkInfo('Mount Agung',
      'Bali\'s highest volcano, 3,031 metres tall.'),
};

class PassengerScreen extends StatefulWidget {
  final Destination destination;

  const PassengerScreen({super.key, required this.destination});

  @override
  State<PassengerScreen> createState() => _PassengerScreenState();
}

class _PassengerScreenState extends State<PassengerScreen>
    with SingleTickerProviderStateMixin {
  final math.Random _rand = math.Random();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final FocusNode _focus = FocusNode();

  _Stage _stage = _Stage.departAirport;
  double _time = 0;

  // Walking scenes.
  List<_Spot> _spots = [];
  double _sceneW = 2000;
  double _x = 80;
  double? _walkTo;
  bool _left = false;
  bool _right = false;
  bool _facingRight = true;
  double _walkPhase = 0;
  bool _moving = false;
  double _camX = 0;
  double _viewW = 400;
  final List<_Npc> _npcs = [];

  // Trip details.
  late final String _seat;
  late final List<_Feature> _scenery;
  final List<_Feature> _landmarks = [];
  int _seen = 0;
  int _day = 1;
  double _night = 0; // 0 = day, 1 = dark while sleeping
  bool _sleeping = false;

  // The flight.
  double _flightP = 0;
  double _flightSeconds = 45;
  double _napTime = 0;
  bool _bigWindow = false;
  bool _film = false;
  bool _snack = false;
  late final double _bumpStart;
  final Set<String> _announced = {};

  String _message = '';
  double _messageTime = 0;

  @override
  void initState() {
    super.initState();
    _seat = '${12 + _rand.nextInt(20)}${'ACDF'[_rand.nextInt(4)]}';
    _scenery = _sceneryFor(widget.destination.city, _rand);
    final seenKinds = <_Lm>{};
    for (final f in _scenery) {
      final key = '${widget.destination.city}|${f.kind.name}';
      if (_landmarkInfo.containsKey(key) && seenKinds.add(f.kind)) {
        _landmarks.add(f);
      }
    }
    final km = _distanceKm(_home, widget.destination);
    _flightSeconds = (35 + km / 600).clamp(35.0, 60.0).toDouble();
    _bumpStart = 0.35 + _rand.nextDouble() * 0.3;
    _enterStage(_Stage.departAirport);
    _say('Welcome to London Airport! Find the Check-in desk. Walk with the '
        'arrow keys, or tap where you want to go.', 5);
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _city => widget.destination.city;

  void _say(String text, [double seconds = 4]) {
    _message = text;
    _messageTime = seconds;
  }

  void _enterStage(_Stage stage, {double startX = 80}) {
    _stage = stage;
    _x = startX;
    _walkTo = null;
    _npcs.clear();
    switch (stage) {
      case _Stage.departAirport:
        _spots = [
          _Spot('checkin', 340, 'Check-in', 'Check in',
              Icons.confirmation_number_rounded),
          _Spot('security', 760, 'Security', 'Walk through the scanner',
              Icons.security_rounded,
              barrier: true),
          _Spot('cafe', 1100, 'Café', 'Buy a snack', Icons.local_cafe_rounded),
          _Spot('gate', 1460, 'Gate 12', 'Show your boarding pass',
              Icons.qr_code_rounded,
              barrier: true),
          _Spot('board', 1800, 'To the plane', 'Walk onto the plane',
              Icons.flight_takeoff_rounded),
        ];
        _sceneW = 1980;
        _addNpcs(7);
        break;
      case _Stage.flight:
        _spots = [];
        break;
      case _Stage.arriveAirport:
        _spots = [
          _Spot('passport', 380, 'Passport control', 'Show your passport',
              Icons.assignment_ind_rounded,
              barrier: true),
          _Spot('bags', 780, 'Baggage claim', 'Grab your suitcase',
              Icons.work_rounded,
              barrier: true),
          _Spot('exit', 1170, 'Exit to $_city', 'Go outside',
              Icons.exit_to_app_rounded),
        ];
        _sceneW = 1360;
        _addNpcs(6);
        break;
      case _Stage.city:
        final list = <_Spot>[
          _Spot('taxi', 150, 'Taxi', 'Take a taxi to the airport',
              Icons.local_taxi_rounded),
          _Spot('hotel', 560, 'Hotel Oscar', 'Go into the hotel',
              Icons.hotel_rounded),
        ];
        for (var i = 0; i < _landmarks.length; i++) {
          final info = _landmarkInfo['$_city|${_landmarks[i].kind.name}']!;
          list.add(_Spot('lm$i', 1080 + i * 820.0, info.name,
              'Look at the ${info.name}', Icons.photo_camera_rounded));
        }
        if (_landmarks.isEmpty) {
          list.add(_Spot('square', 1080, 'Town square', 'Look around',
              Icons.photo_camera_rounded));
        }
        _sceneW = list.last.x + 640;
        _spots = list;
        _addNpcs(9);
        break;
      case _Stage.hotel:
        _spots = [
          _Spot('out', 130, 'Exit', 'Go back outside', Icons.meeting_room_rounded),
          _Spot('reception', 430, 'Reception', 'Check in to your room',
              Icons.room_service_rounded,
              barrier: true),
          _Spot('lift', 780, 'Lifts', 'Ride up to your room',
              Icons.arrow_upward_rounded,
              barrier: true),
          _Spot('bed', 1240, 'Room 404', 'Go to sleep', Icons.hotel_rounded),
          _Spot('window', 1500, 'Window', 'Look out of the window',
              Icons.landscape_rounded),
        ];
        _sceneW = 1700;
        break;
    }
  }

  void _addNpcs(int n) {
    for (var i = 0; i < n; i++) {
      _npcs.add(_Npc(
        _rand.nextDouble() * _sceneW,
        _rand.nextBool() ? 1 : -1,
        40 + _rand.nextDouble() * 50,
        _rand.nextInt(1000),
      ));
    }
  }

  _Spot? _spot(String id) {
    for (final s in _spots) {
      if (s.id == id) return s;
    }
    return null;
  }

  // ---- loop -----------------------------------------------------------------

  void _tick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt > 0.05) dt = 0.05;
    if (dt <= 0) return;
    setState(() => _update(dt));
  }

  void _update(double dt) {
    _time += dt;
    if (_messageTime > 0) _messageTime -= dt;

    if (_sleeping) {
      _night += dt * 0.6;
      if (_night >= 1.6) {
        _sleeping = false;
        _day++;
        _say('Good morning! It\'s day $_day in $_city. Time to explore some '
            'more!', 5);
      }
    } else if (_night > 0) {
      _night = math.max(0.0, _night - dt * 0.8);
    }

    if (_stage == _Stage.flight) {
      _updateFlight(dt);
      return;
    }

    // Walking.
    const speed = 240.0;
    var dx = 0.0;
    if (_left != _right) {
      _walkTo = null;
      dx = (_right ? 1 : -1) * speed * dt;
    } else if (_walkTo != null) {
      final d = _walkTo! - _x;
      if (d.abs() < 4) {
        _walkTo = null;
      } else {
        dx = d.sign * math.min(d.abs(), speed * dt);
      }
    }
    _moving = dx != 0;
    if (_moving) {
      _facingRight = dx > 0;
      _walkPhase += dt * 9;
      var nx = (_x + dx).clamp(40.0, _sceneW - 40).toDouble();
      // You can't walk past a desk or gate until you've done it.
      for (final s in _spots) {
        if (s.barrier && !s.done && _x <= s.x + 20 && nx > s.x + 20) {
          nx = s.x + 20;
          _walkTo = null;
          if (_messageTime <= 0) {
            _say('You need to ${s.action.toLowerCase()} first!', 2.5);
          }
        }
      }
      _x = nx;
    }
    _camX = (_x - _viewW * 0.45).clamp(0.0, math.max(0.0, _sceneW - _viewW)).toDouble();

    for (final n in _npcs) {
      n.x += n.dir * n.speed * dt;
      if (n.x < 0 || n.x > _sceneW) n.dir = -n.dir;
    }
  }

  void _updateFlight(double dt) {
    final speedUp = _napTime > 0 ? 6.0 : 1.0;
    if (_napTime > 0) _napTime -= dt;
    _flightP = math.min(1.0, _flightP + dt * speedUp / _flightSeconds);

    void announce(String id, double at, String text) {
      if (_flightP >= at && _announced.add(id)) _say(text, 5);
    }

    announce('hello', 0.0,
        'Captain: "Welcome aboard Oscar Air to $_city! Seatbelts on for '
            'take-off, please."');
    announce('off', 0.12,
        'Ding! The seatbelt sign is off. Ava is coming round with snacks.');
    announce('bump', _bumpStart,
        'Captain: "A bit of turbulence ahead, folks. Seatbelts on, please!"');
    announce('calm', _bumpStart + 0.08, 'Ding! Smooth air again.');
    announce('down', 0.88,
        'Captain: "We\'re starting our descent into $_city. Seatbelts on!"');
    if (_flightP >= 1 && _announced.add('landed')) {
      _say('Bump! We\'ve landed in $_city! Welcome!', 6);
    }
  }

  bool get _seatbeltOn =>
      _flightP < 0.12 ||
      _flightP > 0.88 ||
      (_flightP > _bumpStart && _flightP < _bumpStart + 0.08);

  bool get _turbulent =>
      _flightP > _bumpStart && _flightP < _bumpStart + 0.08;

  // ---- actions ----------------------------------------------------------------

  _Spot? get _nearSpot {
    _Spot? best;
    var bestD = 90.0;
    for (final s in _spots) {
      final d = (s.x - _x).abs();
      if (d < bestD) {
        bestD = d;
        best = s;
      }
    }
    return best;
  }

  void _doSpot(_Spot s) {
    if (s.id == 'taxi') {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      switch (s.id) {
        case 'checkin':
          s.done = true;
          _say('Here\'s your boarding pass: seat $_seat, Gate 12. Your '
              'suitcase goes on the belt. Now go through Security!', 6);
          break;
        case 'security':
          if (!(_spot('checkin')?.done ?? false)) {
            _say('You need a boarding pass! Go back and check in first.', 3);
            return;
          }
          s.done = true;
          _say('Beep... all clear! Shoes back on. Head to Gate 12.', 4);
          break;
        case 'cafe':
          _snack = true;
          _say('You bought a croissant and an orange juice. Yum!', 3);
          break;
        case 'gate':
          s.done = true;
          _say('Boarding pass scanned. Seat $_seat. Walk down to the plane!', 4);
          break;
        case 'board':
          if (!(_spot('gate')?.done ?? false)) {
            _say('Show your boarding pass at the gate first!', 3);
            return;
          }
          _enterStage(_Stage.flight);
          _flightP = 0;
          _say('You found seat $_seat by the window. Buckle up!', 4);
          break;
        case 'passport':
          s.done = true;
          _say('Stamp! "Welcome to ${widget.destination.country == 'Your pin' ? _city : widget.destination.country}! Enjoy your stay."', 4);
          break;
        case 'bags':
          s.done = true;
          _say('There\'s your suitcase going round on the belt. Got it!', 3);
          break;
        case 'exit':
          _enterStage(_Stage.city, startX: 240);
          _say(_welcomeLine(_city), 6);
          break;
        case 'hotel':
          _enterStage(_Stage.hotel, startX: 200);
          _say('Welcome to Hotel Oscar! Check in at Reception.', 4);
          break;
        case 'out':
          _enterStage(_Stage.city, startX: 600);
          break;
        case 'reception':
          s.done = true;
          _say('"Here\'s your key card. Room 404 on the fourth floor!"', 4);
          break;
        case 'lift':
          if (!(_spot('reception')?.done ?? false)) {
            _say('You need a key card from Reception first!', 3);
            return;
          }
          s.done = true;
          _x = 1000;
          _say('Ding! Fourth floor. Your room is just along here.', 3);
          break;
        case 'bed':
          _sleeping = true;
          _night = 0;
          _say('Zzzzz...', 2);
          break;
        case 'window':
          _say(_landmarks.isEmpty
              ? 'What a view of the city!'
              : 'Wow, you can see the ${_landmarkInfo['$_city|${_landmarks.first.kind.name}']!.name} from here!', 4);
          break;
        default:
          if (s.id.startsWith('lm')) {
            final i = int.parse(s.id.substring(2));
            final info = _landmarkInfo['$_city|${_landmarks[i].kind.name}']!;
            if (!s.done) {
              s.done = true;
              _seen++;
            }
            _say('${info.name}: ${info.fact}', 7);
          } else {
            _say('What a lovely place! Lots of people, shops and cafés.', 4);
          }
      }
    });
    _focus.requestFocus();
  }

  String get _goal {
    switch (_stage) {
      case _Stage.departAirport:
        for (final s in _spots) {
          if ((s.id == 'checkin' || s.id == 'security' || s.id == 'gate') &&
              !s.done) {
            return 'Next: ${s.sign}';
          }
        }
        return 'Next: walk onto the plane';
      case _Stage.flight:
        return 'Seat $_seat';
      case _Stage.arriveAirport:
        for (final s in _spots) {
          if (s.barrier && !s.done) return 'Next: ${s.sign}';
        }
        return 'Next: go outside';
      case _Stage.city:
        return _landmarks.isEmpty
            ? 'Explore $_city'
            : 'Landmarks seen: $_seen of ${_landmarks.length}';
      case _Stage.hotel:
        return 'Hotel Oscar · Day $_day';
    }
  }

  String get _placeName {
    switch (_stage) {
      case _Stage.departAirport:
        return 'London Airport';
      case _Stage.flight:
        return 'Flight to $_city';
      case _Stage.arriveAirport:
        return '$_city Airport';
      case _Stage.city:
        return _city;
      case _Stage.hotel:
        return 'Hotel Oscar';
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      _left = down;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyD) {
      _right = down;
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) &&
        event is KeyDownEvent) {
      final s = _nearSpot;
      if (s != null && _stage != _Stage.flight) _doSpot(s);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
        child: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(builder: (context, c) {
                _viewW = c.maxWidth;
                if (_stage == _Stage.flight) {
                  return CustomPaint(painter: _SeatViewPainter(this));
                }
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    _focus.requestFocus();
                    _walkTo = (_camX + d.localPosition.dx)
                        .clamp(40.0, _sceneW - 40)
                        .toDouble();
                  },
                  onHorizontalDragUpdate: (d) {
                    _walkTo = (_x + d.delta.dx * 3)
                        .clamp(40.0, _sceneW - 40)
                        .toDouble();
                  },
                  child: CustomPaint(painter: _WalkPainter(this)),
                );
              }),
            ),
            SafeArea(child: _buildTop()),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(top: false, child: _buildBottom()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTop() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 0),
      child: Row(
        children: [
          _RoundIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Leave',
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Panel(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _placeName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _goal,
                    style: TextStyle(
                      color: _ink.withValues(alpha: 0.75),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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

  Widget _buildBottom() {
    final children = <Widget>[];
    if (_messageTime > 0 && _message.isNotEmpty) {
      children.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _ink, width: 2.5),
        ),
        child: Text(
          _message,
          style: const TextStyle(
            color: _ink,
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
        ),
      ));
      children.add(const SizedBox(height: 10));
    }

    if (_stage == _Stage.flight) {
      if (_flightP >= 1) {
        children.add(_ChunkyButton(
          label: 'Get off the plane',
          color: _sun,
          onPressed: () => setState(() {
            _enterStage(_Stage.arriveAirport);
            _say('Welcome to $_city Airport! Go through Passport control.', 4);
          }),
        ));
      } else {
        children.add(Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _SmallButton(
              label: _bigWindow ? 'Sit back' : 'Look out of the window',
              icon: Icons.landscape_rounded,
              color: Colors.white,
              onTap: () => setState(() => _bigWindow = !_bigWindow),
            ),
            _SmallButton(
              label: 'Ask for a snack',
              icon: Icons.fastfood_rounded,
              color: _sun,
              onTap: () => setState(() {
                if (_seatbeltOn) {
                  _say('Ava: "Sorry, I can\'t serve while the seatbelt sign '
                      'is on. I\'ll come back soon!"', 3);
                } else {
                  _snack = true;
                  _say('Ava brings you crisps, a cookie and some juice. '
                      'Delicious!', 3);
                }
              }),
            ),
            _SmallButton(
              label: _film ? 'Show the map' : 'Watch a film',
              icon: _film ? Icons.map_rounded : Icons.movie_rounded,
              color: Colors.white,
              onTap: () => setState(() => _film = !_film),
            ),
            _SmallButton(
              label: 'Have a nap',
              icon: Icons.nightlight_round,
              color: const Color(0xFFB79BFF),
              onTap: () => setState(() {
                _napTime = 5;
                _say('Zzz... you nod off for a while.', 3);
              }),
            ),
          ],
        ));
      }
    } else if (!_sleeping) {
      final s = _nearSpot;
      if (s != null) {
        children.add(_ChunkyButton(
          label: s.action,
          color: s.done && s.barrier ? Colors.white : _sun,
          onPressed: () => _doSpot(s),
        ));
      } else {
        children.add(Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'Walk with the arrow keys, drag, or tap where you want to go.',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ));
      }
    }
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}

// ---- drawing people ----------------------------------------------------------

const List<Color> _skinTones = [
  Color(0xFFF3D2B3),
  Color(0xFFE0B48F),
  Color(0xFFB98563),
  Color(0xFF8D5A3B),
  Color(0xFF5E3A24),
];
const List<Color> _hairTones = [
  Color(0xFF2B1D14),
  Color(0xFF5A3A22),
  Color(0xFFC9A15A),
  Color(0xFF8E3B1F),
  Color(0xFF1A1A1A),
  Color(0xFFB0B0B0),
];
const List<Color> _clothes = [
  Color(0xFF3F6FD1),
  Color(0xFFE85D5D),
  Color(0xFF4CAF7A),
  Color(0xFFF2C14E),
  Color(0xFF7B4FB8),
  Color(0xFF555B66),
  Color(0xFFF2F2F2),
];

/// A person seen from the side. [feet] is where they stand, [h] their height.
void _drawWalker(Canvas canvas, Offset feet, double h, double phase,
    bool facingRight, int look,
    {bool backpack = false, bool suitcase = false, bool moving = true}) {
  final skin = _skinTones[look % _skinTones.length];
  final hair = _hairTones[(look ~/ 5) % _hairTones.length];
  final shirt = _clothes[(look ~/ 30) % _clothes.length];
  final trousers = Color.lerp(_clothes[(look ~/ 7) % _clothes.length], Colors.black, 0.45)!;
  final swing = moving ? math.sin(phase) * 0.45 : 0.0;
  final dir = facingRight ? 1.0 : -1.0;

  // Shadow.
  canvas.drawOval(
    Rect.fromCenter(center: feet, width: h * 0.4, height: h * 0.06),
    Paint()..color = Colors.black.withValues(alpha: 0.18),
  );

  final hip = feet.translate(0, -h * 0.47);
  final shoulder = feet.translate(dir * h * 0.01, -h * 0.8);
  final legPaint = Paint()
    ..color = trousers
    ..strokeWidth = h * 0.085
    ..strokeCap = StrokeCap.round;
  final armPaint = Paint()
    ..color = shirt
    ..strokeWidth = h * 0.065
    ..strokeCap = StrokeCap.round;

  Offset limb(Offset from, double len, double angle) =>
      from + Offset(math.sin(angle) * len * dir, math.cos(angle) * len);

  if (suitcase) {
    final handle = limb(shoulder, h * 0.33, -swing - 0.5);
    final caseRect = Rect.fromLTWH(
        handle.dx - dir * h * 0.05 - (facingRight ? h * 0.2 : 0),
        feet.dy - h * 0.3, h * 0.2, h * 0.28);
    canvas.drawRRect(
        RRect.fromRectAndRadius(caseRect, Radius.circular(h * 0.03)),
        Paint()..color = const Color(0xFF2F4F8F));
  }

  // Back leg and arm.
  canvas.drawLine(hip, limb(hip, h * 0.47, -swing), legPaint);
  canvas.drawLine(shoulder, limb(shoulder, h * 0.33, swing), armPaint..color = Color.lerp(shirt, Colors.black, 0.2)!);

  if (backpack) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: shoulder.translate(-dir * h * 0.12, h * 0.13),
            width: h * 0.13,
            height: h * 0.25),
        Radius.circular(h * 0.04),
      ),
      Paint()..color = const Color(0xFFE85D5D),
    );
  }

  // Body.
  final body = RRect.fromRectAndRadius(
    Rect.fromCenter(
        center: Offset((hip.dx + shoulder.dx) / 2, (hip.dy + shoulder.dy) / 2 + h * 0.02),
        width: h * 0.17,
        height: h * 0.37),
    Radius.circular(h * 0.06),
  );
  canvas.drawRRect(body, Paint()..color = shirt);

  // Front leg and arm.
  canvas.drawLine(hip, limb(hip, h * 0.47, swing), legPaint);
  canvas.drawLine(shoulder, limb(shoulder, h * 0.33, -swing), armPaint..color = shirt);

  // Head.
  final head = feet.translate(dir * h * 0.02, -h * 0.9);
  canvas.drawCircle(head, h * 0.085, Paint()..color = skin);
  canvas.drawArc(
    Rect.fromCircle(center: head, radius: h * 0.09),
    facingRight ? math.pi * 0.85 : math.pi * 0.15 - 0.1,
    math.pi * 1.1,
    true,
    Paint()..color = hair,
  );
  canvas.drawCircle(head.translate(dir * h * 0.04, -h * 0.005), h * 0.012,
      Paint()..color = const Color(0xFF1A1A1A));
}

// ---- walking scenes ------------------------------------------------------------

class _WalkPainter extends CustomPainter {
  final _PassengerScreenState s;
  _WalkPainter(this.s);

  late double _w;
  late double _h;
  late double _floorY;

  double _sx(double worldX, [double parallax = 1]) => worldX - s._camX * parallax;

  @override
  void paint(Canvas canvas, Size size) {
    _w = size.width;
    _h = size.height;
    _floorY = _h * 0.78;

    switch (s._stage) {
      case _Stage.departAirport:
      case _Stage.arriveAirport:
        _paintAirport(canvas);
        break;
      case _Stage.city:
        _paintCity(canvas);
        break;
      case _Stage.hotel:
        _paintHotel(canvas);
        break;
      case _Stage.flight:
        break;
    }

    // Other people walking about.
    final personH = _h * 0.2;
    for (final n in s._npcs) {
      final x = _sx(n.x);
      if (x < -60 || x > _w + 60) continue;
      _drawWalker(canvas, Offset(x, _floorY + 6), personH * (0.85 + (n.look % 4) * 0.06),
          s._time * 8 + n.look, n.dir > 0, n.look,
          suitcase: n.look % 3 == 0 && s._stage != _Stage.city);
    }

    // You.
    _drawWalker(
      canvas,
      Offset(_sx(s._x), _floorY + 14),
      personH,
      s._walkPhase,
      s._facingRight,
      7,
      backpack: true,
      suitcase: s._stage == _Stage.city || (s._stage == _Stage.arriveAirport && (s._spot('bags')?.done ?? false)),
      moving: s._moving,
    );
    final me = Offset(_sx(s._x), _floorY + 14 - personH * 1.12);
    final arrow = Path()
      ..moveTo(me.dx - 8, me.dy - 10)
      ..lineTo(me.dx + 8, me.dy - 10)
      ..lineTo(me.dx, me.dy)
      ..close();
    canvas.drawPath(arrow, Paint()..color = _sun);
    canvas.drawPath(
        arrow,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    if (s._night > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFF0A1030).withValues(alpha: math.min(0.85, s._night)),
      );
    }
  }

  // ---- airport -------------------------------------------------------------

  void _paintAirport(Canvas canvas) {
    final winTop = _h * 0.16;
    final winBottom = _h * 0.56;

    // Outside, seen through the big windows (moves slower = further away).
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _w, winBottom),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, winTop), Offset(0, winBottom),
            [const Color(0xFF5E9BD6), const Color(0xFFC9E0F1)]),
    );
    canvas.drawRect(Rect.fromLTWH(0, winBottom - _h * 0.08, _w, _h * 0.08),
        Paint()..color = const Color(0xFF8A8F96));
    for (var i = 0; i < 6; i++) {
      final x = _sx(250 + i * 520.0, 0.55);
      if (x < -400 || x > _w + 400) continue;
      _bigPlane(canvas, Offset(x, winBottom - _h * 0.065), _h * 0.11, i);
    }

    // Wall with window frames.
    final wall = Paint()..color = const Color(0xFFE7E3DC);
    canvas.drawRect(Rect.fromLTWH(0, 0, _w, winTop), wall);
    canvas.drawRect(Rect.fromLTWH(0, winBottom, _w, _floorY - winBottom), wall);
    final mullion = Paint()..color = const Color(0xFF6E747C);
    for (var x = -(s._camX % 180); x < _w + 180; x += 180) {
      canvas.drawRect(Rect.fromLTWH(x, winTop, 8, winBottom - winTop), mullion);
    }
    canvas.drawRect(Rect.fromLTWH(0, winTop - 6, _w, 8), mullion);
    canvas.drawRect(Rect.fromLTWH(0, winBottom - 2, _w, 8), mullion);
    // Ceiling lights.
    for (var x = -(s._camX % 140); x < _w + 140; x += 140) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x + 30, _h * 0.05, 70, 8), const Radius.circular(4)),
        Paint()
          ..color = const Color(0xFFFFFBEA)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }

    // Shiny floor.
    canvas.drawRect(
      Rect.fromLTWH(0, _floorY - 10, _w, _h - _floorY + 10),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, _floorY), Offset(0, _h),
            [const Color(0xFFCFCBC3), const Color(0xFFA9A49B)]),
    );
    final tile = Paint()
      ..color = Colors.black.withValues(alpha: 0.06)
      ..strokeWidth = 1.5;
    for (var x = -(s._camX % 90); x < _w + 90; x += 90) {
      canvas.drawLine(Offset(x, _floorY - 10), Offset(x - 50, _h), tile);
    }

    for (final spot in s._spots) {
      final x = _sx(spot.x);
      if (x < -260 || x > _w + 260) continue;
      _airportThing(canvas, spot, x);
      _hangingSign(canvas, spot.sign, x, _h * 0.1, spot.done);
    }
  }

  void _airportThing(Canvas canvas, _Spot spot, double x) {
    final dark = Paint()..color = const Color(0xFF3A3F47);
    final steel = Paint()..color = const Color(0xFFB9BFC8);
    switch (spot.id) {
      case 'checkin':
      case 'gate':
      case 'passport':
        final desk = Rect.fromLTWH(x - 90, _floorY - _h * 0.13, 180, _h * 0.13);
        canvas.drawRRect(RRect.fromRectAndRadius(desk, const Radius.circular(6)),
            Paint()..color = spot.id == 'passport' ? const Color(0xFF4A5568) : const Color(0xFF2F5DA8));
        canvas.drawRect(Rect.fromLTWH(desk.left, desk.top, desk.width, 8), steel);
        for (final dx in [-50.0, 30.0]) {
          canvas.drawRect(Rect.fromLTWH(x + dx, desk.top - 34, 30, 22), dark);
          canvas.drawRect(Rect.fromLTWH(x + dx + 3, desk.top - 31, 24, 16),
              Paint()..color = const Color(0xFF6FD3F7));
        }
        // Staff behind the desk.
        _drawWalker(canvas, Offset(x - 10, desk.top + 26), _h * 0.17, 0, false,
            spot.id.length * 41, moving: false);
        canvas.drawRRect(RRect.fromRectAndRadius(desk, const Radius.circular(6)),
            Paint()..color = spot.id == 'passport' ? const Color(0xFF4A5568) : const Color(0xFF2F5DA8));
        if (spot.id == 'gate') {
          for (var i = 0; i < 4; i++) {
            final seat = Rect.fromLTWH(x + 120 + i * 34, _floorY - 40, 30, 22);
            canvas.drawRRect(RRect.fromRectAndRadius(seat, const Radius.circular(4)),
                Paint()..color = const Color(0xFF34407A));
          }
        }
        break;
      case 'security':
        final arch = Path()
          ..addRect(Rect.fromLTWH(x - 50, _floorY - _h * 0.3, 14, _h * 0.3))
          ..addRect(Rect.fromLTWH(x + 36, _floorY - _h * 0.3, 14, _h * 0.3))
          ..addRect(Rect.fromLTWH(x - 50, _floorY - _h * 0.3, 100, 16));
        canvas.drawPath(arch, steel);
        canvas.drawCircle(Offset(x, _floorY - _h * 0.3 + 8), 5,
            Paint()..color = spot.done ? _grass : _tomato);
        // X-ray belt.
        canvas.drawRect(Rect.fromLTWH(x + 70, _floorY - 60, 140, 40), dark);
        canvas.drawRect(Rect.fromLTWH(x + 100, _floorY - 90, 70, 34), steel);
        break;
      case 'cafe':
        canvas.drawRect(Rect.fromLTWH(x - 100, _floorY - _h * 0.12, 200, _h * 0.12),
            Paint()..color = const Color(0xFF7A4E2D));
        final awning = Rect.fromLTWH(x - 110, _floorY - _h * 0.34, 220, 30);
        for (var i = 0; i < 8; i++) {
          canvas.drawRect(
            Rect.fromLTWH(awning.left + i * awning.width / 8, awning.top,
                awning.width / 8, awning.height),
            Paint()..color = i.isEven ? _tomato : Colors.white,
          );
        }
        for (var i = 0; i < 5; i++) {
          canvas.drawCircle(Offset(x - 70 + i * 35, _floorY - _h * 0.13 - 8), 8,
              Paint()..color = _itemColors.values.elementAt(i));
        }
        break;
      case 'board':
        // Jet bridge leading to the plane door.
        final tunnel = Rect.fromLTWH(x - 40, _floorY - _h * 0.36, 260, _h * 0.36);
        canvas.drawRect(tunnel, Paint()..color = const Color(0xFF9BA3AD));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x - 20, _floorY - _h * 0.3, 70, _h * 0.3),
              const Radius.circular(14)),
          Paint()..color = Colors.white,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x - 10, _floorY - _h * 0.28, 50, _h * 0.28),
              const Radius.circular(10)),
          Paint()..color = const Color(0xFF2A2E37),
        );
        _textAt(canvas, 'OSCAR AIR', Offset(x + 140, _floorY - _h * 0.22), 14,
            _cobalt);
        break;
      case 'bags':
        final belt = Rect.fromLTWH(x - 140, _floorY - 46, 280, 30);
        canvas.drawRRect(RRect.fromRectAndRadius(belt, const Radius.circular(14)), dark);
        for (var i = 0; i < 6; i++) {
          final bx = belt.left + ((s._time * 40 + i * 50) % belt.width);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(bx - 14, belt.top - 18, 28, 22), const Radius.circular(4)),
            Paint()..color = _clothes[i % _clothes.length],
          );
        }
        break;
      case 'exit':
        final door = Rect.fromLTWH(x - 70, _floorY - _h * 0.32, 140, _h * 0.32);
        canvas.drawRect(door, Paint()..color = const Color(0xFFFFF4C9));
        canvas.drawRect(Rect.fromLTWH(door.left, door.top, 6, door.height), dark);
        canvas.drawRect(Rect.fromLTWH(door.right - 6, door.top, 6, door.height), dark);
        canvas.drawRect(Rect.fromLTWH(door.center.dx - 2, door.top, 4, door.height), dark);
        break;
    }
  }

  void _hangingSign(Canvas canvas, String text, double x, double y, bool done) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = Rect.fromCenter(center: Offset(x, y), width: tp.width + 22, height: tp.height + 10);
    canvas.drawLine(Offset(x - r.width / 3, 0), Offset(x - r.width / 3, r.top),
        Paint()..color = const Color(0xFF6E747C));
    canvas.drawLine(Offset(x + r.width / 3, 0), Offset(x + r.width / 3, r.top),
        Paint()..color = const Color(0xFF6E747C));
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)),
        Paint()..color = done ? const Color(0xFFB6E34A) : _sun);
    tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _bigPlane(Canvas canvas, Offset nose, double h, int seed) {
    final body = Paint()..color = Colors.white;
    final len = h * 5;
    final fus = RRect.fromRectAndCorners(
      Rect.fromLTWH(nose.dx - len, nose.dy - h, len, h),
      topRight: Radius.circular(h * 0.6),
      bottomRight: Radius.circular(h * 0.4),
      topLeft: Radius.circular(h * 0.2),
      bottomLeft: Radius.circular(h * 0.2),
    );
    final tail = Path()
      ..moveTo(nose.dx - len + h * 0.2, nose.dy - h)
      ..lineTo(nose.dx - len - h * 0.1, nose.dy - h * 2.2)
      ..lineTo(nose.dx - len + h * 0.7, nose.dy - h * 2.2)
      ..lineTo(nose.dx - len + h * 1.4, nose.dy - h)
      ..close();
    canvas.drawPath(tail, Paint()..color = seed.isEven ? _cobalt : _tomato);
    canvas.drawRRect(fus, body);
    canvas.drawRect(
        Rect.fromLTWH(nose.dx - len, nose.dy - h * 0.35, len * 0.95, h * 0.12),
        Paint()..color = seed.isEven ? _cobalt : _tomato);
    final win = Paint()..color = const Color(0xFF2A2E37);
    for (var i = 0; i < 14; i++) {
      canvas.drawCircle(Offset(nose.dx - len + h * 1.2 + i * h * 0.24, nose.dy - h * 0.62),
          h * 0.06, win);
    }
    canvas.drawPath(
      Path()
        ..moveTo(nose.dx - len * 0.55, nose.dy - h * 0.3)
        ..lineTo(nose.dx - len * 0.35, nose.dy - h * 0.3)
        ..lineTo(nose.dx - len * 0.6, nose.dy + h * 0.35)
        ..lineTo(nose.dx - len * 0.7, nose.dy + h * 0.35)
        ..close(),
      Paint()..color = const Color(0xFFCDD2D8),
    );
  }

  // ---- city ----------------------------------------------------------------

  void _paintCity(Canvas canvas) {
    final ground = _groundFor(s._city);
    final skyTop = ground == _Ground.desert
        ? const Color(0xFF4F8FD8)
        : ground == _Ground.snow
            ? const Color(0xFF8DA6C2)
            : const Color(0xFF3F86D6);
    final skyLow = ground == _Ground.desert ? const Color(0xFFF1E3C4) : const Color(0xFFD7E8F4);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _w, _floorY),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, _floorY), [skyTop, skyLow]),
    );
    // Sun.
    canvas.drawCircle(Offset(_w * 0.82 - s._camX * 0.02, _h * 0.14), 26,
        Paint()..color = const Color(0xFFFFF4C2));

    final horizon = _floorY - _h * 0.06;

    // Far mountains and hills.
    for (final f in s._scenery) {
      if (f.kind != _Lm.hills && f.kind != _Lm.snowPeak && f.kind != _Lm.tableMountain &&
          f.kind != _Lm.christ && f.kind != _Lm.sugarloaf) {
        continue;
      }
      final k = (_h * 0.32) / math.max(1.0, f.h);
      final x = _sx(400 + f.along * 160 + f.across * 60, 0.25);
      _drawLandmark(canvas, f, Offset(x, horizon), k, 0.35);
    }

    // City skyline in the middle distance.
    var i = 0;
    for (final f in s._scenery) {
      if (f.kind != _Lm.box) continue;
      i++;
      final x = _sx(_hash(f.seed) * s._sceneW * 0.9, 0.5);
      if (x < -80 || x > _w + 80) continue;
      _drawLandmark(canvas, f, Offset(x, horizon), 70, 0.25);
    }

    // Famous landmarks, close to the street.
    for (var li = 0; li < s._landmarks.length; li++) {
      final f = s._landmarks[li];
      final spot = s._spot('lm$li');
      if (spot == null) continue;
      final big = f.kind == _Lm.hills || f.kind == _Lm.snowPeak;
      final k = math.min(170.0, (_h * (big ? 0.35 : 0.6)) / math.max(0.3, f.h));
      final x = _sx(spot.x + 60);
      final width = f.w * k;
      if (x < -width || x > _w + width) continue;
      _drawLandmark(canvas, f, Offset(x, _floorY - _h * 0.03), k, 0.0);
    }

    // Pavement and road.
    canvas.drawRect(Rect.fromLTWH(0, _floorY - _h * 0.03, _w, _h * 0.1),
        Paint()..color = ground == _Ground.snow ? const Color(0xFFE8EDF1) : const Color(0xFFCAC6BE));
    final road = Rect.fromLTWH(0, _floorY + _h * 0.07, _w, _h);
    canvas.drawRect(road, Paint()..color = const Color(0xFF3D4047));
    for (var x = -(s._camX % 80); x < _w + 80; x += 80) {
      canvas.drawRect(Rect.fromLTWH(x, _floorY + _h * 0.14, 40, 4),
          Paint()..color = Colors.white.withValues(alpha: 0.8));
    }
    // Cars driving by.
    for (var c = 0; c < 4; c++) {
      final speed = 120.0 + c * 40;
      final span = s._sceneW + 400;
      final wx = (c * 700 + s._time * speed * (c.isEven ? 1 : -1)) % span - 200;
      final x = _sx(wx < -200 ? wx + span : wx);
      if (x < -100 || x > _w + 100) continue;
      _car(canvas, Offset(x, _floorY + _h * (c.isEven ? 0.12 : 0.18)), c);
    }

    // Street spots: taxi, hotel, info boards.
    for (final spot in s._spots) {
      final x = _sx(spot.x);
      if (x < -300 || x > _w + 300) continue;
      if (spot.id == 'hotel') {
        _hotelBuilding(canvas, x);
      } else if (spot.id == 'taxi') {
        _car(canvas, Offset(x, _floorY + _h * 0.035), 99, taxi: true);
      } else {
        _infoBoard(canvas, x - 70, spot.done);
      }
      _hangingSign(canvas, spot.sign, x, _floorY - _h * 0.5, spot.done);
    }

    // Trees and plants along the pavement.
    for (final f in s._scenery) {
      if (f.kind != _Lm.palm && f.kind != _Lm.acacia && f.kind != _Lm.gabled) continue;
      final x = _sx(300 + _hash(f.seed + 3) * (s._sceneW - 300));
      if (x < -80 || x > _w + 80) continue;
      final k = f.kind == _Lm.gabled ? 120.0 : 260.0;
      _drawLandmark(canvas, f, Offset(x, _floorY - _h * 0.03), k, 0.0);
    }
  }

  void _car(Canvas canvas, Offset c, int seed, {bool taxi = false}) {
    final colour = taxi ? const Color(0xFFFFC93C) : _clothes[seed % _clothes.length];
    final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: 110, height: 28), const Radius.circular(8));
    canvas.drawRRect(body, Paint()..color = colour);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: c.translate(-6, -22), width: 62, height: 24),
          const Radius.circular(8)),
      Paint()..color = colour,
    );
    canvas.drawRect(Rect.fromCenter(center: c.translate(-6, -21), width: 52, height: 15),
        Paint()..color = const Color(0xFF9FD3F5));
    for (final dx in [-32.0, 32.0]) {
      canvas.drawCircle(c.translate(dx, 14), 10, Paint()..color = const Color(0xFF1C1E22));
      canvas.drawCircle(c.translate(dx, 14), 4, Paint()..color = const Color(0xFFB9BFC8));
    }
    if (taxi) {
      canvas.drawRect(Rect.fromCenter(center: c.translate(-6, -38), width: 30, height: 9),
          Paint()..color = _ink);
      _textAt(canvas, 'TAXI', c.translate(-6, -38), 7, _sun);
    }
  }

  void _hotelBuilding(Canvas canvas, double x) {
    final top = _floorY - _h * 0.7;
    final rect = Rect.fromLTRB(x - 130, top, x + 130, _floorY - _h * 0.03);
    canvas.drawRect(rect, Paint()..color = const Color(0xFFE9DCC6));
    canvas.drawRect(Rect.fromLTWH(rect.right - 40, rect.top, 40, rect.height),
        Paint()..color = const Color(0xFFD4C5AC));
    final win = Paint()..color = const Color(0xFF7FA6C9);
    for (var r = 0; r < 7; r++) {
      for (var c = 0; c < 5; c++) {
        canvas.drawRect(
            Rect.fromLTWH(rect.left + 18 + c * 48, rect.top + 50 + r * (rect.height - 130) / 7, 26, 22),
            win);
      }
    }
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, 34),
        Paint()..color = const Color(0xFF6A4FD8));
    _textAt(canvas, 'HOTEL OSCAR', Offset(x, rect.top + 17), 16, Colors.white);
    // Entrance with awning.
    canvas.drawRect(Rect.fromLTWH(x - 40, rect.bottom - 70, 80, 70),
        Paint()..color = const Color(0xFF3A3F47));
    canvas.drawRect(Rect.fromLTWH(x - 60, rect.bottom - 82, 120, 16),
        Paint()..color = _tomato);
  }

  void _infoBoard(Canvas canvas, double x, bool seen) {
    canvas.drawRect(Rect.fromLTWH(x - 3, _floorY - 80, 6, 80),
        Paint()..color = const Color(0xFF3A3F47));
    final board = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 34, _floorY - 118, 68, 44), const Radius.circular(6));
    canvas.drawRRect(board, Paint()..color = seen ? const Color(0xFFB6E34A) : Colors.white);
    canvas.drawRRect(
        board,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
    _textAt(canvas, seen ? 'SEEN!' : 'INFO', board.center, 13, _ink);
  }

  // ---- hotel ---------------------------------------------------------------

  void _paintHotel(Canvas canvas) {
    // Lobby wall on the left, your room on the right (after the lift).
    final roomStart = _sx(950);
    canvas.drawRect(Rect.fromLTWH(0, 0, _w, _floorY),
        Paint()..color = const Color(0xFFF1E4CF));
    canvas.drawRect(Rect.fromLTRB(roomStart, 0, _w + 2000, _floorY),
        Paint()..color = const Color(0xFFD9E4EC));
    // Wallpaper stripes in the room.
    for (var x = roomStart; x < _w; x += 40) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 14, _floorY),
          Paint()..color = Colors.white.withValues(alpha: 0.35));
    }
    canvas.drawRect(Rect.fromLTWH(roomStart - 20, 0, 40, _floorY),
        Paint()..color = const Color(0xFF8C7A62));
    // Floors: marble lobby, carpet room.
    canvas.drawRect(Rect.fromLTWH(0, _floorY - 10, _w, _h),
        Paint()..color = const Color(0xFFE6E1D8));
    canvas.drawRect(Rect.fromLTRB(roomStart, _floorY - 10, _w + 2000, _h),
        Paint()..color = const Color(0xFF7C5A8C));

    // Chandelier.
    final cx = _sx(300);
    canvas.drawLine(Offset(cx, 0), Offset(cx, _h * 0.12),
        Paint()..color = const Color(0xFFB08D57)..strokeWidth = 2);
    canvas.drawCircle(Offset(cx, _h * 0.14), 22,
        Paint()
          ..color = const Color(0xFFFFE9A8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));

    for (final spot in s._spots) {
      final x = _sx(spot.x);
      if (x < -300 || x > _w + 300) continue;
      switch (spot.id) {
        case 'out':
          canvas.drawRect(Rect.fromLTWH(x - 50, _floorY - _h * 0.4, 100, _h * 0.4),
              Paint()..color = const Color(0xFFBFE3F7));
          break;
        case 'reception':
          final desk = Rect.fromLTWH(x - 110, _floorY - _h * 0.14, 220, _h * 0.14);
          _drawWalker(canvas, Offset(x, desk.top + 30), _h * 0.18, 0, false, 321,
              moving: false);
          canvas.drawRRect(RRect.fromRectAndRadius(desk, const Radius.circular(8)),
              Paint()..color = const Color(0xFF6B4A2F));
          canvas.drawCircle(Offset(x + 60, desk.top - 6), 8, Paint()..color = _sun);
          break;
        case 'lift':
          for (final dx in [-46.0, 4.0]) {
            canvas.drawRect(Rect.fromLTWH(x + dx, _floorY - _h * 0.4, 44, _h * 0.4),
                Paint()..color = const Color(0xFFB9BFC8));
          }
          _textAt(canvas, spot.done ? '4' : 'G', Offset(x, _floorY - _h * 0.44), 14, _tomato);
          break;
        case 'bed':
          final bed = Rect.fromLTWH(x - 120, _floorY - 70, 240, 60);
          canvas.drawRect(Rect.fromLTWH(bed.left - 10, bed.top - 60, 20, 120),
              Paint()..color = const Color(0xFF6B4A2F));
          canvas.drawRRect(RRect.fromRectAndRadius(bed, const Radius.circular(10)),
              Paint()..color = Colors.white);
          canvas.drawRect(Rect.fromLTWH(bed.left + 70, bed.top, 170, 40),
              Paint()..color = const Color(0xFF3F6FD1));
          canvas.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTWH(bed.left + 10, bed.top - 14, 54, 22),
                  const Radius.circular(8)),
              Paint()..color = const Color(0xFFF4F1E8));
          break;
        case 'window':
          final win = Rect.fromLTWH(x - 90, _floorY - _h * 0.55, 180, _h * 0.32);
          final night = s._night > 0.3;
          canvas.drawRect(win,
              Paint()..color = night ? const Color(0xFF0E1A3A) : const Color(0xFF8CC4EE));
          if (s._landmarks.isNotEmpty) {
            canvas.save();
            canvas.clipRect(win);
            final f = s._landmarks.first;
            _drawLandmark(canvas, f, Offset(win.center.dx, win.bottom),
                (win.height * 0.8) / math.max(0.3, f.h), night ? 0.0 : 0.2);
            canvas.restore();
          }
          canvas.drawRect(
              win,
              Paint()
                ..color = Colors.white
                ..style = PaintingStyle.stroke
                ..strokeWidth = 8);
          break;
      }
      _hangingSign(canvas, spot.sign, x, _h * 0.1, spot.done && spot.barrier);
    }
  }

  void _textAt(Canvas canvas, String text, Offset at, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _WalkPainter oldDelegate) => true;
}

// ---- in your seat on the plane ----------------------------------------------------

class _SeatViewPainter extends CustomPainter {
  final _PassengerScreenState s;
  _SeatViewPainter(this.s);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final shake = s._turbulent ? 4.0 : 0.0;
    canvas.save();
    canvas.translate(math.sin(s._time * 37) * shake, math.cos(s._time * 29) * shake);

    // Cabin wall.
    canvas.drawRect(Rect.fromLTWH(-10, -10, w + 20, h + 20),
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(w, 0),
              [const Color(0xFFDCD8D0), const Color(0xFFF2EFE9)]));

    // The window.
    final big = s._bigWindow;
    final win = big
        ? Rect.fromCenter(center: Offset(w / 2, h * 0.42), width: w * 0.86, height: h * 0.62)
        : Rect.fromCenter(center: Offset(w * 0.26, h * 0.36), width: w * 0.36, height: h * 0.34);
    final rr = RRect.fromRectAndRadius(win, Radius.circular(win.width * 0.35));
    canvas.save();
    canvas.clipRRect(rr);
    _outside(canvas, win);
    canvas.restore();
    canvas.drawRRect(
        rr,
        Paint()
          ..color = const Color(0xFFBFBAB1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14);

    if (!big) {
      // Seat in front of you with its screen.
      final seat = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.5, h * 0.16, w * 0.46, h * 0.8), const Radius.circular(26));
      canvas.drawRRect(seat, Paint()..color = const Color(0xFF2B3E86));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.52, h * 0.17, w * 0.42, h * 0.08), const Radius.circular(14)),
          Paint()..color = const Color(0xFFE9E6DF));
      final screen = Rect.fromLTWH(w * 0.56, h * 0.3, w * 0.34, h * 0.22);
      canvas.drawRRect(RRect.fromRectAndRadius(screen, const Radius.circular(8)),
          Paint()..color = const Color(0xFF0B0C0E));
      _screen(canvas, screen.deflate(5));

      // Tray table with your snack.
      if (s._snack) {
        final tray = Rect.fromLTWH(w * 0.54, h * 0.62, w * 0.38, h * 0.05);
        canvas.drawRect(tray, Paint()..color = const Color(0xFF9CA3AD));
        canvas.drawRect(Rect.fromLTWH(tray.left + 20, tray.top - 30, 22, 30),
            Paint()..color = const Color(0xFFFF9F43));
        canvas.drawOval(Rect.fromLTWH(tray.left + 60, tray.top - 16, 60, 18),
            Paint()..color = const Color(0xFFE0A85A));
      }
    }

    // Seatbelt sign.
    final on = s._seatbeltOn;
    final sign = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.04, h * 0.04, 150, 30), const Radius.circular(8));
    canvas.drawRRect(sign, Paint()..color = on ? _sun : const Color(0xFF5E636D));
    final tp = TextPainter(
      text: TextSpan(
        text: on ? 'FASTEN SEATBELT' : 'seatbelt sign off',
        style: TextStyle(
            color: on ? _ink : Colors.white70, fontSize: 12, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, sign.center - Offset(tp.width / 2, tp.height / 2));
    canvas.restore();

    if (s._napTime > 0) {
      canvas.drawRect(Offset.zero & size,
          Paint()..color = const Color(0xFF0A1030).withValues(alpha: 0.55));
    }
  }

  void _outside(Canvas canvas, Rect r) {
    final p = s._flightP;
    // Up high in the middle of the flight, low near take-off and landing.
    final height = math.min(1.0, math.min(p / 0.12, (1 - p) / 0.12));
    final horizonY = r.top + r.height * (0.45 + (1 - height) * 0.4);
    canvas.drawRect(
      Rect.fromLTRB(r.left, r.top, r.right, horizonY),
      Paint()
        ..shader = ui.Gradient.linear(r.topCenter, Offset(r.center.dx, horizonY),
            [const Color(0xFF2E6FC1), const Color(0xFFCFE3F2)]),
    );
    final landColour = p < 0.1
        ? const Color(0xFF6B7B4A)
        : p > 0.9
            ? const Color(0xFF7A8458)
            : const Color(0xFF3E6D8C);
    canvas.drawRect(Rect.fromLTRB(r.left, horizonY, r.right, r.bottom),
        Paint()
          ..shader = ui.Gradient.linear(Offset(r.center.dx, horizonY), r.bottomCenter,
              [const Color(0xFFB4C4D0), landColour]));
    // Clouds sliding past.
    for (var i = 0; i < 8; i++) {
      final speed = 30.0 + i * 12;
      final x = r.right - ((s._time * speed + i * 97) % (r.width + 200)) + 100;
      final y = horizonY + (i.isEven ? -1 : 1) * (12 + i * 6.0) * (1 + height);
      final sz = 18.0 + (i % 3) * 10;
      final puff = Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawCircle(Offset(x, y), sz, puff);
      canvas.drawCircle(Offset(x + sz, y + 4), sz * 0.8, puff);
      canvas.drawCircle(Offset(x - sz * 0.9, y + 5), sz * 0.7, puff);
    }
    // The city appears below as we come in to land.
    if (p > 0.9 && s._landmarks.isNotEmpty) {
      final f = s._landmarks.first;
      final k = (r.height * 0.25) / math.max(0.3, f.h) * ((p - 0.9) / 0.1);
      if (k > 1) _drawLandmark(canvas, f, Offset(r.center.dx, r.bottom - 4), k, 0.3);
    }
    // The wing.
    final wing = Path()
      ..moveTo(r.left, r.bottom - r.height * 0.25)
      ..lineTo(r.left + r.width * 0.7, r.bottom - r.height * 0.12)
      ..lineTo(r.left + r.width * 0.75, r.bottom - r.height * 0.08)
      ..lineTo(r.left, r.bottom - r.height * 0.05)
      ..close();
    canvas.drawPath(wing, Paint()..color = const Color(0xFFDDE1E6));
  }

  void _screen(Canvas canvas, Rect r) {
    canvas.save();
    canvas.clipRect(r);
    if (s._film) {
      // A cartoon playing.
      canvas.drawRect(r, Paint()..color = const Color(0xFF8FD3FF));
      canvas.drawRect(Rect.fromLTWH(r.left, r.bottom - r.height * 0.25, r.width, r.height * 0.25),
          Paint()..color = _grass);
      final bx = r.left + (s._time * 40) % r.width;
      final by = r.bottom - r.height * 0.25 - (math.sin(s._time * 6).abs()) * r.height * 0.35;
      canvas.drawCircle(Offset(bx, by - 10), 10, Paint()..color = _tomato);
      canvas.drawCircle(Offset(bx + 4, by - 13), 2, Paint()..color = Colors.white);
    } else {
      // Flight map: London to the destination.
      canvas.drawRect(r, Paint()..color = const Color(0xFF16325C));
      final a = Offset(r.left + 14, r.center.dy + 6);
      final b = Offset(r.right - 14, r.center.dy - 6);
      canvas.drawLine(a, b, Paint()..color = Colors.white54..strokeWidth = 2);
      final p = Offset.lerp(a, b, s._flightP)!;
      canvas.drawLine(a, p, Paint()..color = _sun..strokeWidth = 3);
      canvas.drawCircle(p, 5, Paint()..color = _sun);
      final tp = TextPainter(
        text: TextSpan(
          text: '${(s._flightP * 100).round()}% to ${s._city}',
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r.width);
      tp.paint(canvas, Offset(r.left + 6, r.top + 4));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SeatViewPainter oldDelegate) => true;
}
