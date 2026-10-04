import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../services/sound_service.dart';
import 'models/bow.dart';
import 'models/game_world.dart';
import 'models/player_data.dart';
import 'models/target.dart';
import 'painters/world_painter.dart';

class TargetGameScreen extends StatefulWidget {
  final GameWorld world;
  final PlayerData playerData;
  final VoidCallback onComplete;

  const TargetGameScreen({
    super.key,
    required this.world,
    required this.playerData,
    required this.onComplete,
  });

  @override
  State<TargetGameScreen> createState() => _TargetGameScreenState();
}

class _TargetGameScreenState extends State<TargetGameScreen>
    with TickerProviderStateMixin {
  late int currentLevel;
  List<ShootingTarget> targets = [];
  List<Arrow> arrows = [];
  int targetsHit = 0;
  int totalShots = 0;
  int arrowsLeft = 0;
  bool levelComplete = false;
  bool levelFailed = false;
  bool showCountdown = true;
  int countdown = 3;
  Size? _gameAreaSize;

  double timeLeft = 0;
  double maxTime = 0;

  double windForce = 0;
  static const double gravity = 4.0;

  bool _isAiming = false;
  Offset _aimPoint = Offset.zero;
  double _drawStrength = 0;
  Offset? _dragStart;
  double _bowAngle = -pi / 2;

  // Dark Shadow ability
  bool _pauseAbilityActive = false;
  double _pauseCooldownTimer = 0;

  Timer? _gameLoop;
  Timer? _countdownTimer;
  late AnimationController _hitController;
  late AnimationController _levelUpController;
  Offset? _lastHitPosition;
  int? _lastHitPoints;

  final int targetsPerLevel = 5;

  Offset get _bowPosition {
    final s = _gameAreaSize;
    if (s == null) return Offset.zero;
    return Offset(s.width / 2, s.height - 60);
  }

  // The nock point where the arrow launches from (tip of the bow)
  Offset get _arrowLaunchPoint {
    final bowR = 35.0;
    return Offset(
      _bowPosition.dx + cos(_bowAngle) * bowR * 0.9,
      _bowPosition.dy + sin(_bowAngle) * bowR * 0.9,
    );
  }

  @override
  void initState() {
    super.initState();
    currentLevel = widget.playerData.currentLevel(widget.world.id);
    _hitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _levelUpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _startCountdown();
  }

  @override
  void dispose() {
    _gameLoop?.cancel();
    _countdownTimer?.cancel();
    _hitController.dispose();
    _levelUpController.dispose();
    super.dispose();
  }

  int _arrowBudget() {
    // Level 1-10: 12 arrows, level 11-30: 10, level 31-50: 7
    if (currentLevel <= 10) return 12;
    if (currentLevel <= 30) return 10;
    return (10 - (currentLevel - 30) * 0.15).round().clamp(7, 10);
  }

  double _timeForLevel() {
    // Level 1-5: 40s, then decrease to 15s at level 50
    if (currentLevel <= 5) return 40;
    return (40 - (currentLevel - 5) * 0.56).clamp(15.0, 40.0);
  }

  double _windForLevel() {
    if (currentLevel <= 8) return 0;
    final maxWind = ((currentLevel - 8) * 0.06).clamp(0.0, 2.5);
    return (Random().nextDouble() * 2 - 1) * maxWind;
  }

  void _startCountdown() {
    countdown = 3;
    showCountdown = true;
    levelComplete = false;
    levelFailed = false;
    _pauseAbilityActive = false;
    _pauseCooldownTimer = 0;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        countdown--;
        if (countdown <= 0) {
          SoundService.instance.play(GameSound.countdown);
          showCountdown = false;
          timer.cancel();
          _startLevel();
        } else {
          SoundService.instance.play(GameSound.countdownTick);
        }
      });
    });
  }

  void _startLevel() {
    targetsHit = 0;
    totalShots = 0;
    arrowsLeft = _arrowBudget();
    maxTime = _timeForLevel();
    timeLeft = maxTime;
    windForce = _windForLevel();
    arrows.clear();
    _isAiming = false;
    _drawStrength = 0;

    if (_gameAreaSize != null) {
      _spawnTargets();
    }

    _gameLoop?.cancel();
    _gameLoop = Timer.periodic(const Duration(milliseconds: 16), _tick);
  }

  void _spawnTargets() {
    setState(() {
      targets = ShootingTarget.generateForLevel(
        level: currentLevel,
        areaSize: _gameAreaSize!,
        count: targetsPerLevel,
      );
    });
  }

  void _tick(Timer timer) {
    if (!mounted || levelComplete || levelFailed || showCountdown) return;

    const dt = 1.0 / 60.0;

    setState(() {
      timeLeft -= dt;
      if (timeLeft <= 0) {
        timeLeft = 0;
        SoundService.instance.play(GameSound.levelFail);
        _failLevel();
        return;
      }

      // Pause ability cooldown
      if (_pauseAbilityActive) {
        _pauseCooldownTimer -= dt;
        if (_pauseCooldownTimer <= 0) {
          _pauseAbilityActive = false;
        }
      }

      for (final t in targets) {
        t.update(dt, _gameAreaSize!);
      }

      for (final arrow in arrows) {
        if (!arrow.active || arrow.stuck) continue;

        arrow.update(dt, gravity, windForce);

        if (arrow.isOffScreen(_gameAreaSize!)) {
          arrow.active = false;
          continue;
        }

        for (final target in targets) {
          if (target.isHit) continue;
          if (target.containsPoint(arrow.position)) {
            _onArrowHitTarget(arrow, target);
            break;
          }
        }
      }

      arrows.removeWhere((a) => !a.active && !a.stuck);
    });
  }

  void _onArrowHitTarget(Arrow arrow, ShootingTarget target) {
    arrow.active = false;
    arrow.stuck = true;
    target.isHit = true;
    targetsHit++;
    _lastHitPosition = target.position;
    _lastHitPoints = target.points;
    widget.playerData.totalTargetsHit++;

    SoundService.instance.play(GameSound.hit);
    HapticFeedback.mediumImpact();
    _hitController.forward(from: 0);

    // Dark Shadow ability: pause all remaining targets
    if (widget.playerData.equippedBow.hasPauseAbility && !_pauseAbilityActive) {
      _pauseAbilityActive = true;
      _pauseCooldownTimer = 5.0;
      for (final t in targets) {
        if (!t.isHit) {
          t.pauseFor(5.0);
        }
      }
    }

    if (targetsHit >= targetsPerLevel) {
      _completeLevel();
    }
  }

  void _onPanStart(DragStartDetails details) {
    if (levelComplete || levelFailed || showCountdown || arrowsLeft <= 0) {
      return;
    }
    setState(() {
      _isAiming = true;
      _dragStart = details.localPosition;
      _aimPoint = details.localPosition;
      _drawStrength = 0;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isAiming || _dragStart == null) return;

    setState(() {
      _aimPoint = details.localPosition;
      final pull = (_dragStart! - _aimPoint).distance;
      _drawStrength = (pull / 150.0).clamp(0.0, 1.0);

      final dx = _aimPoint.dx - _bowPosition.dx;
      final dy = _aimPoint.dy - _bowPosition.dy;
      _bowAngle = atan2(dy, dx);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_isAiming) return;

    if (_drawStrength > 0.15) {
      _shootArrow();
    }

    setState(() {
      _isAiming = false;
      _drawStrength = 0;
    });
  }

  void _shootArrow() {
    if (arrowsLeft <= 0) return;

    SoundService.instance.play(GameSound.shoot);
    HapticFeedback.lightImpact();

    final speed = 6.0 + _drawStrength * 10.0;
    final launchPt = _arrowLaunchPoint;
    final dx = _aimPoint.dx - _bowPosition.dx;
    final dy = _aimPoint.dy - _bowPosition.dy;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < 1) return;

    final vx = (dx / dist) * speed;
    final vy = (dy / dist) * speed;

    setState(() {
      arrowsLeft--;
      totalShots++;
      arrows.add(
        Arrow(position: launchPt, vx: vx, vy: vy, angle: atan2(vy, vx)),
      );
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || levelComplete || levelFailed) return;
      if (arrowsLeft <= 0 && targetsHit < targetsPerLevel) {
        final anyActive = arrows.any((a) => a.active && !a.stuck);
        if (!anyActive) {
          SoundService.instance.play(GameSound.bowTwang);
          _failLevel();
        }
      }
    });
  }

  void _completeLevel() {
    _gameLoop?.cancel();
    setState(() => levelComplete = true);
    final reward = widget.world.diamondsPerLevel;
    widget.playerData.completeLevel(widget.world.id, diamondReward: reward);
    widget.onComplete();
    SoundService.instance.play(GameSound.levelComplete);
    _levelUpController.forward(from: 0);
    HapticFeedback.heavyImpact();
  }

  void _failLevel() {
    _gameLoop?.cancel();
    setState(() => levelFailed = true);
    SoundService.instance.play(GameSound.levelFail);
    HapticFeedback.heavyImpact();
  }

  void _nextLevel() {
    if (currentLevel >= PlayerData.maxLevel) {
      _showWorldCompleteDialog();
      return;
    }
    setState(() {
      currentLevel = widget.playerData.currentLevel(widget.world.id);
    });
    _startCountdown();
  }

  void _retryLevel() {
    _startCountdown();
  }

  void _showWorldCompleteDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🏆', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text(
                '${widget.world.name} Complete!',
                style: TextStyle(
                  color: widget.world.primaryColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You conquered all 50 levels!',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('Back to Worlds'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int get _accuracy {
    if (totalShots == 0) return 0;
    return ((targetsHit / totalShots) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: WorldBackgroundPainter(
                world: widget.world,
                level: currentLevel,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildGameArea()),
              ],
            ),
          ),
          if (showCountdown) _buildCountdownOverlay(),
          if (levelComplete) _buildLevelCompleteOverlay(),
          if (levelFailed) _buildFailOverlay(),
          if (_lastHitPosition != null) _buildHitPopup(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white70,
              size: 20,
            ),
            onPressed: () {
              _gameLoop?.cancel();
              Navigator.of(context).pop();
            },
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: widget.world.primaryColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.world.primaryColor.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              'Lv.$currentLevel',
              style: TextStyle(
                color: widget.world.primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _buildHudChip(
            Icons.timer_rounded,
            '${timeLeft.ceil()}s',
            timeLeft <= 5 ? AppTheme.danger : AppTheme.textSecondary,
          ),
          const Spacer(),
          _buildHudChip(
            Icons.arrow_upward_rounded,
            '$arrowsLeft',
            arrowsLeft <= 2 ? AppTheme.warning : AppTheme.accent,
          ),
          const SizedBox(width: 6),
          _buildHudChip(
            Icons.track_changes_rounded,
            '$targetsHit/$targetsPerLevel',
            AppTheme.success,
          ),
          const SizedBox(width: 6),
          if (windForce.abs() > 0.1) _buildWindIndicator(),
          if (_pauseAbilityActive)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _buildHudChip(
                Icons.pause_circle_rounded,
                '${_pauseCooldownTimer.ceil()}s',
                const Color(0xFFFF0040),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHudChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindIndicator() {
    final isLeft = windForce < 0;
    final strength = windForce.abs();
    final label = strength < 1.0
        ? 'Light'
        : strength < 2.0
        ? 'Moderate'
        : 'Strong';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLeft ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded,
            color: AppTheme.blue,
            size: 14,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.blue,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final newSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (_gameAreaSize == null || _gameAreaSize != newSize) {
          _gameAreaSize = newSize;
          if (targets.isEmpty &&
              !showCountdown &&
              !levelComplete &&
              !levelFailed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _spawnTargets();
            });
          }
        }

        return GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          behavior: HitTestBehavior.opaque,
          child: CustomPaint(
            painter: _GamePainter(
              targets: targets,
              arrows: arrows,
              bowPosition: _bowPosition,
              bowAngle: _bowAngle,
              drawStrength: _drawStrength,
              isAiming: _isAiming,
              aimPoint: _aimPoint,
              targetColor: widget.world.targetColor,
              bowColors: widget.playerData.equippedBow.colors,
              arrowColor: widget.playerData.equippedArrow.color,
              windForce: windForce,
              gameAreaSize: newSize,
              isMythic:
                  widget.playerData.equippedBow.rarity == BowRarity.mythic,
              pauseActive: _pauseAbilityActive,
            ),
            size: newSize,
          ),
        );
      },
    );
  }

  Widget _buildCountdownOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.world.name,
              style: TextStyle(
                color: widget.world.primaryColor.withValues(alpha: 0.7),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Level $currentLevel',
              style: TextStyle(
                color: widget.world.primaryColor,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.world.diamondMultiplier > 1) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '💎 x${widget.world.diamondMultiplier} DIAMONDS',
                  style: const TextStyle(
                    color: AppTheme.warning,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            Text(
              countdown > 0 ? '$countdown' : 'GO!',
              style: TextStyle(
                color: countdown > 0 ? Colors.white : AppTheme.success,
                fontSize: 80,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildCountdownInfo(
                  Icons.track_changes_rounded,
                  '$targetsPerLevel targets',
                ),
                const SizedBox(width: 20),
                _buildCountdownInfo(
                  Icons.arrow_upward_rounded,
                  '${_arrowBudget()} arrows',
                ),
                const SizedBox(width: 20),
                _buildCountdownInfo(
                  Icons.timer_rounded,
                  '${_timeForLevel().round()}s',
                ),
              ],
            ),
            if (_windForLevel().abs() > 0.1) ...[
              const SizedBox(height: 12),
              _buildCountdownInfo(Icons.air_rounded, 'Wind active!'),
            ],
            const SizedBox(height: 24),
            Text(
              'Drag to aim • Pull back to draw • Release to shoot',
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownInfo(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppTheme.textSecondary, size: 14),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildLevelCompleteOverlay() {
    final stars = _accuracy >= 80
        ? 3
        : _accuracy >= 50
        ? 2
        : 1;
    final reward = widget.world.diamondsPerLevel;

    return ScaleTransition(
      scale: CurvedAnimation(
        parent: _levelUpController,
        curve: Curves.elasticOut,
      ),
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: widget.world.primaryColor.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.world.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 30,
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🎯', style: TextStyle(fontSize: 44)),
                  const SizedBox(height: 12),
                  Text(
                    'Level $currentLevel Complete!',
                    style: TextStyle(
                      color: widget.world.primaryColor,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (i) => Icon(
                        i < stars
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: AppTheme.warning,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildResultStat('Accuracy', '$_accuracy%'),
                      _buildResultStat('Shots', '$totalShots'),
                      _buildResultStat(
                        'Time',
                        '${(maxTime - timeLeft).toStringAsFixed(1)}s',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.diamond_rounded,
                          color: AppTheme.accent,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '+$reward Diamonds${reward > 5 ? ' (x${widget.world.diamondMultiplier})' : ''}',
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: _retryLevel,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _nextLevel,
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: Text(
                          currentLevel >= PlayerData.maxLevel
                              ? 'Finish'
                              : 'Next Level',
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

  Widget _buildFailOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppTheme.danger.withValues(alpha: 0.5)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('💥', style: TextStyle(fontSize: 44)),
                const SizedBox(height: 12),
                const Text(
                  'Level Failed',
                  style: TextStyle(
                    color: AppTheme.danger,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$targetsHit/$targetsPerLevel targets hit',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
                if (arrowsLeft <= 0) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Ran out of arrows!',
                    style: TextStyle(color: AppTheme.warning, fontSize: 13),
                  ),
                ],
                if (timeLeft <= 0) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Time ran out!',
                    style: TextStyle(color: AppTheme.warning, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _retryLevel,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildHitPopup() {
    return Positioned(
      left: (_lastHitPosition?.dx ?? 0) - 20,
      top: (_lastHitPosition?.dy ?? 0) - 40,
      child: IgnorePointer(
        child: ScaleTransition(
          scale: CurvedAnimation(
            parent: _hitController,
            curve: Curves.elasticOut,
          ),
          child: FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0).animate(
              CurvedAnimation(
                parent: _hitController,
                curve: const Interval(0.5, 1.0),
              ),
            ),
            child: Text(
              '+${_lastHitPoints ?? 10}',
              style: TextStyle(
                color: widget.world.targetColor,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    color: widget.world.targetColor.withValues(alpha: 0.5),
                    blurRadius: 10,
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

class _GamePainter extends CustomPainter {
  final List<ShootingTarget> targets;
  final List<Arrow> arrows;
  final Offset bowPosition;
  final double bowAngle;
  final double drawStrength;
  final bool isAiming;
  final Offset aimPoint;
  final Color targetColor;
  final List<Color> bowColors;
  final Color arrowColor;
  final double windForce;
  final Size gameAreaSize;
  final bool isMythic;
  final bool pauseActive;

  _GamePainter({
    required this.targets,
    required this.arrows,
    required this.bowPosition,
    required this.bowAngle,
    required this.drawStrength,
    required this.isAiming,
    required this.aimPoint,
    required this.targetColor,
    required this.bowColors,
    required this.arrowColor,
    required this.windForce,
    required this.gameAreaSize,
    required this.isMythic,
    required this.pauseActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawTargets(canvas, size);
    _drawArrows(canvas, size);
    _drawBow(canvas, size);
    if (isAiming) {
      _drawAimLine(canvas, size);
      _drawCrosshair(canvas, size);
    }
  }

  void _drawTargets(Canvas canvas, Size size) {
    for (final target in targets) {
      if (target.isHit) continue;

      final center = target.position;
      final r = target.radius;

      // Paused glow
      if (target.isPaused) {
        final pauseGlow = Paint()
          ..color = const Color(0xFFFF0040).withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
        canvas.drawCircle(center, r + 6, pauseGlow);
      }

      final glowPaint = Paint()
        ..color = targetColor.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(center, r + 4, glowPaint);

      final ringColors = [
        targetColor.withValues(alpha: 0.5),
        targetColor,
        targetColor.withValues(alpha: 0.5),
        Colors.white,
      ];
      final ringRatios = [1.0, 0.7, 0.4, 0.15];

      for (int i = 0; i < ringColors.length; i++) {
        final paint = Paint()
          ..color = ringColors[i]
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, r * ringRatios[i], paint);
      }

      final linePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 0.8;
      canvas.drawLine(
        Offset(center.dx - r, center.dy),
        Offset(center.dx + r, center.dy),
        linePaint,
      );
      canvas.drawLine(
        Offset(center.dx, center.dy - r),
        Offset(center.dx, center.dy + r),
        linePaint,
      );
    }
  }

  void _drawArrows(Canvas canvas, Size size) {
    for (final arrow in arrows) {
      if (!arrow.active && !arrow.stuck) continue;

      final arrowLen = 18.0;
      final tip = arrow.position;
      final tail = Offset(
        tip.dx - cos(arrow.angle) * arrowLen,
        tip.dy - sin(arrow.angle) * arrowLen,
      );

      final shaftPaint = Paint()
        ..color = arrowColor
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(tail, tip, shaftPaint);

      final headPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final headSize = 6.0;
      final perpAngle = arrow.angle + pi / 2;
      final headPath = Path()
        ..moveTo(tip.dx + cos(arrow.angle) * 3, tip.dy + sin(arrow.angle) * 3)
        ..lineTo(
          tip.dx + cos(perpAngle) * headSize - cos(arrow.angle) * headSize,
          tip.dy + sin(perpAngle) * headSize - sin(arrow.angle) * headSize,
        )
        ..lineTo(
          tip.dx - cos(perpAngle) * headSize - cos(arrow.angle) * headSize,
          tip.dy - sin(perpAngle) * headSize - sin(arrow.angle) * headSize,
        )
        ..close();
      canvas.drawPath(headPath, headPaint);

      if (arrow.active) {
        final trailPaint = Paint()
          ..color = arrowColor.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawLine(tail, tip, trailPaint);
      }
    }
  }

  void _drawBow(Canvas canvas, Size size) {
    final center = bowPosition;
    final bowR = 35.0;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(bowAngle + pi / 2);

    final bowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    if (bowColors.length > 1) {
      bowPaint.shader = LinearGradient(
        colors: bowColors,
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: bowR));
    } else {
      bowPaint.color = bowColors.first;
    }

    final bowRect = Rect.fromCircle(center: Offset.zero, radius: bowR);
    canvas.drawArc(bowRect, -pi * 0.7, pi * 1.4, false, bowPaint);

    // Mythic glow
    if (isMythic) {
      final mythGlow = Paint()
        ..color = const Color(0xFFFF0040).withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12;
      canvas.drawArc(bowRect, -pi * 0.7, pi * 1.4, false, mythGlow);
    } else {
      final glowP = Paint()
        ..color = bowColors.first.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10;
      canvas.drawArc(bowRect, -pi * 0.7, pi * 1.4, false, glowP);
    }

    final stringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final topP = Offset(bowR * cos(-pi * 0.7), bowR * sin(-pi * 0.7));
    final bottomP = Offset(bowR * cos(pi * 0.7), bowR * sin(pi * 0.7));
    final pullBack = drawStrength * bowR * 0.6;
    final midP = Offset(-pullBack, 0);

    final stringPath = Path()
      ..moveTo(topP.dx, topP.dy)
      ..lineTo(midP.dx, midP.dy)
      ..lineTo(bottomP.dx, bottomP.dy);
    canvas.drawPath(stringPath, stringPaint);

    // Arrow nocked - tip extends to the bow's edge for correct alignment
    if (drawStrength > 0.1) {
      final arrowPaint = Paint()
        ..color = arrowColor.withValues(alpha: 0.9)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(midP, Offset(bowR * 0.9, 0), arrowPaint);

      final tipPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final tipPath = Path()
        ..moveTo(bowR * 0.9 + 6, 0)
        ..lineTo(bowR * 0.9 - 3, -4)
        ..lineTo(bowR * 0.9 - 3, 4)
        ..close();
      canvas.drawPath(tipPath, tipPaint);
    }

    canvas.restore();

    if (drawStrength > 0) {
      final meterPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(AppTheme.success, AppTheme.danger, drawStrength)!;
      final meterRect = Rect.fromCircle(center: center, radius: bowR + 12);
      canvas.drawArc(
        meterRect,
        pi * 0.6,
        -pi * 1.2 * drawStrength,
        false,
        meterPaint,
      );
    }
  }

  void _drawAimLine(Canvas canvas, Size size) {
    if (drawStrength < 0.1) return;

    final speed = 6.0 + drawStrength * 10.0;
    final launchPt = Offset(
      bowPosition.dx + cos(bowAngle) * 35.0 * 0.9,
      bowPosition.dy + sin(bowAngle) * 35.0 * 0.9,
    );
    final dx = aimPoint.dx - bowPosition.dx;
    final dy = aimPoint.dy - bowPosition.dy;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < 1) return;

    final vx = (dx / dist) * speed;
    final vy = (dy / dist) * speed;

    final dotPaint = Paint()..style = PaintingStyle.fill;
    var px = launchPt.dx;
    var py = launchPt.dy;
    var avx = vx;
    var avy = vy;
    const dt = 1.0 / 60.0;

    for (int i = 0; i < 40; i++) {
      avx += windForce * dt;
      avy += 4.0 * dt;
      px += avx * dt * 60;
      py += avy * dt * 60;

      if (px < 0 || px > size.width || py < 0 || py > size.height) break;

      final alpha = (1.0 - i / 40.0) * 0.4;
      dotPaint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(Offset(px, py), 2, dotPaint);
    }
  }

  void _drawCrosshair(Canvas canvas, Size size) {
    final p = aimPoint;
    final r = 16.0;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(p, r, paint);

    canvas.drawLine(
      Offset(p.dx - r * 1.4, p.dy),
      Offset(p.dx - r * 0.4, p.dy),
      paint,
    );
    canvas.drawLine(
      Offset(p.dx + r * 0.4, p.dy),
      Offset(p.dx + r * 1.4, p.dy),
      paint,
    );
    canvas.drawLine(
      Offset(p.dx, p.dy - r * 1.4),
      Offset(p.dx, p.dy - r * 0.4),
      paint,
    );
    canvas.drawLine(
      Offset(p.dx, p.dy + r * 0.4),
      Offset(p.dx, p.dy + r * 1.4),
      paint,
    );

    final dotPaint = Paint()
      ..color = AppTheme.danger
      ..style = PaintingStyle.fill;
    canvas.drawCircle(p, 2.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _GamePainter oldDelegate) => true;
}
