import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { PublicKey, LAMPORTS_PER_SOL, SystemProgram } from "@solana/web3.js";
import { expect } from "chai";

describe("World of Nads - Solana Contracts", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);
  const wallet = provider.wallet as anchor.Wallet;

  // Program instances
  const xpToken = anchor.workspace.XpToken as Program;
  const lootBox = anchor.workspace.LootBox as Program;
  const matchEngine = anchor.workspace.MatchEngine as Program;
  const skins = anchor.workspace.Skins as Program;
  const treasury = anchor.workspace.Treasury as Program;

  // PDAs
  const [xpConfigPda] = PublicKey.findProgramAddressSync(
    [Buffer.from("config")],
    xpToken.programId
  );
  const [lootConfigPda] = PublicKey.findProgramAddressSync(
    [Buffer.from("config")],
    lootBox.programId
  );
  const [matchConfigPda] = PublicKey.findProgramAddressSync(
    [Buffer.from("config")],
    matchEngine.programId
  );
  const [skinConfigPda] = PublicKey.findProgramAddressSync(
    [Buffer.from("config")],
    skins.programId
  );
  const [treasuryConfigPda] = PublicKey.findProgramAddressSync(
    [Buffer.from("config")],
    treasury.programId
  );
  const [treasuryVaultPda] = PublicKey.findProgramAddressSync(
    [Buffer.from("treasury_vault")],
    treasury.programId
  );
  const [playerXpPda] = PublicKey.findProgramAddressSync(
    [Buffer.from("player_xp"), wallet.publicKey.toBuffer()],
    xpToken.programId
  );

  const matchId = anchor.utils.bytes.hexToBytes(
    "0000000000000000000000000000000000000000000000000000000000000001"
  );

  it("Initializes all programs", async () => {
    // Init XP Token
    await xpToken.methods
      .initialize(wallet.publicKey)
      .accounts({ config: xpConfigPda, payer: wallet.publicKey })
      .rpc();

    // Init Loot Box
    await lootBox.methods
      .initialize(wallet.publicKey)
      .accounts({
        config: lootConfigPda,
        matchEngine: matchEngine.programId,
        payer: wallet.publicKey,
      })
      .rpc();

    // Init Match Engine
    await matchEngine.methods
      .initialize(wallet.publicKey, wallet.publicKey)
      .accounts({
        config: matchConfigPda,
        lootBoxProgram: lootBox.programId,
        xpTokenProgram: xpToken.programId,
        payer: wallet.publicKey,
      })
      .rpc();

    // Init Skins
    await skins.methods
      .initialize(wallet.publicKey)
      .accounts({
        config: skinConfigPda,
        xpProgram: xpToken.programId,
        payer: wallet.publicKey,
      })
      .rpc();

    // Init Treasury
    await treasury.methods
      .initialize(wallet.publicKey)
      .accounts({
        config: treasuryConfigPda,
        treasuryVault: treasuryVaultPda,
        payer: wallet.publicKey,
      })
      .rpc();

    // Verify
    const xpConfig = await xpToken.account.config.fetch(xpConfigPda);
    expect(xpConfig.authority.toString()).to.equal(wallet.publicKey.toString());
  });

  it("Sets up roles", async () => {
    // Set XP minter to match engine
    await xpToken.methods
      .setMinter(matchEngine.programId, true)
      .accounts({ config: xpConfigPda, authority: wallet.publicKey })
      .rpc();

    // Set loot box trusted caller
    await lootBox.methods
      .setTrustedCaller(wallet.publicKey)
      .accounts({ config: lootConfigPda, authority: wallet.publicKey })
      .rpc();

    // Set loot box match engine
    await lootBox.methods
      .setMatchEngine(matchEngine.programId)
      .accounts({ config: lootConfigPda, authority: wallet.publicKey })
      .rpc();
  });

  it("Creates a sponsored match", async () => {
    const prizeAmount = 10 * LAMPORTS_PER_SOL; // 10 SOL
    const [matchConfigPda] = PublicKey.findProgramAddressSync(
      [Buffer.from("match"), matchId],
      matchEngine.programId
    );
    const [matchVaultPda] = PublicKey.findProgramAddressSync(
      [Buffer.from("match_vault"), matchId],
      matchEngine.programId
    );

    await matchEngine.methods
      .createSponsoredMatch(
        Array.from(matchId),
        new anchor.BN(prizeAmount),
        20,
        Math.floor(Date.now() / 1000) + 3600,
        "ipfs://winner_uri",
        "ipfs://participation_uri",
        "ipfs://match_meta"
      )
      .accounts({
        matchConfig: matchConfigPda,
        matchVault: matchVaultPda,
        sponsor: wallet.publicKey,
      })
      .rpc();

    const match = await matchEngine.account.matchConfig.fetch(matchConfigPda);
    expect(match.initialized).to.be.true;
    expect(match.winnerPrize.toString()).to.equal(
      new anchor.BN(prizeAmount * 0.8).toString() // 80%
    );
  });

  it("Deposits SOL to treasury and gets $WON", async () => {
    const depositAmount = 5 * LAMPORTS_PER_SOL;
    const [playerBalancePda] = PublicKey.findProgramAddressSync(
      [Buffer.from("player_balance"), wallet.publicKey.toBuffer()],
      treasury.programId
    );

    await treasury.methods
      .deposit(new anchor.BN(depositAmount))
      .accounts({
        config: treasuryConfigPda,
        playerBalance: playerBalancePda,
        treasuryVault: treasuryVaultPda,
        payer: wallet.publicKey,
      })
      .rpc();

    const balance = await treasury.account.playerBalance.fetch(playerBalancePda);
    expect(balance.balanceWon.toString()).to.equal(
      new anchor.BN(depositAmount).toString()
    );
  });
});
