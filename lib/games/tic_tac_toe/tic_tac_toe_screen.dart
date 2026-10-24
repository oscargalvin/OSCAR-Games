import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_scaffold.dart';
import '../../services/sound_service.dart';
import '../../services/save_service.dart';
import '../../widgets/full_screen_game.dart';

class TicTacToeScreen extends StatefulWidget {
  const TicTacToeScreen({super.key});

  @override
  State<TicTacToeScreen> createState() => _TicTacToeScreenState();
}

class _TicTacToeScreenState extends State<TicTacToeScreen>
    with TickerProviderStateMixin, FullScreenGame {
  List<String> board = List.filled(9, '');
  bool isXTurn = true;
  String? winner;
  List<int> winningLine = [];
  late int scoreX;
  late int scoreO;
  late int draws;
  bool vsAI = true;

  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    scoreX = SaveService.instance.tttWinsX;
    scoreO = SaveService.instance.tttWinsO;
    draws = SaveService.instance.tttDraws;
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _bounceAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  void _makeMove(int index) {
    if (board[index].isNotEmpty || winner != null) return;

    SoundService.instance.play(GameSound.place);

    setState(() {
      board[index] = isXTurn ? 'X' : 'O';
      isXTurn = !isXTurn;
    });

    _checkWinner();

    if (vsAI && !isXTurn && winner == null && board.contains('')) {
      Future.delayed(const Duration(milliseconds: 400), _aiMove);
    }
  }

  void _aiMove() {
    if (winner != null || !board.contains('')) return;

    int move = _findBestMove();
    SoundService.instance.play(GameSound.place);
    setState(() {
      board[move] = 'O';
      isXTurn = true;
    });
    _checkWinner();
  }

  int _findBestMove() {
    // Try to win
    for (int i = 0; i < 9; i++) {
      if (board[i].isEmpty) {
        board[i] = 'O';
        if (_checkWinFor('O')) {
          board[i] = '';
          return i;
        }
        board[i] = '';
      }
    }
    // Block player
    for (int i = 0; i < 9; i++) {
      if (board[i].isEmpty) {
        board[i] = 'X';
        if (_checkWinFor('X')) {
          board[i] = '';
          return i;
        }
        board[i] = '';
      }
    }
    // Take center
    if (board[4].isEmpty) return 4;
    // Take corner
    final corners = [0, 2, 6, 8]..shuffle();
    for (var c in corners) {
      if (board[c].isEmpty) return c;
    }
    // Take any
    final available = <int>[];
    for (int i = 0; i < 9; i++) {
      if (board[i].isEmpty) available.add(i);
    }
    return available[Random().nextInt(available.length)];
  }

  bool _checkWinFor(String player) {
    const lines = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8],
      [0, 3, 6], [1, 4, 7], [2, 5, 8],
      [0, 4, 8], [2, 4, 6],
    ];
    for (var line in lines) {
      if (board[line[0]] == player &&
          board[line[1]] == player &&
          board[line[2]] == player) {
        return true;
      }
    }
    return false;
  }

  void _checkWinner() {
    const lines = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8],
      [0, 3, 6], [1, 4, 7], [2, 5, 8],
      [0, 4, 8], [2, 4, 6],
    ];

    for (var line in lines) {
      if (board[line[0]].isNotEmpty &&
          board[line[0]] == board[line[1]] &&
          board[line[1]] == board[line[2]]) {
        SoundService.instance.play(GameSound.win);
        setState(() {
          winner = board[line[0]];
          winningLine = line;
          if (winner == 'X') {
            scoreX++;
          } else {
            scoreO++;
          }
        });
        SaveService.instance.saveTicTacToeStats(
          winsX: scoreX, winsO: scoreO, draws: draws,
        );
        _bounceController.forward(from: 0);
        return;
      }
    }

    if (!board.contains('')) {
      SoundService.instance.play(GameSound.draw);
      setState(() {
        winner = 'Draw';
        draws++;
      });
      SaveService.instance.saveTicTacToeStats(
        winsX: scoreX, winsO: scoreO, draws: draws,
      );
      _bounceController.forward(from: 0);
    }
  }

  void _resetGame() {
    setState(() {
      board = List.filled(9, '');
      isXTurn = true;
      winner = null;
      winningLine = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Tic Tac Toe',
      actions: [
        IconButton(
          icon: Icon(vsAI ? Icons.smart_toy : Icons.people),
          onPressed: () {
            setState(() {
              vsAI = !vsAI;
              _resetGame();
            });
          },
          tooltip: vsAI ? 'vs AI' : 'vs Player',
        ),
      ],
      body: Column(
        children: [
          const SizedBox(height: 16),
          _buildScoreBoard(),
          const SizedBox(height: 8),
          _buildTurnIndicator(),
          const SizedBox(height: 24),
          Expanded(child: _buildBoard()),
          if (winner != null) _buildWinnerBanner(),
          const SizedBox(height: 16),
          _buildResetButton(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildScoreBoard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildScoreItem('X', scoreX, AppTheme.accent),
          _buildScoreItem('Draw', draws, AppTheme.textSecondary),
          _buildScoreItem(vsAI ? 'AI' : 'O', scoreO, AppTheme.pink),
        ],
      ),
    );
  }

  Widget _buildScoreItem(String label, int score, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$score',
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnIndicator() {
    if (winner != null) return const SizedBox.shrink();
    final turn = isXTurn ? 'X' : (vsAI ? 'AI' : 'O');
    final color = isXTurn ? AppTheme.accent : AppTheme.pink;
    return Text(
      "$turn's Turn",
      style: TextStyle(
        color: color,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildBoard() {
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppTheme.accent.withValues(alpha: 0.2),
            ),
          ),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: 9,
            itemBuilder: (context, index) => _buildCell(index),
          ),
        ),
      ),
    );
  }

  Widget _buildCell(int index) {
    final value = board[index];
    final isWinning = winningLine.contains(index);
    final color = value == 'X' ? AppTheme.accent : AppTheme.pink;

    return GestureDetector(
      onTap: () => _makeMove(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: isWinning
              ? color.withValues(alpha: 0.3)
              : AppTheme.cardColor.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isWinning
                ? color
                : value.isNotEmpty
                    ? color.withValues(alpha: 0.3)
                    : Colors.transparent,
            width: isWinning ? 2 : 1,
          ),
          boxShadow: isWinning
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: value.isNotEmpty
                ? Text(
                    value,
                    key: ValueKey('$index-$value'),
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _buildWinnerBanner() {
    final isDraw = winner == 'Draw';
    final color = isDraw
        ? AppTheme.warning
        : (winner == 'X' ? AppTheme.accent : AppTheme.pink);
    final text = isDraw ? "It's a Draw!" : '$winner Wins!';

    return ScaleTransition(
      scale: _bounceAnimation,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.3),
              color.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResetButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _resetGame,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(winner != null ? 'Play Again' : 'Reset'),
        ),
      ),
    );
  }
}
