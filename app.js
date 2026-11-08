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
const prefs = {
  get(k, d) { try { const v = localStorage.getItem('vidgame.' + k); return v === null ? d : v; } catch { return d; } },
  set(k, v) { try { localStorage.setItem('vidgame.' + k, v); } catch {} },
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
  const tv = document.getElementById('home-tut-video');
  tv.src = TUTORIAL_SRC;
  if (document.getElementById('tutorial').hidden) tv.play().catch(() => {});
  cleanup = () => tv.pause();
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
  document.title = v.title + ' · VidGame';
  document.getElementById('watch-channel').textContent = channelName();
  paintAvatar(document.getElementById('watch-avatar'));
  document.getElementById('watch-info').textContent =
    `${viewsText(v.views)} · ${timeAgo(v.createdAt)} · ${fmtSize(v.size)}${v.recorded ? ' · Recorded in VidGame' : ''}`;
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
searchBox.addEventListener('input', () => {
  if (location.hash.length > 2) location.hash = '#/';
  else showHome();
});
window.addEventListener('hashchange', route);
route();
if (!prefs.get('tutorialSeen', '')) tutorial.open();
