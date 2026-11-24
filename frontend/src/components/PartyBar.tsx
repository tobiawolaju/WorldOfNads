import { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import {
  describePartyError,
  fetchPartyState,
  inviteToParty,
  leaveParty,
  respondToPartyInvite,
  searchPartyUsers,
  setPartyMatch,
  setPartyReady
} from "../lib/partyClient";
import "./PartyBar.css";

type PartyMember = {
  username: string;
  ready: boolean;
  skin?: string;
  pfp?: string;
};

type Party = {
  id: string;
  host: string;
  matchId: string;
  status: "open" | "countdown";
  countdownEnd: number | null;
  countdownMs: number;
  maxMembers: number;
  members: PartyMember[];
  pending?: { to: string; pfp?: string; expiresAt: number }[];
  serverNow: number;
};

type PartyInvite = {
  id: string;
  from: string;
  matchId: string;
  pfp?: string;
  expiresAt: number;
};

type SearchUser = {
  username: string;
  profilePictureUrl?: string;
};

export type PartyControls = {
  inParty: boolean;
  countingDown: boolean;
  remainingMs: number;
  meReady: boolean;
  waitingText: string;
  busy: boolean;
  toggleReady: () => void;
  leave: () => void;
};

type PartyBarProps = {
  username: string;
  selectedMatch: string | null;
  skinName: string;
  matches: { matchId: string; sponsor?: string }[];
  onLaunch: (matchId: string) => void;
  onJoinMatch: (matchId: string) => void;
  onControlsChange?: (controls: PartyControls | null) => void;
  isStoreOpen?: boolean;
  isRewardsOpen?: boolean;
};

const POLL_MS = 1500;
const COUNTDOWN_TICK_MS = 100;
// A countdown that is this far in the past is stale (the tab was closed and
// reopened after the squad already launched), so it must not navigate again.
const STALE_LAUNCH_MS = 15000;

function matchLabel(matchId: string, matches: PartyBarProps["matches"]): string {
  const match = matches.find((item) => item.matchId === matchId);
  return match?.sponsor || matchId || "the selected match";
}

function initials(name: string): string {
  const clean = String(name || "?").trim();
  return clean.slice(0, 2).toUpperCase();
}

const PartyBar = ({
  username,
  selectedMatch,
  skinName,
  matches,
  onLaunch,
  onJoinMatch,
  onControlsChange,
  isStoreOpen = false,
  isRewardsOpen = false
}: PartyBarProps) => {
  const [party, setParty] = useState<Party | null>(null);
  const [invites, setInvites] = useState<PartyInvite[]>([]);
  const [remainingMs, setRemainingMs] = useState(0);
  const [modalOpen, setModalOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchUser[]>([]);
  const [searching, setSearching] = useState(false);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [pfpByName, setPfpByName] = useState<Record<string, string>>({});

  const aliveRef = useRef(true);
  const launchedRef = useRef("");
  const staleRef = useRef("");
  const joinedRef = useRef("");
  const clockOffsetRef = useRef(0);
  const partyRef = useRef<Party | null>(null);
  const busyRef = useRef(false);

  const canParty = Boolean(username && username !== "Anon");

  const applyState = useCallback((data: any) => {
    const nextParty: Party | null = data?.party || null;
    const nextInvites = Array.isArray(data?.invites) ? data.invites : [];
    setParty(nextParty);
    setInvites(nextInvites);
    setPfpByName((prev) => {
      let next = prev;
      const add = (name: string, pfp?: string) => {
        const n = String(name || "").trim();
        const p = String(pfp || "").trim();
        if (n && p && prev[n] !== p) {
          if (next === prev) next = { ...prev };
          next[n] = p;
        }
      };
      for (const m of nextParty?.members || []) add(m.username, m.pfp);
      for (const p of nextParty?.pending || []) add(p.to, p.pfp);
      for (const inv of nextInvites) add(inv.from, inv.pfp);
      return next;
    });
    const offset = Number(data?.serverNow || Date.now()) - Date.now();
    clockOffsetRef.current = offset;
  }, []);

  useEffect(() => {
    partyRef.current = party;
  }, [party]);

  useEffect(() => {
    busyRef.current = busy;
  }, [busy]);

  const refresh = useCallback(async () => {
    if (!canParty) return;
    try {
      const data = await fetchPartyState(username);
      if (aliveRef.current) applyState(data);
    } catch {
      // Polling is best-effort; the next tick retries.
    }
  }, [canParty, username, applyState]);

  useEffect(() => {
    aliveRef.current = true;
    if (!canParty) {
      setParty(null);
      setInvites([]);
      return () => {
        aliveRef.current = false;
      };
    }
    refresh();
    const timer = setInterval(refresh, POLL_MS);
    return () => {
      aliveRef.current = false;
      clearInterval(timer);
    };
  }, [canParty, refresh]);

  // The host's currently selected card is the party's match. Guests follow the
  // party's match instead, so accepting an invite pulls them onto the right card.
  useEffect(() => {
    if (!party) return;
    // The host's selection is authoritative: changing a card updates the party
    // via /api/party/match, so only guests follow the stored match.
    if (party.host === username) return;
    if (party.matchId && party.matchId !== selectedMatch) {
      if (joinedRef.current !== `${party.id}:${party.matchId}`) {
        joinedRef.current = `${party.id}:${party.matchId}`;
        onJoinMatch(party.matchId);
      }
    }
  }, [party, selectedMatch, username, onJoinMatch]);

  useEffect(() => {
    if (!party || party.host !== username || !selectedMatch) return;
    if (party.matchId === selectedMatch) return;
    void setPartyMatch({ username, matchId: selectedMatch })
      .then((data) => {
        if (aliveRef.current) applyState(data);
      })
      .catch(() => {});
  }, [party, username, selectedMatch, applyState]);

  const countdownPartyId = party?.id || "";
  const countdownMatchId = party?.matchId || "";
  const countdownEnd = party?.countdownEnd || 0;
  const countdownActive = party?.status === "countdown" && countdownEnd > 0;

  useEffect(() => {
    if (!countdownActive || !countdownEnd) {
      setRemainingMs(0);
      return;
    }
    const tick = () => {
      const serverNow = Date.now() + clockOffsetRef.current;
      const left = Math.max(0, countdownEnd - serverNow);
      setRemainingMs(left);
      if (left > 0 || launchedRef.current === countdownPartyId) return;
      if (serverNow - countdownEnd > STALE_LAUNCH_MS) {
        // The player came back after the squad already launched. Drop the dead
        // party instead of leaving a 0.0s countdown on screen for a minute.
        if (staleRef.current !== countdownPartyId) {
          staleRef.current = countdownPartyId;
          setParty(null);
          setInvites([]);
          void leaveParty({ username }).catch(() => {});
        }
        return;
      }
      launchedRef.current = countdownPartyId;
      onLaunch(countdownMatchId);
    };
    tick();
    const timer = setInterval(tick, COUNTDOWN_TICK_MS);
    return () => clearInterval(timer);
  }, [countdownActive, countdownEnd, countdownPartyId, countdownMatchId, onLaunch, username]);

  useEffect(() => {
    if (!modalOpen) return;
    const q = query.trim();
    if (q.length < 2) {
      setResults([]);
      setSearching(false);
      return;
    }
    setSearching(true);
    const timer = setTimeout(() => {
      searchPartyUsers(q)
        .then((users) => {
          if (!aliveRef.current) return;
          setResults(users);
          setPfpByName((prev) => {
            let next = prev;
            for (const u of users) {
              if (u.profilePictureUrl && prev[u.username] !== u.profilePictureUrl) {
                if (next === prev) next = { ...prev };
                next[u.username] = u.profilePictureUrl;
              }
            }
            return next;
          });
        })
        .catch(() => {
          if (aliveRef.current) setResults([]);
        })
        .finally(() => {
          if (aliveRef.current) setSearching(false);
        });
    }, 250);
    return () => clearTimeout(timer);
  }, [query, modalOpen]);

  const me = party?.members.find((member) => member.username === username) || null;
  const others = party ? party.members.filter((member) => member.username !== username) : [];
  const pending = party?.pending || [];
  const slotMembers = [others[0] || null, others[1] || null, others[2] || null];
  const slotPending = [pending[0] || null, pending[1] || null, pending[2] || null];
  const waitingFor = party
    ? party.members.filter((member) => !member.ready).map((member) => member.username)
    : [];
  const countingDown = party?.status === "countdown" && remainingMs > 0;
  const waitingText = countingDown
    ? "Match is starting…"
    : waitingFor.length
      ? `Waiting for ${waitingFor.join(", ")}`
      : party && me?.ready
        ? "Ready"
        : "";

  const openInvite = () => {
    if (party && party.members.length >= party.maxMembers) {
      setError("Your party is full (4 players max).");
      return;
    }
    setError("");
    setNotice("");
    setQuery("");
    setResults([]);
    setModalOpen(true);
  };

  const sendInvite = async (to: string) => {
    if (!selectedMatch) {
      setError("Pick a match first.");
      return;
    }
    setBusy(true);
    setError("");
    try {
      const data = await inviteToParty({
        from: username,
        to,
        matchId: party?.matchId || selectedMatch,
        skin: skinName
      });
      applyState(data);
      setNotice(`Invite sent to ${to}.`);
      setQuery("");
      setResults([]);
    } catch (failure: any) {
      setError(describePartyError(failure?.code));
    } finally {
      setBusy(false);
    }
  };

  const respond = async (invite: PartyInvite, accept: boolean) => {
    setBusy(true);
    setError("");
    try {
      const data = await respondToPartyInvite({
        username,
        inviteId: invite.id,
        accept,
        skin: skinName
      });
      applyState(data);
      if (accept) {
        joinedRef.current = `${data?.party?.id || ""}:${data?.party?.matchId || ""}`;
        onJoinMatch(data?.party?.matchId || invite.matchId);
      }
    } catch (failure: any) {
      setError(describePartyError(failure?.code));
      setInvites((current) => current.filter((row) => row.id !== invite.id));
    } finally {
      setBusy(false);
    }
  };

  const toggleReady = useCallback(async () => {
    const currentParty = partyRef.current;
    if (!currentParty || busyRef.current) return;
    const currentMe = currentParty.members.find((member) => member.username === username) || null;
    if (!currentMe) return;
    setBusy(true);
    setError("");
    try {
      const data = await setPartyReady({ username, ready: !currentMe.ready });
      if (aliveRef.current) applyState(data);
    } catch (failure: any) {
      if (aliveRef.current) setError(describePartyError(failure?.code));
    } finally {
      if (aliveRef.current) setBusy(false);
    }
  }, [username, applyState]);

  const quitParty = useCallback(async () => {
    if (busyRef.current) return;
    setBusy(true);
    try {
      await leaveParty({ username });
    } catch {
      // Leaving locally is still the right outcome if the request failed.
    }
    if (aliveRef.current) {
      setParty(null);
      setInvites([]);
      launchedRef.current = "";
      joinedRef.current = "";
      setBusy(false);
    }
  }, [username]);

  useEffect(() => {
    if (!onControlsChange) return;
    if (!party) {
      onControlsChange(null);
      return;
    }
    onControlsChange({
      inParty: true,
      countingDown,
      remainingMs,
      meReady: Boolean(me?.ready),
      waitingText,
      busy,
      toggleReady,
      leave: quitParty
    });
  }, [party, countingDown, remainingMs, me?.ready, waitingText, busy, toggleReady, quitParty, onControlsChange]);

  useEffect(() => {
    return () => {
      onControlsChange?.(null);
    };
  }, [onControlsChange]);

  const renderInviteSlot = (
    member: PartyMember | null,
    invited: { to: string } | null,
    index: number,
    position: "left" | "right" | "far"
  ) => {
    const name = member?.username || invited?.to || "";
    const pfp = name ? pfpByName[name] : "";

    if (member) {
      return (
        <div
          className={`party-scene-slot is-person ${member.ready ? "is-ready" : ""}${isRewardsOpen ? " is-store-hidden" : ""}`}
          data-pos={position}
          key={`member-${member.username}`}
          title={member.username}
          aria-hidden={isRewardsOpen}
        >
          <span className="party-scene-person-avatar">
            {pfp ? <img src={pfp} alt="" /> : initials(member.username)}
          </span>
          <span className="party-scene-person-name">{member.username}</span>
        </div>
      );
    }
    if (invited) {
      return (
        <div
          className="party-scene-slot is-person is-pending"
          data-pos={position}
          key={`pending-${invited.to}`}
          title={`${invited.to} (pending)`}
          aria-hidden={isRewardsOpen}
        >
          <span className="party-scene-person-avatar">
            {pfp ? <img src={pfp} alt="" /> : initials(invited.to)}
          </span>
          <span className="party-scene-person-name">
            {invited.to}
            <span className="party-terminal-dots" aria-hidden="true" />
          </span>
        </div>
      );
    }
    const hideEmptySlot = isStoreOpen || isRewardsOpen;
    return (
      <button
        type="button"
        className={`party-scene-slot is-empty${hideEmptySlot ? " is-store-hidden" : ""}`}
        data-pos={position}
        key={`empty-${index}`}
        onClick={openInvite}
        title="Invite a friend"
        aria-label="Invite a friend"
        aria-hidden={hideEmptySlot}
        tabIndex={hideEmptySlot ? -1 : 0}
      >
        <span className="party-scene-slot-plus">+</span>
      </button>
    );
  };

  if (!selectedMatch && !party) return null;

  const incoming = invites[0] || null;

  const modals = (
    <>
      {modalOpen && (
        <div className="party-modal-backdrop" onClick={() => setModalOpen(false)}>
          <div className="party-modal" onClick={(event) => event.stopPropagation()}>
            <div className="party-modal-head">
              <h3>INVITE A FRIEND</h3>
              <p className="party-modal-sub">
                Up to 4 players. Everyone readies up and launches together.
              </p>
            </div>
            <input
              autoFocus
              className="party-input"
              placeholder="Enter a username"
              value={query}
              onChange={(event) => {
                setQuery(event.target.value);
                setError("");
              }}
            />
            <div className="party-results">
              {searching && <div className="party-result-empty">Searching…</div>}
              {!searching && query.trim().length >= 2 && results.length === 0 && (
                <div className="party-result-empty">No players found.</div>
              )}
              {results.map((result) => (
                <button
                  type="button"
                  className="party-result"
                  key={result.username}
                  disabled={busy}
                  onClick={() => sendInvite(result.username)}
                >
                  <span className="party-result-avatar">
                    {result.profilePictureUrl ? (
                      <img src={result.profilePictureUrl} alt="" />
                    ) : (
                      initials(result.username)
                    )}
                  </span>
                  <span className="party-result-name">{result.username}</span>
                  <span className="party-result-action">INVITE</span>
                </button>
              ))}
            </div>
            {notice && <div className="party-notice">{notice}</div>}
            {error && <div className="party-error">{error}</div>}
            <div className="party-modal-actions">
              <button type="button" className="party-btn party-btn--secondary" onClick={() => setModalOpen(false)}>
                CLOSE
              </button>
            </div>
          </div>
        </div>
      )}

      {incoming && !party && (
        <div className="party-modal-backdrop">
          <div className="party-modal party-invite">
            <div className="party-modal-head">
              <h3>PARTY INVITE</h3>
              <p className="party-modal-sub">
                <b>{incoming.from}</b> invited you to{" "}
                <b>{matchLabel(incoming.matchId, matches)}</b>.
              </p>
            </div>
            <div className="party-invite-actions">
              <button
                type="button"
                className="party-btn party-btn--primary"
                disabled={busy}
                onClick={() => respond(incoming, true)}
              >
                ACCEPT
              </button>
              <button
                type="button"
                className="party-btn party-btn--secondary"
                disabled={busy}
                onClick={() => respond(incoming, false)}
              >
                REJECT
              </button>
            </div>
            {error && <div className="party-error">{error}</div>}
          </div>
        </div>
      )}
    </>
  );

  return (
    <>
      <div className="party-scene-overlay" aria-label="Party invites">
        {renderInviteSlot(slotMembers[0], slotPending[0], 0, "left")}
        {party && (
          <button
            type="button"
            className={`party-scene-slot is-me is-leave${isRewardsOpen ? " is-store-hidden" : ""}`}
            data-pos="center"
            title="Leave party"
            aria-label="Leave party"
            onClick={() => void quitParty()}
            disabled={busy || isRewardsOpen}
            aria-hidden={isRewardsOpen}
            tabIndex={isRewardsOpen ? -1 : 0}
          >
            <span className="material-symbols-rounded" aria-hidden="true">logout</span>
          </button>
        )}
        {renderInviteSlot(slotMembers[1], slotPending[1], 1, "right")}
        {renderInviteSlot(slotMembers[2], slotPending[2], 2, "far")}
      </div>
      {createPortal(modals, document.body)}
    </>
  );
};

export default PartyBar;
