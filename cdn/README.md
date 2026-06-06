# CDN Upload Bundle

Upload the entire `godot/` folder in this directory to your static host or CDN.

What must stay together:
- `index.html`
- `index.js`
- `index.wasm`
- `index.pck`
- `index.offline.html`
- `index.service.worker.js`
- `index.audio.worklet.js`
- `index.audio.position.worklet.js`
- all icon and manifest files

How to use it:
1. Upload `cdn/godot/` as a single directory.
2. Note the public base URL, for example `https://cdn.example.com/godot/`.
3. Open the game through `frontend/public/play.html` with:
   - `?godotBaseUrl=https://cdn.example.com/godot/`
   - or set `window.GODOT_BASE_URL = "https://cdn.example.com/godot/"`.

Important:
- Keep the trailing slash on the base URL.
- The files must remain in the same relative layout, because `index.html` loads its sibling assets by filename.
- If your host serves cross-origin isolation headers, keep them enabled because this export uses web threading.

GitHub Pages:
- Publish the `cdn/` directory as the Pages source, or copy the contents of `cdn/` into the branch/folder you publish.
- Keep `cdn/.nojekyll` in place so GitHub Pages serves the files as static assets without Jekyll processing.
- Your public game URL will usually look like `https://<user>.github.io/<repo>/godot/`.
- Then set `godotBaseUrl` to that `godot/` URL.

One-command deploy:
- Run `node push.js` from the repo root.
- It commits your current source changes, publishes `cdn/` to a `gh-pages` branch, and prints the Pages URL.
