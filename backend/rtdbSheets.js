import { randomBytes } from "node:crypto";

/**
 * backend/rtdbSheets.js
 *
 * A firebase/database-compatible subset backed by the Apps Script web app in
 * /appsscript. Swap the import in consumers:
 *
 *   import { ref, get, update } from "./rtdbSheets.js";
 *
 * instead of `firebase/database`, and use `db` from here instead of
 * `getDatabase(...)`. Env config:
 *
 *   SHEETS_API_URL       https://script.google.com/macros/s/<id>/exec
 *   SHEETS_ACCESS_TOKEN  optional; must match the script property
 */

function endpoint_() {
  return process.env.SHEETS_API_URL || "";
}

function token_() {
  return process.env.SHEETS_ACCESS_TOKEN || "";
}

class NodeRef {
  constructor(path = "", constraints = []) {
    this.path = String(path || "").replace(/^\/+/, "").replace(/\/+$/, "");
    this.constraints = constraints;
  }
  get key() {
    if (!this.path) return null;
    return this.path.split("/").pop();
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
    return this._ref.key;
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

function pushId_() {
  const ts = Date.now().toString(36);
  const rnd = randomBytes(9).toString("base64url");
  return ts + rnd;
}

async function api(url, init) {
  if (!endpoint_()) {
    throw new Error("rtdbSheets: SHEETS_API_URL is not set");
  }
  const res = await fetch(url, init);
  const text = await res.text();
  let data = null;
  try {
    data = JSON.parse(text);
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
  if (token_()) body.token = token_();
  return api(endpoint_(), {
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
  if (token_()) params.set("token", token_());
  const data = await api(`${endpoint_()}?${params}`, {
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