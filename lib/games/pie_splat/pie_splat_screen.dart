import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/save_service.dart';
import '../../widgets/game_scaffold.dart';
import 'pie_splat_3d.dart';
import 'pie_splat_game.dart';

/// Menu for Pie Splat Party: who's who, how to play, and a big PLAY button.
class PieSplatScreen extends StatefulWidget {
  const PieSplatScreen({super.key});

  @override
  State<PieSplatScreen> createState() => _PieSplatScreenState();
}

class _PieSplatScreenState extends State<PieSplatScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _play() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PieSplatGameScreen()))
        .then((_) {
          if (mounted) setState(() {});
        });
  }

  @override
  Widget build(BuildContext context) {
    final best = SaveService.instance.getHighScore(kPieSplatId);
    return GameScaffold(
      title: 'Pie Splat Party',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 64, 16, 24),
        child: Column(
          children: [
            SizedBox(
              height: 150,
              child: AnimatedBuilder(
                animation: _anim,
                builder: (context, _) => CustomPaint(
                  size: const Size(double.infinity, 150),
                  painter: _HeroPainter(_anim.value * 4),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'The silliest party in town!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "It's a pie fight in the garden! Throw custard pies at the "
              'show-offs and dodge theirs. Just don\'t splat the guests!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xDDFFFFFF), fontSize: 15),
            ),
            const SizedBox(height: 14),
            if (best > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Your best: $best',
                  style: const TextStyle(color: Color(0xFFFFE082), fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            GestureDetector(
              key: const Key('pie_play'),
              onTap: _play,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4081),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kInk3, width: 3),
                  boxShadow: const [BoxShadow(color: kInk3, offset: Offset(0, 5))],
                ),
                child: const Text(
                  'PLAY!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _card(
              children: [
                _rule('🕹', 'Drag on the left side to run about. On a computer use WASD or the arrow keys.'),
                _rule('🥧', 'Press THROW (or Space) to lob a pie. It aims at the show-off you are facing.'),
                _rule('💨', 'Press DODGE (or Shift) to dash out of the way of a pie.'),
                _rule('👵', 'Splat Granny, the Waiter or Biscuit the puppy and you lose 15 points!'),
                _rule('⭐', 'Grab the golden pie for TRIPLE PIES. Watch out for whoopee cushions!'),
                _rule('👑', 'Most points after 90 seconds wins the party.'),
              ],
            ),
            const SizedBox(height: 14),
            _card(
              children: [
                const Text(
                  "Who's who",
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [for (final g in Kind.values) _portrait(g)],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white24),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );

  Widget _rule(String emoji, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 30, child: Text(emoji, style: const TextStyle(fontSize: 18))),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
      ],
    ),
  );

  Widget _portrait(Kind g) {
    final danger = g.stranger;
    return SizedBox(
      width: 92,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: danger ? const Color(0xFFFFCDD2) : const Color(0xFFFFF6DC),
              shape: BoxShape.circle,
              border: Border.all(color: danger ? const Color(0xFFE53935) : kInk3, width: 3),
            ),
            clipBehavior: Clip.antiAlias,
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) => CustomPaint(
                painter: _PortraitPainter(g, _anim.value * 4),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            g.title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          Text(
            danger ? "DON'T splat!" : g == Kind.chef ? "That's you!" : 'Splat!',
            style: TextStyle(
              color: danger ? const Color(0xFFFF8A80) : const Color(0xFFB9F6CA),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PortraitPainter extends CustomPainter {
  _PortraitPainter(this.g, this.t);
  final Kind g;
  final double t;

  @override
  void paint(Canvas canvas, Size size) => paintPortrait(canvas, size, g, t);

  @override
  bool shouldRepaint(covariant _PortraitPainter old) => old.t != t;
}

/// Lord Snootypants getting a pie in the face, over and over.
class _HeroPainter extends CustomPainter {
  _HeroPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final cycle = t % 2.0; // the pie flies for 0.5s, then 1.5s of custard
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final box = Size(size.height, size.height);
    canvas.translate((size.width - box.width) / 2, 0);
    paintPortrait(canvas, box, Kind.snooty, t, splat: cycle > 0.5 ? cycle - 0.5 : -1);
    if (cycle <= 0.5) {
      final k = cycle / 0.5;
      final from = Offset(-box.width * 0.4, box.height);
      final to = Offset(box.width / 2, box.height * 0.42);
      final pos = Offset.lerp(from, to, k)! - Offset(0, sin(k * pi) * 40);
      _pie2d(canvas, pos, 22 - 6 * k, k * 6);
    }
    canvas.restore();
  }

  void _pie2d(Canvas c, Offset o, double r, double spin) {
    c.save();
    c.translate(o.dx, o.dy);
    c.rotate(spin);
    final tin = Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 1.5);
    c.drawOval(tin, Paint()..color = kCrust3);
    c.drawOval(tin, Paint()
      ..color = kInk3
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    c.drawOval(tin.deflate(r * 0.2), Paint()..color = kCream3);
    c.drawCircle(Offset(0, -r * 0.15), r * 0.18, Paint()..color = const Color(0xFFD50000));
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _HeroPainter old) => old.t != t;
}
