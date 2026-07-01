/**
 * World of Nads - Solana Integration Guide
 *
 * This file shows how the backend integrates with the Solana programs.
 * The pattern mirrors contracts-monad/backend/contractClient.js
 * but uses Solana Web3.js + Anchor for program interactions.
 *
 * DEPLOYED PROGRAM IDs (devnet):
 * - XP Token:     WONsXP111111111111111111111111111111111111
 * - Loot Box:   WONsLootBox11111111111111111111111111111111
 * - Match Engine: WONsMatchEngine111111111111111111111111111111
 * - Skins:      WONsSkins1111111111111111111111111111111111
 * - Treasury:  WONsTreasury111111111111111111111111111111
 *
 * PREREQUISITES:
 * - anchor: ^0.30.1
 * - @solana/web3.js: ^2.0.0
 * - Node.js: ^20
 */

import { Connection, PublicKey, Keypair, LAMPORTS_PER_SOL } from "@solana/web3.js";
import { Program, AnchorProvider, Wallet, BN } from "@coral-xyz/anchor";

// ============================================================
// CONFIGURATION
// ============================================================
export const SOLANA_CLUSTER = "devnet";
export const SOLANA_RPC = "https://api.devnet.solana.com";

export const PROGRAM_IDS = {
  xpToken: new PublicKey("WONsXP111111111111111111111111111111111111"),
  lootBox: new PublicKey("WONsLootBox11111111111111111111111111111111"),
  matchEngine: new PublicKey("WONsMatchEngine111111111111111111111111111111"),
  skins: new PublicKey("WONsSkins1111111111111111111111111111111111"),
  treasury: new PublicKey("WONsTreasury111111111111111111111111111111"),
};

// PDA seeds
const SEEDS = {
  xpConfig: [Buffer.from("config")],
  playerXp: [Buffer.from("player_xp")],
  lootConfig: [Buffer.from("config")],
  matchConfig: [Buffer.from("match")],
  matchVault: [Buffer.from("match_vault")],
  pool: [Buffer.from("pool")],
  poolVault: [Buffer.from("pool_vault")],
  skinConfig: [Buffer.from("config")],
  skin: [Buffer.from("skin")],
  treasuryConfig: [Buffer.from("config")],
  treasuryVault: [Buffer.from("treasury_vault")],
  playerBalance: [Buffer.from("player_balance")],
};

// ============================================================
// HELPERS
// ============================================================

function derivePda(seeds: Buffer[], programId: PublicKey): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(seeds, programId);
}

function getMatchPdas(matchId: Buffer, programId: PublicKey) {
  return {
    matchConfig: derivePda([...SEEDS.matchConfig, matchId], programId)[0],
    matchVault: derivePda([...SEEDS.matchVault, matchId], programId)[0],
    pool: derivePda([...SEEDS.pool, matchId], new PublicKey(PROGRAM_IDS.lootBox))[0],
    poolVault: derivePda([...SEEDS.poolVault, matchId], new PublicKey(PROGRAM_IDS.lootBox))[0],
  };
}

// ============================================================
// SETUP
// ============================================================

export function createSolanaClient(serverWallet: Keypair): {
  connection: Connection;
  provider: AnchorProvider;
  programs: Record<string, Program>;
} {
  const connection = new Connection(SOLANA_RPC, "confirmed");
  const wallet = new Wallet(serverWallet);
  const provider = new AnchorProvider(connection, wallet, {
    commitment: "confirmed",
  });

  // Load IDLs (in production, import from anchor build output)
  const programs: Record<string, Program> = {};

  return { connection, provider, programs };
}

// ============================================================
// MATCH LIFECYCLE (mirrors contracts-monad)
// ============================================================

export interface MatchLifecycle {
  createSponsoredMatch(params: {
    matchId: Buffer;
    totalPrize: number;
    expectedParticipants: number;
    startTime: number;
    winnerTokenURI: string;
    participationTokenURI: string;
    matchMetadataURI: string;
  }): Promise<string>;

  settleMatch(params: {
    matchId: Buffer;
    winner: PublicKey;
    participants: PublicKey[];
  }): Promise<string>;

  cancelMatch(params: {
    matchId: Buffer;
  }): Promise<string>;

  mintXP(params: {
    player: PublicKey;
    amount: number;
  }): Promise<string>;

  batchStreamMON(params: {
    matchId: Buffer;
    player: PublicKey;
    amounts: number[];
  }): Promise<string>;

  lootBoxSteal(params: {
    matchId: Buffer;
    newHolder: PublicKey;
  }): Promise<string>;

  getPoolValue(params: {
    matchId: Buffer;
  }): Promise<number>;
}

export function createMatchClient(serverWallet: Keypair): MatchLifecycle {
  const { provider } = createSolanaClient(serverWallet);

  // In production, replace with actual program instances from IDL
  // const matchEngine = new Program(IDL, PROGRAM_IDS.matchEngine, provider);

  return {
    async createSponsoredMatch(params) {
      const { matchConfig, matchVault } = getMatchPdas(
        params.matchId,
        PROGRAM_IDS.matchEngine
      );

      // const tx = await matchEngine.methods
      //   .createSponsoredMatch(
      //     Array.from(params.matchId),
      //     new BN(params.totalPrize),
      //     params.expectedParticipants,
      //     params.startTime,
      //     params.winnerTokenURI,
      //     params.participationTokenURI,
      //     params.matchMetadataURI
      //   )
      //   .accounts({
      //     matchConfig,
      //     matchVault,
      //     sponsor: serverWallet.publicKey,
      //   })
      //   .rpc();

      return "tx_signature_placeholder";
    },

    async settleMatch(params) {
      const { matchConfig, matchVault } = getMatchPdas(
        params.matchId,
        PROGRAM_IDS.matchEngine
      );

      // const tx = await matchEngine.methods
      //   .settleMatch(
      //     Array.from(params.matchId),
      //     params.winner,
      //     params.participants
      //   )
      //   .accounts({
      //     config: configPda,
      //     matchConfig,
      //     matchVault,
      //     winnerAccount: params.winner,
      //     authority: serverWallet.publicKey,
      //   })
      //   .rpc();

      return "tx_signature_placeholder";
    },

    async cancelMatch(params) {
      // const tx = await matchEngine.methods
      //   .cancelSponsoredMatch(Array.from(params.matchId))
      //   .accounts({ ... })
      //   .rpc();
      return "tx_signature_placeholder";
    },

    async mintXP(params) {
      const [configPda] = derivePda(SEEDS.xpConfig, PROGRAM_IDS.xpToken);
      const [playerXpPda] = derivePda(
        [...SEEDS.playerXp, params.player.toBuffer()],
        PROGRAM_IDS.xpToken
      );

      // const tx = await xpToken.methods
      //   .mintXp(params.player, new BN(params.amount))
      //   .accounts({
      //     config: configPda,
      //     playerXp: playerXpPda,
      //     signer: serverWallet.publicKey,
      //   })
      //   .rpc();

      return "tx_signature_placeholder";
    },

    async batchStreamMON(params) {
      // const tx = await lootBox.methods
      //   .batchStream(Array.from(params.matchId), params.amounts)
      //   .accounts({ ... })
      //   .rpc();
      return "tx_signature_placeholder";
    },

    async lootBoxSteal(params) {
      const { pool, poolVault } = getMatchPdas(
        params.matchId,
        PROGRAM_IDS.lootBox
      );

      // const tx = await lootBox.methods
      //   .steal(Array.from(params.matchId))
      //   .accounts({
      //     config: lootConfigPda,
      //     pool,
      //     poolVault,
      //     newHolder: params.newHolder,
      //     burnAddress: burnPda,
      //     signer: serverWallet.publicKey,
      //   })
      //   .rpc();

      return "tx_signature_placeholder";
    },

    async getPoolValue(params) {
      const { pool } = getMatchPdas(params.matchId, PROGRAM_IDS.lootBox);
      // const poolAccount = await lootBox.account.pool.fetch(pool);
      // return poolAccount.remainingValue.toNumber();
      return 0;
    },
  };
}

// ============================================================
// TREASURY / $WON OPERATIONS
// ============================================================

export async function depositToTreasury(
  serverWallet: Keypair,
  player: PublicKey,
  amountSol: number
): Promise<string> {
  const [configPda] = derivePda(SEEDS.treasuryConfig, PROGRAM_IDS.treasury);
  const [treasuryVaultPda] = derivePda(SEEDS.treasuryVault, PROGRAM_IDS.treasury);
  const [playerBalancePda] = derivePda(
    [...SEEDS.playerBalance, player.toBuffer()],
    PROGRAM_IDS.treasury
  );

  // Player signs this transaction on the frontend
  // const tx = await treasury.methods
  //   .deposit(new BN(amountSol * LAMPORTS_PER_SOL))
  //   .accounts({
  //     config: configPda,
  //     playerBalance: playerBalancePda,
  //     treasuryVault: treasuryVaultPda,
  //     payer: player,
  //   })
  //   .rpc();

  return "tx_signature_placeholder";
}

export async function creditWonFromMonad(
  serverWallet: Keypair,
  user: PublicKey,
  monAmount: number,
  monadTxHash: Buffer
): Promise<string> {
  const [configPda] = derivePda(SEEDS.treasuryConfig, PROGRAM_IDS.treasury);
  const [playerBalancePda] = derivePda(
    [...SEEDS.playerBalance, user.toBuffer()],
    PROGRAM_IDS.treasury
  );
  const [crossChainPda] = derivePda(
    [Buffer.from("cross_chain"), monadTxHash],
    PROGRAM_IDS.treasury
  );

  // 1 MON = 1 $WON (1:1 conversion rate)
  const wonAmount = monAmount;

  // const tx = await treasury.methods
  //   .creditFromMonad(user, new BN(monAmount), new BN(wonAmount), Array.from(monadTxHash))
  //   .accounts({
  //     config: configPda,
  //     playerBalance: playerBalancePda,
  //     crossChainRecord: crossChainPda,
  //     user,
  //     authority: serverWallet.publicKey,
  //   })
  //   .rpc();

  return "tx_signature_placeholder";
}

// ============================================================
// SKIN OPERATIONS
// ============================================================

export async function createSkin(
  serverWallet: Keypair,
  params: {
    maxSupply: number;
    mintPrice: number;
    requiredXp: number;
    tier: number;
    uri: string;
  }
): Promise<string> {
  const [configPda] = derivePda(SEEDS.skinConfig, PROGRAM_IDS.skins);

  // Get next skin ID
  // const config = await skins.account.config.fetch(configPda);
  const skinId = 1; // config.nextSkinId

  const [skinPda] = derivePda(
    [...SEEDS.skin, new BN(skinId).toArrayLike(Buffer, "le", 8)],
    PROGRAM_IDS.skins
  );

  // const tx = await skins.methods
  //   .createSkin(
  //     new BN(params.maxSupply),
  //     new BN(params.mintPrice * LAMPORTS_PER_SOL),
  //     new BN(params.requiredXp),
  //     params.tier,
  //     params.uri
  //   )
  //   .accounts({
  //     config: configPda,
  //     skin: skinPda,
  //     authority: serverWallet.publicKey,
  //   })
  //   .rpc();

  return "tx_signature_placeholder";
}
