import { ethers } from "ethers";

export const sponsorClickContractAbi = [
  "function createSponsoredMatch(bytes32 matchId, address prizeToken, uint256 firstPlacePrize, uint32 expectedParticipants, uint64 startTime, string winnerTokenURI, string participationTokenURI, string matchMetadataURI) external payable",
  "function cancelSponsoredMatch(bytes32 matchId) external",
  "event MatchCreated(bytes32 indexed matchId, address indexed sponsor, address indexed prizeToken, uint256 firstPlacePrize, uint256 winnerTokenId, uint256 participationTokenId, uint32 expectedParticipants, uint256 startTime, string matchMetadataURI)",
  "event MatchCancelled(bytes32 indexed matchId, address indexed sponsor, uint256 amountReturned)"
];

export async function createSponsorMatchOnchain({ 
  embeddedWallet, 
  matchId, 
  prizeToken, 
  prizeAmount, 
  expectedParticipants, 
  startTime,
  winnerTokenURI,
  participationTokenURI,
  matchMetadataURI 
}) {
  if (!embeddedWallet) {
    throw new Error("No Privy wallet available for contract interaction.");
  }

  const providerSource = await embeddedWallet.getEthereumProvider();
  const browserProvider = new ethers.BrowserProvider(providerSource);
  const signer = await browserProvider.getSigner();
  const contractAddress = import.meta.env.VITE_SPONSOR_CLICK_CONTRACT_ADDRESS;

  if (!contractAddress) {
    return {
      txHash: `mock-${matchId}-${Date.now()}`,
      mode: "mock"
    };
  }

  const isNative = !prizeToken || prizeToken === "0x0000000000000000000000000000000000000000";
  const prizeValue = ethers.parseUnits(String(prizeAmount || 0), 18);

  const contract = new ethers.Contract(contractAddress, sponsorClickContractAbi, signer);
  
  // Ensure matchId is a bytes32 hex string. If it's a plain string, hash it.
  const formattedMatchId = matchId.startsWith("0x") && matchId.length === 66 
    ? matchId 
    : ethers.id(matchId);

  const tx = await contract.createSponsoredMatch(
    formattedMatchId,
    isNative ? "0x0000000000000000000000000000000000000000" : prizeToken,
    prizeValue,
    expectedParticipants || 50,
    startTime || Math.floor(Date.now() / 1000) + 3600,
    winnerTokenURI || "",
    participationTokenURI || "",
    matchMetadataURI || "",
    {
      value: isNative ? prizeValue : 0
    }
  );
  const receipt = await tx.wait();

  return {
    txHash: receipt?.hash || tx.hash,
    mode: "onchain"
  };
}

export async function cancelSponsorMatchOnchain({ embeddedWallet, matchId }) {
  if (!embeddedWallet) {
    throw new Error("No Privy wallet available.");
  }

  const providerSource = await embeddedWallet.getEthereumProvider();
  const browserProvider = new ethers.BrowserProvider(providerSource);
  const signer = await browserProvider.getSigner();
  const contractAddress = import.meta.env.VITE_SPONSOR_CLICK_CONTRACT_ADDRESS;

  if (!contractAddress) {
    return { txHash: `mock-cancel-${matchId}`, mode: "mock" };
  }

  const contract = new ethers.Contract(contractAddress, sponsorClickContractAbi, signer);

  // Ensure matchId is a bytes32 hex string. If it's a plain string, hash it.
  const formattedMatchId = matchId.startsWith("0x") && matchId.length === 66 
    ? matchId 
    : ethers.id(matchId);

  const tx = await contract.cancelSponsoredMatch(formattedMatchId);
  const receipt = await tx.wait();

  return {
    txHash: receipt?.hash || tx.hash,
    mode: "onchain"
  };
}
