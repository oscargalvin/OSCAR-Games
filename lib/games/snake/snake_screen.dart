import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_scaffold.dart';
import '../../services/sound_service.dart';
import '../../services/save_service.dart';

enum Direction { up, down, left, right }

class SnakeScreen extends StatefulWidget {
  const SnakeScreen({super.key});

  @override
  State<SnakeScreen> createState() => _SnakeScreenState();
}

class _SnakeScreenState extends State<SnakeScreen> {
  static const int gridSize = 20;
  static const Duration gameSpeed = Duration(milliseconds: 150);

  List<Point<int>> snake = [];
  Point<int> food = const Point(10, 10);
  Direction direction = Direction.right;
  Direction nextDirection = Direction.right;
  bool isPlaying = false;
  bool isGameOver = false;
  int score = 0;
  late int highScore;
  Timer? _gameTimer;

  @override
  void initState() {
    super.initState();
    highScore = SaveService.instance.snakeHighScore;
    _initGame();
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    super.dispose();
  }

  void _initGame() {
    snake = [const Point(5, 10), const Point(4, 10), const Point(3, 10)];
    direction = Direction.right;
    nextDirection = Direction.right;
    score = 0;
    isGameOver = false;
    _spawnFood();
  }

  void _spawnFood() {
    final random = Random();
    Point<int> newFood;
    do {
      newFood = Point(random.nextInt(gridSize), random.nextInt(gridSize));
    } while (snake.contains(newFood));
    food = newFood;
  }

  void _startGame() {
    if (isGameOver) _initGame();
    setState(() => isPlaying = true);
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(gameSpeed, (_) => _update());
  }

  void _pauseGame() {
    setState(() => isPlaying = false);
    _gameTimer?.cancel();
  }

  void _update() {
    if (!isPlaying) return;

    setState(() {
      direction = nextDirection;

      final head = snake.first;
      Point<int> newHead;

      switch (direction) {
        case Direction.up:
          newHead = Point(head.x, (head.y - 1 + gridSize) % gridSize);
        case Direction.down:
          newHead = Point(head.x, (head.y + 1) % gridSize);
        case Direction.left:
          newHead = Point((head.x - 1 + gridSize) % gridSize, head.y);
        case Direction.right:
          newHead = Point((head.x + 1) % gridSize, head.y);
      }

      if (snake.contains(newHead)) {
        isPlaying = false;
        isGameOver = true;
        _gameTimer?.cancel();
        if (score > highScore) {
          highScore = score;
          SaveService.instance.saveSnakeHighScore(score);
        }
        SoundService.instance.play(GameSound.gameOver);
        HapticFeedback.heavyImpact();
        return;
      }

      snake.insert(0, newHead);

      if (newHead == food) {
        score += 10;
        SoundService.instance.play(GameSound.eat);
        HapticFeedback.lightImpact();
        _spawnFood();
      } else {
        snake.removeLast();
      }
    });
  }

  void _changeDirection(Direction newDir) {
    if ((direction == Direction.up && newDir == Direction.down) ||
        (direction == Direction.down && newDir == Direction.up) ||
        (direction == Direction.left && newDir == Direction.right) ||
        (direction == Direction.right && newDir == Direction.left)) {
      return;
    }
    nextDirection = newDir;
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Snake',
      body: LayoutBuilder(
        builder: (context, c) {
          // Phone turned sideways: put the arrow pad beside the board.
          if (c.maxWidth > c.maxHeight) {
            return Column(
              children: [
                const SizedBox(height: 8),
                _buildStats(),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _buildGameArea()),
                      FittedBox(child: _buildControls()),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            );
          }
          return Column(
            children: [
              const SizedBox(height: 16),
              _buildStats(),
              const SizedBox(height: 16),
              Expanded(child: _buildGameArea()),
              const SizedBox(height: 12),
              _buildControls(),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem('Score', '$score', AppTheme.accent),
          _buildStatItem('Best', '$highScore', AppTheme.warning),
          _buildStatItem('Length', '${snake.length}', AppTheme.purple),
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
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameArea() {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (details.delta.dy < -5) _changeDirection(Direction.up);
        if (details.delta.dy > 5) _changeDirection(Direction.down);
      },
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx < -5) _changeDirection(Direction.left);
        if (details.delta.dx > 5) _changeDirection(Direction.right);
      },
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [_buildGrid(), if (!isPlaying) _buildOverlay()],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellSize = constraints.maxWidth / gridSize;
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _SnakePainter(
            snake: snake,
            food: food,
            cellSize: cellSize,
            gridSize: gridSize,
          ),
        );
      },
    );
  }

  Widget _buildOverlay() {
    return Container(
      color: AppTheme.primaryDark.withValues(alpha: 0.8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isGameOver) ...[
              const Text(
                'Game Over',
                style: TextStyle(
                  color: AppTheme.danger,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Score: $score',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 20),
            ],
            ElevatedButton.icon(
              onPressed: _startGame,
              icon: Icon(isGameOver ? Icons.refresh : Icons.play_arrow_rounded),
              label: Text(isGameOver ? 'Try Again' : 'Start'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          _buildControlButton(Icons.keyboard_arrow_up_rounded, Direction.up),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControlButton(
                Icons.keyboard_arrow_left_rounded,
                Direction.left,
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: isPlaying ? _pauseGame : _startGame,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: AppTheme.accent,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildControlButton(
                Icons.keyboard_arrow_right_rounded,
                Direction.right,
              ),
            ],
          ),
          _buildControlButton(
            Icons.keyboard_arrow_down_rounded,
            Direction.down,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(IconData icon, Direction dir) {
    return GestureDetector(
      onTap: () => _changeDirection(dir),
      child: Container(
        width: 56,
        height: 56,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.cardColor.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.textSecondary.withValues(alpha: 0.2),
          ),
        ),
        child: Icon(icon, color: AppTheme.textSecondary, size: 28),
      ),
    );
  }
}

class _SnakePainter extends CustomPainter {
  final List<Point<int>> snake;
  final Point<int> food;
  final double cellSize;
  final int gridSize;

  _SnakePainter({
    required this.snake,
    required this.food,
    required this.cellSize,
    required this.gridSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid dots
    final dotPaint = Paint()
      ..color = AppTheme.textSecondary.withValues(alpha: 0.05);
    for (int x = 0; x < gridSize; x++) {
      for (int y = 0; y < gridSize; y++) {
        canvas.drawCircle(
          Offset(x * cellSize + cellSize / 2, y * cellSize + cellSize / 2),
          1.5,
          dotPaint,
        );
      }
    }

    // Draw food with glow
    final foodCenter = Offset(
      food.x * cellSize + cellSize / 2,
      food.y * cellSize + cellSize / 2,
    );
    final glowPaint = Paint()
      ..color = AppTheme.danger.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(foodCenter, cellSize / 2.5, glowPaint);

    final foodPaint = Paint()..color = AppTheme.danger;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: foodCenter,
          width: cellSize * 0.7,
          height: cellSize * 0.7,
        ),
        Radius.circular(cellSize * 0.2),
      ),
      foodPaint,
    );

    // Draw snake
    for (int i = 0; i < snake.length; i++) {
      final segment = snake[i];
      final isHead = i == 0;
      final t = i / snake.length;
      final color = Color.lerp(AppTheme.accent, AppTheme.accentDark, t)!;

      final rect = Rect.fromLTWH(
        segment.x * cellSize + 1,
        segment.y * cellSize + 1,
        cellSize - 2,
        cellSize - 2,
      );

      final paint = Paint()..color = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(isHead ? 6 : 4)),
        paint,
      );

      if (isHead) {
        final headGlow = Paint()
          ..color = AppTheme.accent.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          headGlow,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SnakePainter oldDelegate) => true;
}
