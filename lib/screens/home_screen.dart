import 'package:flutter/material.dart';
import '../models/game_info.dart';
import '../services/save_service.dart';
import '../theme/app_theme.dart';
import '../widgets/game_card.dart';
import '../games/tic_tac_toe/tic_tac_toe_screen.dart';
import '../games/memory_match/memory_match_screen.dart';
import '../games/snake/snake_screen.dart';
import '../games/reaction/reaction_screen.dart';
import '../games/target_shooter/world_select_screen.dart';
import '../games/boat_fishing/boat_fishing_screen.dart';
// Archived: World Cup is hidden from the home screen but its code is kept in
// lib/games/world_cup/. To bring it back, un-comment this import and the
// World Cup entry in the games list below.
// import '../games/world_cup/world_cup_screen.dart';
import '../games/board_game/board_game_screen.dart';
import '../games/fly_or_crash/fly_or_crash_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  late final List<GameInfo> games = [
    GameInfo(
      id: 'fly_or_crash',
      title: 'Fly or Crash',
      subtitle: 'Fly anywhere in the world',
      description:
          'Pick a city, fly there from London, dodge storms and other planes, '
          'handle emergencies and land safely. Keep your passengers okay!',
      icon: Icons.flight_rounded,
      color: AppTheme.blue,
      secondaryColor: AppTheme.accent,
      screenBuilder: () => const FlyOrCrashScreen(),
      difficulty: 'Medium',
    ),
    GameInfo(
      id: 'board_game',
      title: 'Lucky Board Game',
      subtitle: 'Dice race to the middle',
      description:
          'Pick 1–5 players, enter names, then race around nested squares. '
          'First into the middle wins!',
      icon: Icons.casino_rounded,
      color: AppTheme.accent,
      secondaryColor: AppTheme.warning,
      screenBuilder: () => const BoardGameScreen(),
      minPlayers: 1,
      maxPlayers: 5,
      difficulty: 'Easy',
    ),
    // ARCHIVED (World Cup) — un-comment to show it again.
    // GameInfo(
    //   id: 'world_cup',
    //   title: 'World Cup',
    //   subtitle: '2026 World Cup · 48 nations',
    //   description:
    //       'The 48 nations that qualified for the 2026 FIFA World Cup — '
    //       'Groups A–L, group stage through the Final. Play or quick-play matches.',
    //   icon: Icons.sports_soccer_rounded,
    //   color: AppTheme.success,
    //   secondaryColor: AppTheme.warning,
    //   screenBuilder: () => const WorldCupScreen(),
    //   difficulty: 'Medium',
    // ),
    GameInfo(
      id: 'boat_fishing',
      title: 'Lucky Fish',
      subtitle: 'Cast, sell, upgrade',
      description:
          'In Lucky Fish, cast from your boat, sell catches for fish coins, and buy rods and hulls — rarer bites await!',
      icon: Icons.phishing_rounded,
      color: AppTheme.blue,
      secondaryColor: AppTheme.accent,
      screenBuilder: () => const BoatFishingScreen(),
      difficulty: 'Relax',
    ),
    GameInfo(
      id: 'tic_tac_toe',
      title: 'Tic Tac Toe',
      subtitle: 'Classic strategy game',
      description: 'Challenge the AI or a friend in this timeless classic!',
      icon: Icons.grid_3x3_rounded,
      color: AppTheme.accent,
      secondaryColor: AppTheme.accentDark,
      screenBuilder: () => const TicTacToeScreen(),
      minPlayers: 1,
      maxPlayers: 2,
      difficulty: 'Easy',
    ),
    GameInfo(
      id: 'memory_match',
      title: 'Memory Match',
      subtitle: 'Test your memory',
      description: 'Flip cards and find all matching pairs!',
      icon: Icons.psychology_rounded,
      color: AppTheme.purple,
      secondaryColor: AppTheme.pink,
      screenBuilder: () => const MemoryMatchScreen(),
      difficulty: 'Medium',
    ),
    GameInfo(
      id: 'snake',
      title: 'Snake',
      subtitle: 'Classic arcade action',
      description: 'Guide the snake to eat food and grow longer!',
      icon: Icons.linear_scale_rounded,
      color: AppTheme.success,
      secondaryColor: AppTheme.accent,
      screenBuilder: () => const SnakeScreen(),
      difficulty: 'Medium',
    ),
    GameInfo(
      id: 'reaction',
      title: 'Reaction Speed',
      subtitle: 'How fast are you?',
      description: 'Test your reflexes with this speed challenge!',
      icon: Icons.flash_on_rounded,
      color: AppTheme.warning,
      secondaryColor: AppTheme.danger,
      screenBuilder: () => const ReactionScreen(),
      difficulty: 'Easy',
    ),
    GameInfo(
      id: 'target_shooter',
      title: 'Target Shooter',
      subtitle: '3 Worlds • 20 Levels',
      description: 'Shoot targets across The Playground, Jupiter & The Backrooms!',
      icon: Icons.track_changes_rounded,
      color: AppTheme.danger,
      secondaryColor: AppTheme.warning,
      screenBuilder: () => const WorldSelectScreen(),
      difficulty: 'Hard',
    ),
  ];

  // Hand-picked tile colours so neighbouring games never clash.
  static const Map<String, Color> _tileColors = {
    'fly_or_crash': Color(0xFFFFFFFF), // boarding-pass white
    'board_game': Color(0xFFFFC93C), // sunflower
    'world_cup': Color(0xFF3DDC84), // pitch green
    'boat_fishing': Color(0xFF6FD3F7), // sea
    'tic_tac_toe': Color(0xFFFF8FC7), // bubblegum
    'memory_match': Color(0xFFB79BFF), // lilac
    'snake': Color(0xFFC6EF4F), // lime
    'reaction': Color(0xFFFF9F43), // tangerine
    'target_shooter': Color(0xFFFF6B5B), // tomato
  };

  static const Color _background = Color(0xFF2A3FD4); // cobalt

  int? _getHighScore(String gameId) {
    final save = SaveService.instance;
    switch (gameId) {
      case 'snake':
        final s = save.snakeHighScore;
        return s > 0 ? s : null;
      case 'tic_tac_toe':
        final total = save.tttWinsX + save.tttWinsO + save.tttDraws;
        return total > 0 ? save.tttWinsX : null;
      case 'memory_match':
        return save.memoryBestMoves(4);
      case 'reaction':
        return save.reactionBest;
      case 'target_shooter':
        final s = save.totalLevelsCompleted;
        return s > 0 ? s : null;
      case 'boat_fishing':
        final c = save.fishCoins;
        return c > 0 ? c : null;
      case 'fly_or_crash':
        final l = save.getHighScore('fly_or_crash');
        return l > 0 ? l : null;
      case 'world_cup':
        final w = save.worldCupWins;
        return w > 0 ? w : null;
      default:
        return null;
    }
  }

  void _openGame(GameInfo game) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            game.screenBuilder(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
      ),
    ).then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.8,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildGameCard(index),
                  childCount: games.length,
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildComingSoon()),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 18),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Oscar Galvin's",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Game Center',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 46,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.6,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Tap a game to play.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Transform.rotate(
              angle: 0.12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC93C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kInk, width: 2.5),
                  boxShadow: const [
                    BoxShadow(color: kInk, offset: Offset(0, 4)),
                  ],
                ),
                child: Text(
                  '${games.length} games',
                  style: const TextStyle(
                    color: kInk,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameCard(int index) {
    final game = games[index];
    return GameCard(
      game: game,
      tileColor: _tileColors[game.id],
      highScore: _getHighScore(game.id),
      onTap: () => _openGame(game),
    );
  }

  Widget _buildComingSoon() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.construction_rounded,
              color: Colors.white.withValues(alpha: 0.8),
              size: 28,
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'More games on the way',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Puzzles, quizzes and racing are next.',
                    style: TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
