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
})();
