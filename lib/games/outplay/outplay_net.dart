import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'outplay_net_stub.dart'
    if (dart.library.js_interop) 'outplay_net_web.dart'
    as platform;

/// What a link tells the game about.
class LinkEvents {
  final void Function(String myId) ready;
  final void Function(String text) message;
  final void Function(String id) joined;
  final void Function(String id) left;
  final void Function(String error) error;

  const LinkEvents({
    required this.ready,
    required this.message,
    required this.joined,
    required this.left,
    required this.error,
  });
}

/// A connection to other players. Whoever makes the room is the hub and
/// passes every message on to everyone else.
abstract class OutplayLink {
  void host(String code, LinkEvents events);
  void join(String code, LinkEvents events);
  void send(String text);
  void close();
}

/// The real link in a browser, or null where online play can't work.
OutplayLink? createLink() => platform.createLink();

const _codeLetters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';

String newRoomCode([Random? rnd]) {
  final r = rnd ?? Random();
  return List.generate(
    4,
    (_) => _codeLetters[r.nextInt(_codeLetters.length)],
  ).join();
}

/// One online game room, made or joined from the Duel Zone.
class OutplayRoom {
  final OutplayLink link;
  final bool isHost;
  final String code;
  String myId = '';
  String mapId;
  bool started = false;

  /// For someone joining late: how far into the game it already is.
  double joinClock = 0;

  final Stopwatch _sinceStart = Stopwatch();
  final List<Map<String, dynamic>> _inbox = [];
  bool _closed = false;

  OutplayRoom._(this.link, this.isHost, this.code, this.mapId);

  /// Makes a room and waits until other players can find it.
  static Future<OutplayRoom> host(
    OutplayLink Function() makeLink,
    String mapId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    for (var tries = 0; ; tries++) {
      final link = makeLink();
      final room = OutplayRoom._(link, true, newRoomCode(), mapId);
      final done = Completer<OutplayRoom>();
      link.host(
        room.code,
        LinkEvents(
          ready: (id) {
            room.myId = id;
            if (!done.isCompleted) done.complete(room);
          },
          message: room._receive,
          joined: (id) => room.send({
            't': 'welcome',
            'map': room.mapId,
            'started': room.started,
            'clock': room._sinceStart.elapsedMilliseconds / 1000,
          }),
          left: (id) => room._receive(jsonEncode({'t': 'bye', 'id': id})),
          error: (e) {
            if (!done.isCompleted) done.completeError(e);
          },
        ),
      );
      try {
        return await done.future.timeout(timeout);
      } catch (e) {
        link.close();
        // Someone else already has that code: pick another.
        if (e == 'unavailable-id' && tries < 4) continue;
        throw _friendly(e);
      }
    }
  }

  /// Joins a friend's room by its code and waits to hear which map it is.
  static Future<OutplayRoom> join(
    OutplayLink Function() makeLink,
    String code, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final link = makeLink();
    final room = OutplayRoom._(link, false, code.toUpperCase(), '');
    final done = Completer<OutplayRoom>();
    link.join(
      room.code,
      LinkEvents(
        ready: (id) => room.myId = id,
        message: (text) {
          final m = _decode(text);
          if (m == null) return;
          if (m['t'] == 'welcome' && !done.isCompleted) {
            room.mapId = m['map'] as String;
            room.started = m['started'] == true;
            room.joinClock = (m['clock'] as num?)?.toDouble() ?? 0;
            done.complete(room);
            return;
          }
          if (done.isCompleted) room._inbox.add(m);
        },
        joined: (_) {},
        left: (_) => room._inbox.add({'t': 'hostLeft'}),
        error: (e) {
          if (!done.isCompleted) done.completeError(e);
        },
      ),
    );
    try {
      return await done.future.timeout(timeout);
    } catch (e) {
      link.close();
      if (e is TimeoutException || e == 'peer-unavailable') {
        throw 'No room with the code ${room.code}. Check the code and try again.';
      }
      throw _friendly(e);
    }
  }

  static String _friendly(Object e) {
    if (e is TimeoutException) {
      return "Couldn't reach the online server. Check the internet and try again.";
    }
    if (e == 'network' || e == 'server-error' || e == 'socket-error') {
      return "Couldn't reach the online server. Check the internet and try again.";
    }
    if (e == 'browser-incompatible') {
      return "This browser can't play online. Try Chrome or Safari.";
    }
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
    if (m != null) _inbox.add(m);
  }

  /// Messages that came in since the last call.
  List<Map<String, dynamic>> takeMessages() {
    final out = [..._inbox];
    _inbox.clear();
    return out;
  }

  void send(Map<String, dynamic> m) {
    if (!_closed) link.send(jsonEncode(m));
  }

  /// The host starts the game for everyone.
  void start() {
    started = true;
    _sinceStart
      ..reset()
      ..start();
    send({'t': 'start'});
  }

  void close() {
    if (_closed) return;
    _closed = true;
    link.close();
  }
}

/// Links that talk to each other inside one app, for tests.
class LoopbackHub {
  final Map<String, LoopbackLink> _rooms = {};
  int _next = 0;

  OutplayLink makeLink() => LoopbackLink._(this);
}

class LoopbackLink implements OutplayLink {
  final LoopbackHub hub;
  LinkEvents? _events;
  String id = '';
  LoopbackLink? _host;
  final List<LoopbackLink> _guests = [];

  LoopbackLink._(this.hub);

  @override
  void host(String code, LinkEvents events) {
    _events = events;
    if (hub._rooms.containsKey(code)) {
      events.error('unavailable-id');
      return;
    }
    id = 'peer${hub._next++}';
    hub._rooms[code] = this;
    events.ready(id);
  }

  @override
  void join(String code, LinkEvents events) {
    _events = events;
    final h = hub._rooms[code];
    if (h == null) {
      events.error('peer-unavailable');
      return;
    }
    id = 'peer${hub._next++}';
    _host = h;
    h._guests.add(this);
    events.ready(id);
    h._events?.joined(id);
  }

  @override
  void send(String text) {
    if (_host != null) {
      for (final g in _host!._guests) {
        if (!identical(g, this)) g._events?.message(text);
      }
      _host!._events?.message(text);
    } else {
      for (final g in _guests) {
        g._events?.message(text);
      }
    }
  }

  @override
  void close() {
    final h = _host;
    if (h != null) {
      h._guests.remove(this);
      h._events?.left(id);
      final bye = jsonEncode({'t': 'bye', 'id': id});
      for (final g in h._guests) {
        g._events?.message(bye);
      }
    } else {
      hub._rooms.removeWhere((_, v) => identical(v, this));
      for (final g in [..._guests]) {
        g._events?.left('host');
      }
      _guests.clear();
    }
    _events = null;
  }
}
