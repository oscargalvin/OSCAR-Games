// OscarTube front end: library, watch page, upload, and in-app recording.
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
function render(id) {
  app.innerHTML = '';
  app.appendChild(document.getElementById(id).content.cloneNode(true));
}
// ---------- storage: videos are kept in this browser (IndexedDB) ----------
const DB_NAME = 'oscartube', STORE = 'videos';
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

// ---------- home ----------
async function showHome() {
  render('tpl-home');
  const grid = document.getElementById('grid');
  let videos = [];
  try { videos = await store.list(); } catch (e) { toast(e.message); }
  const q = searchBox.value.trim().toLowerCase();
  if (q) videos = videos.filter((v) => v.title.toLowerCase().includes(q));
  document.getElementById('empty').hidden = videos.length > 0;
  if (q && !videos.length) document.querySelector('#empty p').textContent = `No videos match "${searchBox.value}".`;

  for (const v of videos) {
    const a = document.createElement('a');
    a.className = 'card';
    a.href = '#/watch/' + v.id;
    a.innerHTML = `
      <div class="thumb"><video muted preload="metadata"></video><span class="duration" hidden></span></div>
      <h3></h3><p></p>`;
    a.querySelector('h3').textContent = v.title;
    a.querySelector('p').textContent = `${v.views || 0} view${v.views === 1 ? "" : "s"} · ${timeAgo(v.createdAt)}`;
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
  document.title = v.title + ' · OscarTube';
  document.getElementById('watch-info').textContent =
    `${v.views} view${v.views === 1 ? "" : "s"} · ${timeAgo(v.createdAt)} · ${fmtSize(v.size)}${v.recorded ? ' · Recorded in OscarTube' : ''}`;
  const dl = document.getElementById('download');
  dl.href = mediaUrl(v);
  dl.download = v.title.replace(/[^\w\- ]+/g, '').trim() + '.' + extOf(v);
  document.getElementById('delete').onclick = async () => {
    if (!confirm(`Delete "${v.title}"? This can't be undone.`)) return;
    await store.remove(v.id);
    URL.revokeObjectURL(urls.get(v.id)); urls.delete(v.id);
    toast('Video deleted');
    location.hash = '#/';
  };
  cleanup = () => { player.pause(); document.title = 'OscarTube'; };
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
      btnSave.textContent = 'Save video';
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
    btnSave.textContent = 'Saving…';
    try {
      const v = await uploadVideo(blob, titleInput.value.trim(), true);
      toast('Video saved!');
      location.hash = '#/watch/' + v.id;
    } catch (e) {
      toast(e.message);
      btnSave.disabled = false;
      btnSave.textContent = 'Save video';
    }
  };

  startCamera();
}

// ---------- upload from file ----------
document.getElementById('upload-input').addEventListener('change', async (e) => {
  const file = e.target.files[0];
  e.target.value = '';
  if (!file) return;
  toast('Uploading ' + file.name + '…');
  try {
    const v = await uploadVideo(file, file.name.replace(/\.[^.]+$/, ''), false);
    toast('Uploaded!');
    location.hash = '#/watch/' + v.id;
  } catch (err) { toast(err.message); }
});

// ---------- router ----------
function route() {
  if (cleanup) { cleanup(); cleanup = null; }
  const [, page, id] = location.hash.split('/');
  window.scrollTo(0, 0);
  if (page === 'record') return showRecord();
  if (page === 'watch' && id) return showWatch(id);
  return showHome();
}
searchBox.addEventListener('input', () => {
  if (location.hash.startsWith('#/watch') || location.hash.startsWith('#/record')) location.hash = '#/';
  else showHome();
});
window.addEventListener('hashchange', route);
route();
