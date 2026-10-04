import 'dart:math';

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
  final _rnd = Random();

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

  void _unlockMeleeSlot() {
    if (!_spend(kSecondMeleePrice)) return;
    _save.meleeSlot2 = true;
    for (final id in _save.ownedMelees) {
      if (id != _save.melee) {
        _save.melee2 = id;
        break;
      }
    }
    _commit();
  }

  void _equipMelee(Melee m, [int slot = 0]) {
    if (slot == 0) {
      if (_save.melee2 == m.id) _save.melee2 = _save.melee;
      _save.melee = m.id;
    } else {
      if (_save.melee == m.id) {
        _save.melee = _save.melee2 ?? 'fist';
        if (_save.melee == m.id) _save.melee = 'fist';
      }
      _save.melee2 = m.id;
    }
    if (_save.melee2 == _save.melee) _save.melee2 = null;
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
                        2 => [for (final m in kMelees) _meleeCard(m)],
                        _ => _buildSkins(),
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
        children: [
          tab(0, 'Loadout'),
          tab(1, 'Guns'),
          tab(2, 'Melee'),
          tab(3, 'Skins'),
        ],
      ),
    );
  }

  // ---- Skins -------------------------------------------------------------

  ({WeaponLook look, Color color}) _lookOf(String id) {
    for (final g in kGuns) {
      if (g.id == id) return (look: g.look, color: g.color);
    }
    final m = meleeById(id);
    return (look: m.look, color: m.color);
  }

  void _equipSkin(String weapon, Skin? skin) {
    if (skin == null) {
      _save.equippedSkins.remove(weapon);
    } else {
      _save.equippedSkins[weapon] = skin.id;
    }
    SoundService.instance.play(GameSound.place);
    _commit();
  }

  void _buySkin(String weapon, Skin skin) {
    if (!_spend(skin.price)) return;
    _save.skins.add('$weapon:${skin.id}');
    _save.equippedSkins[weapon] = skin.id;
    _commit();
  }

  Future<void> _openBox() async {
    if (!_spend(kSkinBoxPrice)) return;
    final prize = openSkinBox(_rnd);
    final key = '${prize.weapon}:${prize.skin.id}';
    final duplicate = _save.skins.contains(key);
    if (duplicate) {
      _save.coins += kDuplicateRefund;
    } else {
      _save.skins.add(key);
    }
    _commit();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SkinBoxDialog(
        weapon: prize.weapon,
        skin: prize.skin,
        duplicate: duplicate,
        lookOf: _lookOf,
        onEquip: () => _equipSkin(prize.weapon, prize.skin),
      ),
    );
  }

  List<Widget> _buildSkins() {
    // Weapons you own first, then everything else.
    final owned = [
      ..._save.ownedGuns.where((id) => kGuns.any((g) => g.id == id)),
      ..._save.ownedMelees,
    ];
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4A2C82), Color(0xFF26346B)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _gold, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 64, height: 64, child: SkinBoxPicture()),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Skin Box',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'A random skin for a random weapon. Already got it? '
                        'You get $kDuplicateRefund coins back.',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [
                for (final r in Rarity.values)
                  Text(
                    '${kRarityNames[r]} ${kBoxOdds[r]}%',
                    style: TextStyle(
                      color: kRarityColours[r],
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openBox,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: kOutplayInk,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.monetization_on_rounded),
                label: const Text(
                  'OPEN  ·  $kSkinBoxPrice',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Or buy a skin for one of your weapons. Tap a skin you own to wear it.',
        style: TextStyle(color: Colors.white70, fontSize: 13),
      ),
      const SizedBox(height: 8),
      for (final id in owned) _skinCard(id),
    ];
  }

  Widget _skinChip(String weapon, Skin? skin, {VoidCallback? changed}) {
    final l = _lookOf(weapon);
    final on = _save.skinOn(weapon);
    final owns = skin == null || _save.ownsSkin(weapon, skin.id);
    final wearing = on?.id == skin?.id;
    final colour = skin == null ? Colors.white54 : kRarityColours[skin.rarity]!;
    return GestureDetector(
      onTap: () {
        if (owns) {
          _equipSkin(weapon, skin);
        } else {
          _buySkin(weapon, skin);
        }
        changed?.call();
      },
      child: Container(
        width: 74,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: wearing ? colour.withValues(alpha: 0.25) : _bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: wearing ? colour : colour.withValues(alpha: 0.35),
            width: wearing ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            WeaponIcon(look: l.look, color: l.color, size: 58, skin: skin),
            Text(
              skin?.name ?? 'Normal',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colour,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (!owns)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on_rounded,
                      color: _gold,
                      size: 12,
                    ),
                    Text(
                      ' ${skin.price}',
                      style: const TextStyle(
                        color: _gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                wearing ? 'Wearing' : 'Owned',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }

  List<Skin?> _skinOrder(String weapon) => [
    null,
    // Skins you own come first so you can see them.
    ...kSkins.where((k) => k.fits(weapon) && _save.ownsSkin(weapon, k.id)),
    ...kSkins.where((k) => k.fits(weapon) && !_save.ownsSkin(weapon, k.id)),
  ];

  /// The little skin button's pop-up: switch skins for one weapon.
  Future<void> _pickSkin(String weapon) async {
    SoundService.instance.play(GameSound.tap);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${weaponName(weapon)} skins',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tap a skin to wear it, or buy a new one.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final sk in _skinOrder(weapon))
                      _skinChip(weapon, sk, changed: () => setSheet(() {})),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheet).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// The small round skin button in the corner of a weapon card.
  Widget _skinButton(String weapon) {
    final on = _save.skinOn(weapon);
    final colour = on == null ? _cyan : kRarityColours[on.rarity]!;
    return Material(
      color: _bg,
      shape: CircleBorder(side: BorderSide(color: colour, width: 2)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _pickSkin(weapon),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(
            Icons.brush_rounded,
            color: colour,
            size: 18,
            semanticLabel: 'Skins',
          ),
        ),
      ),
    );
  }

  Widget _skinCard(String weapon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            weaponName(weapon),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final sk in _skinOrder(weapon))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _skinChip(weapon, sk),
                  ),
              ],
            ),
          ),
        ],
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
        skin: _save.skinOn(primary.id),
        weaponId: primary.id,
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
                skin: _save.skinOn(secondary.id),
                weaponId: secondary.id,
              )
      else
        _lockedSlotCard(),
      _slotCard(
        _save.meleeSlot2 ? 'Melee 1' : 'Melee',
        melee.name,
        melee.look,
        melee.color,
        'Level ${_save.levelOf(melee.id)}',
        () => setState(() => _tab = 2),
        skin: _save.skinOn(melee.id),
        weaponId: melee.id,
      ),
      if (!_save.meleeSlot2)
        _lockedSlotCard(
          slot: 'MELEE 2',
          blurb: 'Carry two melees',
          cost: kSecondMeleePrice,
          onUnlock: _unlockMeleeSlot,
        )
      else if (_save.melee2 == null)
        _slotCard(
          'Melee 2',
          'Tap to choose',
          null,
          Colors.white24,
          'Empty',
          () => setState(() => _tab = 2),
        )
      else
        _slotCard(
          'Melee 2',
          meleeById(_save.melee2!).name,
          meleeById(_save.melee2!).look,
          meleeById(_save.melee2!).color,
          'Level ${_save.levelOf(_save.melee2!)}',
          () => setState(() => _tab = 2),
          skin: _save.skinOn(_save.melee2!),
          weaponId: _save.melee2,
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
    VoidCallback onTap, {
    Skin? skin,
    String? weaponId,
  }) {
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
                  : WeaponIcon(look: look, color: color, size: 76, skin: skin),
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
            if (weaponId != null) _skinButton(weaponId),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  Widget _lockedSlotCard({
    String slot = 'GUN 2',
    String blurb = 'Carry two guns',
    int cost = kSecondSlotPrice,
    VoidCallback? onUnlock,
  }) {
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  blurb,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          _coinButton(cost, onUnlock ?? _unlockSlot, label: 'Unlock'),
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
                leading: WeaponIcon(
                  look: g.look,
                  color: g.color,
                  size: 60,
                  skin: _save.skinOn(g.id),
                ),
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
    required String id,
    required WeaponLook look,
    required Color color,
    required String name,
    required String blurb,
    required List<Widget> stats,
    required bool owned,
    required int level,
    required List<Widget> actions,
  }) {
    final card = Container(
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
              WeaponIcon(
                look: look,
                color: color,
                size: 72,
                skin: _save.skinOn(id),
              ),
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
          Padding(
            // Leave room for the skin button in the corner.
            padding: const EdgeInsets.only(right: 44),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [if (owned) _levelDots(level), ...actions],
            ),
          ),
        ],
      ),
    );
    // Skin button in the bottom corner.
    return Stack(
      children: [
        card,
        Positioned(right: 10, bottom: 20, child: _skinButton(id)),
      ],
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
      id: g.id,
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
      if (_save.meleeSlot2) {
        actions.add(
          _equipChip('Melee 1', _save.melee == m.id, () => _equipMelee(m)),
        );
        actions.add(
          _equipChip('Melee 2', _save.melee2 == m.id, () => _equipMelee(m, 1)),
        );
      } else {
        actions.add(
          _equipChip('Equip', _save.melee == m.id, () => _equipMelee(m)),
        );
      }
    }
    return _itemCard(
      id: m.id,
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

/// A treasure-chest style skin box.
class SkinBoxPicture extends StatelessWidget {
  const SkinBoxPicture({super.key});

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _SkinBoxPainter());
}

class _SkinBoxPainter extends CustomPainter {
  const _SkinBoxPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final ink = Paint()
      ..color = kOutplayInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, w * 0.04);
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, h * 0.38, w * 0.84, h * 0.54),
      Radius.circular(w * 0.06),
    );
    final lid = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.04, h * 0.16, w * 0.92, h * 0.26),
      Radius.circular(w * 0.08),
    );
    canvas.drawRRect(body, Paint()..color = const Color(0xFF7E57C2));
    canvas.drawRRect(body, ink);
    canvas.drawRRect(lid, Paint()..color = const Color(0xFF9575CD));
    canvas.drawRRect(lid, ink);
    final band = Paint()..color = _gold;
    canvas.drawRect(
      Rect.fromLTWH(w * 0.44, h * 0.16, w * 0.12, h * 0.76),
      band,
    );
    final lock = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.44),
      width: w * 0.22,
      height: h * 0.2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(lock, Radius.circular(w * 0.04)),
      band,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          color: kOutplayInk,
          fontSize: h * 0.18,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, lock.center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_SkinBoxPainter old) => false;
}

/// Opens a skin box: skins flash past, then it lands on your prize.
class _SkinBoxDialog extends StatefulWidget {
  final String weapon;
  final Skin skin;
  final bool duplicate;
  final ({WeaponLook look, Color color}) Function(String id) lookOf;
  final VoidCallback onEquip;

  const _SkinBoxDialog({
    required this.weapon,
    required this.skin,
    required this.duplicate,
    required this.lookOf,
    required this.onEquip,
  });

  @override
  State<_SkinBoxDialog> createState() => _SkinBoxDialogState();
}

class _SkinBoxDialogState extends State<_SkinBoxDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..forward();
  final _rnd = Random();
  String _shownWeapon = '';
  Skin _shownSkin = kSkins.first;
  int _lastTick = -1;

  @override
  void initState() {
    super.initState();
    _spin.addListener(() {
      // Flick through skins, slowing down, then stop on the prize.
      final t = Curves.easeOutCubic.transform(_spin.value);
      final tick = (t * 24).floor();
      if (_spin.isCompleted) {
        setState(() {});
      } else if (tick != _lastTick) {
        _lastTick = tick;
        final ids = kWeaponIds;
        setState(() {
          _shownSkin = kSkins[_rnd.nextInt(kSkins.length)];
          _shownWeapon = _shownSkin.onlyFor ?? ids[_rnd.nextInt(ids.length)];
        });
        SoundService.instance.play(GameSound.tap);
      }
    });
    _spin.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        SoundService.instance.play(GameSound.levelComplete);
      }
    });
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _spin.isCompleted;
    final weapon = done ? widget.weapon : _shownWeapon;
    final skin = done ? widget.skin : _shownSkin;
    final l = widget.lookOf(weapon.isEmpty ? widget.weapon : weapon);
    final colour = kRarityColours[skin.rarity]!;
    return AlertDialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colour, width: 3),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            done ? kRarityNames[skin.rarity]!.toUpperCase() : 'Opening…',
            style: TextStyle(
              color: colour,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          WeaponIcon(look: l.look, color: l.color, size: 200, skin: skin),
          const SizedBox(height: 10),
          Text(
            '${skin.name} ${weaponName(weapon.isEmpty ? widget.weapon : weapon)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (done)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                widget.duplicate
                    ? 'You already had this one, so you got '
                          '$kDuplicateRefund coins back.'
                    : 'New skin! It\'s yours to keep.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
        ],
      ),
      actions: done
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              if (!widget.duplicate)
                ElevatedButton(
                  onPressed: () {
                    widget.onEquip();
                    Navigator.of(context).pop();
                  },
                  child: const Text('WEAR IT'),
                ),
            ]
          : null,
    );
  }
}
