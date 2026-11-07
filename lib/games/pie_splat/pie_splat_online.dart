import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/game_scaffold.dart';
import 'pie_splat_3d.dart';
import 'pie_splat_game.dart';
import 'pie_splat_net.dart';

/// Online Pie Party: make a room and share its code, or type a
/// friend's code. 1 to 5 real players; bots fill up to 12 people (15 when
/// there are 5 players), and each player leads their own team.
class PieOnlineScreen extends StatefulWidget {
  const PieOnlineScreen({super.key});

  @override
  State<PieOnlineScreen> createState() => _PieOnlineScreenState();
}

class _PieOnlineScreenState extends State<PieOnlineScreen> {
  static String _savedName = '';
  final _name = TextEditingController(text: _savedName);
  final _code = TextEditingController();
  PieNet? _net;
  String? _error;
  bool _busy = false;
  bool _inGame = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(milliseconds: 150), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _net?.close();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _myName {
    final n = _name.text.trim();
    _savedName = n;
    return n.isEmpty ? 'Chef' : n.substring(0, min(12, n.length));
  }

  Future<void> _go(Future<PieNet> Function() connect) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final net = await connect();
      if (!mounted) {
        net.close();
        return;
      }
      setState(() => _net = net);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Guests watch for the host pressing START (or leaving).
  void _check() {
    final net = _net;
    if (net == null || _inGame || !mounted) return;
    if (net.isHost) {
      // Drop anything that came in while waiting (inputs from a last game).
      net.take();
      setState(() {});
      return;
    }
    for (final m in net.take()) {
      if (m['t'] == 'start') {
        final seed = (m['seed'] as num).toInt();
        final ids = [
          for (final p in (m['players'] as List)) ('${(p as List)[0]}', '${p[1]}'),
        ];
        _play(seed, ids, (m['mode'] as num).toInt(), (m['diff'] as num).toInt());
        return;
      }
      if (m['t'] == 'hostLeft') {
        net.close();
        setState(() {
          _net = null;
          _error = 'The room maker left.';
        });
        return;
      }
    }
    setState(() {});
  }

  void _start() {
    final net = _net!;
    final seed = Random().nextInt(1 << 30);
    final players = [...net.players];
    net.started = true;
    net.send({
      't': 'start',
      'seed': seed,
      'players': [for (final p in players) [p.$1, p.$2]],
      'mode': net.mode,
      'diff': net.difficulty,
    });
    _play(seed, players, net.mode, net.difficulty);
  }

  Future<void> _play(int seed, List<(String, String)> players, int mode, int diff) async {
    final net = _net!;
    net.take();
    setState(() => _inGame = true);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PieSplatGameScreen(
          seed: seed,
          setup: PieSetup.online(players.length, mode, diff),
          net: net,
          humans: players,
        ),
      ),
    );
    if (!mounted) return;
    net.started = false;
    if (net.isHost) net.sendLobby();
    setState(() => _inGame = false);
  }

  Widget _bigButton(String label, Color color, VoidCallback? onTap, {Key? key}) => GestureDetector(
    key: key,
    onTap: onTap,
    child: Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kInk3, width: 3),
          boxShadow: const [BoxShadow(color: kInk3, offset: Offset(0, 4))],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900),
        ),
      ),
    ),
  );

  InputDecoration _box(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white38),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.08),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  );

  @override
  Widget build(BuildContext context) {
    final net = _net;
    return GameScaffold(
      title: 'Play online',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
        child: net == null ? _connect() : _room(net),
      ),
    );
  }

  Widget _connect() {
    if (!PieNet.available) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Text(
          'Online play works on the Oscar Games website in a web browser.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Play with up to 5 friends! Everyone gets their own team, and '
          'computer players fill it up to 12 people (15 with 5 players).',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 15),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          maxLength: 12,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: _box('Your name'),
        ),
        const SizedBox(height: 8),
        _bigButton('MAKE A ROOM', const Color(0xFFFF4081),
            _busy ? null : () => _go(() => PieNet.host(_myName)), key: const Key('pie_host')),
        const SizedBox(height: 24),
        const Text('Or join a friend:', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          maxLength: 4,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white, fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.w900),
          textAlign: TextAlign.center,
          decoration: _box('CODE'),
        ),
        _bigButton('JOIN', const Color(0xFF40C4FF), _busy
            ? null
            : () {
                final code = _code.text.trim().toUpperCase();
                if (code.length != 4) {
                  setState(() => _error = 'Codes are 4 letters long.');
                  return;
                }
                _go(() => PieNet.join(code, _myName));
              }, key: const Key('pie_join')),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 15)),
          ),
      ],
    );
  }

  Widget _chip(String label, bool on, VoidCallback? tap) => GestureDetector(
    onTap: tap == null ? null : () => setState(tap),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: on ? const Color(0xFFFFE082) : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: on ? kInk3 : Colors.white24, width: on ? 3 : 1.5),
      ),
      child: Text(label, style: TextStyle(color: on ? kInk3 : Colors.white, fontWeight: FontWeight.w900)),
    ),
  );

  Widget _room(PieNet net) {
    final n = net.players.length;
    final host = net.isHost;
    void setMode(int m) {
      net.mode = m;
      net.sendLobby();
    }

    void setDiff(int d) {
      net.difficulty = d;
      net.sendLobby();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Room code', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
        Text(
          net.code,
          key: const Key('pie_room_code'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFFFE082), fontSize: 52, fontWeight: FontWeight.w900, letterSpacing: 10),
        ),
        Text(
          host ? 'Tell your friends this code!' : 'Waiting for the room maker to start...',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        const SizedBox(height: 16),
        Text('Players ($n of ${PieNet.maxPlayers})',
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        for (var i = 0; i < n; i++)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: n >= 2 ? kTeamColors[i] : Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    net.players[i].$2 + (net.players[i].$1 == net.myId ? ' (you)' : '') + (i == 0 ? ' 👑' : ''),
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          n >= 2
              ? '$n teams, ${n == 5 ? 15 : 12} people. Bots fill up the teams.'
              : 'Everyone vs everyone with 12 people (bots fill in).',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 14),
        const Text('Game mode', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in PieMode.values)
              _chip(m.title, net.mode == m.index, host ? () => setMode(m.index) : null),
          ],
        ),
        const SizedBox(height: 12),
        const Text('How hard?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, name) in const [(0, 'Easy'), (1, 'Medium'), (2, 'Hard')])
              _chip(name, net.difficulty == i, host ? () => setDiff(i) : null),
          ],
        ),
        const SizedBox(height: 20),
        if (host) _bigButton('START THE PARTY!', const Color(0xFFFF4081), _start, key: const Key('pie_online_start')),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            net.close();
            setState(() => _net = null);
          },
          child: const Text('Leave room', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}
