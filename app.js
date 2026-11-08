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
  const m = Math.floor(sec / 60), s = sec % 60;
  return `${m}:${String(s).padStart(2, '0')}`;
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
const EXAMPLES_CHANNEL = { channelId: 'vidgame-examples', channelName: 'VidGame Examples', badge: { type: 'emoji', emoji: '⭐', color: '#e11d48' } };
const EXAMPLES = [
  { id: 'ex-ball', title: 'Bouncing ball challenge', file: 'examples/ball.webm', hoursAgo: 5, baseViews: 128 },
  { id: 'ex-tutorial', title: 'How to record a video on VidGame', file: 'tutorial.webm', hoursAgo: 20, baseViews: 210 },
  { id: 'ex-count', title: 'Colour countdown 10 to 1', file: 'examples/count.webm', hoursAgo: 30, baseViews: 54 },
  { id: 'ex-rocket', title: 'Rocket launch into space', file: 'examples/rocket.webm', hoursAgo: 60, baseViews: 342 },
  { id: 'ex-wave', title: 'Waving at everyone', file: 'examples/wave.webm', hoursAgo: 400, baseViews: 87 },
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
    views: e.baseViews + (extra[e.id] || 0),
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
async function uploadVideo(blob, title, recorded) {
  if (!blob.type.startsWith('video/')) throw new Error('That file is not a video.');
  const v = {
    id: Date.now().toString(36) + Math.random().toString(36).slice(2, 8),
    title: (title || 'Untitled video').slice(0, 120),
    type: blob.type,
    size: blob.size,
    views: 0,
    recorded,
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
    a.querySelector('.stats').textContent = `${viewsText(v.views)} · ${timeAgo(v.createdAt)}`;
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
    .map((v) => ({ v, score: (v.views || 0) / Math.pow(ageHours(v) + 2, 1.2) }))
    .sort((x, y) => y.score - x.score).slice(0, 12).map((x) => x.v);
  // People you watch: channels you keep coming back to.
  const watched = watchedChannels();
  const following = videos.filter((v) => !isMine(v) && watched[v.channelId])
    .sort((x, y) => watched[y.channelId] - watched[x.channelId] || y.createdAt.localeCompare(x.createdAt)).slice(0, 12);

  addShelf(box, '🆕 Brand new', 'Posted in the last 7 days', brandNew, true, 'New videos show up here as soon as they are posted.');
  addShelf(box, '👀 People you watch', 'Channels you watch a lot', following, true, "Watch someone's video and their channel shows up here.");
  addShelf(box, '🔥 Popular right now', 'Most watched lately', popular, true, 'Videos with the most views right now show up here.');
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

async function showRecord() {
  render('tpl-record');
  const $ = (id) => document.getElementById(id);
  const preview = $('preview'), stage = document.querySelector('.stage');
  const msgBox = $('cam-msg'), msgText = $('cam-msg-text'), retry = $('cam-retry');
  const camSel = $('camera-select'), micSel = $('mic-select'), mirror = $('mirror'), mirrorWrap = $('mirror-wrap');
  const srcCamera = $('src-camera'), srcScreen = $('src-screen');
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
  if (!canScreen) srcScreen.hidden = true;

  const stopStream = () => { if (stream) stream.getTracks().forEach((t) => t.stop()); stream = null; preview.srcObject = null; };
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

  function setSource(s) {
    if (recording()) return;
    source = s;
    srcCamera.classList.toggle('active', s === 'camera'); srcCamera.setAttribute('aria-pressed', s === 'camera');
    srcScreen.classList.toggle('active', s === 'screen'); srcScreen.setAttribute('aria-pressed', s === 'screen');
    camSel.hidden = mirrorWrap.hidden = s === 'screen';
    stage.classList.toggle('mirror', mirror.checked && s === 'camera');
    stopStream();
    if (s === 'camera') startCamera();
    else showMsg('Press the red button, then pick the screen or window you want to record.', false);
  }
  srcCamera.onclick = () => setSource('camera');
  srcScreen.onclick = () => setSource('screen');

  // Turn on the camera (or screen). Returns true when there is something to record.
  async function startSource() {
    if (stream) return true;
    if (starting) return starting;
    starting = (async () => {
      if (!canRecord) { showMsg("This browser can't record video. Open VidGame in Chrome, Edge or Safari.", false); return false; }
      try {
        if (source === 'camera') {
          showMsg('Starting camera… If your browser asks, press Allow.', false);
          const video = camSel.value ? { deviceId: { exact: camSel.value } } : {};
          const audio = micSel.value ? { deviceId: { exact: micSel.value } } : true;
          try {
            stream = await navigator.mediaDevices.getUserMedia({ video: { width: { ideal: 1280 }, height: { ideal: 720 }, ...video }, audio });
          } catch (e) {
            if (e.name === 'NotAllowedError' || e.name === 'SecurityError') throw e;
            // Maybe there's no microphone, or the chosen device is gone: try camera only.
            stream = await navigator.mediaDevices.getUserMedia({ video: true });
            toast('No microphone found, recording without sound');
          }
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
        if (source === 'screen') {
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
      preview.srcObject = stream;
      hideMsg();
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
        o.textContent = d.label || `${label} ${i + 1}`;
        if (d.deviceId === currentId) o.selected = true;
        sel.appendChild(o);
      });
      sel.hidden = sel.options.length < 2 || (kind === 'videoinput' && source === 'screen');
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
      srcCamera.disabled = srcScreen.disabled = false;
      camSel.disabled = micSel.disabled = false;
      if (leaving) return;
      if (source === 'screen') { stopStream(); showMsg('Press the red button to record your screen again.', false); }
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
    tick = setInterval(() => { if (recorder.state === 'recording') timer.textContent = fmtTime(++elapsed); }, 1000);
    btnStart.hidden = true;
    btnPause.hidden = typeof recorder.pause !== 'function';
    btnStop.hidden = false;
    srcCamera.disabled = srcScreen.disabled = true;
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
      const v = await uploadVideo(blob, titleInput.value.trim(), true);
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
    t.classList.toggle('active', t.dataset.tab === (page === 'channel' ? 'channel' : !page ? 'home' : '')));
  refreshAvatars();
  if (page === 'record') return showRecord();
  if (page === 'watch' && id) return showWatch(id);
  if (page === 'channel') return showChannel();
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
