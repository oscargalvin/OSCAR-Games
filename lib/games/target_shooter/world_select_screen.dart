import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_scaffold.dart';
import 'models/game_world.dart';
import 'models/player_data.dart';
import 'models/bow.dart';
import 'target_game_screen.dart';
import 'shop_screen.dart';
import 'painters/bow_painter.dart';

class WorldSelectScreen extends StatefulWidget {
  const WorldSelectScreen({super.key});

  @override
  State<WorldSelectScreen> createState() => _WorldSelectScreenState();
}

class _WorldSelectScreenState extends State<WorldSelectScreen>
    with SingleTickerProviderStateMixin {
  final PlayerData playerData = PlayerData.fromSave();
  late AnimationController _floatController;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  void _openWorld(GameWorld world) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TargetGameScreen(
          world: world,
          playerData: playerData,
          onComplete: () => setState(() {}),
        ),
      ),
    );
  }

  void _openShop() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShopScreen(
          playerData: playerData,
          onUpdate: () => setState(() {}),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Target Shooter',
      actions: [
        _buildDiamondBadge(),
        IconButton(
          icon: const Icon(Icons.store_rounded),
          onPressed: _openShop,
        ),
      ],
      body: Column(
        children: [
          const SizedBox(height: 16),
          _buildEquippedBow(),
          const SizedBox(height: 16),
          _buildStatsRow(),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'CHOOSE YOUR WORLD',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildWorldList()),
        ],
      ),
    );
  }

  Widget _buildDiamondBadge() {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.diamond_rounded, color: AppTheme.accent, size: 16),
          const SizedBox(width: 4),
          Text(
            '${playerData.diamonds}',
            style: const TextStyle(
              color: AppTheme.accent,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEquippedBow() {
    final bow = playerData.equippedBow;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Bow.rarityColor(bow.rarity).withValues(alpha: 0.15),
            Bow.rarityColor(bow.rarity).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Bow.rarityColor(bow.rarity).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          BowPreviewWidget(bow: bow, size: 60),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EQUIPPED',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  bow.name,
                  style: TextStyle(
                    color: Bow.rarityColor(bow.rarity),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  Bow.rarityLabel(bow.rarity),
                  style: TextStyle(
                    color: Bow.rarityColor(bow.rarity).withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded, color: AppTheme.accent),
            onPressed: _openShop,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _buildMiniStat(
            Icons.track_changes_rounded,
            '${playerData.totalTargetsHit}',
            'Targets',
            AppTheme.accent,
          ),
          const SizedBox(width: 10),
          _buildMiniStat(
            Icons.flag_rounded,
            '${playerData.totalLevelsCompleted}',
            'Levels',
            AppTheme.success,
          ),
          const SizedBox(width: 10),
          _buildMiniStat(
            Icons.inventory_2_rounded,
            '${playerData.ownedBowIds.length}',
            'Bows',
            AppTheme.purple,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorldList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: GameWorld.worlds.length,
      itemBuilder: (context, index) {
        final world = GameWorld.worlds[index];
        return _buildWorldCard(world);
      },
    );
  }

  Widget _buildWorldCard(GameWorld world) {
    final currentLevel = playerData.currentLevel(world.id);
    final progress = currentLevel / PlayerData.maxLevel;

    return GestureDetector(
      onTap: () => _openWorld(world),
      child: AnimatedBuilder(
        animation: _floatController,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _floatController.value * 4 - 2),
            child: child,
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                world.primaryColor.withValues(alpha: 0.3),
                world.secondaryColor.withValues(alpha: 0.15),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: world.primaryColor.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: world.primaryColor.withValues(alpha: 0.1),
                blurRadius: 16,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: world.primaryColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(world.icon, color: world.primaryColor, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              world.name,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (world.isNight) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A237E)
                                      .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '🌙 NIGHT',
                                  style: TextStyle(fontSize: 9),
                                ),
                              ),
                            ],
                            if (world.diamondMultiplier > 1) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.warning
                                      .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '💎 x${world.diamondMultiplier}',
                                  style: const TextStyle(fontSize: 9),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          world.description,
                          style: TextStyle(
                            color:
                                AppTheme.textSecondary.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: world.primaryColor.withValues(alpha: 0.6),
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Level $currentLevel/${PlayerData.maxLevel}',
                    style: TextStyle(
                      color: world.primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(
                      color: world.primaryColor.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: world.primaryColor.withValues(alpha: 0.1),
                  valueColor:
                      AlwaysStoppedAnimation(world.primaryColor),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
