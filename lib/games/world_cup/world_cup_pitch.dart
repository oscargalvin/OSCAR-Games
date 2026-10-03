import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'world_cup_data.dart';
import 'world_cup_joystick.dart';
import 'world_cup_lineup.dart';
import 'world_cup_models.dart';

/// Mini pitch with all outfield players, ball, and the user's controlled player.
class WorldCupPitchView extends StatelessWidget {
  const WorldCupPitchView({
    super.key,
    required this.homeNationId,
    required this.awayNationId,
    required this.userNationId,
    required this.homeGoals,
    required this.awayGoals,
    required this.homePlayers,
    required this.awayPlayers,
    this.pickPlayer,
    required this.playerPos,
    required this.ballPos,
    required this.fuel,
    required this.buildup,
  });

  final String homeNationId;
  final String awayNationId;
  final String userNationId;
  final int homeGoals;
  final int awayGoals;
  final List<WorldCupPlayer> homePlayers;
  final List<WorldCupPlayer> awayPlayers;
  final WorldCupPlayer? pickPlayer;
  final Offset playerPos;
  final Offset ballPos;
  final double fuel;
  final double buildup;

  @override
  Widget build(BuildContext context) {
    final userHome = homeNationId == userNationId;
    final home = nationById(homeNationId);
    final away = nationById(awayNationId);
    final homeSlots = formation433Home();
    final awaySlots = formation433Away();

    return AspectRatio(
      aspectRatio: 1.55,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2E7D32), Color(0xFF1B5E20), Color(0xFF388E3C)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            Offset toPx(Offset n) => Offset(n.dx * w, n.dy * h);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned.fill(child: CustomPaint(painter: _PitchLinesPainter())),
                Positioned(top: 8, left: 12, child: _teamBadge(home.countryCode, userHome)),
                Positioned(top: 8, right: 12, child: _teamBadge(away.countryCode, !userHome)),
                Positioned(
                  top: 36,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text('$homeGoals', style: _scoreStyle(userHome)),
                      Text('$awayGoals', style: _scoreStyle(!userHome)),
                    ],
                  ),
                ),
                ..._teamTokens(
                  homePlayers,
                  homeSlots,
                  toPx,
                  AppTheme.blue,
                  userHome,
                  pickPlayer?.id,
                  playerPos,
                  userHome,
                ),
                ..._teamTokens(
                  awayPlayers,
                  awaySlots,
                  toPx,
                  AppTheme.warning,
                  !userHome,
                  pickPlayer?.id,
                  playerPos,
                  userHome,
                ),
                Positioned(
                  left: toPx(ballPos).dx - 7,
                  top: toPx(ballPos).dy - 7,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black54, width: 1.5),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 4),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _barLabel('Fuel', fuel, AppTheme.warning),
                      const SizedBox(height: 4),
                      _barLabel('Build-up', buildup, AppTheme.accent),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _teamTokens(
    List<WorldCupPlayer> players,
    List<Offset> slots,
    Offset Function(Offset) toPx,
    Color color,
    bool isUserTeam,
    String? pickId,
    Offset controlledPos,
    bool userHome,
  ) {
    final widgets = <Widget>[];
    for (var i = 0; i < players.length && i < slots.length; i++) {
      final p = players[i];
      final isControlled = pickId == p.id;
      final slot = isControlled ? controlledPos : slots[i];
      final px = toPx(slot);
      widgets.add(
        Positioned(
          left: px.dx - (isControlled ? 18 : 14),
          top: px.dy - (isControlled ? 18 : 14),
          child: _playerToken(
            p,
            color: color,
            isControlled: isControlled,
            isUserTeam: isUserTeam,
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _teamBadge(String code, bool highlight) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? AppTheme.accent.withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11,
          color: highlight ? Colors.white : Colors.white70,
        ),
      ),
    );
  }

  TextStyle _scoreStyle(bool highlight) => TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w900,
        color: highlight ? Colors.white : Colors.white70,
        shadows: const [Shadow(color: Colors.black45, blurRadius: 4)],
      );

  Widget _playerToken(
    WorldCupPlayer player, {
    required Color color,
    required bool isControlled,
    required bool isUserTeam,
  }) {
    final initials = player.name
        .split(' ')
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();
    final size = isControlled ? 36.0 : 28.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isControlled ? AppTheme.accent : color.withValues(alpha: isUserTeam ? 0.95 : 0.75),
            border: Border.all(
              color: isControlled ? Colors.yellowAccent : Colors.white,
              width: isControlled ? 2.5 : 1.5,
            ),
            boxShadow: [
              if (isControlled)
                BoxShadow(color: AppTheme.accent.withValues(alpha: 0.6), blurRadius: 8),
              BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 4),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: isControlled ? 12 : 9,
            ),
          ),
        ),
        if (isControlled) ...[
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              player.name.split(' ').first,
              style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }

  Widget _barLabel(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (value / 100).clamp(0, 1),
            minHeight: 6,
            backgroundColor: Colors.black26,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _PitchLinesPainter extends CustomPainter {
  const _PitchLinesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final midY = size.height / 2;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), paint);
    canvas.drawCircle(Offset(size.width / 2, midY), size.width * 0.12, paint);

    final boxW = size.width * 0.28;
    final boxH = size.height * 0.22;
    canvas.drawRect(Rect.fromLTWH((size.width - boxW) / 2, 8, boxW, boxH), paint);
    canvas.drawRect(
      Rect.fromLTWH((size.width - boxW) / 2, size.height - boxH - 8, boxW, boxH),
      paint,
    );

    _drawGoal(canvas, size, top: true, paint: paint);
    _drawGoal(canvas, size, top: false, paint: paint);
  }

  void _drawGoal(Canvas canvas, Size size, {required bool top, required Paint paint}) {
    final net = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final gw = size.width * 0.22;
    const gh = 14.0;
    final left = (size.width - gw) / 2;
    final topY = top ? 0.0 : size.height - gh;
    canvas.drawRect(Rect.fromLTWH(left, topY, gw, gh), paint);
    for (var i = 1; i < 5; i++) {
      final x = left + (gw / 5) * i;
      canvas.drawLine(Offset(x, topY), Offset(x, topY + gh), net);
    }
    for (var i = 1; i < 3; i++) {
      final y = topY + (gh / 3) * i;
      canvas.drawLine(Offset(left, y), Offset(left + gw, y), net);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

List<WorldCupPlayer> startingXiPlayers(WorldCupSquad squad) => startingPlayers(squad);
