// VidGame front end: home, channel, watch page, posting (record or upload) and the tutorial.
const app = document.getElementById('app');
const searchBox = document.getElementById('search');
let cleanup = null; // runs when leaving a page (e.g. turns the camera off)

// ---------- helpers ----------
function toast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(toast._t);
  toast._t = setTimeout(() => (t.hidden = true), 3000);
}
function fmtTime(sec) {
  if (!isFinite(sec)) return '';
  sec = Math.round(sec);
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  return h ? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}` : `${m}:${String(s).padStart(2, '0')}`;
}
function timeAgo(iso) {
  const s = (Date.now() - new Date(iso)) / 1000;
  const units = [[31536000, 'year'], [2592000, 'month'], [86400, 'day'], [3600, 'hour'], [60, 'minute']];
  for (const [n, name] of units) if (s >= n) { const v = Math.floor(s / n); return `${v} ${name}${v > 1 ? 's' : ''} ago`; }
  return 'just now';
}
function fmtSize(b) { return b > 1e6 ? (b / 1e6).toFixed(1) + ' MB' : Math.max(1, Math.round(b / 1e3)) + ' KB'; }
// Small saved settings (channel name, tutorial seen). Storage can be blocked, so never rely on it.
// If the browser blocks saving (private window, strict settings), keep settings in memory so things still work until you close the tab.
const memoryPrefs = {};
const prefs = {
  get(k, d) {
    try { const v = localStorage.getItem('vidgame.' + k); if (v !== null) return v; } catch {}
    return k in memoryPrefs ? memoryPrefs[k] : d;
  },
  set(k, v) {
    memoryPrefs[k] = v;
    try { localStorage.setItem('vidgame.' + k, v); } catch { prefs.blocked = true; }
  },
};
const AVATAR_COLORS = ['#7c3aed', '#2563eb', '#0d9488', '#16a34a', '#ca8a04', '#ea580c', '#e11d48', '#db2777', '#4f46e5', '#0891b2', '#475569', '#111827'];
const BADGE_EMOJIS = ['😎', '🎮', '🔥', '⚽', '🏀', '🚀', '🦖', '🐱', '🐶', '🦊', '🐼', '🦁', '🐸', '👾', '🤖', '👻', '💎', '⭐', '🌈', '🍕', '🎸', '🏆', '⚡', '🎬'];
function channelName() { return prefs.get('channel', 'My Channel'); }
// Your badge: { type: 'letter' | 'emoji' | 'photo', letters, emoji, photo (small image), color }
function getBadge() {
  try { return JSON.parse(prefs.get('badge', '')) || {}; } catch { return {}; }
}
function defaultColor(name) {
  let h = 0; for (const c of name) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return AVATAR_COLORS[h % AVATAR_COLORS.length];
}
function paintAvatar(el, name = channelName(), badge = getBadge()) {
  if (!el) return;
  const type = badge.type || 'letter';
  el.classList.remove('photo', 'emoji');
  el.style.backgroundImage = '';
  el.style.setProperty('--avatar', badge.color || defaultColor(name));
  const img = type === 'photo' ? badge.photo : type === 'drawing' ? badge.drawing : null;
  if (img) {
    el.textContent = '';
    el.classList.add('photo');
    el.style.backgroundImage = `url("${img}")`;
  } else if (type === 'emoji' && badge.emoji) {
    el.textContent = badge.emoji;
    el.classList.add('emoji');
  } else {
    el.textContent = (badge.letters || name.trim()[0] || 'V').toUpperCase();
  }
}
function refreshAvatars() { document.querySelectorAll('#tab-avatar, #ch-avatar, #watch-avatar').forEach((el) => paintAvatar(el)); }
function myChannelId() {
  let id = prefs.get('channelId', '');
  if (!id) { id = 'ch_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8); prefs.set('channelId', id); }
  return id;
}
const isMine = (v) => !v.channelId || v.channelId === myChannelId();
// Which channels you watch, and how often, for the "People you watch" section.
function watchedChannels() { try { return JSON.parse(prefs.get('watching', '{}')) || {}; } catch { return {}; } }
function noteWatched(v) {
  if (isMine(v)) return;
  const w = watchedChannels(); w[v.channelId] = (w[v.channelId] || 0) + 1;
  prefs.set('watching', JSON.stringify(w));
}
// ⭐ Stars: favourite videos. VidGame: follow a channel (like subscribing).
const MAX_SECONDS = 48 * 3600; // videos can be up to 48 hours long
const SHORT_SECONDS = 60;      // a "short" is 1 minute or less
function readJson(key) { try { return JSON.parse(prefs.get(key, '{}')) || {}; } catch { return {}; } }
const starred = () => readJson('stars');
const isStarred = (v) => !!starred()[v.id];
function toggleStar(v) {
  const s = starred();
  if (s[v.id]) delete s[v.id]; else s[v.id] = Date.now();
  prefs.set('stars', JSON.stringify(s));
  return !!s[v.id];
}
const starCount = (v) => (v.baseStars || 0) + (isStarred(v) ? 1 : 0);
const vidgamed = () => readJson('vidgamed');
const isVidgamed = (channelId) => !!vidgamed()[channelId];
function toggleVidgame(v) {
  const g = vidgamed();
  if (g[v.channelId]) delete g[v.channelId];
  else g[v.channelId] = { name: v.channelName || 'Someone', badge: v.badge || {}, at: Date.now() };
  prefs.set('vidgamed', JSON.stringify(g));
  return !!g[v.channelId];
}
const vidgamerCount = (v) => (v.baseVidgamers || 0) + (isVidgamed(v.channelId) ? 1 : 0);
const plural = (n, word) => `${n.toLocaleString()} ${word}${n === 1 ? '' : 's'}`;
// Work out how long a video file is (in seconds).
function probeDuration(blob) {
  return new Promise((resolve) => {
    const v = document.createElement('video');
    v.preload = 'metadata'; v.muted = true;
    const url = URL.createObjectURL(blob);
    const done = (d) => { URL.revokeObjectURL(url); resolve(d); };
    v.onloadedmetadata = () => fixDuration(v).then(done);
    v.onerror = () => done(NaN);
    setTimeout(() => done(NaN), 8000);
    v.src = url;
  });
}
function viewsText(n) { n = n || 0; return `${n} view${n === 1 ? '' : 's'}`; }

function render(id) {
  app.innerHTML = '';
  app.appendChild(document.getElementById(id).content.cloneNode(true));
}
// ---------- storage: videos are kept in this browser (IndexedDB) ----------
const DB_NAME = 'vidgame', STORE = 'videos';
let dbPromise = null;
function openDb() {
  if (!dbPromise) dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE, { keyPath: 'id' });
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(new Error('This browser cannot save videos (private window?).'));
  });
  return dbPromise;
}
async function tx(mode, fn) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const t = db.transaction(STORE, mode);
    const out = fn(t.objectStore(STORE));
    t.oncomplete = () => resolve(out && 'result' in out ? out.result : out);
    t.onerror = () => reject(new Error(t.error && t.error.name === 'QuotaExceededError'
      ? 'Your browser is out of space. Delete some videos and try again.' : 'Could not save the video.'));
  });
}
// Example videos from the "VidGame Examples" channel, so Home always has something to watch.
const EXAMPLES_CHANNEL = { channelId: 'vidgame-examples', channelName: 'VidGame Examples', badge: { type: 'emoji', emoji: '⭐', color: '#e11d48' }, baseVidgamers: 1250 };
const EXAMPLES = [
  { id: 'ex-ball', title: 'Bouncing ball challenge', file: 'examples/ball.webm', hoursAgo: 5, baseViews: 128, stars: 31, duration: 6 },
  { id: 'ex-tutorial', title: 'How to record a video on VidGame', file: 'tutorial.webm', hoursAgo: 20, baseViews: 210, stars: 57, duration: 44 },
  { id: 'ex-count', title: 'Colour countdown 10 to 1', file: 'examples/count.webm', hoursAgo: 30, baseViews: 54, stars: 9, duration: 6 },
  { id: 'ex-rocket', title: 'Rocket launch into space', file: 'examples/rocket.webm', hoursAgo: 60, baseViews: 342, stars: 88, duration: 6 },
  { id: 'ex-wave', title: 'Waving at everyone', file: 'examples/wave.webm', hoursAgo: 400, baseViews: 87, stars: 14, duration: 6 },
];
function exampleVideos() {
  let first = +prefs.get('firstSeen', 0);
  if (!first) { first = Date.now(); prefs.set('firstSeen', String(first)); }
  let extra = {};
  try { extra = JSON.parse(prefs.get('exampleViews', '{}')) || {}; } catch {}
  return EXAMPLES.map((e) => ({
    ...EXAMPLES_CHANNEL,
    id: e.id, title: e.title, type: 'video/webm', size: 0, recorded: true, example: true,
    src: (window.VIDGAME_MEDIA && window.VIDGAME_MEDIA[e.file]) || e.file,
    views: e.baseViews + (extra[e.id] || 0), baseStars: e.stars, duration: e.duration,
    createdAt: new Date(first - e.hoursAgo * 36e5).toISOString(),
  }));
}
const store = {
  async list() {
    let all = [];
    try { all = await tx('readonly', (s) => s.getAll()); } catch (e) { toast(e.message); }
    return [...all, ...exampleVideos()].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  },
  get: (id) => id.startsWith('ex-') ? exampleVideos().find((v) => v.id === id) : tx('readonly', (s) => s.get(id)),
  put: (v) => {
    if (v.example) {
      let extra = {};
      try { extra = JSON.parse(prefs.get('exampleViews', '{}')) || {}; } catch {}
      extra[v.id] = (extra[v.id] || 0) + 1;
      prefs.set('exampleViews', JSON.stringify(extra));
      return Promise.resolve();
    }
    return tx('readwrite', (s) => s.put(v));
  },
  remove: (id) => tx('readwrite', (s) => s.delete(id)),
};
const urls = new Map(); // id -> object URL, so each video blob is only wrapped once
function mediaUrl(v) {
  if (v.src) return v.src;
  if (!urls.has(v.id)) urls.set(v.id, URL.createObjectURL(v.blob));
  return urls.get(v.id);
}
async function uploadVideo(blob, title, recorded, duration) {
  if (!blob.type.startsWith('video/')) throw new Error('That file is not a video.');
  if (!isFinite(duration)) duration = await probeDuration(blob);
  if (duration > MAX_SECONDS) throw new Error(`That video is ${fmtTime(duration)} long. Videos can be up to 48 hours.`);
  const v = {
    id: Date.now().toString(36) + Math.random().toString(36).slice(2, 8),
    title: (title || 'Untitled video').slice(0, 120),
    type: blob.type,
    size: blob.size,
    views: 0,
    recorded,
    duration: isFinite(duration) ? duration : undefined,
    createdAt: new Date().toISOString(),
    channelId: myChannelId(),
    channelName: channelName(),
    badge: (({ photoSrc, photoPos, ...b }) => b)(getBadge()),
    blob,
  };
  await store.put(v);
  return v;
}
function extOf(v) { return /mp4/.test(v.type) ? 'mp4' : /quicktime/.test(v.type) ? 'mov' : 'webm'; }

// Recordings from the browser have no duration in their header, so Chrome
// reports Infinity. Seeking far ahead forces it to work the real length out.
function fixDuration(video) {
  return new Promise((resolve) => {
    const done = () => { video.currentTime = 0; resolve(video.duration); };
    if (isFinite(video.duration)) return resolve(video.duration);
    video.addEventListener('durationchange', function h() {
      if (isFinite(video.duration)) { video.removeEventListener('durationchange', h); done(); }
    });
    video.currentTime = 1e101;
  });
}

// ---------- video grid (used by home and channel) ----------
function fillGrid(grid, videos) {
  for (const v of videos) {
    const a = document.createElement('a');
    a.className = 'card';
    a.href = '#/watch/' + v.id;
    a.innerHTML = `
      <div class="thumb"><video muted preload="metadata" playsinline></video><span class="duration" hidden></span></div>
      <h3></h3><p class="by"><span class="avatar"></span><span class="by-name"></span></p><p class="stats"></p>`;
    a.querySelector('h3').textContent = v.title;
    if (isMine(v)) { paintAvatar(a.querySelector('.avatar')); a.querySelector('.by-name').textContent = channelName(); }
    else { paintAvatar(a.querySelector('.avatar'), v.channelName || 'Someone', v.badge || {}); a.querySelector('.by-name').textContent = v.channelName || 'Someone'; }
    const stars = starCount(v);
    a.querySelector('.stats').textContent = `${viewsText(v.views)}${stars ? ` · ⭐ ${stars}` : ''} · ${timeAgo(v.createdAt)}`;
    if (v.duration <= SHORT_SECONDS) {
      const tag = document.createElement('span'); tag.className = 'short-tag'; tag.textContent = '⚡ Short';
      a.querySelector('.thumb').appendChild(tag);
    }
    const vid = a.querySelector('video');
    vid.src = mediaUrl(v) + '#t=0.5';
    vid.addEventListener('loadedmetadata', async () => {
      const d = await fixDuration(vid);
      vid.currentTime = Math.min(0.5, d / 2 || 0);
      const badge = a.querySelector('.duration');
      if (isFinite(d)) { badge.textContent = fmtTime(d); badge.hidden = false; }
    }, { once: true });
    a.addEventListener('mouseenter', () => vid.play().catch(() => {}));
    a.addEventListener('mouseleave', () => vid.pause());
    grid.appendChild(a);
  }
}
function wirePostButtons() {
  document.querySelectorAll('.open-post').forEach((b) => (b.onclick = openPostSheet));
}

// ---------- home ----------
async function showHome() {
  render('tpl-home');
  const tv = document.getElementById('home-tut-video');
  tv.src = TUTORIAL_SRC;
  if (document.getElementById('tutorial').hidden) tv.play().catch(() => {});
  cleanup = () => tv.pause();
  wirePostButtons();
  const token = ++showHome.token; // ignore older searches that finish late
  let videos = [];
  try { videos = await store.list(); } catch (e) { toast(e.message); }
  const box = document.getElementById('sections');
  if (token !== showHome.token || !box || !document.getElementById('home-tut-video')) return;
  box.innerHTML = '';
  document.getElementById('empty').hidden = true;
  const q = searchBox.value.trim().toLowerCase();
  if (q) {
    const found = videos.filter((v) => v.title.toLowerCase().includes(q) || (isMine(v) ? channelName() : v.channelName || '').toLowerCase().includes(q));
    document.getElementById('featured').hidden = true;
    addShelf(box, `🔍 Results for "${searchBox.value.trim()}"`, `${found.length} found`, found, false,
      `No videos match "${searchBox.value.trim()}". Try another word.`, true);
    return;
  }
  const now = Date.now();
  const ageHours = (v) => (now - new Date(v.createdAt)) / 36e5;

  // Brand new: posted in the last 7 days, newest first.
  const brandNew = videos.filter((v) => ageHours(v) < 24 * 7).slice(0, 12);
  // Popular right now: lots of views, and newer videos count for more.
  const popular = videos.filter((v) => (v.views || 0) > 0)
    .map((v) => ({ v, score: ((v.views || 0) + starCount(v) * 5) / Math.pow(ageHours(v) + 2, 1.2) }))
    .sort((x, y) => y.score - x.score).slice(0, 12).map((x) => x.v);
  // People you watch: channels you keep coming back to.
  const watched = watchedChannels();
  const weight = (v) => (watched[v.channelId] || 0) + (isVidgamed(v.channelId) ? 1000 : 0);
  const following = videos.filter((v) => !isMine(v) && weight(v))
    .sort((x, y) => weight(y) - weight(x) || y.createdAt.localeCompare(x.createdAt)).slice(0, 12);
  const shorts = videos.filter((v) => v.duration <= SHORT_SECONDS).slice(0, 12);

  addShelf(box, '🆕 Brand new', 'Posted in the last 7 days', brandNew, true, 'New videos show up here as soon as they are posted.');
  addShelf(box, '👀 People you watch', "Channels you VidGame or watch a lot", following, true, "Watch someone's video and their channel shows up here.");
  addShelf(box, '🔥 Popular right now', 'Most watched lately', popular, true, 'Videos with the most views right now show up here.');
  addShelf(box, '⚡ Shorts', '1 minute or less', shorts, true, 'Quick videos of 1 minute or less show up here.');
  addShelf(box, '📺 All videos', `${videos.length} video${videos.length === 1 ? '' : 's'}`, videos, false, 'No videos yet.', false, true);
}
showHome.token = 0;
function addShelf(box, title, sub, videos, asRow, emptyText, clearBtn, postBtn) {
  const sec = document.createElement('section');
  sec.className = 'shelf';
  sec.innerHTML = `<div class="shelf-head"><h2></h2><small></small></div><div class="${asRow ? 'row' : 'grid'}"></div>`;
  sec.querySelector('h2').textContent = title;
  sec.querySelector('small').textContent = sub;
  if (clearBtn) {
    const c = document.createElement('button');
    c.className = 'btn clear-search'; c.textContent = '✕ Clear search';
    c.onclick = () => { searchBox.value = ''; showHome(); };
    sec.firstElementChild.appendChild(c);
  }
  box.appendChild(sec);
  if (videos.length) { fillGrid(sec.lastElementChild, videos); return; }
  const e = document.createElement('div');
  e.className = 'shelf-empty';
  e.textContent = emptyText;
  if (postBtn) {
    const b = document.createElement('button');
    b.className = 'btn btn-primary'; b.textContent = '＋ Post a video'; b.onclick = openPostSheet;
    e.appendChild(b);
  }
  sec.lastElementChild.replaceWith(e);
}

// ---------- your channel ----------
async function showChannel() {
  render('tpl-channel');
  wirePostButtons();
  const nameEl = document.getElementById('ch-name');
  const form = document.getElementById('ch-form');
  const input = document.getElementById('ch-input');
  const editBtn = document.getElementById('ch-edit');
  const paint = () => { nameEl.textContent = channelName(); refreshAvatars(); };
  paint();
  editBtn.onclick = () => {
    input.value = channelName();
    form.hidden = false; nameEl.hidden = true; editBtn.hidden = true;
    input.focus(); input.select();
  };
  form.onsubmit = (e) => {
    e.preventDefault();
    const name = input.value.trim();
    if (name) prefs.set('channel', name);
    form.hidden = true; nameEl.hidden = false; editBtn.hidden = false;
    paint();
    showChannelVideos();
    toast('Channel name saved');
  };
  document.getElementById('ch-tutorial').onclick = () => tutorial.open();
  setupBadgeEditor(() => { paint(); showChannelVideos(); });
  async function showChannelVideos() {
    let videos = [];
    try { videos = (await store.list()).filter(isMine); } catch (e) { toast(e.message); }
    const views = videos.reduce((n, v) => n + (v.views || 0), 0);
    if (!document.getElementById('ch-stats')) return;
    document.getElementById('ch-stats').textContent =
      `${videos.length} video${videos.length === 1 ? '' : 's'} · ${viewsText(views)}`;
    document.getElementById('empty').hidden = videos.length > 0;
    const grid = document.getElementById('grid');
    grid.innerHTML = '';
    fillGrid(grid, videos);
  }
  showChannelVideos();
}

// ---------- badge editor ----------
// Shrink a photo to a small square so it fits in browser storage.
// Load a photo and shrink it (to 640px) so it can be kept in browser storage and re-adjusted later.
function loadPhoto(file) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const url = URL.createObjectURL(file);
    img.onload = () => {
      const max = 640, k = Math.min(1, max / Math.max(img.width, img.height));
      const c = document.createElement('canvas');
      c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      URL.revokeObjectURL(url);
      resolve(c.toDataURL('image/jpeg', 0.85));
    };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error("That photo couldn't be opened. Try a JPG or PNG.")); };
    img.src = url;
  });
}
// Photo cropper: zoom in and drag to choose what shows in the round badge.
function setupPhotoCrop(onChange) {
  const canvas = document.getElementById('crop-canvas'), ctx = canvas.getContext('2d');
  const zoomIn = document.getElementById('crop-zoom');
  const W = canvas.width;
  let img = null, zoom = 1, ox = 0, oy = 0;
  const pointers = new Map();
  let pinchStart = null;

  function scale() { return Math.max(W / img.width, W / img.height) * zoom; }
  function clamp() {
    const s = scale(), halfW = (img.width * s - W) / 2, halfH = (img.height * s - W) / 2;
    ox = Math.max(-halfW, Math.min(halfW, ox));
    oy = Math.max(-halfH, Math.min(halfH, oy));
  }
  function draw(notify = true) {
    if (!img) return;
    clamp();
    const s = scale(), w = img.width * s, h = img.height * s;
    ctx.fillStyle = '#000'; ctx.fillRect(0, 0, W, W);
    ctx.drawImage(img, (W - w) / 2 + ox, (W - h) / 2 + oy, w, h);
    if (notify) {
      clearTimeout(draw.t);
      draw.t = setTimeout(() => onChange(exportCrop(), { zoom, x: ox / W, y: oy / W }), 60);
    }
  }
  function exportCrop() {
    const out = document.createElement('canvas'); out.width = out.height = 192;
    out.getContext('2d').drawImage(canvas, 0, 0, 192, 192);
    return out.toDataURL('image/jpeg', 0.88);
  }
  function setZoom(z) {
    const old = zoom;
    zoom = Math.max(1, Math.min(5, z));
    ox *= zoom / old; oy *= zoom / old; // zoom around the middle
    zoomIn.value = zoom;
    draw();
  }
  const toCanvas = (dx) => dx * (W / canvas.getBoundingClientRect().width);
  canvas.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    canvas.setPointerCapture(e.pointerId);
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (pointers.size === 2) {
      const [a, b] = [...pointers.values()];
      pinchStart = { dist: Math.hypot(a.x - b.x, a.y - b.y), zoom };
    }
  });
  canvas.addEventListener('pointermove', (e) => {
    if (!img || !pointers.has(e.pointerId)) return;
    const prev = pointers.get(e.pointerId);
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (pointers.size === 2 && pinchStart) {
      const [a, b] = [...pointers.values()];
      setZoom(pinchStart.zoom * Math.hypot(a.x - b.x, a.y - b.y) / pinchStart.dist);
    } else if (pointers.size === 1) {
      ox += toCanvas(e.clientX - prev.x); oy += toCanvas(e.clientY - prev.y);
      draw();
    }
  });
  const up = (e) => { pointers.delete(e.pointerId); if (pointers.size < 2) pinchStart = null; };
  canvas.addEventListener('pointerup', up);
  canvas.addEventListener('pointercancel', up);
  canvas.addEventListener('wheel', (e) => { if (!img) return; e.preventDefault(); setZoom(zoom * (e.deltaY < 0 ? 1.1 : 0.9)); }, { passive: false });
  zoomIn.addEventListener('input', () => setZoom(+zoomIn.value));

  return {
    // Show a photo in the cropper, at a saved zoom and position if there is one.
    load(src, pos) {
      return new Promise((resolve) => {
        const i = new Image();
        i.onload = () => {
          img = i;
          zoom = (pos && pos.zoom) || 1; ox = ((pos && pos.x) || 0) * W; oy = ((pos && pos.y) || 0) * W;
          zoomIn.value = zoom;
          draw(false);
          resolve();
        };
        i.onerror = () => resolve();
        i.src = src;
      });
    },
    export: exportCrop,
    position: () => ({ zoom, x: ox / W, y: oy / W }),
    hasPhoto: () => !!img,
  };
}

function setupBadgeEditor(onSaved) {
  const $ = (id) => document.getElementById(id);
  const editor = $('badge-editor'), preview = $('be-avatar');
  let draft = {};
  const groups = { letter: $('be-letter-group'), emoji: $('be-emoji-group'), photo: $('be-photo-group'), drawing: $('be-drawing-group') };
  const pad = setupDrawingPad((dataUrl) => { draft.drawing = dataUrl; draft.type = 'drawing'; paintAvatar(preview, channelName(), draft); });
  const crop = setupPhotoCrop((dataUrl, pos) => { draft.photo = dataUrl; draft.photoPos = pos; draft.type = 'photo'; paintAvatar(preview, channelName(), draft); });
  async function showCrop() {
    const src = draft.photoSrc || draft.photo;
    $('crop-area').hidden = !src;
    if (src) await crop.load(src, draft.photoSrc ? draft.photoPos : null);
  }

  $('be-emojis').innerHTML = BADGE_EMOJIS.map((e) => `<button type="button" data-emoji="${e}" aria-label="${e}">${e}</button>`).join('');
  $('be-colors').innerHTML = AVATAR_COLORS.map((c) => `<button type="button" data-color="${c}" style="background:${c}" aria-label="Colour ${c}"></button>`).join('')
    + `<button type="button" class="rainbow-btn" data-any="1" aria-label="Pick any colour" title="Pick any colour"></button>`;
  let bgPicker = null;

  function update() {
    const type = draft.type || 'letter';
    document.querySelectorAll('.be-tab').forEach((t) => t.classList.toggle('active', t.dataset.type === type));
    for (const k in groups) groups[k].hidden = k !== type;
    $('be-color-group').hidden = type === 'photo' || type === 'drawing';
    const color = draft.color || defaultColor(channelName());
    document.querySelectorAll('#be-emojis button').forEach((b) => b.classList.toggle('sel', b.dataset.emoji === draft.emoji));
    const isPreset = AVATAR_COLORS.includes(color);
    document.querySelectorAll('#be-colors button').forEach((b) =>
      b.classList.toggle('sel', b.dataset.any ? !isPreset || !$('be-picker').hidden : b.dataset.color === color));
    paintAvatar(preview, channelName(), draft);
  }
  function open() {
    draft = { ...getBadge() };
    $('be-letters').value = draft.letters || '';
    if (draft.type === 'drawing') pad.load(draft.drawing);
    if (draft.type === 'photo') showCrop();
    editor.hidden = false;
    update();
    editor.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }
  $('ch-badge').onclick = open;
  $('ch-avatar-btn').onclick = open;
  document.querySelectorAll('.be-tab').forEach((t) => (t.onclick = () => {
    draft.type = t.dataset.type;
    if (draft.type === 'emoji' && !draft.emoji) draft.emoji = BADGE_EMOJIS[0];
    if (draft.type === 'photo') { if (!draft.photo) $('be-photo').click(); else showCrop(); }
    if (draft.type === 'drawing') pad.load(draft.drawing);
    update();
  }));
  $('be-letters').oninput = (e) => { draft.letters = e.target.value.replace(/\s/g, '').slice(0, 2); update(); };
  $('be-emojis').onclick = (e) => { const b = e.target.closest('button'); if (b) { draft.emoji = b.dataset.emoji; update(); } };
  $('be-colors').onclick = (e) => {
    const b = e.target.closest('button'); if (!b) return;
    if (b.dataset.any) {
      const box = $('be-picker');
      box.hidden = !box.hidden;
      const cur = draft.color || defaultColor(channelName());
      if (!box.hidden) {
        if (!bgPicker) bgPicker = createColorPicker(box, cur, (hex) => { draft.color = hex; update(); });
        else bgPicker.set(cur);
      }
      update();
      return;
    }
    draft.color = b.dataset.color;
    if (bgPicker) bgPicker.set(draft.color);
    update();
  };
  $('be-photo').onchange = async (e) => {
    const file = e.target.files[0];
    e.target.value = '';
    if (!file) return;
    try {
      draft.photoSrc = await loadPhoto(file);
      draft.photoPos = { zoom: 1, x: 0, y: 0 };
      draft.type = 'photo';
      await showCrop();
      draft.photo = crop.export();
      update();
      $('crop-area').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    } catch (err) { toast(err.message); }
  };
  $('be-cancel').onclick = () => { editor.hidden = true; };
  $('be-save').onclick = () => {
    if ((draft.type || 'letter') === 'photo' && !draft.photo) { toast('Choose a photo first'); return; }
    if (draft.type === 'drawing') {
      if (pad.isBlank()) { toast('Draw something first'); return; }
      draft.drawing = pad.export();
    }
    if (draft.type === 'photo' && crop.hasPhoto()) { draft.photo = crop.export(); draft.photoPos = crop.position(); }
    prefs.set('badge', JSON.stringify(draft));
    editor.hidden = true;
    refreshAvatars();
    onSaved();
    toast(prefs.blocked ? "Badge changed. Your browser won't keep it after you close this tab." : 'Badge saved');
  };
}

// ---------- any-colour picker (shade box + hue slider + colour code) ----------
function hsvToHex(h, s, v) {
  const f = (n) => { const k = (n + h / 60) % 6; return v - v * s * Math.max(0, Math.min(k, 4 - k, 1)); };
  return '#' + [f(5), f(3), f(1)].map((x) => Math.round(x * 255).toString(16).padStart(2, '0')).join('');
}
function hexToHsv(hex) {
  const n = parseInt(hex.slice(1), 16), r = ((n >> 16) & 255) / 255, g = ((n >> 8) & 255) / 255, b = (n & 255) / 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  let h = 0;
  if (d) h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return { h: (h * 60 + 360) % 360, s: max ? d / max : 0, v: max };
}
function createColorPicker(holder, startHex, onChange) {
  holder.innerHTML = `<div class="cp">
      <canvas class="cp-sv" width="236" height="150" aria-label="Pick a shade"></canvas>
      <input class="cp-hue" type="range" min="0" max="359" aria-label="Pick a colour">
      <div class="cp-row"><span class="cp-swatch"></span><span class="cp-label">Slide the rainbow to pick a colour, then drag in the box for lighter or darker</span></div>
    </div>`;
  const sv = holder.querySelector('.cp-sv'), ctx = sv.getContext('2d');
  const hue = holder.querySelector('.cp-hue'), sw = holder.querySelector('.cp-swatch');
  let st = hexToHsv(startHex || '#e11d48');
  const W = sv.width, H = sv.height;
  function draw() {
    ctx.fillStyle = hsvToHex(st.h, 1, 1); ctx.fillRect(0, 0, W, H);
    let g = ctx.createLinearGradient(0, 0, W, 0); g.addColorStop(0, '#fff'); g.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
    g = ctx.createLinearGradient(0, 0, 0, H); g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, '#000');
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
    const x = st.s * W, y = (1 - st.v) * H;
    ctx.lineWidth = 3; ctx.strokeStyle = st.v > 0.5 && st.s < 0.5 ? '#000' : '#fff';
    ctx.beginPath(); ctx.arc(x, y, 8, 0, Math.PI * 2); ctx.stroke();
  }
  function emit() {
    const hex = hsvToHex(st.h, st.s, st.v);
    sw.style.background = hex;
    hue.value = Math.round(st.h);
    draw();
    onChange(hex);
  }
  let dragging = false;
  const pick = (e) => {
    const r = sv.getBoundingClientRect();
    st.s = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
    st.v = 1 - Math.min(1, Math.max(0, (e.clientY - r.top) / r.height));
    emit();
  };
  sv.addEventListener('pointerdown', (e) => { e.preventDefault(); dragging = true; sv.setPointerCapture(e.pointerId); pick(e); });
  sv.addEventListener('pointermove', (e) => { if (dragging) pick(e); });
  sv.addEventListener('pointerup', () => { dragging = false; });
  hue.addEventListener('input', () => { st.h = +hue.value; if (st.s < 0.05 && st.v > 0.95) { st.s = 1; } emit(); });
  sw.style.background = hsvToHex(st.h, st.s, st.v);
  hue.value = Math.round(st.h);
  draw();
  return { set(hex) { st = hexToHsv(hex); sw.style.background = hex; hue.value = Math.round(st.h); draw(); } };
}

// ---------- drawing pad for the badge ----------
const DRAW_COLORS = ['#111111', '#ffffff', '#e11d48', '#f97316', '#facc15', '#22c55e', '#06b6d4', '#3b82f6', '#8b5cf6', '#ec4899', '#a16207', '#9ca3af'];
function setupDrawingPad(onChange) {
  const $ = (id) => document.getElementById(id);
  const canvas = $('draw-canvas'), ctx = canvas.getContext('2d');
  const W = canvas.width;
  let color = DRAW_COLORS[2], size = 14, erasing = false, filling = false, drawing = false, last = null, history = [], blank = true;

  let custom = [];
  function paintSwatches() {
    const all = [...DRAW_COLORS, ...custom];
    $('draw-colors').innerHTML = all.map((c) => `<button type="button" data-c="${c}" style="background:${c}" aria-label="Colour ${c}"></button>`).join('')
      + `<button type="button" class="rainbow-btn" data-any="1" aria-label="Pick any colour" title="Pick any colour"></button>`;
    markColor();
  }
  const markColor = () => document.querySelectorAll('#draw-colors button').forEach((b) => {
    b.classList.toggle('sel', (b.dataset.c === color && !erasing) || (b.dataset.any && !$('draw-picker').hidden));
  });
  let picker = null;
  function useCustom(hex) {
    color = hex; erasing = false; $('draw-eraser').setAttribute('aria-pressed', 'false');
    if (!DRAW_COLORS.includes(hex)) { custom = [hex, ...custom.filter((c) => c !== hex)].slice(0, 6); }
    clearTimeout(useCustom.t);
    useCustom.t = setTimeout(paintSwatches, 250); // wait until you stop dragging
  }
  function reset() {
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, W, W);
    history = []; blank = true;
  }
  const snapshot = () => { history.push(ctx.getImageData(0, 0, W, W)); if (history.length > 30) history.shift(); };
  const changed = () => { blank = false; onChange(canvas.toDataURL('image/png')); };
  const point = (e) => {
    const r = canvas.getBoundingClientRect();
    return { x: (e.clientX - r.left) * (W / r.width), y: (e.clientY - r.top) * (W / r.height) };
  };
  function stroke(a, b) {
    ctx.strokeStyle = erasing ? '#ffffff' : color;
    ctx.fillStyle = ctx.strokeStyle;
    ctx.lineWidth = size * (W / 240);
    ctx.lineCap = ctx.lineJoin = 'round';
    ctx.beginPath();
    if (a.x === b.x && a.y === b.y) { ctx.arc(a.x, a.y, ctx.lineWidth / 2, 0, Math.PI * 2); ctx.fill(); }
    else { ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke(); }
  }
  canvas.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    canvas.setPointerCapture(e.pointerId);
    snapshot();
    if (filling) { const p = point(e); floodFill(p.x, p.y); changed(); return; }
    drawing = true; last = point(e);
    stroke(last, last);
  });
  canvas.addEventListener('pointermove', (e) => {
    if (!drawing) return;
    const p = point(e);
    stroke(last, p); last = p;
  });
  const end = () => { if (drawing) { drawing = false; changed(); } };
  canvas.addEventListener('pointerup', end);
  canvas.addEventListener('pointercancel', end);

  $('draw-colors').onclick = (e) => {
    const b = e.target.closest('button'); if (!b) return;
    if (b.dataset.any) {
      const box = $('draw-picker');
      box.hidden = !box.hidden;
      if (!box.hidden) {
        if (!picker) picker = createColorPicker(box, color, useCustom);
        else picker.set(color);
      }
      markColor();
      return;
    }
    color = b.dataset.c;
    if (picker) picker.set(color); erasing = false; $('draw-eraser').setAttribute('aria-pressed', 'false'); markColor();
    if (!filling) canvas.style.cursor = 'crosshair';
  };
  document.querySelectorAll('.draw-size').forEach((b) => (b.onclick = () => {
    size = +b.dataset.size;
    document.querySelectorAll('.draw-size').forEach((x) => x.classList.toggle('sel', x === b));
  }));
  $('draw-eraser').onclick = () => {
    erasing = !erasing; filling = false;
    $('draw-eraser').setAttribute('aria-pressed', String(erasing)); $('draw-fill').setAttribute('aria-pressed', 'false');
    markColor();
  };
  $('draw-fill').onclick = () => {
    filling = !filling;
    if (filling) { erasing = false; $('draw-eraser').setAttribute('aria-pressed', 'false'); }
    $('draw-fill').setAttribute('aria-pressed', String(filling));
    markColor();
  };
  // Bucket fill: colour in the area you tap.
  function floodFill(x, y) {
    x = Math.floor(x); y = Math.floor(y);
    const img = ctx.getImageData(0, 0, W, W), px = img.data;
    const at = (i) => [px[i], px[i + 1], px[i + 2]];
    const start = at((y * W + x) * 4);
    const n = parseInt(color.slice(1), 16), fill = [(n >> 16) & 255, (n >> 8) & 255, n & 255];
    const near = (c) => Math.abs(c[0] - start[0]) + Math.abs(c[1] - start[1]) + Math.abs(c[2] - start[2]) < 90;
    if (Math.abs(fill[0] - start[0]) + Math.abs(fill[1] - start[1]) + Math.abs(fill[2] - start[2]) < 3) return;
    const seen = new Uint8Array(W * W), stack = [y * W + x];
    while (stack.length) {
      const p = stack.pop();
      if (seen[p]) continue;
      seen[p] = 1;
      const i = p * 4;
      if (!near(at(i))) continue;
      px[i] = fill[0]; px[i + 1] = fill[1]; px[i + 2] = fill[2]; px[i + 3] = 255;
      const px_ = p % W;
      if (px_ > 0) stack.push(p - 1);
      if (px_ < W - 1) stack.push(p + 1);
      if (p >= W) stack.push(p - W);
      if (p < W * (W - 1)) stack.push(p + W);
    }
    ctx.putImageData(img, 0, 0);
  }
  $('draw-undo').onclick = () => {
    const prev = history.pop();
    if (!prev) return;
    ctx.putImageData(prev, 0, 0);
    if (!history.length) blank = true;
    onChange(canvas.toDataURL('image/png'));
  };
  $('draw-clear').onclick = () => { snapshot(); ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, W, W); blank = true; onChange(canvas.toDataURL('image/png')); };

  reset();
  paintSwatches();
  return {
    load(dataUrl) {
      reset();
      if (!dataUrl) return;
      const img = new Image();
      img.onload = () => { ctx.drawImage(img, 0, 0, W, W); blank = false; };
      img.src = dataUrl;
    },
    isBlank: () => blank,
    // A smaller copy for saving, so it fits in browser storage.
    export() {
      const out = document.createElement('canvas'); out.width = out.height = 192;
      out.getContext('2d').drawImage(canvas, 0, 0, 192, 192);
      return out.toDataURL('image/png');
    },
  };
}

// ---------- watch ----------
async function showWatch(id) {
  render('tpl-watch');
  let v;
  try {
    v = await store.get(id);
    if (!v) throw new Error('Video not found.');
    v.views = (v.views || 0) + 1;
    await store.put(v);
    noteWatched(v);
  } catch (e) { app.innerHTML = `<p class="empty">${e.message} <a class="btn" href="#/">Back</a></p>`; return; }
  const player = document.getElementById('player');
  if (!player) return; // you already moved to another page
  player.src = mediaUrl(v);
  player.addEventListener('loadedmetadata', () => fixDuration(player).then(() => player.play().catch(() => {})), { once: true });
  document.getElementById('watch-title').textContent = v.title;
  document.title = v.title + ' · VidGame';
  if (isMine(v)) {
    document.getElementById('watch-channel').textContent = channelName();
    paintAvatar(document.getElementById('watch-avatar'));
  } else {
    document.getElementById('watch-channel').textContent = v.channelName || 'Someone';
    paintAvatar(document.getElementById('watch-avatar'), v.channelName || 'Someone', v.badge || {});
    document.querySelector('.watch-channel').removeAttribute('href');
    document.getElementById('delete').hidden = true;
  }
  // ⭐ star button on the side
  const starBtn = document.getElementById('star-btn');
  const paintStar = () => {
    const on = isStarred(v);
    starBtn.setAttribute('aria-pressed', on);
    starBtn.querySelector('.rail-icon').textContent = on ? '★' : '☆';
    starBtn.title = on ? 'Starred. Press to un-star' : 'Star this video';
    document.getElementById('star-count').textContent = starCount(v).toLocaleString();
  };
  paintStar();
  starBtn.onclick = () => {
    const on = toggleStar(v);
    paintStar();
    starBtn.classList.remove('pop'); void starBtn.offsetWidth; if (on) starBtn.classList.add('pop');
    toast(on ? '⭐ Starred! Find it in Stars at the bottom.' : 'Star taken off');
  };
  // 🎮 VidGame button (like subscribing)
  const vgBtn = document.getElementById('vidgame-btn'), vgCount = document.getElementById('watch-vidgamers');
  const paintVg = () => {
    vgCount.textContent = plural(vidgamerCount(v), 'VidGamer');
    const on = isVidgamed(v.channelId);
    vgBtn.textContent = on ? '✓ VidGamed' : '🎮 VidGame';
    vgBtn.classList.toggle('on', on);
  };
  if (isMine(v)) vgCount.textContent = '';
  else {
    vgBtn.hidden = false;
    paintVg();
    vgBtn.onclick = () => {
      const on = toggleVidgame(v);
      paintVg();
      toast(on ? `You VidGamed ${v.channelName || 'this channel'}! Their videos are in VidGames at the bottom.` : `You stopped VidGaming ${v.channelName || 'this channel'}`);
    };
  }
  document.getElementById('watch-info').textContent =
    `${viewsText(v.views)} · ${timeAgo(v.createdAt)}` + (v.example ? ' · Example video' : ` · ${fmtSize(v.size)}${v.recorded ? ' · Recorded in VidGame' : ''}`);
  const dl = document.getElementById('download');
  dl.href = mediaUrl(v);
  dl.download = v.title.replace(/[^\w\- ]+/g, '').trim() + '.' + extOf(v);
  const confirmBox = document.getElementById('confirm-delete');
  document.getElementById('delete').onclick = () => { confirmBox.hidden = false; };
  document.getElementById('confirm-no').onclick = () => { confirmBox.hidden = true; };
  document.getElementById('confirm-yes').onclick = async () => {
    await store.remove(v.id);
    URL.revokeObjectURL(urls.get(v.id)); urls.delete(v.id);
    toast('Video deleted');
    location.hash = '#/channel';
  };
  cleanup = () => { player.pause(); document.title = 'VidGame'; };
}

// ---------- Stars and VidGames pages ----------
async function showStars() {
  render('tpl-list');
  document.getElementById('list-title').textContent = '⭐ Your stars';
  document.getElementById('list-sub').textContent = 'Videos you starred. Press ☆ next to any video to add it here.';
  let videos = [];
  try { videos = await store.list(); } catch (e) { toast(e.message); }
  const grid = document.getElementById('grid'); if (!grid) return;
  const s = starred();
  const mine = videos.filter((v) => s[v.id]).sort((a, b) => s[b.id] - s[a.id]);
  if (mine.length) fillGrid(grid, mine);
  else { document.getElementById('empty-text').textContent = "You haven't starred any videos yet."; document.getElementById('empty').hidden = false; }
}
async function showVidgames() {
  render('tpl-list');
  document.getElementById('list-title').textContent = '🎮 VidGames';
  const g = vidgamed(), ids = Object.keys(g);
  document.getElementById('list-sub').textContent = ids.length
    ? `You VidGame ${plural(ids.length, 'channel')}. Their newest videos are here.`
    : 'Press 🎮 VidGame under a video to follow that channel. Their videos show up here.';
  const chips = document.getElementById('list-chips');
  for (const id of ids) {
    const c = document.createElement('span'); c.className = 'chip';
    c.innerHTML = '<span class="avatar"></span><span class="chip-name"></span><button title="Stop VidGaming">✕</button>';
    paintAvatar(c.querySelector('.avatar'), g[id].name, g[id].badge);
    c.querySelector('.chip-name').textContent = g[id].name;
    c.querySelector('button').setAttribute('aria-label', 'Stop VidGaming ' + g[id].name);
    c.querySelector('button').onclick = () => { toggleVidgame({ channelId: id }); showVidgames(); };
    chips.appendChild(c);
  }
  let videos = [];
  try { videos = await store.list(); } catch (e) { toast(e.message); }
  const grid = document.getElementById('grid'); if (!grid) return;
  const list = videos.filter((v) => !isMine(v) && g[v.channelId]);
  if (list.length) fillGrid(grid, list);
  else { document.getElementById('empty-text').textContent = ids.length ? 'No videos from them yet.' : "You don't VidGame anyone yet."; document.getElementById('empty').hidden = false; }
}

// ---------- record ----------
function pickMimeType() {
  const options = [
    'video/webm;codecs=vp9,opus',
    'video/webm;codecs=vp8,opus',
    'video/webm',
    'video/mp4;codecs=avc1,mp4a',
    'video/mp4',
  ];
  return options.find((t) => window.MediaRecorder && MediaRecorder.isTypeSupported(t)) || '';
}

// Screen + face: draws the screen with your camera in a round bubble on top,
// and mixes the screen's sound with your microphone, into one stream to record.
function makeMixer(screen, cam, faceImg, host) {
  const canvas = document.createElement('canvas');
  canvas.className = 'player mix-canvas';
  const ctx = canvas.getContext('2d');
  const sv = document.createElement('video'), cv = document.createElement('video');
  // Keep the camera videos really on the page, just hidden behind the picture we draw:
  // phones (especially iPhones) stop updating videos that aren't on the page.
  const hold = document.createElement('div');
  hold.className = 'mix-hold';
  (host || document.body).appendChild(hold);
  // Show the drawn picture itself as the preview (more reliable on phones than a video of it).
  if (host) host.insertBefore(canvas, host.firstChild);
  for (const [v, src] of [[sv, screen], [cv, cam]]) {
    v.muted = true; v.playsInline = true; v.setAttribute('playsinline', ''); v.autoplay = true;
    hold.appendChild(v);
    if (!src) continue;
    v.srcObject = new MediaStream(src.getVideoTracks());
    v.play().catch(() => {});
  }
  let mainStream = screen, sized = false;
  const m = { size: 0.26, x: 0.82, y: 0.74, face: { x: 0.5, y: 0.42, s: 0.6 } };
  // Follow your face (on browsers that can find faces), so the bubble stays on you as you move.
  let faceTimer = null;
  if ('FaceDetector' in window) {
    try {
      const fd = new window.FaceDetector({ fastMode: true, maxDetectedFaces: 1 });
      let busy = false;
      faceTimer = setInterval(async () => {
        if (!m.sameCam || busy || !sv.videoWidth) return;
        busy = true;
        try {
          const [face] = await fd.detect(sv);
          if (face) {
            const b = face.boundingBox, vw = sv.videoWidth, vh = sv.videoHeight;
            m.faceTarget = { x: (b.x + b.width / 2) / vw, y: (b.y + b.height / 2) / vh, s: Math.min(0.9, Math.max(0.25, (b.width * 1.9) / Math.min(vw, vh))) };
          }
        } catch { clearInterval(faceTimer); }
        busy = false;
      }, 400);
    } catch {}
  }
  const set = screen.getVideoTracks()[0].getSettings();
  canvas.width = set.width || 1280; canvas.height = set.height || 720;
  function draw() {
    // Pick the video size once, so switching cameras mid-video doesn't change it.
    if (!sized && sv.videoWidth) { canvas.width = sv.videoWidth; canvas.height = sv.videoHeight; sized = true; }
    const W = canvas.width, H = canvas.height;
    ctx.fillStyle = '#000'; ctx.fillRect(0, 0, W, H);
    if (sv.videoWidth) {
      // Fit the whole picture in (no stretching), centred.
      const k = Math.min(W / sv.videoWidth, H / sv.videoHeight), w = sv.videoWidth * k, h = sv.videoHeight * k;
      ctx.save(); ctx.translate(W / 2, H / 2); if (m.mirrorMain) ctx.scale(-1, 1);
      ctx.drawImage(sv, -w / 2, -h / 2, w, h); ctx.restore();
    }
    if (m.sameCam && !m.hideBubble && sv.videoWidth) {
      // Bubble = live zoom on your face, from the same camera.
      const vw = sv.videoWidth, vh = sv.videoHeight, f = m.face;
      if (m.faceTarget) for (const k of ['x', 'y', 's']) f[k] += (m.faceTarget[k] - f[k]) * 0.15;
      const side = Math.min(vw, vh) * f.s;
      const sx = Math.min(vw - side, Math.max(0, f.x * vw - side / 2)), sy = Math.min(vh - side, Math.max(0, f.y * vh - side / 2));
      const r = Math.min(W, H) * m.size / 2;
      const cx = Math.min(W - r - 4, Math.max(r + 4, m.x * W)), cy = Math.min(H - r - 4, Math.max(r + 4, m.y * H));
      ctx.save();
      ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.closePath(); ctx.clip();
      ctx.translate(cx, cy); if (m.mirrorMain) ctx.scale(-1, 1);
      ctx.drawImage(sv, sx, sy, side, side, -r, -r, 2 * r, 2 * r);
      ctx.restore();
      ctx.lineWidth = Math.max(3, r * 0.06); ctx.strokeStyle = '#fff';
      ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke();
    }
    const fsrc = m.hideBubble || m.sameCam ? null : cam && cv.videoWidth ? cv : faceImg;
    if (fsrc) {
      const fw = fsrc.videoWidth || fsrc.width, fh = fsrc.videoHeight || fsrc.height;
      const r = Math.min(W, H) * m.size / 2;
      const cx = Math.min(W - r - 4, Math.max(r + 4, m.x * W)), cy = Math.min(H - r - 4, Math.max(r + 4, m.y * H));
      const s = Math.max((2 * r) / fw, (2 * r) / fh);
      const w = fw * s, h = fh * s;
      ctx.save();
      ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.closePath(); ctx.clip();
      ctx.translate(cx, cy); if (m.mirror && fsrc === cv) ctx.scale(-1, 1);
      ctx.drawImage(fsrc, -w / 2, -h / 2, w, h);
      ctx.restore();
      ctx.lineWidth = Math.max(3, r * 0.06); ctx.strokeStyle = '#fff';
      ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke();
    }
  }
  // A worker timer keeps drawing even when you switch to another tab or window.
  let worker;
  try {
    worker = new Worker(URL.createObjectURL(new Blob(['setInterval(() => postMessage(0), 33)'], { type: 'text/javascript' })));
    worker.onmessage = draw;
  } catch {
    const t = setInterval(draw, 33); worker = { terminate: () => clearInterval(t) };
  }
  draw();
  const out = canvas.captureStream(30);
  // Sound: mix the screen's sound and your microphone together.
  const audioIn = [...screen.getAudioTracks(), ...(cam ? cam.getAudioTracks() : [])];
  let ac = null;
  if (audioIn.length === 1) out.addTrack(audioIn[0]);
  else if (audioIn.length > 1) {
    try {
      ac = new AudioContext();
      const dest = ac.createMediaStreamDestination();
      audioIn.forEach((t) => ac.createMediaStreamSource(new MediaStream([t])).connect(dest));
      dest.stream.getAudioTracks().forEach((t) => out.addTrack(t));
    } catch { out.addTrack(audioIn[0]); }
  }
  m.stream = out;
  m.canvas = canvas;
  // Swap which picture is big and which is in the bubble (works mid-video).
  m.swap = () => {
    if (!cam) return;
    const a = sv.srcObject; sv.srcObject = cv.srcObject; cv.srcObject = a;
    sv.play().catch(() => {}); cv.play().catch(() => {});
    [m.mirrorMain, m.mirror] = [!!m.mirror, !!m.mirrorMain];
    m.swapped = !m.swapped;
  };
  // Swap the big picture to another camera without stopping the recording.
  m.setMain = (st) => {
    mainStream.getVideoTracks().forEach((t) => t.stop());
    mainStream = st;
    sv.srcObject = new MediaStream(st.getVideoTracks());
    sv.play().catch(() => {});
  };
  m.stop = () => {
    worker.terminate();
    clearInterval(faceTimer);
    [screen, cam, mainStream].forEach((st) => st && st.getTracks().forEach((t) => t.stop()));
    if (ac) ac.close().catch(() => {});
    sv.srcObject = cv.srcObject = null;
    hold.remove();
    canvas.remove();
  };
  return m;
}

async function showRecord() {
  render('tpl-record');
  const $ = (id) => document.getElementById(id);
  const preview = $('preview'), stage = document.querySelector('.stage');
  const msgBox = $('cam-msg'), msgText = $('cam-msg-text'), retry = $('cam-retry');
  const camSel = $('camera-select'), micSel = $('mic-select'), mirror = $('mirror'), mirrorWrap = $('mirror-wrap');
  const srcCamera = $('src-camera'), srcScreen = $('src-screen'), srcBoth = $('src-both');
  const dualBtn = $('dual-cam'), flipBtn = $('flip-cam'), bubbleWrap = $('bubble-wrap'), bubbleSize = $('bubble-size'), bubbleHint = $('bubble-hint');
  let facing = 'user';      // which camera on a phone: 'user' = front (your face), 'environment' = back
  let mixer = null;         // screen + face: draws both onto one picture
  let singleCamNote = false;
  const bubbleBtn = $('bubble-toggle');
  // Buttons you can use any time, even in the middle of a video.
  function paintLiveControls() {
    bubbleBtn.hidden = !mixer;
    if (mixer) bubbleBtn.textContent = mixer.hideBubble ? '😀 Show face bubble' : '🙈 Hide face bubble';
    if (mixer && mixer.twoCams) flipBtn.textContent = '🔄 Swap big and small';
    else if (mixer && mixer.single) flipBtn.textContent = '🔄 Flip camera';
  }
  bubbleBtn.onclick = () => { if (!mixer) return; mixer.hideBubble = !mixer.hideBubble; paintLiveControls(); };
  const bubble = { x: 0.82, y: 0.74 }; // where the face bubble sits (0..1 across and down)
  const btnStart = $('btn-start'), btnPause = $('btn-pause'), btnStop = $('btn-stop');
  const badge = $('rec-badge'), timer = $('timer'), pausedCover = $('paused-cover'), recLabel = $('rec-label');
  const review = $('review'), reviewPlayer = $('review-player'), titleInput = $('title');
  const btnSave = $('btn-save'), btnDl = $('btn-download-rec'), btnRetake = $('btn-retake');

  let source = 'camera';
  let stream = null, recorder = null, chunks = [], blob = null, blobUrl = null;
  let elapsed = 0, tick = null, leaving = false, starting = null;

  const inFrame = (() => { try { return window.self !== window.top; } catch { return true; } })();
  const canRecord = !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia && window.MediaRecorder);
  const canScreen = !!(navigator.mediaDevices && navigator.mediaDevices.getDisplayMedia);
  if (!canScreen) srcScreen.hidden = srcBoth.hidden = true;

  const stopStream = () => {
    if (mixer) { mixer.stop(); mixer = null; }
    stage.classList.remove('mixing');
    if (stream) stream.getTracks().forEach((t) => t.stop());
    stream = null; preview.srcObject = null;
  };
  cleanup = () => {
    leaving = true;
    if (recorder && recorder.state !== 'inactive') recorder.stop();
    clearInterval(tick);
    stopStream();
    if (blobUrl) URL.revokeObjectURL(blobUrl);
  };

  function showMsg(text, withRetry) {
    msgText.textContent = text;
    retry.hidden = !withRetry;
    msgBox.hidden = false;
  }
  function hideMsg() { msgBox.hidden = true; }
  const recording = () => recorder && recorder.state !== 'inactive';

  mirror.onchange = () => stage.classList.toggle('mirror', mirror.checked && source === 'camera');
  const isPhone = () => matchMedia('(pointer: coarse)').matches || /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
  flipBtn.onclick = async () => {
    if (mixer && mixer.twoCams) { mixer.swap(); return; }
    if (mixer && mixer.single) {
      const next = mixer.facing === 'user' ? 'environment' : 'user';
      let video = { facingMode: next };
      if (!isPhone()) {
        const cams = [...camSel.options].map((o) => o.value);
        if (cams.length < 2) { toast('Your computer only has one camera, so there is nothing to flip to.'); return; }
        camSel.value = cams[(cams.indexOf(camSel.value) + 1) % cams.length];
        video = { deviceId: { exact: camSel.value } };
      }
      flipBtn.disabled = true;
      try {
        mixer.setMain(new MediaStream()); // let go of this camera first
        const st = await navigator.mediaDevices.getUserMedia({ video });
        mixer.setMain(st);
        mixer.facing = next; mixer.mirrorMain = next === 'user';
        paintLiveControls();
      } catch { toast("The other camera couldn't start."); }
      flipBtn.disabled = false;
      return;
    }
    if (recording()) return;
    const cams = [...camSel.options].map((o) => o.value);
    if (!isPhone()) {
      // Computers: switch to the next camera plugged in.
      if (cams.length < 2) { toast('Your computer only has one camera. Plug in another camera (or a phone used as a webcam) to flip.'); return; }
      camSel.value = cams[(cams.indexOf(camSel.value) + 1) % cams.length];
      if (source === 'camera' || source === 'dual') { stopStream(); startSource(); }
      toast('Using ' + (camSel.selectedOptions[0] ? camSel.selectedOptions[0].textContent : 'your other camera'));
      return;
    }
    facing = facing === 'user' ? 'environment' : 'user';
    mirror.checked = facing === 'user'; // the back camera shouldn't be mirrored
    camSel.value = '';
    stage.classList.toggle('mirror', mirror.checked && source === 'camera');
    if (source === 'camera' || source === 'dual') { stopStream(); startSource(); }
    toast(facing === 'user' ? 'Using your front camera' : 'Using your back camera');
  };
  bubbleSize.oninput = () => { if (mixer) mixer.size = +bubbleSize.value; };
  // Drag the face bubble around the preview.
  stage.addEventListener('pointerdown', (e) => {
    if (!mixer || e.target !== mixer.canvas) return;
    e.preventDefault();
    const el = mixer.canvas;
    el.setPointerCapture(e.pointerId);
    const move = (ev) => {
      const r = el.getBoundingClientRect();
      bubble.x = Math.min(1, Math.max(0, (ev.clientX - r.left) / r.width));
      bubble.y = Math.min(1, Math.max(0, (ev.clientY - r.top) / r.height));
    };
    move(e);
    el.onpointermove = move;
    el.onpointerup = el.onpointercancel = () => { el.onpointermove = null; };
  });

  // Try to use two cameras at once (front + back on phones, two cameras on computers).
  async function openTwoCameras(audio) {
    let mainVideo = { facingMode: 'environment' }, faceVideo = { facingMode: 'user' };
    if (!isPhone()) {
      let cams = [];
      try { cams = (await navigator.mediaDevices.enumerateDevices()).filter((d) => d.kind === 'videoinput' && d.deviceId); } catch {}
      if (cams.length < 2) return null;
      const faceId = camSel.value && cams.some((c) => c.deviceId === camSel.value) ? camSel.value : cams[0].deviceId;
      mainVideo = { deviceId: { exact: cams.find((c) => c.deviceId !== faceId).deviceId } };
      faceVideo = { deviceId: { exact: faceId } };
    }
    let main = null, face = null;
    const stopAll = () => [main, face].forEach((st) => st && st.getTracks().forEach((t) => t.stop()));
    try { main = await navigator.mediaDevices.getUserMedia({ video: { ...mainVideo, width: { ideal: 1280 }, height: { ideal: 720 } }, audio }); }
    catch { try { main = await navigator.mediaDevices.getUserMedia({ video: mainVideo }); } catch { return null; } }
    try { face = await navigator.mediaDevices.getUserMedia({ video: { ...faceVideo, width: { ideal: 640 } } }); } catch {}
    await new Promise((r) => setTimeout(r, 700)); // some phones switch the first camera off when the second one starts
    const mt = main.getVideoTracks()[0], ft = face && face.getVideoTracks()[0];
    const ok = ft && mt.readyState === 'live' && ft.readyState === 'live' && !mt.muted && !ft.muted &&
      (!mt.getSettings().deviceId || mt.getSettings().deviceId !== ft.getSettings().deviceId);
    if (!ok || !(await bothMoving(main, face))) { stopAll(); return null; }
    return { main, face };
  }
  // Some phones say both cameras are on, but one picture is frozen. Check both are really moving.
  function bothMoving(...streams) {
    return Promise.all(streams.map((st) => new Promise((resolve) => {
      const v = document.createElement('video');
      v.muted = true; v.playsInline = true; v.setAttribute('playsinline', '');
      v.style.cssText = 'position:fixed;left:0;top:0;width:2px;height:2px;opacity:0.01;pointer-events:none';
      document.body.appendChild(v);
      v.srcObject = new MediaStream(st.getVideoTracks());
      let frames = 0;
      const done = () => { v.remove(); resolve(frames >= 3); };
      if (v.requestVideoFrameCallback) {
        const cb = () => { frames++; v.requestVideoFrameCallback(cb); };
        v.requestVideoFrameCallback(cb);
      } else {
        let last = -1;
        const t = setInterval(() => { if (v.currentTime !== last) { frames++; last = v.currentTime; } }, 150);
        setTimeout(() => clearInterval(t), 1450);
      }
      v.play().catch(() => {});
      setTimeout(done, 1500);
    }))).then((r) => r.every(Boolean));
  }
  function setSource(s) {
    if (recording()) return;
    source = s;
    flipBtn.textContent = '🔄 Flip camera';
    bubbleBtn.hidden = true;
    srcCamera.classList.toggle('active', s === 'camera'); srcCamera.setAttribute('aria-pressed', s === 'camera');
    dualBtn.classList.toggle('active', s === 'dual'); dualBtn.setAttribute('aria-pressed', s === 'dual');
    srcScreen.classList.toggle('active', s === 'screen'); srcScreen.setAttribute('aria-pressed', s === 'screen');
    srcBoth.classList.toggle('active', s === 'both'); srcBoth.setAttribute('aria-pressed', s === 'both');
    mirrorWrap.hidden = s !== 'camera';
    camSel.hidden = s === 'screen' || camSel.options.length < 2;
    flipBtn.hidden = s === 'screen';
    bubbleWrap.hidden = bubbleHint.hidden = s !== 'both' && s !== 'dual';
    stage.classList.toggle('both', s === 'both' || s === 'dual');
    stage.classList.toggle('mirror', mirror.checked && s === 'camera');
    stopStream();
    if (s === 'camera' || s === 'dual') startCamera();
    else if (s === 'both') showMsg('Press the red button, then pick the screen or window. Your face will show in a bubble on top.', false);
    else showMsg('Press the red button, then pick the screen or window you want to record.', false);
  }
  srcCamera.onclick = () => setSource('camera');
  srcScreen.onclick = () => setSource('screen');
  srcBoth.onclick = () => setSource('both');
  dualBtn.onclick = () => setSource('dual');

  // Turn on the camera (or screen). Returns true when there is something to record.
  async function startSource() {
    if (stream) return true;
    if (starting) return starting;
    starting = (async () => {
      if (!canRecord) { showMsg("This browser can't record video. Open VidGame in Chrome, Edge or Safari.", false); return false; }
      try {
        if (source === 'camera') {
          showMsg('Starting camera… If your browser asks, press Allow.', false);
          const video = camSel.value ? { deviceId: { exact: camSel.value } } : { facingMode: facing };
          const audio = micSel.value ? { deviceId: { exact: micSel.value } } : true;
          try {
            stream = await navigator.mediaDevices.getUserMedia({ video: { width: { ideal: 1280 }, height: { ideal: 720 }, ...video }, audio });
          } catch (e) {
            if (e.name === 'NotAllowedError' || e.name === 'SecurityError') throw e;
            // Maybe there's no microphone, or the chosen device is gone: try camera only.
            stream = await navigator.mediaDevices.getUserMedia({ video: true });
            toast('No microphone found, recording without sound');
          }
        } else if (source === 'dual' && !HTMLCanvasElement.prototype.captureStream) {
          throw Object.assign(new Error('no canvas'), { name: 'NoMix' });
        } else if (source === 'dual') {
          // Your face in a bubble + the other way (what's in front of you).
          showMsg('Starting your cameras… If your browser asks, press Allow.', false);
          const audio = micSel.value ? { deviceId: { exact: micSel.value } } : true;
          const two = isPhone() ? null : await openTwoCameras(audio);
          if (two) {
            mixer = makeMixer(two.main, two.face, null, stage);
            mixer.mirror = true;
            mixer.twoCams = true;
          } else {
            // One camera (or one at a time): the background is your camera, and the bubble
            // is a live zoom on your face from the same camera. Works on every device.
            const video = camSel.value && !isPhone() ? { deviceId: { exact: camSel.value } } : { facingMode: 'user' };
            let main;
            try { main = await navigator.mediaDevices.getUserMedia({ video: { ...video, width: { ideal: 1280 }, height: { ideal: 720 } }, audio }); }
            catch (err) {
              if (err.name === 'NotAllowedError' || err.name === 'SecurityError') throw err;
              main = await navigator.mediaDevices.getUserMedia({ video: true });
            }
            mixer = makeMixer(main, null, null, stage);
            mixer.single = true; mixer.sameCam = true; mixer.facing = 'user'; mixer.mirrorMain = true;
          }
          mixer.size = +bubbleSize.value;
          Object.defineProperty(mixer, 'x', { get: () => bubble.x });
          Object.defineProperty(mixer, 'y', { get: () => bubble.y });
          stream = mixer.stream;
        } else if (source === 'both') {
          const screen = await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: 30 }, audio: true });
          let cam = null;
          try {
            cam = await navigator.mediaDevices.getUserMedia({
              video: camSel.value ? { deviceId: { exact: camSel.value } } : { facingMode: facing, width: { ideal: 640 } },
              audio: micSel.value ? { deviceId: { exact: micSel.value } } : true,
            });
          } catch (e) {
            try { cam = await navigator.mediaDevices.getUserMedia({ video: { facingMode: facing } }); } catch {}
            toast(cam ? 'No microphone found, recording without your voice' : "Your camera couldn't start, so only the screen will be recorded");
          }
          mixer = makeMixer(screen, cam, null, stage);
          mixer.size = +bubbleSize.value;
          mixer.mirror = facing === 'user';
          Object.defineProperty(mixer, 'x', { get: () => bubble.x });
          Object.defineProperty(mixer, 'y', { get: () => bubble.y });
          stream = mixer.stream;
          screen.getVideoTracks()[0].addEventListener('ended', () => { if (recording()) recorder.stop(); else stopStream(); });
        } else {
          const screen = await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: 30 }, audio: true });
          // Add the microphone so you can talk over the screen recording.
          try {
            const mic = await navigator.mediaDevices.getUserMedia({ audio: micSel.value ? { deviceId: { exact: micSel.value } } : true });
            mic.getAudioTracks().forEach((t) => screen.addTrack(t));
          } catch {}
          stream = screen;
          // If you press the browser's "Stop sharing" button, finish the recording.
          stream.getVideoTracks()[0].addEventListener('ended', () => { if (recording()) recorder.stop(); else stopStream(); });
        }
      } catch (e) {
        stream = null;
        if (leaving) return false;
        if (e.name === 'NoMix') {
          showMsg("This browser is too old to put your face in a bubble. Update it, or open VidGame in Chrome, Edge, Firefox or Safari.", false);
        } else if (e.name === 'ToScreen') {
          setTimeout(() => {
            setSource('both');
            showMsg('This computer has one camera, so the other way will be your screen. Press the red button and pick what to show. Your face goes in the bubble.', false);
          });
        } else if (source === 'screen' || source === 'both') {
          showMsg(e.name === 'NotAllowedError'
            ? 'Screen recording was cancelled. Press the red button to try again.'
            : "Screen recording couldn't start on this device. Try the 📷 Camera instead.", false);
        } else if (e.name === 'NotAllowedError' || e.name === 'SecurityError') {
          if (inFrame) showMsg("This preview window can't use your camera. Open VidGame in its own browser tab to record, or use ＋ Post to upload a video.", false);
          else showMsg('Your browser blocked the camera. Click the camera icon in the address bar, choose Allow, then press Try again.', true);
        } else if (e.name === 'NotFoundError' || e.name === 'OverconstrainedError') {
          showMsg(canScreen
            ? "No camera was found on this device. Plug one in and press Try again, or switch to 🖥 Screen to record your screen instead."
            : 'No camera was found on this device. Plug one in and press Try again.', true);
        } else if (e.name === 'NotReadableError') {
          showMsg('Your camera is being used by another app (like Zoom or Teams). Close it, then press Try again.', true);
        } else {
          showMsg("The camera couldn't start (" + (e.message || e.name) + '). Press Try again.', true);
        }
        return false;
      }
      if (leaving) { stopStream(); return false; }
      preview.srcObject = mixer ? null : stream;
      stage.classList.toggle('mixing', !!mixer);
      hideMsg();
      paintLiveControls();

      listDevices();
      return true;
    })();
    const ok = await starting;
    starting = null;
    return ok;
  }
  function startCamera() { return startSource(); }
  retry.onclick = () => { stopStream(); startSource(); };

  async function listDevices() {
    let devices = [];
    try { devices = await navigator.mediaDevices.enumerateDevices(); } catch { return; }
    const fill = (sel, kind, label) => {
      const current = stream && stream.getTracks().find((t) => t.kind === kind.replace('input', ''));
      const currentId = current && current.getSettings().deviceId;
      sel.innerHTML = '';
      devices.filter((d) => d.kind === kind).forEach((d, i) => {
        const o = document.createElement('option');
        o.value = d.deviceId;
        o.textContent = kind === 'videoinput' ? camName(d, i) : d.label || `${label} ${i + 1}`;
        if (d.deviceId === currentId) o.selected = true;
        sel.appendChild(o);
      });
      sel.hidden = sel.options.length < 2 || (kind === 'videoinput' && source === 'screen');

    };
    // Friendly camera names: "Front camera (your face)" / "Back camera (the other way)".
    const seen = {};
    const camName = (d, i) => {
      const l = d.label || '';
      let name;
      if (/front|user|facetime|integrated|built-?in|selfie/i.test(l)) name = '🤳 Front camera (your face)';
      else if (/back|rear|environment|world/i.test(l)) name = '🔄 Back camera (the other way)';
      else if (!isPhone() && i === 0) name = '🤳 Front camera (your face)';
      else name = '📷 ' + (l.replace(/\s*\([0-9a-f]{4}:[0-9a-f]{4}\)/i, '') || 'Camera ' + (i + 1));
      seen[name] = (seen[name] || 0) + 1;
      return seen[name] > 1 ? `${name} ${seen[name]}` : name;
    };
    fill(camSel, 'videoinput', 'Camera');
    fill(micSel, 'audioinput', 'Microphone');
  }
  camSel.onchange = () => { stopStream(); startSource(); };
  micSel.onchange = () => { stopStream(); startSource(); };

  function setPausedUi(p) {
    pausedCover.hidden = !p;
    badge.classList.toggle('paused', p);
    btnPause.textContent = p ? '▶ Resume' : '❚❚ Pause';
    recLabel.textContent = p ? 'Paused. Press Resume to keep going.' : 'Recording… press Pause for a break or Stop when you are done';
  }

  btnStart.onclick = async () => {
    if (recording()) return;
    btnStart.disabled = true;
    const ok = await startSource();
    btnStart.disabled = false;
    if (!ok || leaving) return;
    chunks = [];
    const mimeType = pickMimeType();
    try {
      recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
    } catch {
      recorder = new MediaRecorder(stream);
    }
    recorder.ondataavailable = (e) => { if (e.data && e.data.size) chunks.push(e.data); };
    recorder.onstop = () => {
      clearInterval(tick);
      badge.hidden = true;
      pausedCover.hidden = true;
      srcCamera.disabled = srcScreen.disabled = srcBoth.disabled = flipBtn.disabled = dualBtn.disabled = false;
      camSel.disabled = micSel.disabled = false;
      if (leaving) return;
      if (source === 'screen' || source === 'both') { stopStream(); showMsg('Press the red button to record your screen again.', false); }
      btnPause.hidden = btnStop.hidden = true;
      btnStart.hidden = false;
      recLabel.textContent = 'Press the red button to record again';
      if (!chunks.length) { toast('Nothing was recorded. Try again.'); return; }
      blob = new Blob(chunks, { type: (recorder.mimeType || 'video/webm').split(';')[0] });
      if (blobUrl) URL.revokeObjectURL(blobUrl);
      blobUrl = URL.createObjectURL(blob);
      reviewPlayer.src = blobUrl;
      reviewPlayer.addEventListener('loadedmetadata', () => fixDuration(reviewPlayer), { once: true });
      btnDl.href = blobUrl;
      btnDl.download = 'recording.' + (blob.type.includes('mp4') ? 'mp4' : 'webm');
      titleInput.value = 'My video ' + new Date().toLocaleDateString();
      review.hidden = false;
      btnSave.disabled = false;
      btnSave.textContent = 'Post video';
      review.scrollIntoView({ behavior: 'smooth' });
    };
    // Paused time is never written to the file, so breaks don't show up in the video.
    recorder.start(1000);
    review.hidden = true;
    elapsed = 0;
    timer.textContent = '0:00';
    badge.hidden = false;
    setPausedUi(false);
    tick = setInterval(() => {
      if (recorder.state !== 'recording') return;
      timer.textContent = fmtTime(++elapsed);
      if (elapsed >= MAX_SECONDS) { toast('You reached 48 hours, the longest a video can be. Recording stopped.'); recorder.stop(); }
    }, 1000);
    btnStart.hidden = true;
    btnPause.hidden = typeof recorder.pause !== 'function';
    btnStop.hidden = false;
    srcCamera.disabled = srcScreen.disabled = srcBoth.disabled = dualBtn.disabled = true;
    flipBtn.disabled = !(mixer && (mixer.single || mixer.twoCams));
    camSel.disabled = micSel.disabled = true;
  };

  btnPause.onclick = () => {
    if (recorder.state === 'recording') { recorder.pause(); setPausedUi(true); }
    else if (recorder.state === 'paused') { recorder.resume(); setPausedUi(false); }
  };
  btnStop.onclick = () => { if (recording()) recorder.stop(); };
  btnRetake.onclick = () => { review.hidden = true; reviewPlayer.pause(); window.scrollTo(0, 0); btnStart.click(); };

  btnSave.onclick = async () => {
    if (!blob) return;
    btnSave.disabled = true;
    btnSave.textContent = 'Posting…';
    try {
      const v = await uploadVideo(blob, titleInput.value.trim(), true, elapsed);
      toast('Video posted to your channel!');
      location.hash = '#/watch/' + v.id;
    } catch (e) {
      toast(e.message);
      btnSave.disabled = false;
      btnSave.textContent = 'Post video';
    }
  };

  stage.classList.toggle('mirror', mirror.checked);
  if (!canRecord) showMsg("This browser can't record video. Open VidGame in Chrome, Edge or Safari.", false);
  else startCamera();
}

// ---------- post sheet (record or upload) ----------
const sheet = document.getElementById('post-sheet');
function openPostSheet() { sheet.hidden = false; document.getElementById('opt-record').focus(); }
function closePostSheet() { sheet.hidden = true; }
document.getElementById('post-btn').onclick = openPostSheet;
document.getElementById('sheet-cancel').onclick = closePostSheet;
document.getElementById('opt-record').addEventListener('click', closePostSheet);
sheet.addEventListener('click', (e) => { if (e.target === sheet) closePostSheet(); });
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !sheet.hidden) closePostSheet(); });

document.getElementById('upload-input').addEventListener('change', async (e) => {
  const file = e.target.files[0];
  e.target.value = '';
  closePostSheet();
  if (!file) return;
  toast('Uploading ' + file.name + '…');
  try {
    const v = await uploadVideo(file, file.name.replace(/\.[^.]+$/, ''), false);
    toast('Video posted to your channel!');
    location.hash = '#/watch/' + v.id;
  } catch (err) { toast(err.message); }
});

// ---------- tutorial video ----------
// The tutorial is a real screen recording of the app (tutorial.webm).
const TUTORIAL_SRC = window.VIDGAME_TUTORIAL_SRC || 'tutorial.webm';
const tutorial = (() => {
  const el = document.getElementById('tutorial');
  const video = document.getElementById('tut-video');
  const input = document.getElementById('tut-name-input');
  function finish() {
    const name = input.value.trim();
    if (name) prefs.set('channel', name);
    el.hidden = true;
    video.pause();
    prefs.set('tutorialSeen', '1');
    route();
  }
  document.getElementById('tut-done').onclick = finish;
  document.getElementById('tut-skip').onclick = finish;
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') finish(); });
  document.addEventListener('keydown', (e) => { if (!el.hidden && e.key === 'Escape') finish(); });
  return {
    open() {
      closePostSheet();
      if (!video.src) video.src = TUTORIAL_SRC;
      input.value = prefs.get('channel', '');
      el.hidden = false;
      video.currentTime = 0;
      video.play().catch(() => {});
    },
  };
})();
document.getElementById('help-btn').onclick = () => tutorial.open();

// ---------- router ----------
function route() {
  if (cleanup) { cleanup(); cleanup = null; }
  const [, page, id] = location.hash.split('/');
  window.scrollTo(0, 0);
  document.querySelectorAll('.bottom-bar .tab').forEach((t) =>
    t.classList.toggle('active', t.dataset.tab === (['channel', 'stars', 'vidgames'].includes(page) ? page : !page ? 'home' : '')));
  refreshAvatars();
  if (page === 'record') return showRecord();
  if (page === 'watch' && id) return showWatch(id);
  if (page === 'channel') return showChannel();
  if (page === 'stars') return showStars();
  if (page === 'vidgames') return showVidgames();
  return showHome();
}
function runSearch() {
  if (location.hash.length > 2) location.hash = '#/';
  else showHome();
}
searchBox.addEventListener('input', runSearch);
document.getElementById('search-form').addEventListener('submit', (e) => {
  e.preventDefault();
  searchBox.blur();
  runSearch();
});
window.addEventListener('hashchange', route);
route();
if (!prefs.get('tutorialSeen', '')) tutorial.open();
