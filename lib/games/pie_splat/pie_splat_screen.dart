import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/save_service.dart';
import '../../widgets/game_scaffold.dart';
import 'pie_splat_art.dart';
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
              'A bunch of show-offs keep popping out of the windows. '
              'Tap them to splat them with a custard pie!',
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
                  border: Border.all(color: kPieInk, width: 3),
                  boxShadow: const [BoxShadow(color: kPieInk, offset: Offset(0, 5))],
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
                _rule('🥧', 'Tap a show-off to splat them. Splat lots in a row for a big combo.'),
                _rule('👵', "Don't splat Granny or Biscuit the puppy, or you lose a heart."),
                _rule('🐔', 'Splat the Golden Chicken for a MEGA PIE that splats everyone!'),
                _rule('💨', 'Tap the whoopee cushion for points and extra time.'),
                _rule('⏱', 'You have 60 seconds. Lose 3 hearts and it is game over.'),
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
                  children: [for (final g in Goof.values) _portrait(g)],
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

  Widget _portrait(Goof g) {
    final danger = g.noSplat;
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
              border: Border.all(color: danger ? const Color(0xFFE53935) : kPieInk, width: 3),
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
            danger ? "DON'T splat!" : g == Goof.chicken ? 'MEGA PIE' : 'Splat!',
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
  final Goof g;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * 0.28;
    paintGoof(canvas, g, Offset(size.width / 2, size.height * 0.56), r, time: t);
  }

  @override
  bool shouldRepaint(covariant _PortraitPainter old) => old.t != t;
}

/// Lord Snootypants getting a pie in the face, over and over.
class _HeroPainter extends CustomPainter {
  _HeroPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final r = 46.0;
    final head = Offset(cx + 30, 88);
    final cycle = t % 2.0; // pie flies for 0.5s, then 1.5s of custard
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    paintGoof(
      canvas,
      Goof.snooty,
      head,
      r,
      time: t,
      splat: cycle > 0.5 ? cycle - 0.5 : null,
    );
    canvas.restore();
    if (cycle <= 0.5) {
      final k = cycle / 0.5;
      final from = Offset(max(30, cx - 150), 130);
      final pos = Offset.lerp(from, head, k)! - Offset(0, sin(k * pi) * 40);
      paintPie(canvas, pos, 22 - 6 * k, spin: k * 6);
    }
  }

  @override
  bool shouldRepaint(covariant _HeroPainter old) => old.t != t;
}
