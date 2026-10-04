import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_scaffold.dart';
import '../../services/sound_service.dart';
import '../../services/save_service.dart';

enum ReactionState { waiting, ready, tooEarly, result }

class ReactionScreen extends StatefulWidget {
  const ReactionScreen({super.key});

  @override
  State<ReactionScreen> createState() => _ReactionScreenState();
}

class _ReactionScreenState extends State<ReactionScreen>
    with SingleTickerProviderStateMixin {
  ReactionState _state = ReactionState.waiting;
  int _reactionTime = 0;
  late int _bestTime;
  final List<int> _times = [];
  Timer? _waitTimer;
  DateTime? _startTime;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _bestTime = SaveService.instance.reactionBest ?? 9999;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _startRound();
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startRound() {
    setState(() => _state = ReactionState.waiting);

    final delay = Duration(milliseconds: 1500 + Random().nextInt(4000));
    _waitTimer = Timer(delay, () {
      if (mounted) {
        setState(() {
          _state = ReactionState.ready;
          _startTime = DateTime.now();
        });
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _onTap() {
    switch (_state) {
      case ReactionState.waiting:
        _waitTimer?.cancel();
        SoundService.instance.play(GameSound.tooEarly);
        setState(() => _state = ReactionState.tooEarly);
        HapticFeedback.heavyImpact();
      case ReactionState.ready:
        SoundService.instance.play(GameSound.reactionTap);
        final now = DateTime.now();
        final reaction = now.difference(_startTime!).inMilliseconds;
        setState(() {
          _reactionTime = reaction;
          _state = ReactionState.result;
          _times.add(reaction);
          if (reaction < _bestTime) _bestTime = reaction;
        });
        SaveService.instance.saveReactionBest(reaction);
        SaveService.instance.saveReactionGamesPlayed(_times.length);
        HapticFeedback.lightImpact();
      case ReactionState.tooEarly:
        _startRound();
      case ReactionState.result:
        _startRound();
    }
  }

  Color get _backgroundColor {
    switch (_state) {
      case ReactionState.waiting:
        return AppTheme.danger;
      case ReactionState.ready:
        return AppTheme.success;
      case ReactionState.tooEarly:
        return AppTheme.warning;
      case ReactionState.result:
        return AppTheme.accent;
    }
  }

  String get _mainText {
    switch (_state) {
      case ReactionState.waiting:
        return 'Wait for green...';
      case ReactionState.ready:
        return 'TAP NOW!';
      case ReactionState.tooEarly:
        return 'Too Early!';
      case ReactionState.result:
        return '${_reactionTime}ms';
    }
  }

  String get _subText {
    switch (_state) {
      case ReactionState.waiting:
        return "Don't tap yet!";
      case ReactionState.ready:
        return 'Tap as fast as you can!';
      case ReactionState.tooEarly:
        return 'Tap to try again';
      case ReactionState.result:
        return _getReactionComment();
    }
  }

  String _getReactionComment() {
    if (_reactionTime < 200) return 'Incredible! ⚡';
    if (_reactionTime < 250) return 'Amazing! 🔥';
    if (_reactionTime < 300) return 'Great! ⭐';
    if (_reactionTime < 400) return 'Good! 👍';
    return 'Keep practicing! 💪';
  }

  int get _averageTime {
    if (_times.isEmpty) return 0;
    return (_times.reduce((a, b) => a + b) / _times.length).round();
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Reaction Speed',
      body: Column(
        children: [
          const SizedBox(height: 16),
          _buildStats(),
          const SizedBox(height: 24),
          Expanded(child: _buildTapArea()),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(
            'Best',
            _bestTime < 9999 ? '${_bestTime}ms' : '--',
            AppTheme.success,
          ),
          _buildStatItem(
            'Average',
            _times.isNotEmpty ? '${_averageTime}ms' : '--',
            AppTheme.accent,
          ),
          _buildStatItem('Tries', '${_times.length}', AppTheme.purple),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTapArea() {
    return GestureDetector(
      onTap: _state == ReactionState.waiting || _state == ReactionState.ready
          ? _onTap
          : _onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              _backgroundColor.withValues(alpha: 0.4),
              _backgroundColor.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: _backgroundColor.withValues(alpha: 0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: _backgroundColor.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _state == ReactionState.ready
                          ? 1.0 + _pulseController.value * 0.1
                          : 1.0,
                      child: child,
                    );
                  },
                  child: Icon(
                    _state == ReactionState.waiting
                        ? Icons.hourglass_top_rounded
                        : _state == ReactionState.ready
                        ? Icons.touch_app_rounded
                        : _state == ReactionState.tooEarly
                        ? Icons.warning_rounded
                        : Icons.timer_rounded,
                    color: _backgroundColor,
                    size: 64,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _mainText,
                  style: TextStyle(
                    color: _backgroundColor,
                    fontSize: _state == ReactionState.result ? 48 : 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _subText,
                  style: TextStyle(
                    color: _backgroundColor.withValues(alpha: 0.7),
                    fontSize: 16,
                  ),
                ),
                if (_state == ReactionState.result) ...[
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Tap to try again',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
