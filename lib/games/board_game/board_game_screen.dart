import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_scaffold.dart';
import '../../services/sound_service.dart';
import 'board_models.dart';
import 'nested_board_painter.dart';
import '../../widgets/full_screen_game.dart';

enum _SetupStep { pickCount, enterNames, playing }

class BoardGameScreen extends StatefulWidget {
  const BoardGameScreen({super.key});

  @override
  State<BoardGameScreen> createState() => _BoardGameScreenState();
}

class _BoardGameScreenState extends State<BoardGameScreen>
    with SingleTickerProviderStateMixin, FullScreenGame {
  static const playerColors = [
    AppTheme.accent,
    AppTheme.danger,
    AppTheme.purple,
    AppTheme.warning,
    AppTheme.success,
  ];
  static const int _maxEffectChain = 5;
  static const int minPlayers = 1;
  static const int maxPlayers = 5;

  late NestedSquareBoard board;
  final _rng = Random();

  _SetupStep step = _SetupStep.pickCount;
  int playerCount = 2;
  List<TextEditingController> nameControllers = [];
  List<String> playerNames = [];

  List<int> playerPathIndex = [];
  int currentPlayer = 0;
  int? lastRoll;
  int? winner;
  bool busy = false;
  int? highlightPathIndex;
  String status = '';

  late AnimationController _diceController;

  String nameOf(int i) =>
      i < playerNames.length ? playerNames[i] : 'Player ${i + 1}';

  List<String> get tokenLabels => [
        for (final n in playerNames)
          n.isEmpty ? '?' : n.characters.first.toUpperCase(),
      ];

  @override
  void initState() {
    super.initState();
    board = NestedSquareBoard(ringCount: 6, midsPerSide: 1);
    _diceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _diceController.dispose();
    for (final c in nameControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _goToNames() {
    SoundService.instance.play(GameSound.tap);
    for (final c in nameControllers) {
      c.dispose();
    }
    nameControllers = List.generate(
      playerCount,
      (i) => TextEditingController(text: 'Player ${i + 1}'),
    );
    setState(() => step = _SetupStep.enterNames);
  }

  void _startGame() {
    final names = <String>[];
    for (var i = 0; i < playerCount; i++) {
      final raw = nameControllers[i].text.trim();
      names.add(raw.isEmpty ? 'Player ${i + 1}' : raw);
    }
    SoundService.instance.play(GameSound.tap);
    setState(() {
      playerNames = names;
      playerPathIndex = List.filled(playerCount, 0);
      currentPlayer = 0;
      lastRoll = null;
      winner = null;
      busy = false;
      highlightPathIndex = null;
      status = '${names[0]}\'s turn — roll the dice!';
      step = _SetupStep.playing;
    });
  }

  void _backToSetup() {
    SoundService.instance.play(GameSound.tap);
    setState(() {
      step = _SetupStep.pickCount;
      winner = null;
      busy = false;
      lastRoll = null;
      highlightPathIndex = null;
    });
  }

  void _nextPlayer() {
    currentPlayer = (currentPlayer + 1) % playerCount;
  }

  Future<void> _rollDice() async {
    if (winner != null || busy) return;

    setState(() {
      busy = true;
      status = 'Rolling…';
      highlightPathIndex = null;
    });
    SoundService.instance.play(GameSound.tap);
    _diceController.forward(from: 0);

    for (var i = 0; i < 6; i++) {
      await Future.delayed(const Duration(milliseconds: 55));
      if (!mounted) return;
      setState(() => lastRoll = _rng.nextInt(6) + 1);
    }

    final roll = _rng.nextInt(6) + 1;
    if (!mounted) return;
    setState(() => lastRoll = roll);

    await Future.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;

    final from = playerPathIndex[currentPlayer];
    final target = from + roll;

    if (target > board.finishIndex) {
      SoundService.instance.play(GameSound.noMatch);
      final roller = nameOf(currentPlayer);
      final need = board.finishIndex - from;
      _nextPlayer();
      setState(() {
        busy = false;
        status =
            '$roller rolled $roll — need exactly $need to finish. '
            '${nameOf(currentPlayer)}\'s turn.';
      });
      return;
    }

    setState(() => status = '${nameOf(currentPlayer)} moves $roll…');
    await _hopTo(target);
    if (!mounted || winner != null) return;

    await _resolveLanding(depth: 0);
    if (!mounted || winner != null) return;

    setState(() {
      busy = false;
      highlightPathIndex = null;
      _nextPlayer();
      status = '${nameOf(currentPlayer)}\'s turn — roll the dice!';
    });
  }

  Future<void> _hopTo(int target, {int stepMs = 280}) async {
    final from = playerPathIndex[currentPlayer];
    if (target == from) return;

    if (target > from) {
      for (var next = from + 1; next <= target; next++) {
        await Future.delayed(Duration(milliseconds: stepMs));
        if (!mounted) return;
        SoundService.instance.play(GameSound.place);
        setState(() {
          playerPathIndex[currentPlayer] = next;
          highlightPathIndex = next;
        });
      }
    } else {
      for (var next = from - 1; next >= target; next--) {
        await Future.delayed(Duration(milliseconds: stepMs));
        if (!mounted) return;
        SoundService.instance.play(GameSound.place);
        setState(() {
          playerPathIndex[currentPlayer] = next;
          highlightPathIndex = next;
        });
      }
    }
  }

  Future<void> _jumpTo(int target) async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    SoundService.instance.play(GameSound.cardFlip);
    setState(() {
      playerPathIndex[currentPlayer] = target;
      highlightPathIndex = target;
    });
    await Future.delayed(const Duration(milliseconds: 220));
  }

  Future<void> _resolveLanding({required int depth}) async {
    final index = playerPathIndex[currentPlayer];

    if (index == board.finishIndex) {
      SoundService.instance.play(GameSound.win);
      setState(() {
        winner = currentPlayer;
        busy = false;
        highlightPathIndex = index;
        status = '${nameOf(currentPlayer)} reached the middle — you win!';
      });
      return;
    }

    if (depth >= _maxEffectChain) return;

    final effect = board.path[index].effect;
    if (effect == SpaceEffect.none) return;

    await Future.delayed(const Duration(milliseconds: 280));
    if (!mounted || winner != null) return;

    setState(
      () => status = '${nameOf(currentPlayer)}: ${effect.description}',
    );

    switch (effect) {
      case SpaceEffect.back3:
        final dest = (index - 3).clamp(0, board.finishIndex);
        await _hopTo(dest, stepMs: 220);
        break;
      case SpaceEffect.forward3:
        final dest = (index + 3).clamp(0, board.finishIndex);
        await _hopTo(dest, stepMs: 220);
        break;
      case SpaceEffect.goStart:
        await _jumpTo(0);
        break;
      case SpaceEffect.goLast:
        await _jumpTo(board.lastBeforeWinIndex);
        break;
      case SpaceEffect.none:
        return;
    }

    if (!mounted || winner != null) return;
    await _resolveLanding(depth: depth + 1);
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Lucky Board Game',
      actions: [
        if (step == _SetupStep.playing)
          IconButton(
            tooltip: 'New game',
            onPressed: busy ? null : _backToSetup,
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
      body: switch (step) {
        _SetupStep.pickCount => _buildPickCount(),
        _SetupStep.enterNames => _buildEnterNames(),
        _SetupStep.playing => _buildPlaying(),
      },
    );
  }

  Widget _buildPickCount() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'How many players?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose 1 to 5 players for this game.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.9),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 28),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var n = minPlayers; n <= maxPlayers; n++)
                _CountChip(
                  count: n,
                  selected: playerCount == n,
                  color: playerColors[(n - 1) % playerColors.length],
                  onTap: () {
                    SoundService.instance.play(GameSound.tap);
                    setState(() => playerCount = n);
                  },
                ),
            ],
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _goToNames,
            child: Text('Next · $playerCount player${playerCount == 1 ? '' : 's'}'),
          ),
        ],
      ),
    );
  }

  Widget _buildEnterNames() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Player names',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Type a name for each player.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.9),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ListView.separated(
              itemCount: playerCount,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final color = playerColors[i % playerColors.length];
                return TextField(
                  controller: nameControllers[i],
                  textCapitalization: TextCapitalization.words,
                  textInputAction: i == playerCount - 1
                      ? TextInputAction.done
                      : TextInputAction.next,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Player ${i + 1}',
                    labelStyle: TextStyle(color: color.withValues(alpha: 0.9)),
                    prefixIcon: Icon(Icons.person_rounded, color: color),
                    filled: true,
                    fillColor: AppTheme.surface.withValues(alpha: 0.55),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: color.withValues(alpha: 0.35)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: color, width: 1.6),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  SoundService.instance.play(GameSound.tap);
                  setState(() => step = _SetupStep.pickCount);
                },
                child: const Text('Back'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _startGame,
                  child: const Text('Start game'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaying() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
          child: Text(
            'Watch for -3, +3, START, and LAST squares. '
            'First into the middle wins.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.9),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
        _buildTurnRow(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Center(
              child: NestedBoardView(
                board: board,
                playerPathIndex: List<int>.from(playerPathIndex),
                playerColors: playerColors,
                tokenLabels: tokenLabels,
                highlightPathIndex: highlightPathIndex,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            status,
            textAlign: TextAlign.center,
            style: TextStyle(
              color:
                  winner != null ? AppTheme.success : AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: winner != null ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildDiceBar(),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildTurnRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Row(
        children: List.generate(playerCount, (p) {
          final color = playerColors[p % playerColors.length];
          final active = winner == null && currentPlayer == p;
          final won = winner == p;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: active || won ? 0.18 : 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: color.withValues(alpha: active || won ? 0.7 : 0.25),
                  width: active || won ? 1.6 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    won ? '${nameOf(p)} wins' : nameOf(p),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDiceBar() {
    final canRoll = winner == null && !busy;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _DiceFace(
            value: lastRoll,
            spinning: busy && lastRoll != null && highlightPathIndex == null,
            animation: _diceController,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: canRoll ? _rollDice : null,
              icon: const Icon(Icons.casino_rounded),
              label: Text(
                winner != null
                    ? 'Game over'
                    : busy
                        ? 'Moving…'
                        : 'Roll dice · ${nameOf(currentPlayer)}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _CountChip({
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: color.withValues(alpha: selected ? 0.22 : 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: selected ? 0.9 : 0.3),
              width: selected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiceFace extends StatelessWidget {
  final int? value;
  final bool spinning;
  final Animation<double> animation;

  const _DiceFace({
    required this.value,
    required this.spinning,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final tilt = spinning ? sin(animation.value * pi * 4) * 0.18 : 0.0;
        return Transform.rotate(angle: tilt, child: child);
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withValues(alpha: 0.12),
              blurRadius: 10,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          value == null ? '?' : '$value',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
