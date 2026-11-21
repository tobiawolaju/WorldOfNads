// Party (squad) client shared by the React dashboard and the Godot dashboard.
// The Node backend owns the short-lived party state because the web and native
// clients both poll it; the match itself stays a normal free-for-all round.

const API_BASE = (
  import.meta.env.VITE_ANALYTICS_API_URL || "https://worldofnads.onrender.com"
).replace(/\/$/, "");

async function partyRequest(path, options = {}) {
  let response;
  try {
    response = await fetch(`${API_BASE}${path}`, {
      cache: "no-store",
      ...options,
      headers: {
        "Content-Type": "application/json",
        ...(options.headers || {})
      }
    });
  } catch (error) {
    const offline = new Error("offline");
    offline.code = "offline";
    throw offline;
  }

  let data = null;
  try {
    data = await response.json();
  } catch {
    data = null;
  }

  if (!response.ok || !data?.ok) {
    const failure = new Error(data?.error || `request_failed_${response.status}`);
    failure.code = data?.error || "request_failed";
    failure.status = response.status;
    failure.party = data?.party || null;
    failure.invites = data?.invites || [];
    throw failure;
  }
  return data;
}

export function searchPartyUsers(query) {
  const q = String(query || "").trim();
  if (q.length < 2) return Promise.resolve([]);
  return partyRequest(`/api/party/search?q=${encodeURIComponent(q)}`).then(
    (data) => data.users || []
  );
}

export function fetchPartyState(username) {
  return partyRequest(`/api/party/state?username=${encodeURIComponent(username)}`);
}

export function inviteToParty({ from, to, matchId, skin }) {
  return partyRequest("/api/party/invite", {
    method: "POST",
    body: JSON.stringify({ from, to, matchId, skin })
  });
}

export function respondToPartyInvite({ username, inviteId, accept, skin }) {
  return partyRequest("/api/party/respond", {
    method: "POST",
    body: JSON.stringify({ username, inviteId, accept, skin })
  });
}

export function setPartyReady({ username, ready }) {
  return partyRequest("/api/party/ready", {
    method: "POST",
    body: JSON.stringify({ username, ready })
  });
}

export function setPartyMatch({ username, matchId }) {
  return partyRequest("/api/party/match", {
    method: "POST",
    body: JSON.stringify({ username, matchId })
  });
}

export function leaveParty({ username }) {
  return partyRequest("/api/party/leave", {
    method: "POST",
    body: JSON.stringify({ username })
  });
}

export function describePartyError(code) {
  switch (code) {
    case "unknown_user":
      return "No player with that username.";
    case "already_in_party":
      return "That player is already in a party.";
    case "party_full":
      return "That party is full (4 players max).";
    case "already_member":
      return "They are already in your party.";
    case "cannot_invite_self":
      return "You cannot invite yourself.";
    case "invite_expired":
      return "That invite has expired.";
    case "offline":
      return "Party service is unreachable. Check your connection.";
    default:
      return "Something went wrong. Try again.";
  }
}
