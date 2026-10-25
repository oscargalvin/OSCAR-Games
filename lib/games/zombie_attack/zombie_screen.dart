import 'package:flutter/material.dart';

import '../../services/sound_service.dart';
import '../outplay/outplay_net.dart';
import 'zombie_data.dart';
import 'zombie_game.dart';
import 'zombie_net.dart';
import 'zombie_sim.dart';

const _bg = Color(0xFF13241A);
const _panel = Color(0xFF1F3A29);
const _green = Color(0xFF69F0AE);
const _gold = Color(0xFFFFD54F);

/// Zombie Attack menu: pick a map, a level and a gun, then survive.
class ZombieScreen extends StatefulWidget {
  /// How to go online (swapped for pretend links in tests).
  final OutplayLink? Function() makeLink;
  final OutplayDirectory? Function() makeDirectory;

  const ZombieScreen({
    super.key,
    this.makeLink = createLink,
    this.makeDirectory = createDirectory,
  });

  @override
  State<ZombieScreen> createState() => _ZombieScreenState();
}

class _ZombieScreenState extends State<ZombieScreen> {
  final _save = ZombieSave.instance;
  ZombieMap _map = ZombieMap.town;
  int _level = 1;
  bool _versus = false; // 2 players: zombie vs human instead of teaming up
  bool _beZombie = false; // in zombie vs human, you play the zombies
  String? _busy; // what we're waiting for online

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

  Future<bool> _askName() async {
    if (_save.name.trim().isNotEmpty) return true;
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a player name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: 'Your name'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    final clean = (name ?? '').trim();
    if (clean.isEmpty) return false;
    setState(() => _save.name = clean);
    await _save.save();
    return true;
  }

  Future<String?> _askCode() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Type your friend's room code"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 4,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'ABCD'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('JOIN'),
          ),
        ],
      ),
    );
    final clean = (code ?? '').trim().toUpperCase();
    return clean.length == 4 ? clean : null;
  }

  void _say(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// 2 players online. [code] joins a friend's room; [friends] makes a room
  /// with a code to share; otherwise it looks for someone who picked the
  /// same game, or waits for one.
  Future<void> _playOnline({bool friends = false, String? code}) async {
    if (!await _askName() || !mounted) return;
    final make = widget.makeLink;
    final dir = widget.makeDirectory();
    if (make() == null || dir == null) {
      _say('2 players only works on the website.');
      return;
    }
    final setup = ZombieRoomSetup(
      _versus ? ZombieMode.versus : ZombieMode.coop,
      _map,
      _level,
      hostIsZombie: _versus && _beZombie,
    );
    OutplayRoom? room;
    try {
      if (code != null) {
        setState(() => _busy = 'Joining $code...');
        room = await OutplayRoom.join(() => make()!, code);
        if (!isZombieRoom(room.mapId)) {
          room.close();
          throw 'That code is for a different game, not Zombie Attack.';
        }
      } else if (friends) {
        setState(() => _busy = 'Making a room...');
        room = await OutplayRoom.host(
          () => make()!,
          setup.roomName,
          teamSize: 1,
          showCode: true,
        );
      } else {
        setState(() => _busy = 'Looking for a player...');
        // Someone waiting for the same game, playing the other side.
        final want = ZombieRoomSetup(
          setup.mode,
          _map,
          _level,
          hostIsZombie: _versus && !_beZombie,
        ).roomName;
        var rooms = const <RoomInfo>[];
        dir.browse((r) => rooms = r);
        await Future<void>.delayed(const Duration(milliseconds: 2500));
        dir.stopBrowse();
        for (final r in rooms.where(
          (r) => r.mapId == want && !r.friends && !r.playing,
        )) {
          try {
            room = await OutplayRoom.join(() => make()!, r.code);
            break;
          } catch (_) {
            // Gone or full: try the next one.
          }
        }
        room ??= await OutplayRoom.host(
          () => make()!,
          setup.roomName,
          teamSize: 1,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = null);
        _say('$e');
      }
      return;
    }
    if (!mounted) {
      room.close();
      return;
    }
    setState(() => _busy = null);
    final session = ZombieSession(
      room: room,
      lister: room.isHost && !room.showCode ? dir : null,
      myName: _save.name.trim(),
      myGun: _save.gun,
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ZombieGameScreen(
          map: session.setup.map,
          level: session.setup.level,
          gunId: _save.gun,
          session: session,
        ),
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
            _heading('2 PLAYERS'),
            _twoPlayers(),
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

  Widget _choice(String label, bool on, VoidCallback tap) => Expanded(
    child: ChoiceChip(
      label: SizedBox(
        width: double.infinity,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: on ? Colors.black : Colors.white,
          ),
        ),
      ),
      selected: on,
      showCheckmark: false,
      selectedColor: _green,
      backgroundColor: _bg,
      onSelected: (_) => setState(tap),
    ),
  );

  /// Play with a friend on another phone or tablet.
  Widget _twoPlayers() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _choice('Team up', !_versus, () => _versus = false),
            const SizedBox(width: 8),
            _choice('Zombie vs Human', _versus, () => _versus = true),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _versus
              ? 'One of you is the human. The other is the zombies: send '
                    'zombies in with brains, then become the Zombie King at '
                    'wave $kKingArrives!'
              : 'Two humans against the zombies, on the map and level you '
                    'picked above.',
          style: const TextStyle(color: Colors.white70),
        ),
        if (_versus) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _choice('Be the human', !_beZombie, () => _beZombie = false),
              const SizedBox(width: 8),
              _choice('Be the zombies', _beZombie, () => _beZombie = true),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (_busy != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _busy!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _green),
            ),
          )
        else ...[
          ElevatedButton.icon(
            onPressed: () => _playOnline(),
            icon: const Icon(Icons.public_rounded),
            label: const Text('FIND A PLAYER'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7B1FA2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _playOnline(friends: true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('MAKE A ROOM'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final code = await _askCode();
                    if (code != null) await _playOnline(code: code);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('JOIN A CODE'),
                ),
              ),
            ],
          ),
        ],
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
