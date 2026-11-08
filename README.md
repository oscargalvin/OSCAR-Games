# OscarTube

A video app where you can record videos with your camera and mic, upload video files, and watch them back.

## Use it online

Open **https://oscargalvin.github.io/OSCAR-Games/** in Chrome, Edge or Safari, on a computer or phone. Nothing needs to be installed or running. It's published by GitHub Pages from the `oscartube` branch of the OSCAR-Games repo, so pushing to that branch updates the site.

## Run it on your own computer instead (optional)

### Setup (one time)

1. Install **Node.js** (version 18 or newer) from https://nodejs.org if you don't have it. To check, open a terminal and run `node -v`.
2. That's it. The app has no other packages to install.

### Start the app

**Easiest (Windows):** double-click `start.bat`. It starts the app and opens it in your browser.

**From a terminal:**

```
cd "path\to\oscar-tube"
npm start
```

Then open http://localhost:3000 in Chrome or Edge. Press `Ctrl+C` in the terminal to stop it.

To use a different port: `set PORT=4000 && npm start` (Windows) or `PORT=4000 npm start` (Mac/Linux).

## How to use it

- **Record:** click **● Record**, allow the camera and microphone when the browser asks, then press **Start recording**. You can pause, resume and stop. After stopping you can watch it back, give it a title, and **Save video**, **Download** it, or **Record again**. Pick a different camera or mic from the dropdowns if you have more than one.
- **Upload:** click **⬆ Upload** and pick a video file from your computer.
- **Watch:** click any video on the home page. Each watch counts a view. You can download or delete it from there.
- **Search:** type in the search box to filter videos by title.

## Where videos are saved

Videos are saved inside the browser you recorded them in (in its storage, called IndexedDB). That means:

- They stay there after you close the tab or restart the computer.
- They only show up in that browser on that device. A different browser or phone has its own separate list.
- Clearing your browser data deletes them, so use **Download** to keep a copy of anything important.

## Notes

- The camera only works on the https link or on `http://localhost:3000`. Browsers block cameras on other plain http addresses.
- If the camera is blocked, click the camera icon in the address bar, allow it, and reload.
- Recordings are saved as `.webm` files, which play in Chrome, Edge, Firefox and VLC.

## Files

- `server.js` runs the app on your own computer (not needed for the online version)
- `index.html`, `app.js`, `style.css` are the website
- `start.bat` is the one-click starter for Windows
