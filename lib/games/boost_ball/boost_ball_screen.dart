import 'dart:math';

import 'package:flutter/material.dart';

import '../../services/sound_service.dart';
import '../outplay/outplay_net.dart';
import 'boost_ball_3d.dart';
import 'boost_ball_data.dart';
import 'boost_ball_game.dart';
import 'boost_ball_net.dart';

const Color _bg = Color(0xFF0E1A2B);
const Color _card = Color(0xFF1B2A41);
const Color _gold = Color(0xFFFFC93C);

/// Boost Ball garage: pick a match, then buy and paint your car.
class BoostBallScreen extends StatefulWidget {
  /// How to go online (swapped for pretend links in tests).
  final OutplayLink? Function() makeLink;
  final OutplayDirectory? Function() makeDirectory;

  const BoostBallScreen({
    super.key,
    this.makeLink = createLink,
    this.makeDirectory = createDirectory,
  });

  @override
  State<BoostBallScreen> createState() => _BoostBallScreenState();
}

class _BoostBallScreenState extends State<BoostBallScreen> {
  final _save = BoostBallSave.instance;
  bool _loaded = false;
  int _size = 1;
  int _difficulty = 1;
  BoostMode _mode = BoostMode.classic;
  bool _people = false; // play against real people instead of bots
  String? _busy; // what we're waiting for online
  final _rnd = Random();
  double _spinAngle = 0.7; // drag the car in the garage to spin it

  @override
  void initState() {
    super.initState();
    _save.load().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  bool get _free => _mode == BoostMode.freePlay;
  bool get _online => _people && !_free;

  Future<void> _play() async {
    SoundService.instance.play(GameSound.tap);
    if (_online) return _playOnline();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoostBallGameScreen(
          teamSize: _size,
          difficulty: _difficulty,
          mode: _mode,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Other people see your name online, so ask for one the first time.
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
    _save.name = clean;
    await _save.save();
    return true;
  }

  Future<String?> _askCode() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Type your friend's code"),
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

  /// Finds real people to play: join a room waiting for the same match, or
  /// make one. [friends] makes a room with a code to share; [code] joins one.
  Future<void> _playOnline({bool friends = false, String? code}) async {
    if (!await _askName() || !mounted) return;
    final make = widget.makeLink;
    final dir = widget.makeDirectory();
    if (make() == null || dir == null) {
      _say('Online play only works on the website.');
      return;
    }
    final map = boostRoomMap(_mode);
    OutplayRoom? room;
    try {
      if (code != null) {
        setState(() => _busy = 'Joining $code...');
        room = await OutplayRoom.join(() => make()!, code);
        if (!isBoostRoom(room.mapId)) {
          room.close();
          throw 'That code is for an Outplay game, not Boost Ball.';
        }
      } else if (friends) {
        setState(() => _busy = 'Making a room...');
        room = await OutplayRoom.host(
          () => make()!,
          map,
          teamSize: _size,
          showCode: true,
        );
      } else {
        setState(() => _busy = 'Looking for players...');
        var rooms = const <RoomInfo>[];
        dir.browse((r) => rooms = r);
        await Future<void>.delayed(
          Duration(milliseconds: 2000 + _rnd.nextInt(1000)),
        );
        dir.stopBrowse();
        final open =
            rooms
                .where(
                  (r) =>
                      r.mapId == map &&
                      r.teamSize == _size &&
                      !r.friends &&
                      !r.playing &&
                      r.players < _size * 2,
                )
                .toList()
              ..sort((a, b) => b.players.compareTo(a.players));
        for (final r in open.take(2)) {
          try {
            room = await OutplayRoom.join(() => make()!, r.code);
            break;
          } catch (_) {
            // Gone or full: try the next one.
          }
        }
        room ??= await OutplayRoom.host(() => make()!, map, teamSize: _size);
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
    final session = BoostBallSession(
      room: room,
      lister: room.isHost && !room.showCode ? dir : null,
      myName: _save.name.trim(),
      myCar: carById(_save.car),
      myColour: _save.colour,
    );
    final again = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoostBallGameScreen(
          teamSize: session.teamSize,
          mode: session.mode,
          session: session,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (again == kPlayAgainOnline) await _playOnline(friends: friends);
  }

  void _buy(CarSpec car) {
    if (_save.coins < car.price) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'You need ${car.price - _save.coins} more coins. '
              'Win matches to earn coins!',
            ),
          ),
        );
      return;
    }
    setState(() {
      _save.coins -= car.price;
      _save.cars.add(car.id);
      _save.car = car.id;
    });
    SoundService.instance.play(GameSound.levelComplete);
    _save.save();
  }

  /// Buys the VIP pass: 7 random cars you don't have yet.
  Future<void> _buyVip() async {
    final missing = kCars.where((c) => !_save.cars.contains(c.id)).toList();
    if (missing.isEmpty) {
      _say('You already have every car!');
      return;
    }
    if (_save.coins < kVipPrice) {
      _say(
        'You need ${kVipPrice - _save.coins} more coins. '
        'Win matches to earn coins!',
      );
      return;
    }
    missing.shuffle(_rnd);
    final won = missing.take(kVipCars).toList();
    setState(() {
      _save.coins -= kVipPrice;
      _save.vip = true;
      _save.cars.addAll(won.map((c) => c.id));
    });
    SoundService.instance.play(GameSound.levelComplete);
    await _save.save();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _card,
        title: const Text(
          'VIP PASS!',
          style: TextStyle(color: _gold, fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You got ${won.length} new cars:',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            for (final c in won)
              Text(
                c.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('AWESOME'),
          ),
        ],
      ),
    );
  }

  Widget _vipCard() {
    final missing = kCars.where((c) => !_save.cars.contains(c.id)).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF4A148C), Color(0xFFB8860B)],
        ),
        border: Border.all(color: _gold, width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium_rounded, color: _gold, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VIP PASS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  _save.vip
                      ? 'You are a VIP!'
                      : '$kVipCars random cars you don\'t have yet',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (_save.vip || missing == 0)
            const Chip(
              label: Text('VIP'),
              backgroundColor: _gold,
              labelStyle: TextStyle(fontWeight: FontWeight.w900),
            )
          else
            ElevatedButton.icon(
              onPressed: _buyVip,
              style: ElevatedButton.styleFrom(
                backgroundColor: _save.coins >= kVipPrice
                    ? _gold
                    : Colors.white24,
                foregroundColor: Colors.black87,
              ),
              icon: const Icon(Icons.monetization_on_rounded, size: 18),
              label: const Text('$kVipPrice'),
            ),
        ],
      ),
    );
  }

  void _pick(CarSpec car) {
    setState(() => _save.car = car.id);
    SoundService.instance.play(GameSound.place);
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
          'BOOST BALL',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3),
        ),
        centerTitle: true,
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
          : _busy != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: kBlueTeam),
                  const SizedBox(height: 14),
                  Text(
                    _busy!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            )
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      _hero(),
                      const SizedBox(height: 14),
                      _section('Game mode'),
                      _modes(),
                      if (!_free) ...[
                        const SizedBox(height: 10),
                        _section('Match'),
                        _choices(
                          const ['1v1', '2v2', '3v3'],
                          _size - 1,
                          (i) => _size = i + 1,
                        ),
                        const SizedBox(height: 10),
                        _section('Play against'),
                        _choices(
                          const ['Bots', 'People'],
                          _people ? 1 : 0,
                          (i) => _people = i == 1,
                        ),
                      ],
                      if (!_free && !_people) ...[
                        const SizedBox(height: 10),
                        _section('Bots'),
                        _choices(
                          kDifficultyNames,
                          _difficulty,
                          (i) => _difficulty = i,
                          colours: const [
                            Color(0xFF66BB6A),
                            Color(0xFFFFB300),
                            Color(0xFFE53935),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 58,
                        child: ElevatedButton.icon(
                          onPressed: _play,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kBlueTeam,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: Icon(
                            _online
                                ? Icons.public_rounded
                                : Icons.sports_soccer_rounded,
                          ),
                          label: Text(
                            _free
                                ? 'START FREE PLAY'
                                : _online
                                ? 'FIND PLAYERS ${_size}v$_size'
                                : 'PLAY ${_size}v$_size',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      if (_online) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _playOnline(friends: true),
                                icon: const Icon(Icons.group_add_rounded),
                                label: const Text('MAKE A ROOM'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final code = await _askCode();
                                  if (code != null) {
                                    await _playOnline(code: code);
                                  }
                                },
                                icon: const Icon(Icons.vpn_key_rounded),
                                label: const Text('ENTER CODE'),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        _free
                            ? 'Hardest shot ever: ${_save.bestKph} KPH'
                            : 'Win to earn '
                                  '${kWinCoins[_online ? 1 : _difficulty]} '
                                  'coins · ${_save.wins} wins · '
                                  'hardest shot ${_save.bestKph} KPH',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 18),
                      _section('Paint'),
                      _paints(),
                      const SizedBox(height: 14),
                      _section('Garage'),
                      _vipCard(),
                      for (final car in kCars) _carCard(car),
                      const SizedBox(height: 8),
                      _howTo(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _hero() {
    return GestureDetector(
      onHorizontalDragUpdate: (d) =>
          setState(() => _spinAngle -= d.delta.dx / 80),
      child: Container(
        height: 170,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: CarShowcase(
                  carById(_save.car).body,
                  kCarColours[_save.colour],
                  angle: _spinAngle,
                ),
              ),
            ),
            const Positioned(
              right: 12,
              bottom: 12,
              child: Row(
                children: [
                  Icon(Icons.swipe_rounded, color: Colors.white54, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'Swipe to spin',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 14,
              bottom: 10,
              child: Text(
                carById(_save.car).name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in BoostMode.values)
              ChoiceChip(
                label: Text(m.title),
                selected: m == _mode,
                onSelected: (_) {
                  SoundService.instance.play(GameSound.tap);
                  setState(() => _mode = m);
                },
                selectedColor: kBlueTeam,
                backgroundColor: _card,
                showCheckmark: false,
                labelStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(_mode.blurb, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Colors.white54,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
        fontSize: 12,
      ),
    ),
  );

  Widget _choices(
    List<String> names,
    int selected,
    void Function(int) onPick, {
    List<Color>? colours,
  }) {
    return Row(
      children: [
        for (var i = 0; i < names.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < names.length - 1 ? 8 : 0),
              child: GestureDetector(
                onTap: () {
                  SoundService.instance.play(GameSound.tap);
                  setState(() => onPick(i));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? (colours?[i] ?? kBlueTeam) : _card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (colours?[i] ?? kBlueTeam).withValues(alpha: 0.7),
                      width: 2,
                    ),
                  ),
                  child: Text(
                    names[i].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _paints() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < kCarColours.length; i++)
          GestureDetector(
            onTap: () {
              setState(() => _save.colour = i);
              _save.save();
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: kCarColours[i],
                shape: BoxShape.circle,
                border: Border.all(
                  color: i == _save.colour ? Colors.white : Colors.white24,
                  width: i == _save.colour ? 4 : 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _carCard(CarSpec car) {
    final owned = _save.cars.contains(car.id);
    final using = _save.car == car.id;
    Widget stat(String name, double value) => Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            name,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value.clamp(0.05, 1),
              minHeight: 5,
              backgroundColor: Colors.white10,
              color: kBlueTeam,
            ),
          ),
        ),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: using ? kBlueTeam : Colors.white12,
          width: using ? 3 : 1.5,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            height: 76,
            child: CustomPaint(
              painter: CarShowcase(
                car.body,
                owned ? kCarColours[_save.colour] : const Color(0xFF616161),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  car.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  car.blurb,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                stat('Speed', (car.speed - 17) / 9),
                const SizedBox(height: 3),
                stat('Power', (car.hit - 0.7) / 0.7),
                const SizedBox(height: 3),
                stat('Jump', (car.jump - 9) / 7),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: using
                      ? const Chip(
                          label: Text('DRIVING'),
                          backgroundColor: kBlueTeam,
                          labelStyle: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : owned
                      ? OutlinedButton(
                          onPressed: () => _pick(car),
                          child: const Text('Drive it'),
                        )
                      : ElevatedButton.icon(
                          onPressed: () => _buy(car),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _save.coins >= car.price
                                ? _gold
                                : Colors.white24,
                            foregroundColor: Colors.black87,
                          ),
                          icon: const Icon(
                            Icons.monetization_on_rounded,
                            size: 18,
                          ),
                          label: Text('${car.price}'),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _howTo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        'How to play: drag on the left side, up to go and sideways to steer. '
        'Hold BOOST to go faster. Tap JUMP to jump, and tap it again in the '
        'air to flip into the ball for a super hit. Drive over the orange '
        'pads to fill up your boost. Ram an enemy at full boost to demolish '
        'them! Score more goals than orange before the clock runs out.',
        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
      ),
    );
  }
}
