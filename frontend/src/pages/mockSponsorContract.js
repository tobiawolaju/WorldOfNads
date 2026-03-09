import { ethers } from "ethers";

export const sponsorClickContractAbi = [
  "function clickCreateMatch(bytes32 matchId) external payable",
  "event MatchClicked(bytes32 indexed matchId, address indexed sender, uint256 amount)"
];

export async function createSponsorMatchOnchain({ embeddedWallet, matchId, prizeAmount }) {
  if (!embeddedWallet) {
    throw new Error("No Privy wallet available for contract interaction.");
  }

  const providerSource = await embeddedWallet.getProvider();
  const browserProvider = new ethers.BrowserProvider(providerSource);
  const signer = await browserProvider.getSigner();
  const contractAddress = import.meta.env.VITE_SPONSOR_CLICK_CONTRACT_ADDRESS;

  if (!contractAddress) {
    return {
      txHash: `mock-${matchId}-${Date.now()}`,
      mode: "mock"
    };
  }

  const contract = new ethers.Contract(contractAddress, sponsorClickContractAbi, signer);
  const tx = await contract.clickCreateMatch(ethers.id(matchId), {
    value: ethers.parseEther(String(prizeAmount || 0))
  });
  const receipt = await tx.wait();

  return {
    txHash: receipt?.hash || tx.hash,
    mode: "onchain"
  };
}
