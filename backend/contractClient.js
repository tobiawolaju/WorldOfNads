import { ethers } from "ethers";
import * as dotenv from 'dotenv';
dotenv.config();

const MATCH_ENGINE_ABI = [
    "function createSponsoredMatch(bytes32 matchId, address prizeToken, uint256 totalPrize, uint32 expectedParticipants, uint64 startTime, string winnerTokenURI, string participationTokenURI, string matchMetadataURI) external payable",
    "function settleMatch(bytes32 matchId, address winner, address[] calldata participants, address lootBoxFinalHolder, uint256 gasCompensation) external",
    "function cancelSponsoredMatch(bytes32 matchId) external",
    "function getMatch(bytes32 matchId) external view returns (address sponsor, address prizeToken, uint256 winnerPrize, uint256 lootBoxPool, uint256 winnerTokenId, uint256 participationTokenId, uint32 expectedParticipants, uint64 createdAt, uint64 startTime, uint64 settledAt, bool settled, bool cancelled, string matchMetadataURI)"
];

const XP_ABI = [
    "function mintXP(address to, uint256 amount) external",
    "function balanceOf(address account) external view returns (uint256)"
];

const LOOTBOX_ABI = [
    "function batchStream(bytes32 matchId, address[] calldata players, uint256[] calldata amounts) external",
    "function steal(bytes32 matchId, address newHolder) external",
    "function getPoolValue(bytes32 matchId) external view returns (uint256)"
];

const SKINS_ABI = [
    "function mintSkin(uint256 skinId, uint256 amount) external payable",
    "function createSkin(uint256 maxSupply, uint256 mintPrice, uint256 requiredXP, uint8 tier, string calldata uri) external",
    "function balanceOf(address account, uint256 id) external view returns (uint256)",
    "function uri(uint256 tokenId) external view returns (string memory)",
    "function getRequiredXPForSkin(uint256 skinId) external view returns (uint256)",
    "function nextSkinId() external view returns (uint256)",
    "function skins(uint256 skinId) external view returns (uint256 maxSupply, uint256 minted, uint256 mintPrice, uint256 requiredXP, uint8 tier, bool exists)",
    "event SkinCreated(uint256 indexed skinId, uint256 maxSupply, uint256 mintPrice, uint256 requiredXP, uint8 tier)"
];

const provider = new ethers.JsonRpcProvider(process.env.MN_RPC_URL || "https://testnet-rpc.monad.xyz");
const wallet = new ethers.Wallet(process.env.TRUSTED_AUTHORITY_PRIVATE_KEY, provider);

function getContract(address, abi) {
    return new ethers.Contract(address, abi, wallet);
}

function getMatchEngine() {
    return getContract(process.env.MATCH_ENGINE_ADDRESS, MATCH_ENGINE_ABI);
}

function getXP() {
    return getContract(process.env.XP_TOKEN_ADDRESS, XP_ABI);
}

function getLootBox() {
    return getContract(process.env.LOOTBOX_ADDRESS, LOOTBOX_ABI);
}

function getSkins() {
    return getContract(process.env.SKINS_ADDRESS, SKINS_ABI);
}

function toBytes32(matchIdStr) {
    if (matchIdStr.startsWith('0x') && matchIdStr.length === 66) {
        return matchIdStr;
    }
    return ethers.id(matchIdStr);
}

export async function createMatchOnchain(matchIdStr, prizeAmount, startTime) {
    try {
        const matchIdBytes = toBytes32(matchIdStr);
        const matchEngine = getMatchEngine();
        const prizeValue = ethers.parseUnits(String(prizeAmount || 0), 18);
        const startTimeU64 = BigInt(Math.floor(startTime || (Date.now() / 1000 + 3600)));

        const tx = await matchEngine.createSponsoredMatch(
            matchIdBytes,
            "0x0000000000000000000000000000000000000000",
            prizeValue,
            20,
            startTimeU64,
            "",
            "",
            "",
            { value: prizeValue, gasLimit: 500000 }
        );

        const receipt = await tx.wait();
        return { success: true, txHash: tx.hash, blockNumber: receipt.blockNumber };
    } catch (error) {
        console.error(`[Onchain] createMatch failed:`, error.message);
        return { success: false, error: error.message };
    }
}

export async function settleMatchOnchain(matchIdStr, winnerAddress, participantAddresses, lootBoxFinalHolder) {
    try {
        const matchIdBytes = toBytes32(matchIdStr);
        const matchEngine = getMatchEngine();
        const uniqueParticipants = [...new Set(participantAddresses.filter(a => !!a))];

        const finalHolder = lootBoxFinalHolder || winnerAddress;

        // Estimate gas to ensure tx will succeed, but no compensation taken from winner
        const gasEstimate = await matchEngine.settleMatch.estimateGas(
            matchIdBytes,
            winnerAddress,
            uniqueParticipants,
            finalHolder,
            0n
        );
        // Include a buffer so the tx doesn't run out of gas
        const gasLimit = (gasEstimate * 120n / 100n) > 500000n ? (gasEstimate * 120n / 100n) : 500000n;

        const tx = await matchEngine.settleMatch(
            matchIdBytes,
            winnerAddress,
            uniqueParticipants,
            finalHolder,
            0n, // No gas compensation — winner gets full prize
            { gasLimit: gasLimit }
        );

        const receipt = await tx.wait();
        return { success: true, txHash: tx.hash, blockNumber: receipt.blockNumber };
    } catch (error) {
        console.error(`[Onchain] settleMatch failed:`, error.message);
        return { success: false, error: error.message };
    }
}

// Returns per-stream micro-reward amount based on pool size to guarantee at least 1000 streams
export function calcMicroRewardPerStream(poolValueEther) {
    const MIN_STREAMS = 1000;
    const poolWei = ethers.parseUnits(String(poolValueEther), 18);
    if (poolWei <= 0n) return "0";
    const perStream = poolWei / BigInt(MIN_STREAMS);
    return ethers.formatEther(perStream);
}

// Calculates the dynamic MON-per-second streaming rate for the match
export function calcMonPerSec(poolValueEther, matchDurationSec) {
    const perStream = calcMicroRewardPerStream(poolValueEther);
    // Spread the per-stream amount across the match duration
    // (streams happen every ~1 second so rate = perStream / matchDuration)
    const perStreamWei = ethers.parseUnits(perStream, 18);
    if (perStreamWei <= 0n) return 0;
    // Scale so a fully-proximate player earns ~perStream over the whole match
    return Number(ethers.formatEther(perStreamWei)) / matchDurationSec;
}

export async function cancelMatchOnchain(matchIdStr) {
    try {
        const matchIdBytes = toBytes32(matchIdStr);
        const matchEngine = getMatchEngine();
        const tx = await matchEngine.cancelSponsoredMatch(matchIdBytes, { gasLimit: 300000 });
        const receipt = await tx.wait();
        return { success: true, txHash: tx.hash };
    } catch (error) {
        console.error(`[Onchain] cancelMatch failed:`, error.message);
        return { success: false, error: error.message };
    }
}

export async function mintXP(playerAddress, amount) {
    try {
        const xp = getXP();
        const amountWei = ethers.parseUnits(String(amount), 18);
        const tx = await xp.mintXP(playerAddress, amountWei, { gasLimit: 100000 });
        await tx.wait();
        return { success: true, txHash: tx.hash };
    } catch (error) {
        console.error(`[Onchain] mintXP failed:`, error.message);
        return { success: false, error: error.message };
    }
}

export async function batchStreamMON(matchIdStr, playerAddresses, amounts) {
    try {
        const matchIdBytes = toBytes32(matchIdStr);
        const lootBox = getLootBox();
        const amountWei = amounts.map(a => {
            const str = typeof a === 'bigint' ? ethers.formatEther(a) : String(a);
            return ethers.parseUnits(str, 18);
        });

        const tx = await lootBox.batchStream(matchIdBytes, playerAddresses, amountWei, { gasLimit: 300000 });
        await tx.wait();
        return { success: true, txHash: tx.hash };
    } catch (error) {
        console.error(`[Onchain] batchStreamMON failed:`, error.message);
        return { success: false, error: error.message };
    }
}

export async function lootBoxSteal(matchIdStr, newHolder) {
    try {
        const matchIdBytes = toBytes32(matchIdStr);
        const lootBox = getLootBox();
        const tx = await lootBox.steal(matchIdBytes, newHolder, { gasLimit: 100000 });
        await tx.wait();
        return { success: true, txHash: tx.hash };
    } catch (error) {
        console.error(`[Onchain] lootBoxSteal failed:`, error.message);
        return { success: false, error: error.message };
    }
}

export async function getPoolValue(matchIdStr) {
    try {
        const matchIdBytes = toBytes32(matchIdStr);
        const lootBox = getLootBox();
        const value = await lootBox.getPoolValue(matchIdBytes);
        return ethers.formatEther(value);
    } catch (error) {
        console.error(`[Onchain] getPoolValue failed:`, error.message);
        return "0";
    }
}

export async function getSkinData(skinId) {
    try {
        const skins = getSkins();
        const [maxSupply, minted, mintPrice, requiredXP, tier, exists] = await skins.skins(skinId);
        const tokenUri = await skins.uri(skinId);
        return {
            maxSupply: Number(maxSupply),
            minted: Number(minted),
            mintPrice: ethers.formatEther(mintPrice),
            requiredXP: Number(requiredXP),
            tier: Number(tier),
            exists,
            uri: tokenUri
        };
    } catch (error) {
        console.error(`[Onchain] getSkinData failed:`, error.message);
        return null;
    }
}

export async function getAllSkins() {
    try {
        const skins = getSkins();
        const count = await skins.nextSkinId();
        const results = [];
        for (let i = 1; i < Number(count); i++) {
            const data = await getSkinData(i);
            if (data && data.exists) {
                results.push({ skinId: i, ...data });
            }
        }
        return results;
    } catch (error) {
        console.error(`[Onchain] getAllSkins failed:`, error.message);
        return [];
    }
}

export async function contractWithdraw(contractAddress) {
    try {
        const contract = new ethers.Contract(contractAddress, [
            "function withdraw() external"
        ], wallet);
        const tx = await contract.withdraw({ gasLimit: 100000 });
        await tx.wait();
        return { success: true, txHash: tx.hash };
    } catch (error) {
        console.error(`[Onchain] withdraw failed for ${contractAddress}:`, error.message);
        return { success: false, error: error.message };
    }
}

export async function getXPBalance(address) {
    try {
        const xp = getXP();
        const balance = await xp.balanceOf(address);
        return ethers.formatEther(balance);
    } catch (error) {
        console.error(`[Onchain] getXPBalance failed:`, error.message);
        return "0";
    }
}

export async function createSkinOnchain(maxSupply, mintPrice, requiredXP, tier, uri) {
    try {
        const skins = getSkins();
        const priceWei = ethers.parseUnits(String(mintPrice), 18);
        const tx = await skins.createSkin(
            BigInt(maxSupply),
            priceWei,
            BigInt(requiredXP),
            tier,
            uri || `https://worldofnads.com/api/skins/${Date.now()}`,
            { gasLimit: 650000 }
        );
        const receipt = await tx.wait();
        let skinId = null;
        if (receipt.logs && receipt.logs.length > 0) {
            try {
                const parsed = skins.interface.parseLog(receipt.logs[0]);
                if (parsed && parsed.name === 'SkinCreated') {
                    skinId = Number(parsed.args.skinId);
                }
            } catch { /* event parse failed, ignore */ }
        }
        return { success: true, txHash: tx.hash, blockNumber: receipt.blockNumber, skinId };
    } catch (error) {
        console.error(`[Onchain] createSkin failed:`, error.message);
        return { success: false, error: error.message };
    }
}

export async function getSkinBalance(address, skinId) {
    try {
        const skins = getSkins();
        const balance = await skins.balanceOf(address, skinId);
        return Number(balance);
    } catch (error) {
        console.error(`[Onchain] getSkinBalance failed:`, error.message);
        return 0;
    }
}
