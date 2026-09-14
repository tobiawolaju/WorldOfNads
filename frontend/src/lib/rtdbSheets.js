/**
 * frontend/src/lib/rtdbSheets.js
 *
 * Browser-side firebase/database-compatible subset backed by the Apps Script
 * web app in /appsscript. Mirrors backend/rtdbSheets.js so both runtimes use
 * the same call shape. Env config (frontend/.env):
 *
 *   VITE_SHEETS_API_URL       https://script.google.com/macros/s/<id>/exec
 *   VITE_SHEETS_ACCESS_TOKEN  optional; must match the script property
 *
 * Writes are POSTed with Content-Type text/plain (JSON body) so the browser
 * never triggers a CORS preflight, which Apps Script cannot answer.
 */

const ENV = {
  endpoint: import.meta.env.VITE_SHEETS_API_URL || "",
  token: import.meta.env.VITE_SHEETS_ACCESS_TOKEN || ""
};

function pushId_() {
  const ts = Date.now().toString(36);
  const bytes = new Uint8Array(9);
  crypto.getRandomValues(bytes);
  let rnd = "";
  for (const b of bytes) {
    rnd += String.fromCharCode(b).replace(/[^a-zA-Z0-9]/g, "x");
  }
  return ts + rnd;
}

class NodeRef {
  constructor(path = "", constraints = []) {
    this.path = String(path || "").replace(/^\/+/, "").replace(/\/+$/, "");
    this.constraints = constraints;
  }
  _chain(constraints) {
    return new NodeRef(this.path, constraints);
  }
}

class Snapshot {
  constructor(ref, value) {
    this._ref = ref;
    this._value = value === undefined ? null : value;
  }
  exists() {
    return this._value !== null;
  }
  val() {
    return this._value;
  }
  get key() {
    return this._ref.path.split("/").pop() || null;
  }
  get ref() {
    return this._ref;
  }
}

export const db = new NodeRef();

export function ref(_db, path) {
  return new NodeRef(path);
}

export function query(nodeRef, ...constraints) {
  return nodeRef._chain(constraints);
}

export function orderByChild(key) {
  return { type: "orderByChild", key: String(key) };
}

export function startAt(value) {
  return { type: "startAt", value };
}

export function endAt(value) {
  return { type: "endAt", value };
}

async function api(url, init) {
  if (!ENV.endpoint) {
    throw new Error("rtdbSheets: VITE_SHEETS_API_URL is not set");
  }
  const res = await fetch(url, init);
  let data = null;
  try {
    data = await res.json();
  } catch (_) {
    data = null;
  }
  if (res.ok && data && data.ok === true) return data;
  const msg = data && data.error ? data.error : `Sheets API HTTP ${res.status}`;
  throw new Error(`rtdbSheets: ${msg}`);
}

async function write(path, op, value, key) {
  const body = { path, op };
  if (value !== undefined) body.value = value;
  if (key) body.key = key;
  if (ENV.token) body.token = ENV.token;
  return api(ENV.endpoint, {
    method: "POST",
    headers: { "Content-Type": "text/plain" },
    body: JSON.stringify(body)
  });
}

export async function get(nodeRef) {
  const params = new URLSearchParams();
  params.set("path", nodeRef.path);
  for (const c of nodeRef.constraints) {
    if (c.type === "orderByChild") params.set("orderByChild", c.key);
    else if (c.type === "startAt") params.set("startAt", String(c.value));
    else if (c.type === "endAt") params.set("endAt", String(c.value));
  }
  if (ENV.token) params.set("token", ENV.token);
  const data = await api(`${ENV.endpoint}?${params}`, {
    headers: { "Cache-Control": "no-store" }
  });
  return new Snapshot(nodeRef, data.value);
}

export async function set(nodeRef, value) {
  await write(nodeRef.path, "set", value);
}

export async function update(nodeRef, value) {
  await write(nodeRef.path, "update", value);
}

export async function remove(nodeRef) {
  await write(nodeRef.path, "remove");
}

export async function push(nodeRef, value) {
  const key = pushId_();
  if (value !== undefined) {
    await write(nodeRef.path, "push", value, key);
  }
  return { key, path: `${nodeRef.path}/${key}` };
}