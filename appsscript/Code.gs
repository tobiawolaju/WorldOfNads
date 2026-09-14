/**
 * WON Sheets Backend — Apps Script web app
 *
 * A minimal Realtime-Database-compatible data store on top of Google Sheets.
 * It is designed to be a drop-in backend for the RTDB paths used by
 * world_of_nads backend and frontend:
 *
 *   users/<username>          matches/<matchId>    rewards/<rewardId>
 *   skins/<skinId>            analytics/events/*   analytics/sponsorDailyPlayers/<date>/<sponsor>/...
 *
 * Storage model
 * ----------------------------------------------------------------------------
 * One sheet per top-level node ("users", "matches", "rewards", "skins",
 * "analytics"). Every row is one RTDB node stored as:
 *
 *   A  key        full path, e.g.  users/tobiawolaju  or  analytics/events/-xxxx
 *   B  value      JSON string of the node value
 *   C  updatedAt  ISO timestamp
 *
 * API
 * ----------------------------------------------------------------------------
 * GET  ?path=<node>[&orderByChild=<field>&startAt=<v>&endAt=<v>&token=<t>]
 *      Returns { ok: true, value: <subtree> }  (value is null when nothing set)
 * POST body (application/json OR text/plain — plain avoids browser preflight):
 *      { path: <node>, op: "set"|"update"|"remove"|"push",
 *        value: <any>, key: <optional push key>, token: <t> }
 *      set    -> replace the node
 *      update -> deep-merge the node value (RTDB update semantics)
 *      remove -> delete the node and all descendants
 *      push   -> write under a generated key, returns { ok: true, key }
 *
 * Reads on a parent path return a nested object keyed by the child segments,
 * matching how snapshot.val() worked in Firebase.
 *
 * Concurrency
 * ----------------------------------------------------------------------------
 * Writes are serialized with LockService.getScriptLock(). Because the web app is
 * deployed "execute as me", every request runs as your Google account, so the
 * script-wide lock does serialize concurrent writes from the backend and
 * frontend. (Google's documented caveat: locks are not guaranteed to span
 * separately-created web app deployments/executions — keep deployment stable.)
 *
 * Quotas (consumer account): ~20k daily execution calls, 6-min cap per call.
 * At current match/user/event volume that is far more than enough.
 *
 * Setup
 * ----------------------------------------------------------------------------
 * 1. Create a Google Spreadsheet.
 * 2. Extensions > Apps Script, paste these two files (Code.gs, appsscript.json).
 * 3. (Recommended) Project Settings > Script Properties, add
 *        SHEETS_ACCESS_TOKEN = <long random string>
 *    If set, every request must include it (?token= or body.token).
 *    If unset, the endpoint is open — fine for a fast move, tighten later.
 * 4. Deploy > New deployment > Web app:
 *        Execute as:  Me
 *        Who has access:  Anyone
 *    Copy the /exec URL. This is SHEETS_API_URL.
 * 5. Point the backend shim (backend/rtdbSheets.js) at it via
 *        SHEETS_API_URL, SHEETS_ACCESS_TOKEN
 *    and the frontend shim (frontend/src/lib/rtdbSheets.js) via
 *        VITE_SHEETS_API_URL, VITE_SHEETS_ACCESS_TOKEN
 *
 * Sheets never appear in the app, so tabs are safe to open/rename later.
 */

var HEADER = ['key', 'value', 'updatedAt'];
var COL_KEY = 1;
var COL_VALUE = 2;
var COL_UPDATED = 3;
var TOKEN_PROP = 'SHEETS_ACCESS_TOKEN';

function tableNameFromPath_(path) {
  var first = String(path || '').split('/')[0];
  return first || '_root';
}

function getAccessToken_() {
  return PropertiesService.getScriptProperties().getProperty(TOKEN_PROP) || '';
}

function authorized_(token) {
  var expected = getAccessToken_();
  return !expected || token === expected;
}

function parseJson_(raw) {
  if (raw === undefined || raw === null || raw === '') return null;
  if (typeof raw === 'string') {
    try {
      return JSON.parse(raw);
    } catch (e) {
      return raw;
    }
  }
  return raw;
}

function pushId_() {
  var chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  var rnd = '';
  for (var i = 0; i < 12; i++) {
    rnd += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return Date.now().toString(36) + rnd;
}

function ensureSheet_(name) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(name);
  if (!sheet) {
    sheet = ss.insertSheet(name);
    sheet.getRange(1, 1, 1, HEADER.length).setValues([HEADER]);
    sheet.setFrozenRows(1);
    sheet.getRange(1, 1, 1, HEADER.length).setFontWeight('bold');
  }
  return sheet;
}

function loadRows_(name) {
  var sheet = ensureSheet_(name);
  var last = sheet.getLastRow();
  var keys = [];
  var values = [];
  var updated = [];
  if (last >= 2) {
    var data = sheet.getRange(1, 1, last, 3).getValues();
    for (var i = 1; i < data.length; i++) {
      var k = String(data[i][0] || '');
      if (!k) continue;
      keys.push(k);
      values.push(parseJson_(data[i][1]));
      updated.push(data[i][2] || '');
    }
  }
  return { keys: keys, values: values, updated: updated };
}

function keyToRowIndex_(sheet) {
  var map = {};
  var last = sheet.getLastRow();
  if (last >= 2) {
    var keys = sheet.getRange(2, 1, last - 1, 1).getValues();
    for (var i = 0; i < keys.length; i++) {
      var k = String(keys[i][0] || '');
      if (k) map[k] = i + 2;
    }
  }
  return map;
}

function assignLeaf_(root, sub, value) {
  var segs = sub.split('/');
  var node = root;
  for (var i = 0; i < segs.length - 1; i++) {
    var seg = segs[i];
    if (!node[seg] || typeof node[seg] !== 'object' || Array.isArray(node[seg])) {
      node[seg] = {};
    }
    node = node[seg];
  }
  node[segs[segs.length - 1]] = value;
}

function mergeObjects_(base, patch) {
  if (!base || typeof base !== 'object' || Array.isArray(base)) return patch;
  if (!patch || typeof patch !== 'object' || Array.isArray(patch)) return patch;
  var out = {};
  Object.keys(base).forEach(function (k) { out[k] = base[k]; });
  Object.keys(patch).forEach(function (k) {
    var pv = patch[k];
    var bv = out[k];
    if (pv && typeof pv === 'object' && !Array.isArray(pv) &&
        bv && typeof bv === 'object' && !Array.isArray(bv)) {
      out[k] = mergeObjects_(bv, pv);
    } else {
      out[k] = pv;
    }
  });
  return out;
}

function filterOrdered_(value, childKey, startAt, endAt) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return value;
  var out = {};
  var count = 0;
  Object.keys(value).forEach(function (k) {
    var v = value[k];
    var field = v && typeof v === 'object' && !Array.isArray(v) ? v[childKey] : undefined;
    if (field === undefined) return;
    if (startAt !== undefined && startAt !== null && String(field) < String(startAt)) return;
    if (endAt !== undefined && endAt !== null && String(field) > String(endAt)) return;
    out[k] = v;
    count += 1;
  });
  return count ? out : null;
}

function doRead_(path, params) {
  var name = tableNameFromPath_(path);
  var rows = loadRows_(name);
  var prefix = path === '' ? '' : (path + '/');
  var exact = null;
  var exactFound = false;
  var tree = {};
  for (var i = 0; i < rows.keys.length; i++) {
    var k = rows.keys[i];
    if (k === path) {
      exact = rows.values[i];
      exactFound = true;
      continue;
    }
    if (prefix && k.indexOf(prefix) !== 0) continue;
    var sub = path === '' ? k : k.slice(prefix.length);
    if (!sub) continue;
    assignLeaf_(tree, sub, rows.values[i]);
  }

  var value = null;
  var hasTree = Object.keys(tree).length > 0;
  if (exactFound && hasTree) {
    value = mergeObjects_(exact, tree);
  } else if (exactFound) {
    value = exact;
  } else if (hasTree) {
    value = tree;
  }

  if (params.orderByChild) {
    value = filterOrdered_(value, params.orderByChild, params.startAt, params.endAt);
  }
  return value;
}

function removeRowsByPrefix_(sheet, prefix) {
  var last = sheet.getLastRow();
  if (last < 2) return;
  var keys = sheet.getRange(2, 1, last - 1, 1).getValues();
  var toDelete = [];
  for (var i = 0; i < keys.length; i++) {
    var k = String(keys[i][0] || '');
    if (k === prefix || (prefix && k.indexOf(prefix + '/') === 0)) {
      toDelete.push(i + 2);
    }
  }
  for (var j = toDelete.length - 1; j >= 0; j--) {
    sheet.deleteRow(toDelete[j]);
  }
}

function doWrite_(path, op, value, clientKey) {
  var name = tableNameFromPath_(path);
  var sheet = ensureSheet_(name);
  var idx = keyToRowIndex_(sheet);
  var rowKey = path;

  if (op === 'remove') {
    removeRowsByPrefix_(sheet, path);
    return { ok: true, removed: true, key: path };
  }

  if (op === 'set' && (value === null || value === undefined)) {
    removeRowsByPrefix_(sheet, path);
    return { ok: true, removed: true, key: path };
  }

  var next;
  if (op === 'push') {
    rowKey = (path ? path + '/' : '') + (clientKey || pushId_());
    next = value;
  } else if (op === 'set') {
    next = value;
  } else if (op === 'update') {
    var existing = null;
    if (idx[rowKey] !== undefined) {
      existing = parseJson_(sheet.getRange(idx[rowKey], COL_VALUE).getValue());
    }
    if (existing && typeof existing === 'object' && !Array.isArray(existing) &&
        value && typeof value === 'object' && !Array.isArray(value)) {
      next = mergeObjects_(existing, value);
    } else {
      next = value;
    }
  } else {
    return { ok: false, error: 'Unknown op: ' + op };
  }

  var row;
  if (idx[rowKey] !== undefined) {
    row = idx[rowKey];
    sheet.getRange(row, COL_VALUE).setValue(JSON.stringify(next));
    sheet.getRange(row, COL_UPDATED).setValue(new Date().toISOString());
  } else {
    sheet.appendRow([rowKey, JSON.stringify(next), new Date().toISOString()]);
  }
  return { ok: true, key: rowKey, value: next };
}

function handleRequest_(e) {
  var params = e.parameter || {};
  var token = params.token || '';
  var path = String(params.path || '');
  var op = '';
  var value;
  var clientKey;

  if (e.postData && e.postData.contents) {
    var body;
    try {
      body = JSON.parse(e.postData.contents);
    } catch (err) {
      return { ok: false, error: 'Invalid JSON body' };
    }
    token = token || body.token || '';
    path = path || body.path || '';
    op = body.op || '';
    value = body.value;
    clientKey = body.key || undefined;
  }

  if (!authorized_(token)) {
    return { ok: false, error: 'Unauthorized' };
  }

  var lock = LockService.getScriptLock();
  try {
    lock.waitLock(20000);
  } catch (err) {
    return { ok: false, error: 'Lock timeout — try again' };
  }

  try {
    if (op) {
      return doWrite_(path, op, value, clientKey);
    }
    var readOpts = {
      orderByChild: params.orderByChild || undefined,
      startAt: params.startAt !== undefined ? params.startAt : undefined,
      endAt: params.endAt !== undefined ? params.endAt : undefined
    };
    return { ok: true, value: doRead_(path, readOpts) };
  } catch (err) {
    return { ok: false, error: err && err.message ? err.message : String(err) };
  } finally {
    lock.releaseLock();
  }
}

function respond_(payload) {
  return ContentService.createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}

function doGet(e) {
  return respond_(handleRequest_(e));
}

function doPost(e) {
  return respond_(handleRequest_(e));
}