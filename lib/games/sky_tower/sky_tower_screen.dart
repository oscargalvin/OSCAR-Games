import 'package:flutter/material.dart';

import 'sky_tower_game.dart';
import 'sky_tower_sim.dart';

/// Sky Tower's menu: your best tower, coins, block colours and PLAY.
class SkyTowerScreen extends StatefulWidget {
  const SkyTowerScreen({super.key});

  @override
  State<SkyTowerScreen> createState() => _SkyTowerScreenState();
}

class _SkyTowerScreenState extends State<SkyTowerScreen> {
  final _save = TowerSave.instance;
  bool _loaded = false;

  static const _bg = Color(0xFF1A2350);
  static const _panel = Color(0xFF26306A);
  static const _yellow = Color(0xFFFFD54F);

  @override
  void initState() {
    super.initState();
    _save.load().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  Future<void> _play() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SkyTowerGameScreen(
          theme: _save.theme,
          onFinish: (floors, coins) {
            _save
              ..coins += coins
              ..games += 1;
            if (floors > _save.best) _save.best = floors;
            _save.save();
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _tapTheme(TowerTheme t) {
    if (_save.themes.contains(t.id)) {
      setState(() => _save.theme = t.id);
      _save.save();
      return;
    }
    if (_save.coins < t.price) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You need ${t.price - _save.coins} more coins. '
            'Build taller towers to earn them!',
          ),
        ),
      );
      return;
    }
    setState(() {
      _save
        ..coins -= t.price
        ..themes.add(t.id)
        ..theme = t.id;
    });
    _save.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text(
          'Sky Tower',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                const Icon(Icons.monetization_on_rounded, color: _yellow),
                const SizedBox(width: 4),
                Text(
                  '${_save.coins}',
                  style: const TextStyle(
                    color: _yellow,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  _intro(),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: _play,
                      icon: const Icon(Icons.play_arrow_rounded, size: 30),
                      label: const Text(
                        'PLAY',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
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
                  const Text(
                    'BLOCK COLOURS',
                    style: TextStyle(
                      color: _yellow,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final t in kThemes) _themeTile(t),
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
        const Icon(Icons.apartment_rounded, color: _yellow, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Build a tower up to space!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Best: ${_save.best} floors  •  ${skyName(_save.best)}',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _themeTile(TowerTheme t) {
    final owned = _save.themes.contains(t.id);
    final using = _save.theme == t.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _tapTheme(t),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: using ? Border.all(color: _yellow, width: 2) : null,
            ),
            child: Row(
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    width: 14,
                    height: 30,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: towerColour(t.id, i * 4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        t.blurb,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                if (using)
                  const Text(
                    'USING',
                    style: TextStyle(
                      color: _yellow,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                else if (owned)
                  const Text(
                    'PICK',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                else
                  Row(
                    children: [
                      const Icon(
                        Icons.monetization_on_rounded,
                        color: _yellow,
                        size: 18,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${t.price}',
                        style: const TextStyle(
                          color: _yellow,
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
      'A block slides over your tower. Tap (or press Space) to drop it. '
      'Any bit hanging over the edge gets chopped off, so your blocks get '
      'smaller! Drop it right on top for a PERFECT, and get 3 perfects in a '
      'row to make your blocks bigger again. Climb past the city, through '
      'the clouds and up into space. You get 1 coin for every floor and 2 '
      'extra for every perfect.',
      style: TextStyle(color: Colors.white70, height: 1.4),
    ),
  );
}
