import { useEffect, useMemo, useState } from "react";
import { usePrivy, useWallets } from "@privy-io/react-auth";
import { FullScreenLoader } from "../components/ui/fullscreen-loader";
import {
  fetchMatchesFromFirebase,
  getPrimaryWalletAddress,
  getUsernameFromPrivy,
  saveUserToFirebase,
  updateUserProjects,
  deleteMatchFromFirebase,
  saveMatchToFirebase
} from "./firebaseClient";
import {
  createSponsorMatchOnchain,
  cancelSponsorMatchOnchain
} from "./mockSponsorContract";
import { trackMatchCreated, trackSponsorAdded, trackSponsorMatchCreated } from "../lib/analyticsClient";
import "./SpounsorDashbaord.css";

function buildMatchId(sponsor) {
  const slug = sponsor.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  return `match-${slug || "sponsor"}-${Date.now()}`;
}

const MATCH_SLOT_MINUTES = 30;
const MAX_SUGGEST_DAYS = 60;

function toMinutes(timeValue) {
  if (!timeValue || typeof timeValue !== "string") return null;
  const [hoursStr, minutesStr] = timeValue.split(":");
  const hours = Number(hoursStr);
  const minutes = Number(minutesStr);
  if (!Number.isFinite(hours) || !Number.isFinite(minutes)) return null;
  return hours * 60 + minutes;
}

function formatDateInput(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function formatTimeInput(date) {
  const hours = String(date.getHours()).padStart(2, "0");
  const minutes = String(date.getMinutes()).padStart(2, "0");
  return `${hours}:${minutes}`;
}

function roundUpToSlot(date) {
  const slotMs = MATCH_SLOT_MINUTES * 60 * 1000;
  return new Date(Math.ceil(date.getTime() / slotMs) * slotMs);
}

function findConflictingMatch(dateValue, timeValue, matchList) {
  const selectedMinutes = toMinutes(timeValue);
  if (!dateValue || selectedMinutes === null) return null;
  return matchList.find((match) => {
    if (!match || match.status === "cancelled") return false;
    if (match.date !== dateValue) return false;
    const matchMinutes = toMinutes(match.time);
    if (matchMinutes === null) return false;
    return Math.abs(matchMinutes - selectedMinutes) <= MATCH_SLOT_MINUTES;
  }) || null;
}

function findSuggestedSlot({ dateValue, timeValue, matchList }) {
  const slotMs = MATCH_SLOT_MINUTES * 60 * 1000;
  let start;

  if (dateValue && timeValue) {
    start = new Date(`${dateValue}T${timeValue}`);
  } else if (dateValue) {
    start = new Date(`${dateValue}T00:00`);
  } else {
    start = new Date();
  }

  start = roundUpToSlot(start);
  const maxIterations = MAX_SUGGEST_DAYS * 24 * (60 / MATCH_SLOT_MINUTES);

  for (let i = 0; i < maxIterations; i += 1) {
    const candidate = new Date(start.getTime() + i * slotMs);
    const candidateDate = formatDateInput(candidate);
    const candidateTime = formatTimeInput(candidate);
    const conflict = findConflictingMatch(candidateDate, candidateTime, matchList);
    if (!conflict) {
      return { date: candidateDate, time: candidateTime };
    }
  }

  return null;
}

const initialForm = {
  sponsor: "",
  prizeAmount: "",
  date: "",
  time: "",
  minPlayersToStart: "3",
  maxPlayers: "50",
  image: "/logo.jpg",
  description: "",
  url: ""
};

export default function SpounsorDashbaord() {
  const { ready, authenticated, user } = usePrivy();
  const { wallets, ready: walletsReady } = useWallets();
  const [matches, setMatches] = useState([]);
  const [allMatches, setAllMatches] = useState([]);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [feedback, setFeedback] = useState("");
  const [form, setForm] = useState(initialForm);

  const walletAddress = useMemo(() => getPrimaryWalletAddress(user), [user]);
  const twitterAccount = useMemo(
    () => user?.linkedAccounts?.find((acc) => acc.type === "twitter_oauth"),
    [user]
  );
  const sponsorHandle = twitterAccount?.username ? `@${twitterAccount.username}` : "";
  const sponsorUrl = twitterAccount?.username ? `https://x.com/${twitterAccount.username}` : "";
  const sponsorAvatar = twitterAccount?.profilePictureUrl || "/logo.jpg";

  const activeEthWallet = useMemo(() => {
    if (!walletsReady || !wallets.length) return null;

    // 1. Try to find the specific wallet that matches our primary ETH address
    if (walletAddress) {
      const match = wallets.find(w => w.address.toLowerCase() === walletAddress.toLowerCase());
      if (match) return match;
    }

    // 2. Prioritize sub-selection of Privy Embedded Ethereum wallet
    const embedded = wallets.find(w => w.walletClientType === 'privy' && w.chainType === 'ethereum');
    if (embedded) return embedded;

    // 3. Fall back to any Ethereum wallet present in the Privy list
    return wallets.find(w => w.chainType === 'ethereum');
  }, [wallets, walletsReady, walletAddress]);

  useEffect(() => {
    if (!authenticated || !walletAddress) return;

    const hydrateMatches = async () => {
      try {
        const records = await fetchMatchesFromFirebase();
        setAllMatches(records);
        // Only show matches created by this wallet
        const myMatches = records.filter(m => m.createdByWallet === walletAddress);
        setMatches(myMatches);
      } catch (error) {
        console.error("Failed to load sponsor matches", error);
      }
    };

    hydrateMatches();
  }, [authenticated, walletAddress]);

  useEffect(() => {
    if (!user) return;
    setForm((current) => ({
      ...current,
      sponsor: current.sponsor || getUsernameFromPrivy(user),
      image: sponsorAvatar || current.image,
      url: current.url || sponsorUrl
    }));
  }, [user, sponsorAvatar, sponsorUrl]);

  const closeModal = () => {
    setIsModalOpen(false);
    setForm((current) => ({
      ...initialForm,
      sponsor: current.sponsor || getUsernameFromPrivy(user),
      image: sponsorAvatar || current.image,
      url: current.url || sponsorUrl
    }));
  };

  const handleChange = (event) => {
    const { name, value } = event.target;
    setForm((current) => ({ ...current, [name]: value }));
  };

  const handleCreateMatch = async () => {
    if (!form.sponsor || !form.prizeAmount || !form.date || !form.time) {
      setFeedback("Fill sponsor, prize amount, match date, and match time.");
      return;
    }

    const minPlayersValue = Number(form.minPlayersToStart);
    const maxPlayersValue = form.maxPlayers === "unlimited" ? null : Number(form.maxPlayers);

    if (!Number.isFinite(minPlayersValue) || minPlayersValue < 1) {
      setFeedback("Minimum players must be at least 1.");
      return;
    }

    if (maxPlayersValue !== null && (!Number.isFinite(maxPlayersValue) || maxPlayersValue < minPlayersValue)) {
      setFeedback("Maximum players must be greater than or equal to minimum players.");
      return;
    }

    const conflict = findConflictingMatch(form.date, form.time, allMatches);
    if (conflict) {
      setFeedback("That time is already booked or too close to another match. Please select another time.");
      return;
    }

    if (!activeEthWallet) {
      setFeedback("No Ethereum wallet found. Please ensure your Privy wallet is created and ready.");
      return;
    }

    setIsSubmitting(true);
    setFeedback("");

    const matchId = buildMatchId(form.sponsor);
    const matchDateTime = new Date(`${form.date}T${form.time}`);
    const startTime = Math.floor(matchDateTime.getTime() / 1000);

    try {
      const contractResult = await createSponsorMatchOnchain({
        embeddedWallet: activeEthWallet,
        matchId,
        prizeAmount: Number(form.prizeAmount),
        prizeToken: "0x0000000000000000000000000000000000000000",
        startTime,
        expectedParticipants: maxPlayersValue,
        winnerTokenURI: `/metadata/winner-${matchId}.json`,
        participationTokenURI: `/metadata/participant-${matchId}.json`,
        matchMetadataURI: form.url || `https://wons.example.com/matches/${matchId}`
      });

      const record = await saveMatchToFirebase({
        id: Date.now(),
        matchId,
        sponsor: form.sponsor,
        prize: `${form.prizeAmount} MON`,
        prizeAmount: Number(form.prizeAmount),
        prizeToken: "MON",
        status: "upcoming",
        time: form.time,
        date: form.date,
        startTime,
        minPlayersToStart: minPlayersValue,
        maxPlayers: maxPlayersValue,
        image: form.image || "/logo.jpg",
        description: form.description || `${form.sponsor} sponsored match`,
        url: form.url,
        createdAt: new Date().toISOString(),
        createdByWallet: walletAddress,
        depositTxHash: contractResult.txHash
      });

      setMatches((current) => [record, ...current]);
      setAllMatches((current) => [record, ...current]);

      trackMatchCreated({
        userId: user?.id,
        matchId,
        sponsorId: form.sponsor,
        value: Number(form.prizeAmount),
        metadata: {
          prizeToken: "MON",
          createdByWallet: walletAddress
        }
      });

      trackSponsorAdded({
        sponsorId: form.sponsor,
        value: Number(form.prizeAmount),
        metadata: { createdByWallet: walletAddress }
      });

      trackSponsorMatchCreated({
        userId: user?.id,
        matchId,
        sponsorId: form.sponsor,
        value: Number(form.prizeAmount),
        metadata: { prizeToken: "MON" }
      });
      setFeedback(
        contractResult.mode === "onchain"
          ? "Match created and deposit transaction confirmed."
          : "Match created with mock contract confirmation. Add VITE_SPONSOR_CLICK_CONTRACT_ADDRESS for real MON."
      );
      setIsModalOpen(false);
    } catch (error) {
      console.error(error);
      setFeedback(error?.message || "Failed to create match.");
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleCancelMatch = async (matchId) => {
    if (!window.confirm("Are you sure you want to cancel this match and refund the prize?")) return;

    setIsSubmitting(true);
    setFeedback("");

    try {
      const result = await cancelSponsorMatchOnchain({ embeddedWallet: activeEthWallet, matchId });

      // Remove from Firebase after successful on-chain cancellation
      await deleteMatchFromFirebase(matchId);

      // Update local state by removing the match
      setMatches(prev => prev.filter(m => m.matchId !== matchId));
      setAllMatches(prev => prev.filter(m => m.matchId !== matchId));

      setFeedback(result.mode === "onchain"
        ? "Match cancelled successfully. Funds returned and removed from dashboard."
        : "Match cancelled (mock).");
    } catch (error) {
      console.error(error);
      setFeedback(error?.message || "Failed to cancel match.");
    } finally {
      setIsSubmitting(false);
    }
  };

  if (!ready || !walletsReady) return <FullScreenLoader />;
  if (!authenticated || !user) return null;

  const handleSuggestTime = () => {
    const suggestion = findSuggestedSlot({
      dateValue: form.date,
      timeValue: form.time,
      matchList: allMatches
    });

    if (!suggestion) {
      setFeedback("No available time found in the next 60 days. Try another date.");
      return;
    }

    setForm((current) => ({
      ...current,
      date: suggestion.date,
      time: suggestion.time
    }));
    setFeedback(`Suggested time: ${suggestion.date} at ${suggestion.time}`);
  };

  return (
    <div className="sponsor-dashboard">
      <div className="sponsor-dashboard__header">
        <div>
          <p className="sponsor-dashboard__eyebrow">Sponsor Console</p>
          <h1>Spounsor Dashboard</h1>
          <p className="sponsor-dashboard__subtext">
            Create sponsor-funded matches, track deposited prizes, and push them into Firebase for the player dashboard.
          </p>
        </div>
        <button
          className="sponsor-dashboard__cta"
          onClick={() => setIsModalOpen(true)}
        >
          CreateMatch
        </button>
      </div>

      {feedback ? <div className="sponsor-dashboard__notice">{feedback}</div> : null}

      <div className="sponsor-dashboard__table">
        <div className="sponsor-dashboard__row sponsor-dashboard__row--head">
          <span>Match Date</span>
          <span>Time</span>
          <span>Prize</span>
          <span>Match ID</span>
        </div>
        {matches.length === 0 ? (
          <div className="sponsor-dashboard__empty">No sponsor matches yet.</div>
        ) : (
          matches.map((match) => (
            <div className="sponsor-dashboard__row" key={match.matchId}>
              <span>{match.date}</span>
              <span>{match.time}</span>
              <span>{match.prize}</span>
              <span className="sponsor-dashboard__match-id">{match.matchId}</span>
              <div className="sponsor-dashboard__actions">
                {match.status === "upcoming" && match.createdByWallet === walletAddress && (
                  <button
                    className="sponsor-dashboard__cancel-btn"
                    onClick={() => handleCancelMatch(match.matchId)}
                    disabled={isSubmitting}
                  >
                    Cancel
                  </button>
                )}
                {match.status === "cancelled" && <span className="status-cancelled">Cancelled</span>}
              </div>
            </div>
          ))
        )}
      </div>

      {isModalOpen ? (
        <div className="sponsor-modal__backdrop" onClick={closeModal}>
          <div className="sponsor-modal" onClick={(event) => event.stopPropagation()}>
            <div className="sponsor-modal__grid">
              <div className="sponsor-modal__identity sponsor-modal__wide">
                <img className="sponsor-modal__avatar" src={form.image || "/logo.jpg"} alt={form.sponsor} />
                <div>
                  <span className="sponsor-modal__name">{form.sponsor}</span>
                  {sponsorHandle ? <span className="sponsor-modal__handle">{sponsorHandle}</span> : null}
                </div>
              </div>
              <label>
                Prize Amount
                <div className="sponsor-modal__amount">
                  <input
                    name="prizeAmount"
                    type="number"
                    min="0"
                    step="0.0001"
                    placeholder="0.001"
                    value={form.prizeAmount}
                    onChange={handleChange}
                  />
                  <span className="sponsor-modal__token">MON</span>
                </div>
              </label>
              <label>
                Match Date
                <input name="date" type="date" value={form.date} onChange={handleChange} />
              </label>
              <label>
                Match Time (24h Format)
                <div className="sponsor-modal__time-row">
                  <input name="time" type="time" value={form.time} onChange={handleChange} />
                  <button
                    type="button"
                    className="sponsor-modal__suggest-btn"
                    onClick={handleSuggestTime}
                    disabled={isSubmitting}
                  >
                    Suggest Time
                  </button>
                </div>
              </label>
              <label>
                Minimum Players
                <input
                  name="minPlayersToStart"
                  type="number"
                  min="1"
                  step="1"
                  value={form.minPlayersToStart}
                  onChange={handleChange}
                />
              </label>
              <label>
                Maximum Players
                <select name="maxPlayers" value={form.maxPlayers} onChange={handleChange}>
                  <option value="10">10</option>
                  <option value="20">20</option>
                  <option value="30">30</option>
                  <option value="50">50</option>
                  <option value="75">75</option>
                  <option value="100">100</option>
                  <option value="unlimited">Unlimited</option>
                </select>
              </label>
              <label className="sponsor-modal__wide">
                Description
                <textarea name="description" rows="4" value={form.description} onChange={handleChange} />
              </label>
            </div>

            <div className="sponsor-modal__footer">
              <p className="sponsor-modal__hint">
                Uses your Privy EVM wallet. If no click-contract address is configured, the app writes a mock tx hash and still stores the match in Firebase.
              </p>
              <div className="sponsor-modal__footer-actions">
                <button className="sponsor-modal__cancel-btn" onClick={closeModal} disabled={isSubmitting}>
                  Cancel
                </button>
                <button className="sponsor-dashboard__cta" disabled={isSubmitting} onClick={handleCreateMatch}>
                  {isSubmitting ? "Creating..." : "Create Match"}
                </button>
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
