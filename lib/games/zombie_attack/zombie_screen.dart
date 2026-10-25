import 'package:flutter/material.dart';

import '../../services/sound_service.dart';
import 'zombie_data.dart';
import 'zombie_game.dart';

const _bg = Color(0xFF13241A);
const _panel = Color(0xFF1F3A29);
const _green = Color(0xFF69F0AE);
const _gold = Color(0xFFFFD54F);

/// Zombie Attack menu: pick a map, a level and a gun, then survive.
class ZombieScreen extends StatefulWidget {
  const ZombieScreen({super.key});

  @override
  State<ZombieScreen> createState() => _ZombieScreenState();
}

class _ZombieScreenState extends State<ZombieScreen> {
  final _save = ZombieSave.instance;
  ZombieMap _map = ZombieMap.town;
  int _level = 1;

  @override
  void initState() {
    super.initState();
    _save.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _play() async {
    SoundService.instance.play(GameSound.tap);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ZombieGameScreen(map: _map, level: _level, gunId: _save.gun),
      ),
    );
    if (mounted) setState(() {});
  }

  void _tapGun(Gun g) {
    if (_save.guns.contains(g.id)) {
      setState(() => _save.gun = g.id);
      _save.save();
      return;
    }
    if (_save.coins < g.price) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You need ${g.price - _save.coins} more coins. '
            'Survive more waves to earn them!',
          ),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Buy ${g.name}?'),
        content: Text('${g.blurb}\n\nIt costs ${g.price} coins.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('NO'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _save.coins -= g.price;
                _save.guns.add(g.id);
                _save.gun = g.id;
              });
              _save.save();
              SoundService.instance.play(GameSound.win);
            },
            child: const Text('BUY'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text(
          'Zombie Attack',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(
              children: [
                const Icon(Icons.monetization_on_rounded, color: _gold),
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _intro(),
            const SizedBox(height: 18),
            _heading('MAP'),
            for (final m in ZombieMap.values) _mapTile(m),
            const SizedBox(height: 14),
            _heading('LEVEL'),
            _levels(),
            const SizedBox(height: 18),
            SizedBox(
              height: 58,
              child: ElevatedButton.icon(
                onPressed: _play,
                icon: const Icon(Icons.play_arrow_rounded, size: 30),
                label: const Text(
                  'PLAY',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF43A047),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            _heading('GUN SHOP'),
            for (final g in kGuns)
              if (!g.dropOnly || _save.guns.contains(g.id)) _gunTile(g),
            const SizedBox(height: 14),
            _howTo(),
          ],
        ),
      ),
    );
  }

  Widget _intro() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const Icon(Icons.coronavirus_rounded, color: _green, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Survive the zombie waves!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Best: wave ${_save.bestWave}  •  '
                '${_save.kills} zombies zapped',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: _green,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
      ),
    ),
  );

  Widget _mapTile(ZombieMap m) {
    final on = m == _map;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: on ? const Color(0xFF2E5B3E) : _panel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _map = m),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: on ? _green : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: m.ground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: m.block, width: 4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        m.blurb,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                if (on) const Icon(Icons.check_circle_rounded, color: _green),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _levels() => Row(
    children: [
      for (var i = 0; i < kZombieLevels.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: ChoiceChip(
            label: SizedBox(
              width: double.infinity,
              child: Text(
                kZombieLevels[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: i == _level ? Colors.black : Colors.white,
                ),
              ),
            ),
            selected: i == _level,
            showCheckmark: false,
            selectedColor: _green,
            backgroundColor: _panel,
            onSelected: (_) => setState(() => _level = i),
          ),
        ),
      ],
    ],
  );

  Widget _gunTile(Gun g) {
    final owned = _save.guns.contains(g.id);
    final using = _save.gun == g.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _tapGun(g),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: g.colour.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.flash_on_rounded, color: g.colour),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        g.blurb,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (using)
                  const Text(
                    'USING',
                    style: TextStyle(
                      color: _green,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                else if (owned)
                  const Text(
                    'EQUIP',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.monetization_on_rounded,
                        color: _gold,
                        size: 18,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${g.price}',
                        style: const TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _howTo() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Text(
      'HOW TO PLAY\n'
      'Phone or tablet: drag on the left to run and drag on the right to '
      'turn the camera. Hold the red SHOOT button to shoot and tap the '
      'green button to throw a grenade.\n'
      'Computer: WASD to run, drag the mouse (or press Q and E) to turn, '
      'hold Space or the SHOOT button to shoot, G for a grenade.\n'
      'Every 5th wave the Zombie King comes. Grab first-aid kits to heal!\n'
      'Zombies holding a sword drop it when you beat them. Grab it to use '
      'it for that game, and there is a 5% chance you get to keep it!\n'
      'Each corner of the map is a green safe zone: zombies cannot get in, '
      'but you cannot shoot from it either.',
      style: TextStyle(color: Colors.white70, height: 1.4),
    ),
  );
}
