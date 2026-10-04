// Outplay online play: a tiny wrapper around PeerJS (WebRTC).
// The player who makes a room is the hub: everyone connects to them and
// they pass each message on to everyone else. No game server needed; the
// free PeerJS server only helps phones find each other.
(function () {
  let peer = null;
  let conns = [];
  let isHost = false;
  let cb = {};

  function options() {
    // ?peerhost=localhost&peerport=9000 points at a local PeerJS server
    // for testing; normally the free public one is used.
    const q = new URLSearchParams(location.search);
    const host = q.get('peerhost');
    if (!host) return { debug: 0 };
    return {
      host: host,
      port: Number(q.get('peerport') || 9000),
      path: '/',
      secure: false,
      debug: 0,
    };
  }

  function call(name, ...args) {
    try {
      if (cb[name]) cb[name](...args);
    } catch (e) {
      console.error(e);
    }
  }

  function wire(conn) {
    conn.on('data', (d) => {
      if (isHost) {
        for (const c of conns) if (c !== conn && c.open) c.send(d);
      }
      call('message', String(d));
    });
    conn.on('close', () => {
      conns = conns.filter((c) => c !== conn);
      if (isHost) {
        const bye = JSON.stringify({ t: 'bye', id: conn.peer });
        for (const c of conns) if (c.open) c.send(bye);
        call('left', conn.peer);
      } else {
        call('left', 'host');
      }
    });
  }

  function failed(e) {
    call('error', (e && e.type) || String(e));
  }

  window.outplayNet = {
    available: () => typeof Peer !== 'undefined',
    host(code, callbacks) {
      cb = callbacks;
      isHost = true;
      conns = [];
      peer = new Peer('outplay-room-' + code, options());
      peer.on('open', (id) => call('ready', id));
      peer.on('connection', (conn) => {
        conn.on('open', () => {
          conns.push(conn);
          wire(conn);
          call('joined', conn.peer);
        });
      });
      peer.on('error', failed);
    },
    join(code, callbacks) {
      cb = callbacks;
      isHost = false;
      conns = [];
      peer = new Peer(options());
      peer.on('open', (id) => {
        const conn = peer.connect('outplay-room-' + code, { reliable: true });
        conn.on('open', () => {
          conns = [conn];
          wire(conn);
          call('ready', id);
        });
      });
      peer.on('error', failed);
    },
    send(text) {
      for (const c of conns) if (c.open) c.send(text);
    },
    close() {
      cb = {};
      try {
        if (peer) peer.destroy();
      } catch (e) {}
      peer = null;
      conns = [];
    },
  };

  // ---- The Join list --------------------------------------------------
  // Whoever is first to look for rooms becomes the "lobby": everyone else
  // connects to them, rooms tell the lobby they're waiting, and the lobby
  // shares the list. If the lobby leaves, someone else takes over.
  const LOBBY = 'outplay-lobby-v1';
  const lobby = {
    peer: null,
    conn: null,
    isLobby: false,
    guests: [],
    rooms: new Map(),
    mine: null,
    onList: null,
    retry: null,
  };

  function lobbyWanted() {
    return !!(lobby.onList || lobby.mine);
  }

  function roomList() {
    const now = Date.now();
    const out = [];
    if (lobby.mine) out.push(lobby.mine);
    for (const [code, v] of lobby.rooms) {
      if (now - v.seen > 10000) lobby.rooms.delete(code);
      else if (!lobby.mine || code !== lobby.mine.code) out.push(v.room);
    }
    return out;
  }

  function lobbyStart() {
    if (lobby.peer || !lobbyWanted() || typeof Peer === 'undefined') return;
    const p = new Peer(LOBBY, options());
    lobby.peer = p;
    p.on('open', () => {
      lobby.isLobby = true;
      lobbyTick();
    });
    p.on('connection', (c) => {
      c.on('open', () => {
        lobby.guests.push(c);
        c.send(JSON.stringify({ t: 'list', rooms: roomList() }));
      });
      c.on('data', (d) => {
        try {
          const m = JSON.parse(d);
          if (m.t === 'room' && m.room && m.room.code) {
            lobby.rooms.set(m.room.code, { room: m.room, conn: c, seen: Date.now() });
          } else if (m.t === 'gone') {
            lobby.rooms.delete(m.code);
          }
        } catch (e) {}
      });
      c.on('close', () => {
        lobby.guests = lobby.guests.filter((g) => g !== c);
        for (const [code, v] of lobby.rooms) if (v.conn === c) lobby.rooms.delete(code);
      });
    });
    p.on('error', (e) => {
      if (lobby.peer !== p) return;
      if (e && e.type === 'unavailable-id') {
        // Someone else is already the lobby: connect to them.
        lobby.peer = null;
        try { p.destroy(); } catch (err) {}
        lobbyConnect();
      } else {
        lobbyRetry();
      }
    });
  }

  function lobbyConnect() {
    const p = new Peer(options());
    lobby.peer = p;
    p.on('open', () => {
      const c = p.connect(LOBBY, { reliable: true });
      lobby.conn = c;
      c.on('open', () => {
        if (lobby.mine) c.send(JSON.stringify({ t: 'room', room: lobby.mine }));
      });
      c.on('data', (d) => {
        try {
          const m = JSON.parse(d);
          if (m.t === 'list' && lobby.onList) lobby.onList(JSON.stringify(m.rooms));
        } catch (e) {}
      });
      c.on('close', () => {
        if (lobby.peer === p) lobbyRetry();
      });
    });
    // No lobby yet (or it just left): try to become it.
    p.on('error', () => {
      if (lobby.peer === p) lobbyRetry();
    });
  }

  function lobbyStop() {
    const p = lobby.peer;
    lobby.peer = null;
    lobby.conn = null;
    lobby.isLobby = false;
    lobby.guests = [];
    lobby.rooms.clear();
    clearTimeout(lobby.retry);
    try { if (p) p.destroy(); } catch (e) {}
  }

  function lobbyRetry() {
    lobbyStop();
    lobby.retry = setTimeout(lobbyStart, 300 + Math.random() * 1500);
  }

  function lobbyTick() {
    if (!lobby.peer) return;
    if (lobby.isLobby) {
      const rooms = roomList();
      const text = JSON.stringify({ t: 'list', rooms: rooms });
      for (const c of lobby.guests) if (c.open) c.send(text);
      call2(lobby.onList, JSON.stringify(rooms));
    } else if (lobby.conn && lobby.conn.open && lobby.mine) {
      lobby.conn.send(JSON.stringify({ t: 'room', room: lobby.mine }));
    }
  }
  setInterval(lobbyTick, 2000);

  function call2(fn, arg) {
    try {
      if (fn) fn(arg);
    } catch (e) {
      console.error(e);
    }
  }

  window.outplayLobby = {
    browse(onList) {
      lobby.onList = onList;
      lobbyStart();
      lobbyTick();
    },
    stopBrowse() {
      lobby.onList = null;
      if (!lobbyWanted()) lobbyStop();
    },
    announce(text) {
      lobby.mine = JSON.parse(text);
      lobbyStart();
    },
    unannounce() {
      const mine = lobby.mine;
      lobby.mine = null;
      if (mine && lobby.conn && lobby.conn.open) {
        lobby.conn.send(JSON.stringify({ t: 'gone', code: mine.code }));
      }
      if (!lobbyWanted()) setTimeout(() => { if (!lobbyWanted()) lobbyStop(); }, 300);
    },
  };
})();
