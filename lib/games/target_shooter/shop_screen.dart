import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_scaffold.dart';
import 'models/bow.dart';
import 'models/player_data.dart';
import 'painters/bow_painter.dart';

class ShopScreen extends StatefulWidget {
  final PlayerData playerData;
  final VoidCallback onUpdate;

  const ShopScreen({
    super.key,
    required this.playerData,
    required this.onUpdate,
  });

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedMoodIndex = 0;
  int _buyDiamondTapCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  PlayerData get player => widget.playerData;

  void _showMessage(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color ?? AppTheme.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _buyBow(Bow bow) {
    if (player.ownsBow(bow.id)) {
      player.equipBow(bow.id);
      setState(() {});
      widget.onUpdate();
      _showMessage('Equipped ${bow.name}!');
      return;
    }

    if (player.spendDiamonds(bow.diamondPrice)) {
      player.unlockBow(bow.id);
      player.equipBow(bow.id);
      setState(() {});
      widget.onUpdate();
      _showMessage('Unlocked ${bow.name}!', color: AppTheme.success);
    } else {
      _showMessage(
        'Need ${bow.diamondPrice - player.diamonds} more diamonds!',
        color: AppTheme.danger,
      );
    }
  }

  void _buyArrow(ArrowSkin arrow) {
    if (player.ownsArrow(arrow.id)) {
      player.equipArrow(arrow.id);
      setState(() {});
      widget.onUpdate();
      _showMessage('Equipped ${arrow.name}!');
      return;
    }

    if (player.spendDiamonds(arrow.diamondPrice)) {
      player.unlockArrow(arrow.id);
      player.equipArrow(arrow.id);
      setState(() {});
      widget.onUpdate();
      _showMessage('Unlocked ${arrow.name}!', color: AppTheme.success);
    } else {
      _showMessage(
        'Need ${arrow.diamondPrice - player.diamonds} more diamonds!',
        color: AppTheme.danger,
      );
    }
  }

  void _openStandardCrate() {
    if (!player.spendDiamonds(50)) {
      _showMessage('Need 50 diamonds for a crate!', color: AppTheme.danger);
      return;
    }

    final bow = _rollStandardCrate();
    player.unlockBow(bow.id);
    setState(() {});
    widget.onUpdate();
    _showCrateResult(bow);
  }

  Bow _rollStandardCrate() {
    final roll = Random().nextInt(100);
    if (roll < 50) {
      return Bow.allBows.firstWhere((b) => b.id == 'pink');
    } else if (roll < 72) {
      final opts = ['yellow_orange', 'red_orange', 'blue_purple'];
      return Bow.allBows.firstWhere((b) => b.id == opts[Random().nextInt(opts.length)]);
    } else if (roll < 85) {
      final opts = ['orange_purple', 'yellow_green', 'red_pink'];
      return Bow.allBows.firstWhere((b) => b.id == opts[Random().nextInt(opts.length)]);
    } else if (roll < 95) {
      final opts = ['gold', 'neon_green'];
      return Bow.allBows.firstWhere((b) => b.id == opts[Random().nextInt(opts.length)]);
    } else {
      return Bow.allBows.firstWhere((b) => b.id == 'rainbow');
    }
  }

  void _openMysteryCrate() {
    if (!player.spendDiamonds(100)) {
      _showMessage('Need 100 diamonds!', color: AppTheme.danger);
      return;
    }

    final roll = Random().nextInt(100);
    if (roll < 25) {
      // Dark Shadow Bow
      final bow = Bow.allBows.firstWhere((b) => b.id == 'dark_shadow');
      player.unlockBow(bow.id);
      setState(() {});
      widget.onUpdate();
      _showCrateResult(bow);
    } else if (roll < 50) {
      // Rainbow Bow
      final bow = Bow.allBows.firstWhere((b) => b.id == 'rainbow');
      player.unlockBow(bow.id);
      setState(() {});
      widget.onUpdate();
      _showCrateResult(bow);
    } else if (roll < 75) {
      // Blue Bow
      final bow = Bow.allBows.firstWhere((b) => b.id == 'blue_purple');
      player.unlockBow(bow.id);
      setState(() {});
      widget.onUpdate();
      _showCrateResult(bow);
    } else if (roll < 99) {
      // 67 Keychain
      player.has67Keychain = true;
      player.save();
      setState(() {});
      widget.onUpdate();
      _showKeychainResult('67 Keychain', '🔑 67', const Color(0xFFFF6B6B));
    } else {
      // Everything from the crate
      for (final bow in Bow.allBows) {
        player.unlockBow(bow.id);
      }
      player.has67Keychain = true;
      player.save();
      setState(() {});
      widget.onUpdate();
      _showJackpotResult();
    }
  }

  void _showCrateResult(Bow bow) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Bow.rarityColor(bow.rarity).withValues(alpha: 0.3),
                      Colors.transparent,
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: BowPreviewWidget(bow: bow, size: 100),
              ),
              const SizedBox(height: 16),
              Text(
                bow.name,
                style: TextStyle(
                  color: Bow.rarityColor(bow.rarity),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Bow.rarityColor(bow.rarity).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  Bow.rarityLabel(bow.rarity),
                  style: TextStyle(
                    color: Bow.rarityColor(bow.rarity),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              if (bow.hasPauseAbility) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF0040).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '⚡ Pause Ability: Freezes all targets for 5s on hit!',
                    style: TextStyle(
                      color: Color(0xFFFF0040),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (bow.hasMoodMode) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '✨ Includes Mood Mode!',
                    style: TextStyle(
                      color: AppTheme.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  player.equipBow(bow.id);
                  setState(() {});
                  widget.onUpdate();
                  Navigator.of(ctx).pop();
                  _showMessage('Equipped ${bow.name}!');
                },
                child: const Text('Equip Now!'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showKeychainResult(String name, String emoji, Color color) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text(
                name,
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Added to your collection!',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Nice!'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showJackpotResult() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.red, Colors.orange, Colors.yellow,
                    Colors.green, Colors.blue, Colors.purple],
                ).createShader(bounds),
                child: const Text(
                  'JACKPOT!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You got EVERYTHING!\nAll bows + 67 Keychain unlocked!',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Amazing!'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _buyVip() {
    _showPurchaseDialog(
      title: 'VIP Pass',
      price: '£3.50',
      description: 'Choose any 5 bows from the collection!',
      icon: Icons.workspace_premium_rounded,
      color: AppTheme.warning,
      onConfirm: () {
        player.hasVip = true;
        for (final bow in Bow.allBows) {
          player.unlockBow(bow.id);
        }
        setState(() {});
        widget.onUpdate();
        _showMessage('VIP Activated! All bows unlocked!', color: AppTheme.warning);
      },
    );
  }

  void _buyShieldKeychain() {
    _showPurchaseDialog(
      title: 'Shield Keychain',
      price: '£0.59',
      description: 'A special shield keychain accessory for your bow!',
      icon: Icons.shield_rounded,
      color: AppTheme.purple,
      onConfirm: () {
        player.hasShieldKeychain = true;
        player.save();
        setState(() {});
        widget.onUpdate();
        _showMessage('Shield Keychain acquired!', color: AppTheme.purple);
      },
    );
  }

  void _buy67Keychain() {
    if (player.has67Keychain) {
      _showMessage('You already have the 67 Keychain!');
      return;
    }
    _showMessage('67 Keychain only available from the Mystery Crate!',
        color: AppTheme.warning);
  }

  void _buyComboKeychain() {
    if (player.hasComboKeychain) {
      _showMessage('You already have the Combo Keychain!');
      return;
    }
    if (!player.hasShieldKeychain || !player.has67Keychain) {
      _showMessage('You need both Shield & 67 keychains first!',
          color: AppTheme.danger);
      return;
    }
    if (player.spendDiamonds(320)) {
      player.hasComboKeychain = true;
      player.save();
      setState(() {});
      widget.onUpdate();
      _showMessage('Combo Keychain unlocked!', color: AppTheme.success);
    } else {
      _showMessage('Need ${320 - player.diamonds} more diamonds!',
          color: AppTheme.danger);
    }
  }

  void _buyExclusiveCrate() {
    _showPurchaseDialog(
      title: 'Exclusive Crate',
      price: '£1.50',
      description:
          '1% chance for the Legendary Rainbow Bow with Mood Mode!\n\n'
          '50% Pink Bow\n'
          '22% Orange/Yellow/Blue Bow\n'
          '13% Multi-Color Bow\n'
          '5% Rare Quad-Color Bow\n'
          '1% 🌈 Rainbow Bow w/ Mood Mode',
      icon: Icons.inventory_2_rounded,
      color: AppTheme.accent,
      onConfirm: () {
        final bow = _rollStandardCrate();
        player.unlockBow(bow.id);
        setState(() {});
        widget.onUpdate();
        _showCrateResult(bow);
      },
    );
  }

  // --- Secret diamond hack ---
  void _onBuyDiamondsTap(int amount) {
    _buyDiamondTapCount++;
    if (_buyDiamondTapCount >= 7) {
      _buyDiamondTapCount = 0;
      _showPasswordDialog(amount);
    } else {
      _showPurchaseDialog(
        title: '$amount Diamonds',
        price: amount == 100
            ? '£0.59'
            : amount == 500
                ? '£1.29'
                : '£3.00',
        description: 'Purchase $amount diamonds to spend in the shop!',
        icon: Icons.diamond_rounded,
        color: AppTheme.accent,
        onConfirm: () {
          player.addDiamonds(amount);
          setState(() {});
          widget.onUpdate();
          _showMessage('+$amount Diamonds!', color: AppTheme.success);
        },
      );
    }
  }

  void _showPasswordDialog(int amount) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, color: AppTheme.accent, size: 40),
              const SizedBox(height: 16),
              const Text(
                'Enter Password',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Password...',
                  hintStyle: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: AppTheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (controller.text.toLowerCase() == 'oscar') {
                        Navigator.of(ctx).pop();
                        player.addDiamonds(amount);
                        setState(() {});
                        widget.onUpdate();
                        _showMessage('💎 +$amount Diamonds! Boss mode activated!',
                            color: AppTheme.success);
                      } else {
                        Navigator.of(ctx).pop();
                        _showMessage('Wrong password!', color: AppTheme.danger);
                      }
                    },
                    child: const Text('Submit'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPurchaseDialog({
    required String title,
    required String price,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  price,
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      onConfirm();
                    },
                    child: Text('Buy for $price'),
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
      title: 'Shop',
      actions: [_buildDiamondBadge()],
      body: Column(
        children: [
          const SizedBox(height: 8),
          TabBar(
            controller: _tabController,
            labelColor: AppTheme.accent,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.accent,
            indicatorSize: TabBarIndicatorSize.label,
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
            tabs: const [
              Tab(text: 'BOWS'),
              Tab(text: 'ARROWS'),
              Tab(text: 'CRATES'),
              Tab(text: 'PASSES'),
              Tab(text: 'ITEMS'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBowsTab(),
                _buildArrowsTab(),
                _buildCratesTab(),
                _buildPassesTab(),
                _buildItemsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiamondBadge() {
    return Container(
      margin: const EdgeInsets.only(right: 16),
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
            '${player.diamonds}',
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

  // === BOWS TAB ===
  Widget _buildBowsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildEquippedPreview(),
        const SizedBox(height: 20),
        if (player.ownsBow('rainbow') && player.equippedBowId == 'rainbow') ...[
          _buildMoodModeSection(),
          const SizedBox(height: 20),
        ],
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.7,
          ),
          itemCount: Bow.allBows.length,
          itemBuilder: (context, index) => _buildBowCard(Bow.allBows[index]),
        ),
      ],
    );
  }

  // === ARROWS TAB ===
  Widget _buildArrowsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Equipped arrow
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: player.equippedArrow.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: player.equippedArrow.color.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: player.equippedArrow.color.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_upward_rounded,
                    color: player.equippedArrow.color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EQUIPPED ARROW',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      player.equippedArrow.name,
                      style: TextStyle(
                        color: player.equippedArrow.color,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...ArrowSkin.allArrows.map((arrow) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildArrowCard(arrow),
        )),
      ],
    );
  }

  Widget _buildArrowCard(ArrowSkin arrow) {
    final owned = player.ownsArrow(arrow.id);
    final equipped = player.equippedArrowId == arrow.id;

    return GestureDetector(
      onTap: () => _buyArrow(arrow),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: owned
              ? arrow.color.withValues(alpha: 0.08)
              : AppTheme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: equipped
                ? arrow.color
                : arrow.color.withValues(alpha: 0.2),
            width: equipped ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: arrow.color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_upward_rounded,
                  color: arrow.color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    arrow.name,
                    style: TextStyle(
                      color: arrow.color,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (owned)
              Text(
                equipped ? '✓ Active' : 'Tap to Equip',
                style: TextStyle(
                  color: equipped ? AppTheme.success : AppTheme.textSecondary,
                  fontSize: 12,
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.diamond_rounded,
                        color: AppTheme.accent, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      '${arrow.diamondPrice}',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
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

  Widget _buildEquippedPreview() {
    final bow = player.equippedBow;
    return Container(
      padding: const EdgeInsets.all(20),
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
          BowPreviewWidget(
            bow: bow,
            size: 80,
            moodIndex: bow.hasMoodMode ? _selectedMoodIndex : null,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CURRENTLY EQUIPPED',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  bow.name,
                  style: TextStyle(
                    color: Bow.rarityColor(bow.rarity),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Bow.rarityColor(bow.rarity).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    Bow.rarityLabel(bow.rarity),
                    style: TextStyle(
                      color: Bow.rarityColor(bow.rarity),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (bow.hasPauseAbility) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '⚡ Pause Ability Active',
                    style: TextStyle(
                      color: Color(0xFFFF0040),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (bow.hasMoodMode) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '✨ Mood Mode Available',
                    style: TextStyle(
                      color: AppTheme.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodModeSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.palette_rounded, color: AppTheme.warning, size: 18),
              SizedBox(width: 8),
              Text(
                'MOOD MODE',
                style: TextStyle(
                  color: AppTheme.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMoodChip(-1, 'Rainbow', null),
              ...List.generate(
                MoodMode.presets.length,
                (i) => _buildMoodChip(
                  i,
                  MoodMode.presets[i].name,
                  MoodMode.presets[i].colors.first,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMoodChip(int index, String label, Color? color) {
    final isClean = label == 'Clean';
    final isSelected = (index == -1 && _selectedMoodIndex == -1) ||
        _selectedMoodIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() => _selectedMoodIndex = index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (color ?? AppTheme.warning).withValues(alpha: 0.2)
              : AppTheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? (color ?? AppTheme.warning)
                : AppTheme.textSecondary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isClean && color != null)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            if (index == -1)
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.red, Colors.orange, Colors.yellow,
                    Colors.green, Colors.blue, Colors.purple],
                ).createShader(bounds),
                child: const Icon(Icons.circle, size: 12, color: Colors.white),
              ),
            if (index == -1) const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? (color ?? AppTheme.warning)
                    : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBowCard(Bow bow) {
    final owned = player.ownsBow(bow.id);
    final equipped = player.equippedBowId == bow.id;
    final rarityColor = Bow.rarityColor(bow.rarity);

    return GestureDetector(
      onTap: () => _buyBow(bow),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: owned
              ? rarityColor.withValues(alpha: 0.08)
              : AppTheme.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: equipped
                ? rarityColor
                : rarityColor.withValues(alpha: 0.2),
            width: equipped ? 2 : 1,
          ),
          boxShadow: equipped
              ? [
                  BoxShadow(
                    color: rarityColor.withValues(alpha: 0.2),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            if (equipped)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'EQUIPPED',
                  style: TextStyle(
                    color: AppTheme.success,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            Expanded(
              child: BowPreviewWidget(bow: bow, size: 65),
            ),
            const SizedBox(height: 4),
            Text(
              bow.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: rarityColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: rarityColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                Bow.rarityLabel(bow.rarity),
                style: TextStyle(
                  color: rarityColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (bow.hasPauseAbility) ...[
              const SizedBox(height: 4),
              const Text(
                '⚡ Pause',
                style: TextStyle(
                  color: Color(0xFFFF0040),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 6),
            if (owned)
              Text(
                equipped ? '✓ Active' : 'Tap to Equip',
                style: TextStyle(
                  color: equipped ? AppTheme.success : AppTheme.textSecondary,
                  fontSize: 11,
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.diamond_rounded,
                        color: AppTheme.accent, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      '${bow.diamondPrice}',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
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

  // === CRATES TAB ===
  Widget _buildCratesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCrateCard(
          title: 'Standard Crate',
          subtitle: 'Open with diamonds',
          price: '50',
          currency: 'diamonds',
          icon: Icons.inventory_2_rounded,
          color: AppTheme.accent,
          drops: [
            'Common Bow (50%)',
            'Uncommon Bow (22%)',
            'Multi-Color Bow (13%)',
            'Rare Bow (5%)',
            'Legendary Rainbow (1%)',
          ],
          onBuy: _openStandardCrate,
        ),
        const SizedBox(height: 16),
        _buildCrateCard(
          title: 'Mystery Crate',
          subtitle: 'Rare drops inside!',
          price: '100',
          currency: 'diamonds',
          icon: Icons.help_outline_rounded,
          color: const Color(0xFFFF0040),
          drops: [
            '🖤 Dark Shadow Bow (25%)',
            '🌈 Rainbow Bow (25%)',
            '💙 Blue Bow (25%)',
            '🔑 67 Keychain (24%)',
            '🎉 EVERYTHING! (1%)',
          ],
          onBuy: _openMysteryCrate,
        ),
        const SizedBox(height: 16),
        _buildCrateCard(
          title: 'Exclusive Crate',
          subtitle: 'Premium odds!',
          price: '£1.50',
          currency: 'money',
          icon: Icons.stars_rounded,
          color: AppTheme.warning,
          drops: [
            'Pink Bow (50%)',
            'Orange/Yellow/Blue Bow (22%)',
            'Multi-Color Bow (13%)',
            'Rare Bow (5%)',
            '🌈 Rainbow Bow w/ Mood Mode (1%)',
          ],
          onBuy: _buyExclusiveCrate,
        ),
      ],
    );
  }

  Widget _buildCrateCard({
    required String title,
    required String subtitle,
    required String price,
    required String currency,
    required IconData icon,
    required Color color,
    required List<String> drops,
    required VoidCallback onBuy,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.15),
            color.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'DROP RATES:',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          ...drops.map((drop) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 6,
                        color: color.withValues(alpha: 0.5)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        drop,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onBuy,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: AppTheme.primaryDark,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (currency == 'diamonds')
                    const Icon(Icons.diamond_rounded, size: 16),
                  if (currency == 'diamonds') const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      currency == 'diamonds' ? '$price Diamonds' : price,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // === PASSES TAB ===
  Widget _buildPassesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPassCard(
          title: 'VIP Pass',
          price: '£3.50',
          description:
              'Get access to ALL bows! Pick any 5 of your choice and unlock them instantly.',
          icon: Icons.workspace_premium_rounded,
          color: AppTheme.warning,
          perks: [
            'Unlock all bow designs',
            'Choose 5 bows of your choice',
            'Includes Rainbow Bow',
            'Mood Mode for Rainbow Bow',
            'VIP badge on profile',
          ],
          owned: player.hasVip,
          onBuy: _buyVip,
        ),
        const SizedBox(height: 16),
        // Diamond purchase options
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'BUY DIAMONDS',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ),
        _buildDiamondPurchase(100, '£0.59'),
        const SizedBox(height: 10),
        _buildDiamondPurchase(500, '£1.29'),
        const SizedBox(height: 10),
        _buildDiamondPurchase(1500, '£3.00'),
      ],
    );
  }

  Widget _buildDiamondPurchase(int amount, String price) {
    return GestureDetector(
      onTap: () => _onBuyDiamondsTap(amount),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.accent.withValues(alpha: 0.12),
              AppTheme.accent.withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.diamond_rounded,
                  color: AppTheme.accent, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                '$amount Diamonds',
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                price,
                style: const TextStyle(
                  color: AppTheme.primaryDark,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPassCard({
    required String title,
    required String price,
    required String description,
    required IconData icon,
    required Color color,
    required List<String> perks,
    required bool owned,
    required VoidCallback onBuy,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.2),
            color.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          ...perks.map((perk) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: color, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        perk,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: owned ? null : onBuy,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: AppTheme.primaryDark,
                disabledBackgroundColor: color.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                owned ? 'OWNED ✓' : 'Buy for $price',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // === ITEMS TAB ===
  Widget _buildItemsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildItemCard(
          title: 'Shield Keychain',
          price: '£0.59',
          description: 'A special shield keychain accessory for your bow!',
          icon: Icons.shield_rounded,
          color: AppTheme.purple,
          owned: player.hasShieldKeychain,
          onBuy: _buyShieldKeychain,
        ),
        const SizedBox(height: 12),
        _buildItemCard(
          title: '67 Keychain',
          price: 'Mystery Crate',
          description:
              'The viral 67 keychain. Only available from the Mystery Crate!',
          icon: Icons.key_rounded,
          color: const Color(0xFFFF6B6B),
          owned: player.has67Keychain,
          onBuy: _buy67Keychain,
        ),
        const SizedBox(height: 12),
        _buildItemCard(
          title: 'Combo Keychain',
          price: '320 💎',
          description:
              'Combines Shield + 67 keychains into one ultimate keychain! '
              'Requires both keychains first.',
          icon: Icons.all_inclusive_rounded,
          color: AppTheme.warning,
          owned: player.hasComboKeychain,
          onBuy: _buyComboKeychain,
        ),
      ],
    );
  }

  Widget _buildItemCard({
    required String title,
    required String price,
    required String description,
    required IconData icon,
    required Color color,
    required bool owned,
    required VoidCallback onBuy,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.15),
            color.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 36),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: owned ? null : onBuy,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: color.withValues(alpha: 0.3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      owned ? 'OWNED ✓' : price,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
