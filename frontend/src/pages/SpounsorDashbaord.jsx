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
import "./SpounsorDashbaord.css";

function buildMatchId(sponsor) {
  const slug = sponsor.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  return `match-${slug || "sponsor"}-${Date.now()}`;
}

const initialForm = {
  sponsor: "",
  prizeAmount: "10",
  prizeToken: "MON",
  date: "",
  time: "",
  image: "/logo.jpg",
  description: "",
  url: ""
};

export default function SpounsorDashbaord() {
  const { ready, authenticated, user } = usePrivy();
  const { wallets, ready: walletsReady } = useWallets();
  const [matches, setMatches] = useState([]);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [feedback, setFeedback] = useState("");
  const [form, setForm] = useState(initialForm);

  const walletAddress = useMemo(() => getPrimaryWalletAddress(user), [user]);

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
    if (!authenticated) return;

    const hydrateMatches = async () => {
      try {
        const records = await fetchMatchesFromFirebase();
        setMatches(records);
      } catch (error) {
        console.error("Failed to load sponsor matches", error);
      }
    };

    hydrateMatches();
  }, [authenticated]);

  useEffect(() => {
    if (!user) return;
    setForm((current) => ({
      ...current,
      sponsor: current.sponsor || getUsernameFromPrivy(user)
    }));
  }, [user]);

  const closeModal = () => {
    setIsModalOpen(false);
    setForm((current) => ({
      ...initialForm,
      sponsor: current.sponsor || getUsernameFromPrivy(user)
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
        prizeToken: form.prizeToken === "MON" ? "0x0000000000000000000000000000000000000000" : form.prizeToken,
        startTime,
        expectedParticipants: 50,
        winnerTokenURI: `/metadata/winner-${matchId}.json`,
        participationTokenURI: `/metadata/participant-${matchId}.json`,
        matchMetadataURI: form.url || `https://wons.example.com/matches/${matchId}`
      });

      const record = await saveMatchToFirebase({
        id: Date.now(),
        matchId,
        sponsor: form.sponsor,
        prize: `${form.prizeAmount} ${form.prizeToken}`,
        prizeAmount: Number(form.prizeAmount),
        prizeToken: form.prizeToken,
        status: "upcoming",
        time: form.time,
        date: form.date,
        startTime,
        image: form.image || "/logo.jpg",
        description: form.description || `${form.sponsor} sponsored match`,
        url: form.url,
        createdAt: new Date().toISOString(),
        createdByWallet: walletAddress,
        depositTxHash: contractResult.txHash
      });

      setMatches((current) => [record, ...current]);
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
              <label>
                Sponsor
                <input name="sponsor" value={form.sponsor} onChange={handleChange} />
              </label>
              <label>
                Prize Amount
                <input name="prizeAmount" type="number" min="0" value={form.prizeAmount} onChange={handleChange} />
              </label>
              <label>
                Token
                <input name="prizeToken" value={form.prizeToken} onChange={handleChange} />
              </label>
              <label>
                Match Date
                <input name="date" type="date" value={form.date} onChange={handleChange} />
              </label>
              <label>
                Match Time
                <input name="time" type="time" value={form.time} onChange={handleChange} />
              </label>
              <label>
                Banner/Image
                <input name="image" value={form.image} onChange={handleChange} />
              </label>
              <label className="sponsor-modal__wide">
                Description
                <textarea name="description" rows="4" value={form.description} onChange={handleChange} />
              </label>
              <label className="sponsor-modal__wide">
                URL
                <input name="url" value={form.url} onChange={handleChange} />
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
