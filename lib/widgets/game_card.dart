import 'package:flutter/material.dart';
import '../models/game_info.dart';

/// Ink colour used for outlines, hard shadows and text on the bright tiles.
const Color kInk = Color(0xFF15172A);

/// A flat, chunky game tile: solid colour, thick ink outline and a hard
/// offset shadow. Pressing it pushes the tile down onto its shadow.
class GameCard extends StatefulWidget {
  final GameInfo game;
  final int? highScore;
  final VoidCallback onTap;
  final Color? tileColor;

  const GameCard({
    super.key,
    required this.game,
    this.highScore,
    required this.onTap,
    this.tileColor,
  });

  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
  static const double _lift = 6;
  bool _isPressed = false;

  String get _players {
    final g = widget.game;
    if (g.maxPlayers > g.minPlayers) return '${g.minPlayers}–${g.maxPlayers} players';
    return g.minPlayers == 1 ? '1 player' : '${g.minPlayers} players';
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.tileColor ?? widget.game.color;
    final offset = _isPressed ? 1.0 : _lift;

    return Semantics(
      button: true,
      label: 'Play ${widget.game.title}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            margin: EdgeInsets.only(top: _lift - offset, bottom: offset),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kInk, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: kInk,
                  offset: Offset(0, offset),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(widget.game.icon, color: kInk, size: 40),
                      const Spacer(),
                      if (widget.highScore != null)
                        _BestSticker(score: widget.highScore!),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    widget.game.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kInk,
                      fontSize: 19,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.game.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: kInk.withValues(alpha: 0.75),
                      fontSize: 12.5,
                      height: 1.25,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(height: 2, color: kInk.withValues(alpha: 0.18)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        widget.game.difficulty,
                        style: const TextStyle(
                          color: kInk,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _players,
                        style: TextStyle(
                          color: kInk.withValues(alpha: 0.75),
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
        ),
      ),
    );
  }
}

/// Small white "sticker" showing the player's best for that game.
class _BestSticker extends StatelessWidget {
  final int score;
  const _BestSticker({required this.score});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.06,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kInk, width: 2),
        ),
        child: Text(
          'Best $score',
          style: const TextStyle(
            color: kInk,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
