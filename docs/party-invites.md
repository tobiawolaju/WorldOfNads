# Party / friend invites

Squad up from either dashboard: the React dashboard on the web and
`scenes/dshbord.tscn` in the native build. Both poll the same short-lived party
state on the Node backend, so a web host and an Android friend can play the same
match.

The match itself is unchanged: still free-for-all, still one winner. The party
only synchronises the room id, the ready state and the launch countdown.

## Flow

1. Pick a match, then tap one of the three `+` slots around your player card.
2. Search a username and tap the result. The backend creates the party (max 4
   players) and stores a pending invite addressed to that username.
3. The invitee gets a popup on their dashboard: **Accept** or **Reject**.
4. Accepting puts them in the party and switches their dashboard to the party's
   match. The host's card selection stays authoritative; changing it updates the
   party for everyone.
5. Every member toggles **Ready**. When every member is ready the backend starts
   a 5 second synchronised countdown. Each client launches the same match id, so
   everyone joins the same room.
6. A solo party starts the countdown as soon as the only member readies up.

Invites expire after 3 minutes. Parties are idle-pruned after 45 minutes, and a
party whose countdown finished more than a minute ago is dropped so a dashboard
opened later does not show a dead `0.0s` countdown.

## API

All endpoints are JSON and CORS-open (the web dashboard calls Render directly).
State is in-process: a Render restart drops live parties, which is fine for a
short squad session.

| Method | Path | Body / query | Result |
| --- | --- | --- | --- |
| GET | `/api/party/search?q=` | username prefix (2+ chars) | `{ users: [{ username, profilePictureUrl }] }` |
| GET | `/api/party/state?username=` | | `{ party, invites, serverNow }` |
| POST | `/api/party/invite` | `{ from, to, matchId, skin }` | party state |
| POST | `/api/party/respond` | `{ username, inviteId, accept, skin }` | party state |
| POST | `/api/party/ready` | `{ username, ready }` | party state |
| POST | `/api/party/match` | `{ username, matchId }` (host) | party state |
| POST | `/api/party/leave` | `{ username }` | party state |

`party` is `null` when the caller is not in one. A party view looks like:

```json
{
  "id": "…",
  "host": "alice",
  "matchId": "default",
  "status": "open",
  "countdownEnd": null,
  "countdownMs": 5000,
  "maxMembers": 4,
  "members": [{ "username": "alice", "ready": false, "skin": "s-default", "joinedAt": 0 }],
  "pending": [{ "to": "bob", "expiresAt": 0 }],
  "serverNow": 0
}
```

`countdownEnd` and `serverNow` are Unix milliseconds. Clients compute the
remaining time from the server offset and launch locally, so a slow poll does not
desynchronise the start.

## Files

- `backend/index.js` — party store, routes and cleanup.
- `backend/firebaseClient.js` — `searchUsers()` for the invite dialog.
- `frontend/src/lib/partyClient.js` — typed-ish fetch helpers.
- `frontend/src/components/PartyBar.tsx` / `.css` — web squad strip and modals.
- `frontend/src/pages/Dashboard.tsx` — mounts the bar; shared launch helper.
- `godot/scripts/screens/dshbord.gd` — native squad strip, dialogs and poller.
