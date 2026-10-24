import 'dart:math';

import 'package:flutter/material.dart';

import '../../services/sound_service.dart';
import 'boost_ball_data.dart';
import 'boost_ball_game.dart';

const Color _bg = Color(0xFF0E1A2B);
const Color _card = Color(0xFF1B2A41);
const Color _gold = Color(0xFFFFC93C);

/// Boost Ball garage: pick a match, then buy and paint your car.
class BoostBallScreen extends StatefulWidget {
  const BoostBallScreen({super.key});

  @override
  State<BoostBallScreen> createState() => _BoostBallScreenState();
}

class _BoostBallScreenState extends State<BoostBallScreen> {
  final _save = BoostBallSave.instance;
  bool _loaded = false;
  int _size = 1;
  int _difficulty = 1;

  @override
  void initState() {
    super.initState();
    _save.load().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  Future<void> _play() async {
    SoundService.instance.play(GameSound.tap);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            BoostBallGameScreen(teamSize: _size, difficulty: _difficulty),
      ),
    );
    if (mounted) setState(() {});
  }

  void _buy(CarSpec car) {
    if (_save.coins < car.price) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'You need ${car.price - _save.coins} more coins. '
              'Win matches to earn coins!',
            ),
          ),
        );
      return;
    }
    setState(() {
      _save.coins -= car.price;
      _save.cars.add(car.id);
      _save.car = car.id;
    });
    SoundService.instance.play(GameSound.levelComplete);
    _save.save();
  }

  void _pick(CarSpec car) {
    setState(() => _save.car = car.id);
    SoundService.instance.play(GameSound.place);
    _save.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text(
          'BOOST BALL',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(
              children: [
                const Icon(Icons.monetization_on_rounded, color: _gold),
                const SizedBox(width: 4),
                Text(
                  '${_save.coins}',
                  style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      _hero(),
                      const SizedBox(height: 14),
                      _section('Match'),
                      _choices(
                        const ['1v1', '2v2', '3v3'],
                        _size - 1,
                        (i) => _size = i + 1,
                      ),
                      const SizedBox(height: 10),
                      _section('Bots'),
                      _choices(
                        kDifficultyNames,
                        _difficulty,
                        (i) => _difficulty = i,
                        colours: const [
                          Color(0xFF66BB6A),
                          Color(0xFFFFB300),
                          Color(0xFFE53935),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 58,
                        child: ElevatedButton.icon(
                          onPressed: _play,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kBlueTeam,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.sports_soccer_rounded),
                          label: Text(
                            'PLAY ${_size}v$_size',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Win to earn ${kWinCoins[_difficulty]} coins · '
                        '${_save.wins} wins · ${_save.goals} goals',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 18),
                      _section('Paint'),
                      _paints(),
                      const SizedBox(height: 14),
                      _section('Garage'),
                      for (final car in kCars) _carCard(car),
                      const SizedBox(height: 8),
                      _howTo(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _hero() {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: CarPicture(
                carById(_save.car).body,
                kCarColours[_save.colour],
                ball: true,
              ),
            ),
          ),
          Positioned(
            left: 14,
            bottom: 10,
            child: Text(
              carById(_save.car).name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Colors.white54,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
        fontSize: 12,
      ),
    ),
  );

  Widget _choices(
    List<String> names,
    int selected,
    void Function(int) onPick, {
    List<Color>? colours,
  }) {
    return Row(
      children: [
        for (var i = 0; i < names.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < names.length - 1 ? 8 : 0),
              child: GestureDetector(
                onTap: () {
                  SoundService.instance.play(GameSound.tap);
                  setState(() => onPick(i));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? (colours?[i] ?? kBlueTeam) : _card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (colours?[i] ?? kBlueTeam).withValues(alpha: 0.7),
                      width: 2,
                    ),
                  ),
                  child: Text(
                    names[i].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _paints() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < kCarColours.length; i++)
          GestureDetector(
            onTap: () {
              setState(() => _save.colour = i);
              _save.save();
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: kCarColours[i],
                shape: BoxShape.circle,
                border: Border.all(
                  color: i == _save.colour ? Colors.white : Colors.white24,
                  width: i == _save.colour ? 4 : 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _carCard(CarSpec car) {
    final owned = _save.cars.contains(car.id);
    final using = _save.car == car.id;
    Widget stat(String name, double value) => Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            name,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value.clamp(0.05, 1),
              minHeight: 5,
              backgroundColor: Colors.white10,
              color: kBlueTeam,
            ),
          ),
        ),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: using ? kBlueTeam : Colors.white12,
          width: using ? 3 : 1.5,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            height: 64,
            child: CustomPaint(
              painter: CarPicture(
                car.body,
                owned ? kCarColours[_save.colour] : Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  car.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  car.blurb,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                stat('Speed', (car.speed - 17) / 9),
                const SizedBox(height: 3),
                stat('Power', (car.hit - 0.7) / 0.7),
                const SizedBox(height: 3),
                stat('Jump', (car.jump - 9) / 7),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: using
                      ? const Chip(
                          label: Text('DRIVING'),
                          backgroundColor: kBlueTeam,
                          labelStyle: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : owned
                      ? OutlinedButton(
                          onPressed: () => _pick(car),
                          child: const Text('Drive it'),
                        )
                      : ElevatedButton.icon(
                          onPressed: () => _buy(car),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _save.coins >= car.price
                                ? _gold
                                : Colors.white24,
                            foregroundColor: Colors.black87,
                          ),
                          icon: const Icon(
                            Icons.monetization_on_rounded,
                            size: 18,
                          ),
                          label: Text('${car.price}'),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _howTo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        'How to play: drag on the left side to drive the way you point. '
        'Hold BOOST to go faster. Tap JUMP to jump, and tap it again in the '
        'air to flip into the ball for a super hit. Drive over the orange '
        'pads to fill up your boost. Ram an enemy at full boost to demolish '
        'them! Score more goals than orange before the clock runs out.',
        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
      ),
    );
  }
}

/// A side-on picture of a car (and maybe the ball) for the garage.
class CarPicture extends CustomPainter {
  final CarBody body;
  final Color colour;
  final bool ball;

  CarPicture(this.body, this.colour, {this.ball = false});

  @override
  void paint(Canvas canvas, Size size) {
    final u = min(size.width / (ball ? 12 : 6.4), size.height / 3.4);
    final ground = size.height * (ball ? 0.78 : 0.86);
    final cx = ball ? size.width * 0.38 : size.width / 2;
    final paint = Paint()..color = colour;
    final dark = Paint()..color = const Color(0xFF102027);
    final glass = Paint()..color = const Color(0xFF90CAF9);
    final edge = Paint()
      ..color = Colors.black45
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, ground + 0.15 * u),
        width: 5.4 * u,
        height: 0.5 * u,
      ),
      Paint()..color = Colors.black26,
    );

    void wheel(double x, double r) {
      final c = Offset(cx + x * u, ground - r * u);
      canvas.drawCircle(c, r * u, dark);
      canvas.drawCircle(
        c,
        r * 0.45 * u,
        Paint()..color = const Color(0xFFB0BEC5),
      );
    }

    Path shape(List<Offset> pts) => Path()
      ..addPolygon([
        for (final p in pts) Offset(cx + p.dx * u, ground - p.dy * u),
      ], true);

    switch (body) {
      case CarBody.sport:
        final b = shape(const [
          Offset(-2.6, 0.5),
          Offset(-2.6, 1.3),
          Offset(-1.2, 1.4),
          Offset(-0.5, 2.1),
          Offset(1.0, 2.1),
          Offset(1.8, 1.3),
          Offset(2.7, 1.1),
          Offset(2.7, 0.5),
        ]);
        canvas.drawPath(b, paint);
        canvas.drawPath(b, edge);
        canvas.drawPath(
          shape(const [
            Offset(-0.3, 1.45),
            Offset(-0.2, 1.95),
            Offset(0.9, 1.95),
            Offset(1.5, 1.4),
          ]),
          glass,
        );
        canvas.drawRect(
          Rect.fromLTWH(cx - 2.9 * u, ground - 1.9 * u, 0.9 * u, 0.25 * u),
          dark,
        );
        wheel(-1.6, 0.6);
        wheel(1.7, 0.6);
      case CarBody.hornet:
        final b = shape(const [
          Offset(-2.5, 0.4),
          Offset(-2.5, 1.3),
          Offset(-0.8, 1.6),
          Offset(0.2, 1.9),
          Offset(1.0, 1.5),
          Offset(3.0, 0.7),
          Offset(3.0, 0.4),
        ]);
        canvas.drawPath(b, paint);
        canvas.drawPath(b, edge);
        for (final x in [-1.8, -1.2]) {
          canvas.drawRect(
            Rect.fromLTWH(cx + x * u, ground - 1.4 * u, 0.3 * u, 1.0 * u),
            Paint()..color = const Color(0xFFFFD600),
          );
        }
        canvas.drawPath(
          shape(const [Offset(0.1, 1.5), Offset(0.3, 1.8), Offset(0.9, 1.45)]),
          glass,
        );
        wheel(-1.6, 0.55);
        wheel(1.9, 0.5);
      case CarBody.truck:
        final b = shape(const [
          Offset(-2.8, 0.6),
          Offset(-2.8, 1.5),
          Offset(0.3, 1.5),
          Offset(0.5, 2.5),
          Offset(2.0, 2.5),
          Offset(2.7, 1.6),
          Offset(2.8, 0.6),
        ]);
        canvas.drawPath(b, paint);
        canvas.drawPath(b, edge);
        canvas.drawPath(
          shape(const [
            Offset(0.7, 1.7),
            Offset(0.8, 2.3),
            Offset(1.9, 2.3),
            Offset(2.4, 1.7),
          ]),
          glass,
        );
        canvas.drawRect(
          Rect.fromLTWH(cx + 2.7 * u, ground - 1.4 * u, 0.3 * u, 0.9 * u),
          Paint()..color = const Color(0xFFB0BEC5),
        );
        wheel(-1.7, 0.75);
        wheel(1.7, 0.75);
      case CarBody.goatKart:
        final b = shape(const [
          Offset(-2.2, 0.5),
          Offset(-2.2, 1.0),
          Offset(2.2, 1.0),
          Offset(2.4, 0.5),
        ]);
        canvas.drawPath(b, paint);
        canvas.drawPath(b, edge);
        // The goat.
        final goat = Paint()..color = Colors.white;
        canvas.drawOval(
          Rect.fromLTWH(cx - 1.1 * u, ground - 2.2 * u, 1.4 * u, 1.3 * u),
          goat,
        );
        canvas.drawOval(
          Rect.fromLTWH(cx - 0.1 * u, ground - 2.8 * u, 1.1 * u, 0.9 * u),
          goat,
        );
        final horn = Paint()
          ..color = const Color(0xFF8D6E63)
          ..strokeWidth = 0.2 * u
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(cx + 0.2 * u, ground - 2.7 * u),
          Offset(cx - 0.2 * u, ground - 3.3 * u),
          horn,
        );
        canvas.drawCircle(
          Offset(cx + 0.65 * u, ground - 2.45 * u),
          0.1 * u,
          dark,
        );
        canvas.drawLine(
          Offset(cx + 1.2 * u, ground - 1.0 * u),
          Offset(cx + 0.7 * u, ground - 1.7 * u),
          Paint()
            ..color = dark.color
            ..strokeWidth = 0.15 * u,
        ); // steering wheel
        wheel(-1.6, 0.5);
        wheel(1.7, 0.5);
      case CarBody.monster:
        final b = shape(const [
          Offset(-2.4, 1.3),
          Offset(-2.4, 2.1),
          Offset(-0.6, 2.2),
          Offset(-0.1, 2.9),
          Offset(1.1, 2.9),
          Offset(1.7, 2.2),
          Offset(2.5, 2.0),
          Offset(2.5, 1.3),
        ]);
        canvas.drawPath(b, paint);
        canvas.drawPath(b, edge);
        canvas.drawPath(
          shape(const [
            Offset(0.0, 2.25),
            Offset(0.1, 2.75),
            Offset(1.0, 2.75),
            Offset(1.45, 2.25),
          ]),
          glass,
        );
        wheel(-1.6, 1.0);
        wheel(1.7, 1.0);
    }
    // Headlight.
    canvas.drawCircle(
      Offset(
        cx + 2.55 * u,
        ground - (body == CarBody.monster ? 1.8 : 0.95) * u,
      ),
      0.18 * u,
      Paint()..color = const Color(0xFFFFF59D),
    );

    if (ball) {
      final c = Offset(size.width * 0.78, ground - 1.6 * u);
      final r = 1.6 * u;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.4, -0.5),
            colors: [Colors.white, Color(0xFFCFD8DC), Color(0xFF78909C)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      final patch = Paint()..color = const Color(0xFF37474F);
      for (var i = 0; i < 5; i++) {
        final a = i * 2 * pi / 5 - pi / 2;
        canvas.drawCircle(c + Offset(cos(a), sin(a)) * r * 0.6, r * 0.2, patch);
      }
      canvas.drawCircle(c, r * 0.22, patch);
      // Speed lines.
      final lines = Paint()
        ..color = Colors.white54
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 3; i++) {
        final y = ground - (1.0 + i * 0.6) * u;
        canvas.drawLine(
          Offset(cx - (3.2 + i * 0.3) * u, y),
          Offset(cx - (4.4 + i * 0.5) * u, y),
          lines,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CarPicture old) =>
      old.body != body || old.colour != colour;
}
