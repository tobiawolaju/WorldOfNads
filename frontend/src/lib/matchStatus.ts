// What a match card should say *now*, rather than what the record last said.
//
// The control plane owns the stored `matches/<id>/status` and flips it on a 30 s
// worker (backend/index.js, `match-status-worker`): upcoming -> live five
// minutes before the start, live -> completed five minutes after the round ends
// (300 s round + 60 s buffer). Cards used to render that field verbatim, so when
// the worker had not run — the free instance was asleep, it restarted, or the
// record was written by hand — an event whose time had passed kept advertising
// "upcoming"/"live" indefinitely.
//
// `cancelled` had no display value either: NadArena bucketed every unknown
// status into "upcoming" (a refunded event looked like a future one), and the
// dashboard sorted it to index -1, i.e. to the very front of the carousel, where
// it rendered unstyled and no filter tab could reach it.
//
// So the status shown is derived from the record *and* the clock. The windows
// mirror the control plane, so a card never disagrees with what the server is
// about to write on its next tick.

export const MATCH_DURATION_SECONDS = 300;
export const MATCH_END_BUFFER_SECONDS = 60;
export const MATCH_LIVE_LEAD_SECONDS = 300;

export type DisplayMatchStatus = "upcoming" | "live" | "completed" | "cancelled";

const CANCELLED_STATUSES = new Set(["cancelled", "canceled", "refunded", "refund"]);
const COMPLETED_STATUSES = new Set(["completed", "settled", "finished"]);

function normaliseStatus(status?: string | null): string {
  return String(status || "").trim().toLowerCase();
}

/**
 * Resolve the status a match card should show at `nowMs`.
 *
 * Terminal statuses win over the clock (a refund stays refunded even if the
 * start time is still ahead), and a record without a usable `startTime` keeps
 * the stored value because there is nothing to compare against.
 *
 * The shared training lobby (`ctaMode: "play"`) is not a round at all — it has
 * no start and never ends — so it always reads live.
 */
export function displayMatchStatus(
  match: { status?: string | null; startTime?: number | string | null; ctaMode?: string | null } | null | undefined,
  nowMs: number
): DisplayMatchStatus {
  if (!match) return "upcoming";

  if (match.ctaMode === "play") return "live";

  const status = normaliseStatus(match.status);
  if (CANCELLED_STATUSES.has(status)) return "cancelled";
  if (COMPLETED_STATUSES.has(status)) return "completed";

  const startSeconds = Number(match.startTime);
  if (!Number.isFinite(startSeconds) || startSeconds <= 0) {
    return status === "live" || status === "upcoming" ? status : "upcoming";
  }

  const nowSeconds = nowMs / 1000;
  if (nowSeconds >= startSeconds + MATCH_DURATION_SECONDS + MATCH_END_BUFFER_SECONDS) {
    return "completed";
  }
  if (nowSeconds >= startSeconds - MATCH_LIVE_LEAD_SECONDS) {
    return "live";
  }
  return "upcoming";
}
