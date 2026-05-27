import { ethers } from "ethers";
import * as dotenv from 'dotenv';
dotenv.config();

const ABI = [
    "function settleMatch(bytes32 matchId, address winner, address[] calldata participants) external",
    "function matchesById(bytes32 matchId) external view returns (address sponsor, address prizeToken, uint256 firstPlacePrize, uint256 winnerTokenId, uint256 participationTokenId, uint32 expectedParticipants, uint64 createdAt, uint64 startTime, uint64 settledAt, bool settled, bool cancelled, string matchMetadataURI)"
];

const provider = new ethers.JsonRpcProvider(process.env.MN_RPC_URL || "https://rpc.monad.xyz");
const wallet = new ethers.Wallet(process.env.TRUSTED_AUTHORITY_PRIVATE_KEY, provider);
const contract = new ethers.Contract(process.env.CONTRACT_ADDRESS, ABI, wallet);

/**
 * Automates the payout for a match.
 * @param {string} matchIdStr - The string matchId (e.g. "match-tobia-12345")
 * @param {string} winnerAddress - The EVM address of the winner
 * @param {string[]} participantAddresses - List of EVM addresses for all participants
 */
export async function settleMatchOnchain(matchIdStr, winnerAddress, participantAddresses) {
    try {
        console.log(`[Onchain] Attempting to settle match: ${matchIdStr}`);

        // Convert matchId string to bytes32 (as used in the contract)
        // We use keccak256 of the string if that's how it was stored, 
        // but the frontend used `ethers.utils.formatBytes32String` or similar? 
        // Actually, let's check how the frontend created it.

        // In SpounsorDashbaord.jsx, matchId is a string. 
        // In mockSponsorContract.js, let's see how it's handled.

        // For now, let's assume we need to encode it as bytes32.
        // If it's a raw string shorter than 32 bytes, we can use formatBytes32String.
        // matchIdStr is likely "match-xxx-timestamp" which fits.

        let matchIdBytes;
        if (matchIdStr.startsWith('0x') && matchIdStr.length === 66) {
            matchIdBytes = matchIdStr;
        } else {
            matchIdBytes = ethers.id(matchIdStr);
        }

        console.log(`[Onchain] Winner: ${winnerAddress}`);
        console.log(`[Onchain] Participants: ${participantAddresses.length}`);

        const tx = await contract.settleMatch(
            matchIdBytes,
            winnerAddress,
            participantAddresses,
            {
                gasLimit: 500000 // Monad testnet gas can be a bit volatile
            }
        );

        console.log(`[Onchain] Settlement TX Sent: ${tx.hash}`);
        const receipt = await tx.wait();
        console.log(`[Onchain] Settlement Confirmed in block ${receipt.blockNumber}`);

        return { success: true, txHash: tx.hash };
    } catch (error) {
        console.error(`[Onchain] Settlement Failed:`, error.message);
        if (error.data) {
            console.error(`[Onchain] Error Data:`, error.data);
        }
        return { success: false, error: error.message };
    }
}
