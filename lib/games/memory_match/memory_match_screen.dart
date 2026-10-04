import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_scaffold.dart';
import '../../services/sound_service.dart';
import '../../services/save_service.dart';

class MemoryMatchScreen extends StatefulWidget {
  const MemoryMatchScreen({super.key});

  @override
  State<MemoryMatchScreen> createState() => _MemoryMatchScreenState();
}

class _MemoryMatchScreenState extends State<MemoryMatchScreen> {
  static const List<String> _allEmojis = [
    '🎮', '🚀', '⭐', '🎯', '🔥', '💎', '🎪', '🌈',
    '🦄', '🎸', '🏆', '🎲', '🧩', '🎭', '🌙', '⚡',
  ];

  List<String> cards = [];
  List<bool> flipped = [];
  List<bool> matched = [];
  int? firstFlipped;
  int? secondFlipped;
  bool isChecking = false;
  int moves = 0;
  int matchesFound = 0;
  int gridSize = 4;
  int totalPairs = 8;
  Stopwatch stopwatch = Stopwatch();
  Timer? _timer;
  String elapsedTime = '00:00';

  @override
  void initState() {
    super.initState();
    _initGame();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _initGame() {
    totalPairs = (gridSize * gridSize) ~/ 2;
    final emojis = List<String>.from(_allEmojis.sublist(0, totalPairs));
    cards = [...emojis, ...emojis]..shuffle(Random());
    flipped = List.filled(cards.length, false);
    matched = List.filled(cards.length, false);
    firstFlipped = null;
    secondFlipped = null;
    isChecking = false;
    moves = 0;
    matchesFound = 0;
    stopwatch.reset();
    stopwatch.start();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          final seconds = stopwatch.elapsed.inSeconds;
          elapsedTime =
              '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
        });
      }
    });
  }

  void _onCardTap(int index) {
    if (isChecking || flipped[index] || matched[index]) return;

    SoundService.instance.play(GameSound.cardFlip);

    setState(() {
      flipped[index] = true;

      if (firstFlipped == null) {
        firstFlipped = index;
      } else {
        secondFlipped = index;
        moves++;
        isChecking = true;

        if (cards[firstFlipped!] == cards[secondFlipped!]) {
          SoundService.instance.play(GameSound.match);
          matched[firstFlipped!] = true;
          matched[secondFlipped!] = true;
          matchesFound++;
          firstFlipped = null;
          secondFlipped = null;
          isChecking = false;

          if (matchesFound == totalPairs) {
            stopwatch.stop();
            _timer?.cancel();
            SoundService.instance.play(GameSound.levelComplete);
            SaveService.instance.saveMemoryBestMoves(gridSize, moves);
            SaveService.instance.saveMemoryBestTime(
              gridSize, stopwatch.elapsed.inSeconds,
            );
            _showWinDialog();
          }
        } else {
          final a = firstFlipped!, b = secondFlipped!;
          Future.delayed(const Duration(milliseconds: 800), () {
            // Skip if the game was restarted while the cards were showing.
            if (mounted && firstFlipped == a && secondFlipped == b) {
              SoundService.instance.play(GameSound.noMatch);
              setState(() {
                flipped[a] = false;
                flipped[b] = false;
                firstFlipped = null;
                secondFlipped = null;
                isChecking = false;
              });
            }
          });
        }
      }
    });
  }

  void _showWinDialog() {
    final stars = moves <= totalPairs + 2
        ? 3
        : moves <= totalPairs * 2
            ? 2
            : 1;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '🎉',
                style: TextStyle(fontSize: 48),
              ),
              const SizedBox(height: 16),
              const Text(
                'You Won!',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  3,
                  (i) => Icon(
                    i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: AppTheme.warning,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Moves: $moves  |  Time: $elapsedTime',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      setState(_initGame);
                    },
                    child: const Text('Play Again'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Memory Match',
      actions: [
        PopupMenuButton<int>(
          icon: const Icon(Icons.grid_view_rounded),
          onSelected: (size) {
            setState(() {
              gridSize = size;
              _initGame();
            });
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 4, child: Text('4x4 (Easy)')),
            const PopupMenuItem(value: 6, child: Text('6x6 (Hard)')),
          ],
        ),
      ],
      body: Column(
        children: [
          const SizedBox(height: 16),
          _buildStats(),
          const SizedBox(height: 24),
          Expanded(child: _buildGrid()),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => setState(_initGame),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('New Game'),
              ),
            ),
          ),
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
          _buildStat('Moves', '$moves', AppTheme.accent),
          _buildStat('Pairs', '$matchesFound/$totalPairs', AppTheme.success),
          _buildStat('Time', elapsedTime, AppTheme.purple),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridSize,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: cards.length,
        itemBuilder: (context, index) => _buildCard(index),
      ),
    );
  }

  Widget _buildCard(int index) {
    final isFlipped = flipped[index] || matched[index];
    final isMatched = matched[index];

    return GestureDetector(
      onTap: () => _onCardTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isMatched
              ? AppTheme.success.withValues(alpha: 0.2)
              : isFlipped
                  ? AppTheme.accent.withValues(alpha: 0.15)
                  : AppTheme.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMatched
                ? AppTheme.success.withValues(alpha: 0.5)
                : isFlipped
                    ? AppTheme.accent.withValues(alpha: 0.5)
                    : AppTheme.surface,
            width: 1.5,
          ),
          boxShadow: isFlipped
              ? [
                  BoxShadow(
                    color: (isMatched ? AppTheme.success : AppTheme.accent)
                        .withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: isFlipped
                ? Text(
                    cards[index],
                    key: ValueKey('emoji-$index'),
                    style: TextStyle(
                      fontSize: gridSize == 4 ? 32 : 22,
                    ),
                  )
                : Icon(
                    Icons.question_mark_rounded,
                    key: const ValueKey('question'),
                    color: AppTheme.textSecondary.withValues(alpha: 0.4),
                    size: gridSize == 4 ? 28 : 20,
                  ),
          ),
        ),
      ),
    );
  }
}
