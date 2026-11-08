// VidPlay front end: home, channel, watch page, posting (record or upload) and the tutorial.
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
const prefs = {
  get(k, d) { try { const v = localStorage.getItem('vidplay.' + k); return v === null ? d : v; } catch { return d; } },
  set(k, v) { try { localStorage.setItem('vidplay.' + k, v); } catch {} },
};
const AVATAR_COLORS = ['#7c3aed', '#2563eb', '#0d9488', '#ea580c', '#db2777', '#4f46e5', '#16a34a'];
function channelName() { return prefs.get('channel', 'My Channel'); }
function paintAvatar(el, name = channelName()) {
  if (!el) return;
  el.textContent = (name.trim()[0] || 'V').toUpperCase();
  let h = 0; for (const c of name) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  el.style.setProperty('--avatar', AVATAR_COLORS[h % AVATAR_COLORS.length]);
}
function refreshAvatars() { document.querySelectorAll('#tab-avatar, #ch-avatar, #watch-avatar').forEach((el) => paintAvatar(el)); }
function viewsText(n) { n = n || 0; return `${n} view${n === 1 ? '' : 's'}`; }

function render(id) {
  app.innerHTML = '';
  app.appendChild(document.getElementById(id).content.cloneNode(true));
}
// ---------- storage: videos are kept in this browser (IndexedDB) ----------
const DB_NAME = 'vidplay', STORE = 'videos';
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
const store = {
  async list() {
    const all = await tx('readonly', (s) => s.getAll());
    return all.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  },
  get: (id) => tx('readonly', (s) => s.get(id)),
  put: (v) => tx('readwrite', (s) => s.put(v)),
  remove: (id) => tx('readwrite', (s) => s.delete(id)),
};
const urls = new Map(); // id -> object URL, so each video blob is only wrapped once
function mediaUrl(v) {
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
    paintAvatar(a.querySelector('.avatar'));
    a.querySelector('.by-name').textContent = channelName();
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
  document.getElementById('tut-card').onclick = () => tutorial.open();
  wirePostButtons();
  let videos = [];
  try { videos = await store.list(); } catch (e) { toast(e.message); }
  const q = searchBox.value.trim().toLowerCase();
  if (q) videos = videos.filter((v) => v.title.toLowerCase().includes(q));
  document.getElementById('empty').hidden = videos.length > 0;
  if (q && !videos.length) document.querySelector('#empty p').textContent = `No videos match "${searchBox.value}".`;
  fillGrid(document.getElementById('grid'), videos);
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
  async function showChannelVideos() {
    let videos = [];
    try { videos = await store.list(); } catch (e) { toast(e.message); }
    const views = videos.reduce((n, v) => n + (v.views || 0), 0);
    document.getElementById('ch-stats').textContent =
      `${videos.length} video${videos.length === 1 ? '' : 's'} · ${viewsText(views)}`;
    document.getElementById('empty').hidden = videos.length > 0;
    const grid = document.getElementById('grid');
    grid.innerHTML = '';
    fillGrid(grid, videos);
  }
  showChannelVideos();
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
  } catch (e) { app.innerHTML = `<p class="empty">${e.message} <a class="btn" href="#/">Back</a></p>`; return; }
  const player = document.getElementById('player');
  player.src = mediaUrl(v);
  player.addEventListener('loadedmetadata', () => fixDuration(player).then(() => player.play().catch(() => {})), { once: true });
  document.getElementById('watch-title').textContent = v.title;
  document.title = v.title + ' · VidPlay';
  document.getElementById('watch-channel').textContent = channelName();
  paintAvatar(document.getElementById('watch-avatar'));
  document.getElementById('watch-info').textContent =
    `${viewsText(v.views)} · ${timeAgo(v.createdAt)} · ${fmtSize(v.size)}${v.recorded ? ' · Recorded in VidPlay' : ''}`;
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
  cleanup = () => { player.pause(); document.title = 'VidPlay'; };
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
  const preview = document.getElementById('preview');
  const stage = document.querySelector('.stage');
  const msg = document.getElementById('cam-msg');
  const camSel = document.getElementById('camera-select');
  const micSel = document.getElementById('mic-select');
  const mirror = document.getElementById('mirror');
  const btnStart = document.getElementById('btn-start');
  const btnPause = document.getElementById('btn-pause');
  const btnStop = document.getElementById('btn-stop');
  const badge = document.getElementById('rec-badge');
  const timer = document.getElementById('timer');
  const review = document.getElementById('review');
  const reviewPlayer = document.getElementById('review-player');
  const titleInput = document.getElementById('title');
  const btnSave = document.getElementById('btn-save');
  const btnDl = document.getElementById('btn-download-rec');
  const btnRetake = document.getElementById('btn-retake');

  let stream = null, recorder = null, chunks = [], blob = null, blobUrl = null;
  let elapsed = 0, tick = null, leaving = false;

  const stopStream = () => { if (stream) stream.getTracks().forEach((t) => t.stop()); stream = null; };
  cleanup = () => {
    leaving = true;
    if (recorder && recorder.state !== 'inactive') recorder.stop();
    clearInterval(tick);
    stopStream();
    if (blobUrl) URL.revokeObjectURL(blobUrl);
  };

  mirror.onchange = () => stage.classList.toggle('mirror', mirror.checked);
  stage.classList.toggle('mirror', mirror.checked);

  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || !window.MediaRecorder) {
    msg.textContent = 'This browser cannot record video. Try Chrome or Edge.';
    return;
  }

  async function startCamera() {
    stopStream();
    msg.textContent = 'Starting camera…';
    btnStart.disabled = true;
    const video = camSel.value ? { deviceId: { exact: camSel.value } } : {};
    const audio = micSel.value ? { deviceId: { exact: micSel.value } } : true;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        video: { width: { ideal: 1280 }, height: { ideal: 720 }, ...video },
        audio,
      });
    } catch (e) {
      // Fall back to camera only if there is no microphone.
      try { stream = await navigator.mediaDevices.getUserMedia({ video: true }); toast('No microphone found, recording without sound'); }
      catch (e2) {
        msg.textContent = e2.name === 'NotAllowedError'
          ? 'Camera access was blocked. Click the camera icon in the address bar, allow it, then reload the page.'
          : 'No camera found. Plug one in and reload the page.';
        return;
      }
    }
    if (leaving) return stopStream();
    preview.srcObject = stream;
    msg.textContent = '';
    btnStart.disabled = false;
    await listDevices();
  }

  async function listDevices() {
    const devices = await navigator.mediaDevices.enumerateDevices();
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
      sel.hidden = sel.options.length < 2;
    };
    fill(camSel, 'videoinput', 'Camera');
    fill(micSel, 'audioinput', 'Microphone');
  }
  camSel.onchange = startCamera;
  micSel.onchange = startCamera;

  btnStart.onclick = () => {
    if (!stream) return;
    chunks = [];
    const mimeType = pickMimeType();
    recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
    recorder.ondataavailable = (e) => { if (e.data.size) chunks.push(e.data); };
    recorder.onstop = () => {
      clearInterval(tick);
      badge.hidden = true;
      if (leaving) return;
      blob = new Blob(chunks, { type: (recorder.mimeType || 'video/webm').split(';')[0] });
      if (blobUrl) URL.revokeObjectURL(blobUrl);
      blobUrl = URL.createObjectURL(blob);
      reviewPlayer.src = blobUrl;
      reviewPlayer.addEventListener('loadedmetadata', () => fixDuration(reviewPlayer), { once: true });
      btnDl.href = blobUrl;
      btnDl.download = 'recording.' + (blob.type.includes('mp4') ? 'mp4' : 'webm');
      titleInput.value = 'My video ' + new Date().toLocaleString();
      review.hidden = false;
      btnSave.disabled = false;
      btnSave.textContent = 'Post video';
      btnPause.hidden = btnStop.hidden = true;
      camSel.disabled = micSel.disabled = false;
      review.scrollIntoView({ behavior: 'smooth' });
    };
    recorder.start(1000);
    review.hidden = true;
    elapsed = 0;
    timer.textContent = '0:00';
    badge.hidden = false;
    badge.classList.remove('paused');
    tick = setInterval(() => { if (recorder.state === 'recording') timer.textContent = fmtTime(++elapsed); }, 1000);
    btnStart.hidden = true;
    btnPause.hidden = btnStop.hidden = false;
    btnPause.textContent = '❚❚ Pause';
    camSel.disabled = micSel.disabled = true;
  };

  btnPause.onclick = () => {
    if (recorder.state === 'recording') { recorder.pause(); btnPause.textContent = '▶ Resume'; badge.classList.add('paused'); }
    else if (recorder.state === 'paused') { recorder.resume(); btnPause.textContent = '❚❚ Pause'; badge.classList.remove('paused'); }
  };
  btnStop.onclick = () => recorder && recorder.state !== 'inactive' && recorder.stop();
  btnRetake.onclick = () => { review.hidden = true; reviewPlayer.pause(); btnStart.click(); };

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

  startCamera();
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

// ---------- tutorial: a short "video" that plays itself, with Back / Pause / Next ----------
const TAP = (x, y) => `<span class="m-tap" style="left:${x};top:${y}"></span>`;
const PHONE_HOME = `<div class="m-top"><span class="logo-mark">▶</span>VidPlay</div>
  <div class="m-grid"><div class="m-thumb"></div><div class="m-thumb"></div><div class="m-thumb"></div><div class="m-thumb"></div></div>`;
const PHONE_BAR = `<div class="m-bar"><span></span><span class="m-plus">＋</span><span class="m-me"></span></div>`;
const TUTORIAL_STEPS = [
  {
    title: 'Welcome to VidPlay',
    body: 'Make videos, post them, and watch them back. This quick tutorial shows you how.',
    screen: `<div class="m-hello"><div><span class="logo-mark">▶</span><b>VidPlay</b></div></div>`,
  },
  {
    title: 'Tap Post to make a video',
    body: 'The big red ＋ button at the bottom lets you record a new video or upload one you already have.',
    screen: PHONE_HOME + PHONE_BAR + TAP('calc(50% - 19px)', 'calc(100% - 50px)'),
  },
  {
    title: 'Pick Record or Upload',
    body: 'Record uses your camera and microphone. Upload picks a video file from your device.',
    screen: PHONE_HOME + PHONE_BAR + `<div class="m-sheet"><div><b>●</b> Record a video</div><div>⬆ Upload a video</div></div>`,
  },
  {
    title: 'Press the red button to record',
    body: 'Allow the camera when your browser asks. Press Start to record, Pause if you need a break, and Stop when you are done.',
    screen: `<div class="m-cam"></div><span class="m-badge">0:07</span><span class="m-rec"></span>`,
  },
  {
    title: 'Give it a title and post it',
    body: 'Watch your recording back first. If you like it, type a title and press Post video.',
    screen: `<div class="m-review"><div class="m-thumb"></div><div class="m-input"><span>My first video!!</span></div><div class="m-post">Post video</div></div>`,
  },
  {
    title: 'Find it on Your channel',
    body: 'Everything you post is on Your channel, at the bottom right. Give your channel a name to get started.',
    screen: `<div class="m-top"><span class="logo-mark">▶</span>VidPlay</div>
      <div class="m-channel"><span class="avatar" id="tut-avatar"></span><b id="tut-chname"></b><small>3 videos · 12 views</small>
      <div class="m-grid"><div class="m-thumb"></div><div class="m-thumb"></div></div></div>` + PHONE_BAR + TAP('calc(83% - 19px)', 'calc(100% - 42px)'),
    extra: `<input id="tut-name-input" class="tut-name" maxlength="40" placeholder="Your channel name" aria-label="Your channel name">`,
    last: true,
  },
];
const STEP_MS = 5500;
const tutorial = (() => {
  const el = document.getElementById('tutorial');
  const bars = document.getElementById('tut-bars');
  const screen = document.getElementById('tut-screen');
  const pauseBtn = document.getElementById('tut-pause');
  const nextBtn = document.getElementById('tut-next');
  const backBtn = document.getElementById('tut-back');
  let i = 0, elapsed = 0, last = 0, paused = false, raf = 0;

  bars.innerHTML = TUTORIAL_STEPS.map(() => '<div class="tut-bar"><i></i></div>').join('');
  const fills = [...bars.querySelectorAll('i')];

  function show(n) {
    i = Math.max(0, Math.min(TUTORIAL_STEPS.length - 1, n));
    const step = TUTORIAL_STEPS[i];
    elapsed = 0;
    screen.innerHTML = step.screen;
    document.getElementById('tut-title').textContent = step.title;
    document.getElementById('tut-body').textContent = step.body;
    document.getElementById('tut-extra').innerHTML = step.extra || '';
    fills.forEach((f, k) => (f.style.width = k < i ? '100%' : '0%'));
    backBtn.disabled = i === 0;
    nextBtn.textContent = step.last ? 'Start using VidPlay' : 'Next';
    if (step.last) {
      const input = document.getElementById('tut-name-input');
      const preview = () => {
        const name = input.value.trim() || channelName();
        document.getElementById('tut-chname').textContent = name;
        paintAvatar(document.getElementById('tut-avatar'), name);
      };
      input.value = prefs.get('channel', '') ;
      input.oninput = preview;
      input.onkeydown = (e) => { if (e.key === 'Enter') finish(); };
      input.onfocus = () => setPaused(true);
      preview();
    }
  }
  function setPaused(p) {
    paused = p;
    pauseBtn.textContent = p ? '▶' : '❚❚';
    pauseBtn.setAttribute('aria-label', p ? 'Play tutorial' : 'Pause tutorial');
  }
  function frame(t) {
    const dt = last ? t - last : 0;
    last = t;
    if (!paused && !TUTORIAL_STEPS[i].last) {
      elapsed += dt;
      fills[i].style.width = Math.min(100, (elapsed / STEP_MS) * 100) + '%';
      if (elapsed >= STEP_MS) show(i + 1);
    } else if (TUTORIAL_STEPS[i].last) {
      fills[i].style.width = '100%';
    }
    raf = requestAnimationFrame(frame);
  }
  function finish() {
    const input = document.getElementById('tut-name-input');
    if (input && input.value.trim()) prefs.set('channel', input.value.trim());
    close();
    route();
  }
  function close() {
    el.hidden = true;
    cancelAnimationFrame(raf);
    prefs.set('tutorialSeen', '1');
    refreshAvatars();
  }
  nextBtn.onclick = () => (TUTORIAL_STEPS[i].last ? finish() : show(i + 1));
  backBtn.onclick = () => show(i - 1);
  pauseBtn.onclick = () => setPaused(!paused);
  document.getElementById('tut-skip').onclick = finish;
  document.addEventListener('keydown', (e) => {
    if (el.hidden || e.target.tagName === 'INPUT') return;
    if (e.key === 'Escape') finish();
    if (e.key === 'ArrowRight') nextBtn.click();
    if (e.key === 'ArrowLeft') backBtn.click();
  });
  return {
    open() {
      closePostSheet();
      el.hidden = false;
      setPaused(false);
      last = 0;
      show(0);
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(frame);
      nextBtn.focus();
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
searchBox.addEventListener('input', () => {
  if (location.hash.length > 2) location.hash = '#/';
  else showHome();
});
window.addEventListener('hashchange', route);
route();
if (!prefs.get('tutorialSeen', '')) tutorial.open();
