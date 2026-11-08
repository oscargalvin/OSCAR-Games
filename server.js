// Runs OscarTube on your own computer at http://localhost:3000.
// You don't need this for the online version on GitHub Pages. No packages needed. Run with: npm start
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;
const PUBLIC_DIR = __dirname;
const ALLOWED = new Set(['/index.html', '/app.js', '/style.css']);
const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
};

http.createServer((req, res) => {
  const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const name = p === '/' ? '/index.html' : p;
  if (!ALLOWED.has(name)) { res.writeHead(404); return res.end('Not found'); }
  const file = path.join(PUBLIC_DIR, name);
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end('Not found'); }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
    res.end(data);
  });
}).listen(PORT, () => {
  console.log(`\n  OscarTube is running! Open http://localhost:${PORT} in Chrome or Edge.\n  Press Ctrl+C to stop.\n`);
});
