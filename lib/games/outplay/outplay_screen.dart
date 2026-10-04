import 'package:flutter/material.dart';

import '../../services/sound_service.dart';
import 'outplay_art.dart';
import 'outplay_avatar.dart';
import 'outplay_data.dart';
import 'outplay_game.dart';

const Color _bg = Color(0xFF1B2138);
const Color _card = Color(0xFF262E4F);
const Color _gold = Color(0xFFFFC93C);
const Color _cyan = Color(0xFF4FC3F7);

/// Outplay lobby: pick your loadout, buy and upgrade weapons, then duel.
class OutplayScreen extends StatefulWidget {
  const OutplayScreen({super.key});

  @override
  State<OutplayScreen> createState() => _OutplayScreenState();
}

class _OutplayScreenState extends State<OutplayScreen> {
  final _save = OutplaySave.instance;
  bool _loaded = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _save.load().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  Future<void> _editPlayer() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const OutplayAvatarScreen()));
    if (mounted) setState(() {});
  }

  Future<void> _play() async {
    SoundService.instance.play(GameSound.tap);
    // Everyone needs a name and a player before they can fight.
    if (_save.name.trim().isEmpty) {
      await _editPlayer();
      if (!mounted || _save.name.trim().isEmpty) return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const OutplayGameScreen()));
    if (mounted) setState(() {});
  }

  bool _spend(int cost) {
    if (_save.coins < cost) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'You need ${cost - _save.coins} more coins. '
              'Win duels to earn them!',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      return false;
    }
    _save.coins -= cost;
    SoundService.instance.play(GameSound.levelComplete);
    return true;
  }

  void _commit() {
    _save.save();
    setState(() {});
  }

  void _buyGun(Gun g) {
    if (!_spend(g.price)) return;
    _save.ownedGuns.add(g.id);
    _commit();
  }

  void _buyMelee(Melee m) {
    if (!_spend(m.price)) return;
    _save.ownedMelees.add(m.id);
    _save.melee = m.id;
    _commit();
  }

  void _upgrade(String id, int cost) {
    if (!_spend(cost)) return;
    _save.levels[id] = _save.levelOf(id) + 1;
    _commit();
  }

  void _unlockSlot() {
    if (!_spend(kSecondSlotPrice)) return;
    _save.secondSlot = true;
    // Fill it with any other gun you already own.
    for (final id in _save.ownedGuns) {
      if (id != _save.primary) {
        _save.secondary = id;
        break;
      }
    }
    _commit();
  }

  void _equipGun(Gun g, int slot) {
    if (slot == 0) {
      if (_save.secondary == g.id) _save.secondary = _save.primary;
      _save.primary = g.id;
    } else {
      if (_save.primary == g.id) {
        _save.primary = _save.secondary ?? kGuns.first.id;
        if (_save.primary == g.id) _save.primary = kGuns.first.id;
      }
      _save.secondary = g.id;
    }
    if (_save.secondary == _save.primary) _save.secondary = null;
    SoundService.instance.play(GameSound.place);
    _commit();
  }

  void _equipMelee(Melee m) {
    _save.melee = m.id;
    SoundService.instance.play(GameSound.place);
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text(
          'OUTPLAY',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.monetization_on_rounded,
                  color: _gold,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  '${_save.coins}',
                  style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  _buildTabs(),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
                      children: switch (_tab) {
                        0 => _buildLoadout(),
                        1 => [for (final g in kGuns) _gunCard(g)],
                        _ => [for (final m in kMelees) _meleeCard(m)],
                      },
                    ),
                  ),
                  _buildPlayButton(),
                ],
              ),
            ),
    );
  }

  Widget _buildTabs() {
    Widget tab(int i, String label) {
      final on = _tab == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = i),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: on ? _cyan : _card,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: on ? kOutplayInk : Colors.white70,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Row(
        children: [tab(0, 'Loadout'), tab(1, 'Guns'), tab(2, 'Melee')],
      ),
    );
  }

  Widget _buildPlayButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _play,
          style: ElevatedButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: kOutplayInk,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: const Icon(Icons.sports_esports_rounded),
          label: const Text(
            'DUEL  ·  First to 5',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
        ),
      ),
    );
  }

  Widget _playerCard() {
    final named = _save.name.trim().isNotEmpty;
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _editPlayer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              AvatarPreview(avatar: _save.avatar, height: 72),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MY PLAYER',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      named ? _save.name : 'Tap to make your player',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_rounded, color: _cyan),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLoadout() {
    final primary = gunById(_save.primary);
    final secondary = _save.secondary == null
        ? null
        : gunById(_save.secondary!);
    final melee = meleeById(_save.melee);
    return [
      _playerCard(),
      const SizedBox(height: 10),
      Text(
        '${_save.wins} wins  ·  ${_save.losses} losses',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white60, fontSize: 13),
      ),
      const SizedBox(height: 10),
      _slotCard(
        'Gun 1',
        primary.name,
        primary.look,
        primary.color,
        'Level ${_save.levelOf(primary.id)}',
        () => _pickGun(0),
      ),
      if (_save.secondSlot)
        secondary == null
            ? _slotCard(
                'Gun 2',
                'Tap to choose',
                null,
                Colors.white24,
                'Empty',
                () => _pickGun(1),
              )
            : _slotCard(
                'Gun 2',
                secondary.name,
                secondary.look,
                secondary.color,
                'Level ${_save.levelOf(secondary.id)}',
                () => _pickGun(1),
              )
      else
        _lockedSlotCard(),
      _slotCard(
        'Melee',
        melee.name,
        melee.look,
        melee.color,
        'Level ${_save.levelOf(melee.id)}',
        () => setState(() => _tab = 2),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          'How to play: drag on the left side to walk. Drag on the right side '
          'to look around. Hold FIRE to shoot (slide your thumb on it to aim), '
          'tap JUMP to jump, and tap your weapons at the bottom to switch. '
          'In the Duel Zone, walk onto a glowing pad to start a game.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
      ),
    ];
  }

  Widget _slotCard(
    String slot,
    String name,
    WeaponLook? look,
    Color color,
    String detail,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: look == null
                  ? const Icon(
                      Icons.add_rounded,
                      color: Colors.white38,
                      size: 32,
                    )
                  : WeaponIcon(look: look, color: color, size: 76),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slot.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    detail,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  Widget _lockedSlotCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12, width: 2),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 44,
            child: Icon(Icons.lock_rounded, color: Colors.white38, size: 30),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GUN 2',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  'Carry two guns',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          _coinButton(kSecondSlotPrice, _unlockSlot, label: 'Unlock'),
        ],
      ),
    );
  }

  void _pickGun(int slot) {
    final owned = kGuns.where((g) => _save.ownedGuns.contains(g.id)).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: _bg,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: [
            Text(
              'Choose Gun ${slot + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            for (final g in owned)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: WeaponIcon(look: g.look, color: g.color, size: 60),
                title: Text(
                  g.name,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Level ${_save.levelOf(g.id)}',
                  style: const TextStyle(color: Colors.white54),
                ),
                trailing: (slot == 0 ? _save.primary : _save.secondary) == g.id
                    ? const Icon(Icons.check_circle_rounded, color: _cyan)
                    : null,
                onTap: () {
                  _equipGun(g, slot);
                  Navigator.of(ctx).pop();
                },
              ),
            if (owned.length < kGuns.length)
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() => _tab = 1);
                },
                child: const Text('Buy more guns'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _coinButton(int cost, VoidCallback onTap, {String? label}) {
    final can = _save.coins >= cost;
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: can ? _gold : Colors.white24,
        foregroundColor: kOutplayInk,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(0, 40),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Text(label, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
          ],
          const Icon(Icons.monetization_on_rounded, size: 16),
          const SizedBox(width: 3),
          Text('$cost', style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _levelDots(int level) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= kMaxLevel; i++)
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: i <= level ? _gold : Colors.white12,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }

  Widget _stat(String label, String value) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(color: Colors.white54),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 12),
    );
  }

  Widget _itemCard({
    required WeaponLook look,
    required Color color,
    required String name,
    required String blurb,
    required List<Widget> stats,
    required bool owned,
    required int level,
    required List<Widget> actions,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: owned ? color.withValues(alpha: 0.5) : Colors.white10,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              WeaponIcon(look: look, color: color, size: 72),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      blurb,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 2, children: stats),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [if (owned) _levelDots(level), ...actions],
          ),
        ],
      ),
    );
  }

  Widget _gunCard(Gun g) {
    final owned = _save.ownedGuns.contains(g.id);
    final level = _save.levelOf(g.id);
    final dmg = g.damage * levelDamageMul(level) * g.pellets;
    final perSec = 1 / (g.fireInterval * levelSpeedMul(level));
    final actions = <Widget>[];
    if (!owned) {
      actions.add(_coinButton(g.price, () => _buyGun(g), label: 'Buy'));
    } else {
      if (level < kMaxLevel) {
        final cost = gunUpgradeCost(g, level);
        actions.add(
          _coinButton(cost, () => _upgrade(g.id, cost), label: 'Upgrade'),
        );
      }
      final inSlot1 = _save.primary == g.id;
      final inSlot2 = _save.secondary == g.id;
      actions.add(_equipChip('Gun 1', inSlot1, () => _equipGun(g, 0)));
      if (_save.secondSlot) {
        actions.add(_equipChip('Gun 2', inSlot2, () => _equipGun(g, 1)));
      }
    }
    return _itemCard(
      look: g.look,
      color: g.color,
      name: g.name,
      blurb: g.blurb,
      owned: owned,
      level: level,
      stats: [
        _stat('Damage', dmg.round().toString()),
        _stat('Shots/sec', perSec.toStringAsFixed(1)),
        if (g.custom)
          const Text(
            '★ Outplay original',
            style: TextStyle(
              color: Color(0xFFFFC93C),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        _stat('Ammo', '${g.mag}'),
      ],
      actions: actions,
    );
  }

  Widget _meleeCard(Melee m) {
    final owned = _save.ownedMelees.contains(m.id);
    final level = _save.levelOf(m.id);
    final actions = <Widget>[];
    if (!owned) {
      actions.add(_coinButton(m.price, () => _buyMelee(m), label: 'Buy'));
    } else {
      if (level < kMaxLevel) {
        final cost = meleeUpgradeCost(m, level);
        actions.add(
          _coinButton(cost, () => _upgrade(m.id, cost), label: 'Upgrade'),
        );
      }
      actions.add(
        _equipChip('Equip', _save.melee == m.id, () => _equipMelee(m)),
      );
    }
    return _itemCard(
      look: m.look,
      color: m.color,
      name: m.name,
      blurb: m.blurb,
      owned: owned,
      level: level,
      stats: [
        _stat('Damage', (m.damage * levelDamageMul(level)).round().toString()),
        _stat('Reach', m.reach < 1.4 ? 'Short' : 'Long'),
        _stat('Speed', m.moveMul >= 1.2 ? 'Fast' : 'Normal'),
      ],
      actions: actions,
    );
  }

  Widget _equipChip(String label, bool on, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: on ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: _cyan,
        side: BorderSide(color: on ? _cyan : Colors.white24),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(0, 40),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: on ? _cyan : Colors.white, fontSize: 13),
          ),
          if (on) ...[
            const SizedBox(width: 4),
            const Icon(Icons.check_rounded, color: _cyan, size: 16),
          ],
        ],
      ),
    );
  }
}
