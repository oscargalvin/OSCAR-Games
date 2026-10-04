import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/save_service.dart';
import '../../services/sound_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_scaffold.dart';
import 'fishing_art.dart';
import 'fishing_codes.dart';
import 'fishing_models.dart';

enum _FishTab { outing, shop, cooler, codes }

enum _FishPhase { idle, waiting, biteWindow, escaped, landed }

class BoatFishingScreen extends StatefulWidget {
  const BoatFishingScreen({super.key});

  @override
  State<BoatFishingScreen> createState() => _BoatFishingScreenState();
}

class _BoatFishingScreenState extends State<BoatFishingScreen>
    with TickerProviderStateMixin {
  late int _coins;
  late List<String> _ownedBoats;
  late List<String> _ownedRods;
  late String _equippedBoat;
  late String _equippedRod;
  late Map<String, int> _inventory;
  late int _totalCaught;

  _FishTab _tab = _FishTab.outing;
  _FishPhase _phase = _FishPhase.idle;
  Timer? _phaseTimer;
  FishSpecies? _lastCatch;

  /// Committed cast position after you tap “Land rod here” (–1…1).
  double _aimX = 0;
  double _pushUpAccum = 0;
  bool _reeling = false;
  bool _rodLocked = false;

  /// Snapshotted aim when this cast went out (drives rarity rolls).
  double _castAimX = 0;

  /// Snapshotted bite-hook window (ms) for this cast — matches rod used when you tapped Cast line.
  int _castBiteWindowMs = kBiteHookWindowSeconds * 1000;

  late List<String> _redeemedFishingCodes;
  late TextEditingController _promoCodeController;

  late AnimationController _bobberController;
  late AnimationController _biteTimer;
  /// Smooth left↔right sweep while choosing where to cast (idle, unlocked).
  late AnimationController _swingController;

  @override
  void initState() {
    super.initState();
    final save = SaveService.instance;
    _coins = save.fishCoins;
    _ownedBoats = List<String>.from(save.fishingOwnedBoats);
    _ownedRods = List<String>.from(save.fishingOwnedRods);
    _equippedBoat = save.fishingEquippedBoatId;
    _equippedRod = save.fishingEquippedRodId;
    _inventory = Map<String, int>.from(save.fishingInventory);
    _totalCaught = save.fishingTotalCaught;

    _redeemedFishingCodes =
        List<String>.from(save.fishingRedeemedCodes);
    _promoCodeController = TextEditingController();

    _bobberController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _biteTimer = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: rodById('bamboo').biteWindowMs),
    );
    _swingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
    _biteTimer.addStatusListener((status) async {
      if (status != AnimationStatus.completed || !mounted) return;
      if (_phase != _FishPhase.biteWindow || _reeling) return;
      _bobberController.stop();
      _bobberController.reset();
      setState(() => _phase = _FishPhase.escaped);
      SoundService.instance.play(GameSound.noMatch);
      await _persist();
    });
  }

  double get _paintAimX {
    final swinging = _phase == _FishPhase.idle && !_rodLocked;
    if (swinging) {
      return rodSweepTriangleAim(_swingController.value).clamp(-1.0, 1.0);
    }
    return _aimX;
  }

  void _syncSwingPlayback() {
    final wantSwing = _phase == _FishPhase.idle && !_rodLocked;
    if (wantSwing && !_swingController.isAnimating) {
      _swingController.repeat();
    } else if (!wantSwing && _swingController.isAnimating) {
      _swingController.stop();
    }
  }

  void _landRodHere() {
    if (_phase != _FishPhase.idle || _rodLocked) return;
    final v = rodSweepTriangleAim(_swingController.value).clamp(-1.0, 1.0);
    SoundService.instance.play(GameSound.tap);
    HapticFeedback.mediumImpact();
    setState(() {
      _aimX = v;
      _rodLocked = true;
      _syncSwingPlayback();
    });
  }

  void _unlockRod() {
    if (_phase != _FishPhase.idle || !_rodLocked) return;
    SoundService.instance.play(GameSound.tap);
    setState(() {
      _rodLocked = false;
      _syncSwingPlayback();
    });
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _bobberController.dispose();
    _biteTimer.dispose();
    _swingController.dispose();
    _promoCodeController.dispose();
    super.dispose();
  }

  Future<void> _tryRedeemFishingCode(String raw) async {
    final code = normalizeFishingPromoCode(raw);
    if (code.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a code.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final reward = fishingRewardForNormalizedCode(code);
    if (reward == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That code doesn’t match anything.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_redeemedFishingCodes.contains(code)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already redeemed that code.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    SoundService.instance.play(GameSound.win);
    HapticFeedback.mediumImpact();
    setState(() {
      _coins += reward.fishCoins;
      _redeemedFishingCodes = [..._redeemedFishingCodes, code];
      _promoCodeController.clear();
    });
    await SaveService.instance.saveFishingRedeemedCodes(_redeemedFishingCodes);
    await _persist();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Redeemed! +${reward.fishCoins} fish coins.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _persist() async {
    await SaveService.instance.saveFishingProgress(
      fishCoins: _coins,
      ownedBoats: _ownedBoats,
      ownedRods: _ownedRods,
      equippedBoatId: _equippedBoat,
      equippedRodId: _equippedRod,
      inventory: _inventory,
      totalCaught: _totalCaught,
    );
  }

  FishingBoatDef get _boat => boatById(_equippedBoat);
  FishingRodDef get _rod => rodById(_equippedRod);

  void _ensureOwnedDefaults() {
    if (!_ownedBoats.contains('dinghy')) _ownedBoats.add('dinghy');
    if (!_ownedRods.contains('bamboo')) _ownedRods.add('bamboo');
  }

  int _inventoryCount() {
    var n = 0;
    for (final c in _inventory.values) {
      n += c;
    }
    return n;
  }

  void _startCast() {
    if (_phase == _FishPhase.landed || _phase == _FishPhase.escaped) {
      setState(() {
        _phase = _FishPhase.idle;
        _rodLocked = false;
        _lastCatch = null;
      });
      _syncSwingPlayback();
      return;
    }

    if (_phase != _FishPhase.idle) {
      return;
    }
    if (!_rodLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Watch the rod swing, then tap “Land rod here” where you want to fish.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _ensureOwnedDefaults();
    SoundService.instance.play(GameSound.place);
    HapticFeedback.mediumImpact();

    _phaseTimer?.cancel();
    _biteTimer.stop();
    _biteTimer.reset();
    setState(() {
      _castAimX = _aimX;
      _castBiteWindowMs = _rod.biteWindowMs;
      _phase = _FishPhase.waiting;
      _lastCatch = null;
      _rodLocked = false;
    });
    _syncSwingPlayback();

    _bobberController.repeat(reverse: true);

    final rng = Random();
    final wait = rng.nextInt(_rod.waitMsMax - _rod.waitMsMin + 1) + _rod.waitMsMin;

    _phaseTimer = Timer(Duration(milliseconds: wait), () {
      if (!mounted || _phase != _FishPhase.waiting) return;
      SoundService.instance.play(GameSound.countdownTick);
      HapticFeedback.heavyImpact();
      setState(() {
        _phase = _FishPhase.biteWindow;
        _pushUpAccum = 0;
      });
      _biteTimer.duration = Duration(milliseconds: _castBiteWindowMs);
      _biteTimer.stop();
      _biteTimer.reset();
      _biteTimer.forward(from: 0);
    });
  }

  Future<void> _onPushUpHook() async {
    if (_phase != _FishPhase.biteWindow || _reeling) return;
    _reeling = true;
    _phaseTimer?.cancel();
    _biteTimer.stop();
    _biteTimer.reset();
    _bobberController.stop();
    _bobberController.reset();

    final fish = rollFish(Random(), _boat.tier, _castAimX);
    _inventory.update(fish.id, (v) => v + 1, ifAbsent: () => 1);
    _totalCaught++;

    SoundService.instance.play(GameSound.match);
    HapticFeedback.lightImpact();

    setState(() {
      _phase = _FishPhase.landed;
      _lastCatch = fish;
    });
    try {
      await _persist();
      if (!mounted) return;
      _showCatchReveal(fish);
    } finally {
      _reeling = false;
    }
  }

  void _registerPushUpGesture(DragUpdateDetails d) {
    if (_phase != _FishPhase.biteWindow) return;
    _pushUpAccum += -d.delta.dy;
    if (_pushUpAccum >= 56) {
      _pushUpAccum = 0;
      unawaited(_onPushUpHook());
    }
  }

  void _registerPushUpFling(DragEndDetails d) {
    if (_phase != _FishPhase.biteWindow) return;
    final v = d.primaryVelocity;
    if (v != null && v < -180) {
      _pushUpAccum = 0;
      unawaited(_onPushUpHook());
    }
  }

  void _showCatchReveal(FishSpecies fish) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: fish.rarity.color.withValues(alpha: 0.45), width: 2),
          ),
          backgroundColor: AppTheme.primaryMid,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Reeled in!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: fish.rarity.color,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),
                FishCatchArt(species: fish, size: 240, softGlow: true),
                const SizedBox(height: 14),
                Text(
                  fish.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: fish.rarity.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: fish.rarity.color.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    fish.rarity.label,
                    style: TextStyle(
                      color: fish.rarity.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Sell value: ${fish.sellPrice} fish coins',
                  style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.95)),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Add to cooler'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _buyBoat(FishingBoatDef b) async {
    if (!_ownedBoats.contains(b.id) && _coins < b.cost) return;
    if (_ownedBoats.contains(b.id)) {
      setState(() => _equippedBoat = b.id);
      SoundService.instance.play(GameSound.tap);
      await _persist();
      return;
    }
    setState(() {
      _coins -= b.cost;
      _ownedBoats.add(b.id);
      _equippedBoat = b.id;
    });
    SoundService.instance.play(GameSound.win);
    HapticFeedback.selectionClick();
    await _persist();
  }

  Future<void> _buyRod(FishingRodDef r) async {
    if (!_ownedRods.contains(r.id) && _coins < r.cost) return;
    if (_ownedRods.contains(r.id)) {
      setState(() => _equippedRod = r.id);
      SoundService.instance.play(GameSound.tap);
      await _persist();
      return;
    }
    setState(() {
      _coins -= r.cost;
      _ownedRods.add(r.id);
      _equippedRod = r.id;
    });
    SoundService.instance.play(GameSound.win);
    HapticFeedback.selectionClick();
    await _persist();
  }

  Future<void> _sellAll() async {
    if (_inventory.isEmpty) return;
    var total = 0;
    for (final e in _inventory.entries) {
      final fish = speciesById(e.key);
      total += fish.sellPrice * e.value;
    }
    SoundService.instance.play(GameSound.hit);
    HapticFeedback.mediumImpact();
    setState(() {
      _coins += total;
      _inventory.clear();
    });
    await _persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sold your catch for $total fish coins!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Lucky Fish',
      actions: [
        IconButton(
          tooltip: 'Fish coin codes',
          onPressed: () {
            SoundService.instance.play(GameSound.tap);
            setState(() => _tab = _FishTab.codes);
          },
          icon: const Icon(Icons.key_rounded),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.monetization_on_rounded,
                    color: AppTheme.warning, size: 20),
                const SizedBox(width: 6),
                Text(
                  '$_coins',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      bottomBar: BottomNavigationBar(
        backgroundColor: AppTheme.surface,
        selectedItemColor: AppTheme.accent,
        unselectedItemColor: AppTheme.textSecondary,
        currentIndex: _tab.index,
        onTap: (i) {
          SoundService.instance.play(GameSound.tap);
          setState(() => _tab = _FishTab.values[i]);
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.phishing_rounded),
            label: 'Lucky Fish',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.storefront_rounded),
            label: 'Shop',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.ac_unit_rounded),
            label: 'Cooler',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.card_giftcard_rounded),
            label: 'Codes',
          ),
        ],
      ),
      body: switch (_tab) {
        _FishTab.outing => _buildOuting(),
        _FishTab.shop => _buildShop(),
        _FishTab.cooler => _buildCooler(),
        _FishTab.codes => _buildCodes(),
      },
    );
  }

  Widget _buildOuting() {
    final busy = _phase == _FishPhase.waiting || _phase == _FishPhase.biteWindow;
    const sceneH = 260.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _equipmentChips(),
          const SizedBox(height: 14),
          if (_phase == _FishPhase.idle) ...[
            Text(
              _rodLocked
                  ? 'Rod locked — Cast line next. On BITE! you get ${_rod.biteHookSeconds.toStringAsFixed(1)}s (${_rod.name}). Your boat may block low rarities (e.g. Yacht never Legendary; only Research gets Special). Center water still favors Secret over Legendary when both apply.'
                  : 'The rod swings: end → middle → other end → repeat. Corners favor what your boat still allows; center pushes Secret & Special over Legendary when those tiers are legal.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppTheme.textSecondary.withValues(alpha: 0.92),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _rodLocked ? null : _landRodHere,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.black87,
                    ),
                    child: const Text('Land rod here'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _rodLocked ? _unlockRod : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Aim again'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final bobberX = LakeFishingScenePainter.bobberX(Size(w, sceneH), _paintAimX);
              return SizedBox(
                height: sceneH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (d) {
                          if (_phase == _FishPhase.biteWindow) _registerPushUpGesture(d);
                        },
                        onVerticalDragEnd: (d) {
                          if (_phase == _FishPhase.biteWindow) _registerPushUpFling(d);
                        },
                        child: AnimatedBuilder(
                          animation: Listenable.merge([
                            _bobberController,
                            _biteTimer,
                            _swingController,
                          ]),
                          builder: (context, child) {
                            final t = busy
                                ? Curves.easeInOut.transform(_bobberController.value)
                                : 0.0;
                            return CustomPaint(
                              painter: LakeFishingScenePainter(
                                bobberBob: busy ? (t - 0.5) * 14 : 0,
                                aimX: _paintAimX,
                                boatTier: _boat.tier,
                                rodTier: _rod.tier,
                                showRodZones: _phase == _FishPhase.idle ||
                                    _phase == _FishPhase.waiting ||
                                    _phase == _FishPhase.biteWindow,
                              ),
                              child: child,
                            );
                          },
                        ),
                      ),
                    ),
                    if (_phase == _FishPhase.biteWindow)
                      Positioned(
                        left: (bobberX - 56).clamp(6.0, w - 118),
                        top: sceneH * 0.34,
                        width: 112,
                        child: AnimatedBuilder(
                          animation: _biteTimer,
                          builder: (context, _) {
                            final hookSec = _castBiteWindowMs / 1000.0;
                            final secLeft = (hookSec * (1.0 - _biteTimer.value))
                                .clamp(0.0, hookSec);
                            final show = secLeft <= 0.05 ? '0.0' : secLeft.toStringAsFixed(1);
                            return Material(
                              elevation: 8,
                              borderRadius: BorderRadius.circular(14),
                              color: Colors.black.withValues(alpha: 0.82),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'BITE!',
                                      style: TextStyle(
                                        color: AppTheme.warning,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$show s',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 28,
                                        fontFeatures: [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: 1.0 - _biteTimer.value,
                                        minHeight: 6,
                                        backgroundColor: Colors.white24,
                                        color: AppTheme.accent,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Swipe ↑',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.85),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          if (busy && _phase == _FishPhase.waiting)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Line’s out — watch the bobber. When BITE! hits, you’ll have ${_rod.biteHookSeconds.toStringAsFixed(1)}s on the timer with this rod.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary.withValues(alpha: 0.85),
                ),
              ),
            ),
          if (_phase == _FishPhase.biteWindow)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Timer on your bobber — ${_fmtHookSeconds(_castBiteWindowMs)}, then it’s gone. Swipe UP on the lake or strip!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.warning.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 20),
          _phasePanel(),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: busy ? null : _startCast,
            icon: Icon(_phase == _FishPhase.landed || _phase == _FishPhase.escaped
                ? Icons.refresh_rounded
                : Icons.sailing_rounded),
            label: Text(
              _phase == _FishPhase.landed || _phase == _FishPhase.escaped
                  ? 'Next cast'
                  : 'Cast line',
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          if (_lastCatch != null && (_phase == _FishPhase.landed || _phase == _FishPhase.escaped))
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (_phase == _FishPhase.landed && _lastCatch != null)
                        FishCatchArt(species: _lastCatch!, size: 88, softGlow: false)
                      else
                        Icon(Icons.water_drop_outlined,
                            color: AppTheme.blue.withValues(alpha: 0.85), size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _phase == _FishPhase.landed
                              ? 'That catch is in your cooler now. Open the cooler tab anytime to sell!'
                              : 'Too slippery — it never grabbed the hook and slipped off your line. Try a quicker swipe in the ${_fmtHookSeconds(_castBiteWindowMs)} next BITE!',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _equipmentChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(Icons.directions_boat_filled_rounded, _boat.name, AppTheme.blue),
        _chip(Icons.adjust_rounded, _rod.name, AppTheme.success),
        _chip(Icons.inventory_2_rounded, 'Cooler: ${_inventoryCount()}', AppTheme.purple),
      ],
    );
  }

  Widget _chip(IconData icon, String label, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtHookSeconds(int biteWindowMs) {
    if (biteWindowMs % 1000 == 0) return '${biteWindowMs ~/ 1000} seconds';
    return '${(biteWindowMs / 1000).toStringAsFixed(1)} seconds';
  }

  Widget _phasePanel() {
    switch (_phase) {
      case _FishPhase.idle:
        return _statusCard(
          'Ready',
          'Sweep path: outer → middle → other side. Boats hard‑cap bites: Rowboat never Common; Motorboat never Rare; Coastal Yacht never Legendary, only Secret; Research Trawler is the only boat that rolls Special fish. Aim still shifts odds. Better tiers also soften low‑tier weights. BITE! timer: ${_fmtHookSeconds(_rod.biteWindowMs)}.',
          Icons.waves_rounded,
        );
      case _FishPhase.waiting:
        return _statusCard(
          'Waiting…',
          'Your line is where you landed it. Rarity odds already factored that spot in — now wait for the bite.',
          Icons.visibility_rounded,
        );
      case _FishPhase.biteWindow:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: _registerPushUpGesture,
          onVerticalDragEnd: _registerPushUpFling,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.danger.withValues(alpha: 0.88),
                  AppTheme.warning.withValues(alpha: 0.74),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              children: [
                Icon(Icons.touch_app_rounded, size: 36, color: Colors.white.withValues(alpha: 0.95)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Hook fast! Swipe UP here or on the lake. You’ve got ${_fmtHookSeconds(_castBiteWindowMs)} on the bobber for this rod.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                      color: Colors.white.withValues(alpha: 0.96),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case _FishPhase.escaped:
        return _statusCard(
          'It got away!',
          'Too slippery — it slid off before your rod really had it (${_fmtHookSeconds(_castBiteWindowMs)} goes quick). Faster swipe next time!',
          Icons.water_damage_rounded,
        );
      case _FishPhase.landed:
        return _statusCard(
          'Nice catch!',
          'Fish go to your cooler. Sell anytime for fish coins.',
          Icons.anchor_rounded,
        );
    }
  }

  Widget _statusCard(String title, String body, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppTheme.accent, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    body,
                    style: TextStyle(
                      color: AppTheme.textSecondary.withValues(alpha: 0.95),
                      height: 1.35,
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

  Widget _buildCodes() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.card_giftcard_rounded, color: AppTheme.accent, size: 28),
                      const SizedBox(width: 12),
                      const Text(
                        'Fish coin codes',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Enter a secret phrase to add fish coins. Capitals and spacing don’t matter. '
                    'Each phrase works once. Below are riddles — they never spell the answer outright.',
                    style: TextStyle(
                      color: AppTheme.textSecondary.withValues(alpha: 0.95),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Riddle hints',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.textSecondary.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 8),
          ...kFishingPromoHints.map((h) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline_rounded,
                              size: 20, color: AppTheme.warning.withValues(alpha: 0.9)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              h.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        h.clue,
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.94),
                          height: 1.4,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          TextField(
            controller: _promoCodeController,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Your guess',
              hintText: 'Type the phrase you think matches a riddle…',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
            ),
            onSubmitted: (s) => unawaited(_tryRedeemFishingCode(s)),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              SoundService.instance.play(GameSound.tap);
              unawaited(_tryRedeemFishingCode(_promoCodeController.text));
            },
            icon: const Icon(Icons.redeem_rounded),
            label: const Text('Redeem for fish coins'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'You’ve redeemed ${_redeemedFishingCodes.length} code${_redeemedFishingCodes.length == 1 ? '' : 's'} so far.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.85),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShop() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            labelColor: AppTheme.accent,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.accent,
            tabs: [
              Tab(text: 'Boats'),
              Tab(text: 'Rods'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [_shopBoats(), _shopRods()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shopBoats() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (_, i) {
        final b = kBoats[i];
        final owned = _ownedBoats.contains(b.id);
        final equipped = _equippedBoat == b.id;
        final affordable = owned || _coins >= b.cost;
        final subtitle =
            '${b.blurb}\nBetter boats shift odds toward Rare, Legendary, Secret & Special.';
        return _shopTile(
          preview: SizedBox(
            width: 118,
            height: 88,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.blue.withValues(alpha: 0.25)),
                color: AppTheme.cardColor.withValues(alpha: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BoatShopPreview(tier: b.tier),
              ),
            ),
          ),
          title: b.name,
          subtitle: subtitle,
          price: b.cost,
          owned: owned,
          equipped: equipped,
          affordable: affordable,
          accent: AppTheme.blue,
          onEquipBuy: () => _buyBoat(b),
          equipLabel: 'Sail',
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: kBoats.length,
    );
  }

  Widget _shopRods() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (_, i) {
        final r = kRods[i];
        final owned = _ownedRods.contains(r.id);
        final equipped = _equippedRod == r.id;
        final affordable = owned || _coins >= r.cost;
        final subtitle =
            '${r.blurb}\nCast timing: ${_rodWaitReadable(r)} on average. After BITE!, you have ${_fmtHookSeconds(r.biteWindowMs)} to hook — better rods give more time.';
        return _shopTile(
          preview: SizedBox(
            width: 72,
            height: 108,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.success.withValues(alpha: 0.25)),
                color: AppTheme.cardColor.withValues(alpha: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: RodShopPreview(tier: r.tier),
              ),
            ),
          ),
          title: r.name,
          subtitle: subtitle,
          price: r.cost,
          owned: owned,
          equipped: equipped,
          affordable: affordable,
          accent: AppTheme.success,
          onEquipBuy: () => _buyRod(r),
          equipLabel: 'Use',
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: kRods.length,
    );
  }

  String _rodWaitReadable(FishingRodDef r) =>
      '${(r.waitMsMin / 1000).toStringAsFixed(1)}–${(r.waitMsMax / 1000).toStringAsFixed(1)}s';

  Widget _shopTile({
    required Widget preview,
    required String title,
    required String subtitle,
    required int price,
    required bool owned,
    required bool equipped,
    required bool affordable,
    required Color accent,
    required VoidCallback onEquipBuy,
    required String equipLabel,
  }) {
    final priceLabel =
        owned ? 'Owned — tap to $equipLabel' : (price <= 0 ? 'Free starter' : '$price coins');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                preview,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (equipped)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Equipped',
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.92),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Wrap so the button drops below the price on narrow phones.
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Text.rich(
                            TextSpan(children: [
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Icon(Icons.monetization_on_rounded,
                                      color: affordable ? AppTheme.warning : AppTheme.danger,
                                      size: 18),
                                ),
                              ),
                              TextSpan(text: priceLabel),
                            ]),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: affordable ? AppTheme.textPrimary : AppTheme.danger,
                            ),
                          ),
                          FilledButton(
                            onPressed:
                                equipped ? null : ((!owned && !affordable) ? null : onEquipBuy),
                            style: FilledButton.styleFrom(
                              backgroundColor: equipped ? accent : AppTheme.accent,
                              foregroundColor: Colors.black87,
                            ),
                            child:
                                Text(equipped ? 'Equipped' : (owned ? equipLabel : 'Buy')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCooler() {
    if (_inventory.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.icecream_rounded,
                  size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.35)),
              const SizedBox(height: 16),
              Text(
                'Your cooler is empty',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Catch fish out on the water — they chill here until you sell them.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.6),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      );
    }

    var totalSell = 0;
    final rows = <Widget>[];
    for (final e in _inventory.entries) {
      final fish = speciesById(e.key);
      totalSell += fish.sellPrice * e.value;
      rows.add(Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          leading: FishCatchArt(species: fish, size: 72, softGlow: false),
          title: Text(fish.name),
          subtitle: Text('${fish.rarity.label} · ${fish.sellPrice}c each'),
          trailing: Text(
            '× ${e.value}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ));
      rows.add(const SizedBox(height: 8));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.attach_money_rounded, color: AppTheme.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sell everything for $totalSell fish coins',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                FilledButton(
                  onPressed: _sellAll,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.black87,
                  ),
                  child: const Text('Sell all'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }
}
