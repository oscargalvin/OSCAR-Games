import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../outplay/outplay_net.dart' show LinkEvents, OutplayLink, createLink;

/// Online Pie Party. Whoever makes the room runs the party on their
/// phone (the host) and sends everyone else what is happening; the others
/// just send their stick, THROW and DODGE presses. Up to 5 real players.
class PieNet {
  PieNet._(this.link, this.isHost, this.code);

  static const int maxPlayers = 5;

  final OutplayLink link;
  final bool isHost;
  final String code;
  String myId = '';
  String myName = 'Chef';

  /// Everyone in the room, room maker first: (id, name).
  List<(String, String)> players = [];
  int mode = 0;
  int difficulty = 0;
  bool started = false;
  bool closed = false;

  final List<Map<String, dynamic>> _inbox = [];

  /// Can this device play online at all? (Only in a web browser.)
  static bool get available => createLink() != null;

  static const _letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';

  /// Codes are 4 letters; underneath they're kept apart from Outplay rooms.
  static String _peerCode(String code) => 'pie$code';

  static Future<PieNet> host(String name) async {
    for (var tries = 0; ; tries++) {
      final link = createLink();
      if (link == null) throw 'Online play only works in a web browser.';
      final r = Random();
      final code = List.generate(4, (_) => _letters[r.nextInt(_letters.length)]).join();
      final net = PieNet._(link, true, code)..myName = name;
      final done = Completer<PieNet>();
      link.host(
        _peerCode(code),
        LinkEvents(
          ready: (id) {
            net.myId = id;
            net.players = [(id, name)];
            if (!done.isCompleted) done.complete(net);
          },
          message: net._receive,
          joined: (id) {
            if (net.started || net.players.length >= maxPlayers) {
              net.send({'t': 'full', 'to': id});
              return;
            }
            net.players.add((id, 'Player ${net.players.length + 1}'));
            net.sendLobby();
          },
          left: (id) {
            net.players.removeWhere((p) => p.$1 == id);
            net._inbox.add({'t': 'bye', 'id': id});
            if (!net.started) net.sendLobby();
          },
          error: (e) {
            if (!done.isCompleted) done.completeError(e);
          },
        ),
      );
      try {
        return await done.future.timeout(const Duration(seconds: 15));
      } catch (e) {
        link.close();
        if (e == 'unavailable-id' && tries < 4) continue;
        throw _friendly(e);
      }
    }
  }

  static Future<PieNet> join(String code, String name) async {
    final link = createLink();
    if (link == null) throw 'Online play only works in a web browser.';
    final net = PieNet._(link, false, code.toUpperCase())..myName = name;
    final done = Completer<PieNet>();
    link.join(
      _peerCode(net.code),
      LinkEvents(
        ready: (id) {
          net.myId = id;
          net.send({'t': 'hi', 'id': id, 'name': name});
        },
        message: (text) {
          final m = _decode(text);
          if (m == null) return;
          if (m['t'] == 'full' && m['to'] == net.myId) {
            if (!done.isCompleted) done.completeError('full');
            return;
          }
          if (m['t'] == 'lobby') {
            net._readLobby(m);
            if (!done.isCompleted && net.players.any((p) => p.$1 == net.myId)) {
              done.complete(net);
            }
            return;
          }
          net._inbox.add(m);
        },
        joined: (_) {},
        left: (_) => net._inbox.add({'t': 'hostLeft'}),
        error: (e) {
          if (!done.isCompleted) done.completeError(e);
        },
      ),
    );
    try {
      return await done.future.timeout(const Duration(seconds: 20));
    } catch (e) {
      link.close();
      if (e == 'full') throw 'That party is full or already started.';
      if (e == 'no-link') {
        throw "Found party ${net.code} but couldn't connect. Some Wi-Fi (like "
            'school Wi-Fi) blocks games: try mobile data or the same Wi-Fi.';
      }
      if (e is TimeoutException || e == 'peer-unavailable') {
        throw 'No party with the code ${net.code}. Check the code and try again.';
      }
      throw _friendly(e);
    }
  }

  static String _friendly(Object e) {
    if (e is TimeoutException || e == 'network' || e == 'server-error' || e == 'socket-error') {
      return "Couldn't reach the online server. Check the internet and try again.";
    }
    if (e == 'browser-incompatible') return "This browser can't play online. Try Chrome or Safari.";
    return 'Something went wrong going online ($e).';
  }

  static Map<String, dynamic>? _decode(String text) {
    try {
      final m = jsonDecode(text);
      return m is Map<String, dynamic> ? m : null;
    } catch (_) {
      return null;
    }
  }

  void _receive(String text) {
    final m = _decode(text);
    if (m == null) return;
    if (isHost && m['t'] == 'hi') {
      final id = m['id'];
      final i = players.indexWhere((p) => p.$1 == id);
      if (i >= 0) {
        final name = (m['name'] as String?)?.trim() ?? '';
        players[i] = (players[i].$1, name.isEmpty ? 'Player ${i + 1}' : name.substring(0, min(12, name.length)));
        sendLobby();
      }
      return;
    }
    _inbox.add(m);
  }

  void _readLobby(Map<String, dynamic> m) {
    players = [
      for (final p in (m['players'] as List? ?? const []))
        if (p is List && p.length == 2) ('${p[0]}', '${p[1]}'),
    ];
    mode = (m['mode'] as num?)?.toInt() ?? 0;
    difficulty = (m['diff'] as num?)?.toInt() ?? 0;
  }

  void sendLobby() => send({
    't': 'lobby',
    'players': [for (final p in players) [p.$1, p.$2]],
    'mode': mode,
    'diff': difficulty,
  });

  /// Messages that came in since the last call.
  List<Map<String, dynamic>> take() {
    final out = [..._inbox];
    _inbox.clear();
    return out;
  }

  void send(Map<String, dynamic> m) {
    if (!closed) link.send(jsonEncode(m));
  }

  void close() {
    if (closed) return;
    closed = true;
    link.close();
  }
}
