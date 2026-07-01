import { ethers } from "ethers";

const MONAD_TESTNET_CHAIN_ID = 10143n;
const MONAD_TESTNET_HEX = '0x279F';

export const matchEngineAbi = [
  "function createSponsoredMatch(bytes32 matchId, address prizeToken, uint256 totalPrize, uint32 expectedParticipants, uint64 startTime, string winnerTokenURI, string participationTokenURI, string matchMetadataURI) external payable",
  "function cancelSponsoredMatch(bytes32 matchId) external",
  "function getMatch(bytes32 matchId) external view returns (address sponsor, address prizeToken, uint256 winnerPrize, uint256 lootBoxPool, uint256 winnerTokenId, uint256 participationTokenId, uint32 expectedParticipants, uint64 createdAt, uint64 startTime, uint64 settledAt, bool settled, bool cancelled, string matchMetadataURI)",
  "event MatchCreated(bytes32 indexed matchId, address indexed sponsor, address indexed prizeToken, uint256 totalPrize, uint256 winnerPrize, uint256 lootBoxPool, uint256 winnerTokenId, uint256 participationTokenId, uint32 expectedParticipants, uint256 startTime, string matchMetadataURI)",
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

  const network = await browserProvider.getNetwork();
  if (BigInt(network.chainId) !== MONAD_TESTNET_CHAIN_ID) {
    try {
      await providerSource.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: MONAD_TESTNET_HEX }],
      });
    } catch (switchError) {
      if (switchError.code === 4902) {
        throw new Error("Monad Testnet network not found in provider. Please add it.");
      }
      throw switchError;
    }
  }

  const signer = await browserProvider.getSigner();
  const contractAddress = import.meta.env.VITE_MATCH_ENGINE_ADDRESS;

  if (!contractAddress) {
    return {
      txHash: `mock-${matchId}-${Date.now()}`,
      mode: "mock"
    };
  }

  const isNative = !prizeToken || prizeToken === "0x0000000000000000000000000000000000000000";
  const prizeValue = ethers.parseUnits(String(prizeAmount || 0), 18);

  const contract = new ethers.Contract(contractAddress, matchEngineAbi, signer);
  const maxUint32 = 4294967295;
  const normalizedExpectedParticipants = Number.isFinite(expectedParticipants) && expectedParticipants > 0
    ? Math.min(expectedParticipants, maxUint32)
    : maxUint32;

  const formattedMatchId = matchId.startsWith("0x") && matchId.length === 66
    ? matchId
    : ethers.id(matchId);

  const tx = await contract.createSponsoredMatch(
    formattedMatchId,
    isNative ? "0x0000000000000000000000000000000000000000" : prizeToken,
    prizeValue,
    normalizedExpectedParticipants,
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

  const network = await browserProvider.getNetwork();
  if (BigInt(network.chainId) !== MONAD_TESTNET_CHAIN_ID) {
    try {
      await providerSource.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: MONAD_TESTNET_HEX }],
      });
    } catch (switchError) {
      if (switchError.code === 4902) {
        throw new Error("Monad Testnet network not found in provider.");
      }
      throw switchError;
    }
  }

  const signer = await browserProvider.getSigner();
  const contractAddress = import.meta.env.VITE_MATCH_ENGINE_ADDRESS;

  if (!contractAddress) {
    return { txHash: `mock-cancel-${matchId}`, mode: "mock" };
  }

  const contract = new ethers.Contract(contractAddress, matchEngineAbi, signer);

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
