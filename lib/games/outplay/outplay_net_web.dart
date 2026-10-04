import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'outplay_net.dart';

@JS('outplayNet')
external _JsNet? get _net;

@JS('outplayLobby')
external _JsLobby? get _lobby;

extension type _JsLobby._(JSObject _) implements JSObject {
  external void browse(JSFunction onList);
  external void stopBrowse();
  external void announce(String room);
  external void unannounce();
}

OutplayDirectory? createDirectory() {
  final lobby = _lobby;
  final net = _net;
  if (lobby == null || net == null || !net.available()) return null;
  return _WebDirectory(lobby);
}

class _WebDirectory implements OutplayDirectory {
  final _JsLobby lobby;
  _WebDirectory(this.lobby);

  @override
  void browse(void Function(List<RoomInfo>) onList) => lobby.browse(
    ((JSString text) => onList(RoomInfo.listFrom(text.toDart))).toJS,
  );

  @override
  void stopBrowse() => lobby.stopBrowse();

  @override
  void announce(RoomInfo room) => lobby.announce(jsonEncode(room.toJson()));

  @override
  void unannounce() => lobby.unannounce();
}

extension type _JsNet._(JSObject _) implements JSObject {
  external bool available();
  external void host(String code, JSObject callbacks);
  external void join(String code, JSObject callbacks);
  external void send(String text);
  external void close();
}

/// The browser link, using web/outplay_net.js (PeerJS underneath).
OutplayLink? createLink() {
  final net = _net;
  if (net == null || !net.available()) return null;
  return _WebLink(net);
}

class _WebLink implements OutplayLink {
  final _JsNet net;
  _WebLink(this.net);

  JSObject _callbacks(LinkEvents e) {
    final o = JSObject();
    o['ready'] = ((JSString id) => e.ready(id.toDart)).toJS;
    o['message'] = ((JSString t) => e.message(t.toDart)).toJS;
    o['joined'] = ((JSString id) => e.joined(id.toDart)).toJS;
    o['left'] = ((JSString id) => e.left(id.toDart)).toJS;
    o['error'] = ((JSString err) => e.error(err.toDart)).toJS;
    return o;
  }

  @override
  void host(String code, LinkEvents events) =>
      net.host(code, _callbacks(events));

  @override
  void join(String code, LinkEvents events) =>
      net.join(code, _callbacks(events));

  @override
  void send(String text) => net.send(text);

  @override
  void close() => net.close();
}
