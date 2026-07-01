use anchor_lang::prelude::*;
use anchor_lang::system_program;

declare_id!("WONsMatchEngine111111111111111111111111111111");

pub const MAX_PARTICIPANTS: u64 = 64;
pub const WINNER_SHARE_BPS: u64 = 8000; // 80%
pub const LOOTBOX_SHARE_BPS: u64 = 2000; // 20%

#[program]
pub mod match_engine {
    use super::*;

    pub fn initialize(
        ctx: Context<Initialize>,
        authority: Pubkey,
        trusted_authority: Pubkey,
    ) -> Result<()> {
        let config = &mut ctx.accounts.config;
        config.authority = authority;
        config.trusted_authority = trusted_authority;
        config.loot_box = ctx.accounts.loot_box_program.key();
        config.xp_token = ctx.accounts.xp_token_program.key();
        config.next_token_id = 1;
        Ok(())
    }

    pub fn set_trusted_authority(
        ctx: Context<SetTrustedAuthority>,
        new_authority: Pubkey,
    ) -> Result<()> {
        require!(
            ctx.accounts.authority.key() == ctx.accounts.config.authority,
            MatchError::Unauthorized
        );
        ctx.accounts.config.trusted_authority = new_authority;
        Ok(())
    }

    pub fn set_loot_box(ctx: Context<SetLootBox>, loot_box: Pubkey) -> Result<()> {
        require!(
            ctx.accounts.authority.key() == ctx.accounts.config.authority,
            MatchError::Unauthorized
        );
        ctx.accounts.config.loot_box = loot_box;
        Ok(())
    }

    pub fn set_xp_token(ctx: Context<SetXpToken>, xp_token: Pubkey) -> Result<()> {
        require!(
            ctx.accounts.authority.key() == ctx.accounts.config.authority,
            MatchError::Unauthorized
        );
        ctx.accounts.config.xp_token = xp_token;
        Ok(())
    }

    pub fn create_sponsored_match(
        ctx: Context<CreateSponsoredMatch>,
        match_id: [u8; 32],
        total_prize: u64,
        expected_participants: u32,
        start_time: i64,
        winner_token_uri: String,
        participation_token_uri: String,
        match_metadata_uri: String,
    ) -> Result<()> {
        require!(total_prize > 0, MatchError::PrizeMustBePositive);
        require!(
            expected_participants <= MAX_PARTICIPANTS as u32,
            MatchError::TooManyParticipants
        );

        let match_config = &mut ctx.accounts.match_config;
        require!(!match_config.initialized, MatchError::MatchAlreadyExists);

        let winner_prize = total_prize
            .checked_mul(WINNER_SHARE_BPS)
            .unwrap()
            .checked_div(10000)
            .unwrap();
        let loot_box_pool = total_prize
            .checked_mul(LOOTBOX_SHARE_BPS)
            .unwrap()
            .checked_div(10000)
            .unwrap();

        require!(
            winner_prize.checked_add(loot_box_pool).unwrap() <= total_prize,
            MatchError::ShareMismatch
        );

        let clock = Clock::get()?;

        match_config.match_id = match_id;
        match_config.sponsor = ctx.accounts.sponsor.key();
        match_config.winner_prize = winner_prize;
        match_config.loot_box_pool = loot_box_pool;
        match_config.expected_participants = expected_participants;
        match_config.created_at = clock.unix_timestamp;
        match_config.start_time = start_time;
        match_config.initialized = true;
        match_config.settled = false;
        match_config.cancelled = false;
        match_config.winner_token_uri = winner_token_uri;
        match_config.participation_token_uri = participation_token_uri;
        match_config.match_metadata_uri = match_metadata_uri;

        // Transfer total prize from sponsor to match vault
        let transfer_ix = system_program::Transfer {
            from: ctx.accounts.sponsor.to_account_info(),
            to: ctx.accounts.match_vault.to_account_info(),
        };
        let cpi_ctx = CpiContext::new(
            ctx.accounts.system_program.to_account_info(),
            transfer_ix,
        );
        system_program::transfer(cpi_ctx, total_prize)?;

        emit!(MatchCreated {
            match_id,
            sponsor: ctx.accounts.sponsor.key(),
            total_prize,
            winner_prize,
            loot_box_pool,
            expected_participants,
            start_time,
            match_metadata_uri: ctx.accounts.match_config.match_metadata_uri.clone(),
        });

        Ok(())
    }

    pub fn settle_match(
        ctx: Context<SettleMatch>,
        match_id: [u8; 32],
        winner: Pubkey,
        participants: Vec<Pubkey>,
    ) -> Result<()> {
        require!(
            ctx.accounts.authority.key() == ctx.accounts.config.trusted_authority,
            MatchError::Unauthorized
        );

        let match_config = &mut ctx.accounts.match_config;
        require!(match_config.initialized, MatchError::MatchNotFound);
        require!(!match_config.settled, MatchError::AlreadySettled);
        require!(!match_config.cancelled, MatchError::AlreadyCancelled);
        require!(
            (participants.len() as u64) <= MAX_PARTICIPANTS,
            MatchError::TooManyParticipants
        );

        // Verify no duplicate participants
        let mut sorted = participants.clone();
        sorted.sort();
        sorted.dedup();
        require!(sorted.len() == participants.len(), MatchError::DuplicateParticipant);

        match_config.settled = true;
        match_config.settled_at = Clock::get()?.unix_timestamp;

        // Pay winner 80%
        let winner_payout = match_config.winner_prize;
        if winner_payout > 0 {
            let transfer_ix = system_program::Transfer {
                from: ctx.accounts.match_vault.to_account_info(),
                to: ctx.accounts.winner_account.to_account_info(),
            };
            let seeds: &[&[u8]] = &[b"match_vault", &match_id, &[ctx.bumps.match_vault]];
            let cpi_ctx = CpiContext::new_with_signer(
                ctx.accounts.system_program.to_account_info(),
                transfer_ix,
                &[seeds],
            );
            system_program::transfer(cpi_ctx, winner_payout)?;
        }

        // Remaining 20% stays in vault for loot box settlement (or drain)
        emit!(MatchSettled {
            match_id,
            winner,
            winner_prize: winner_payout,
            participant_count: participants.len() as u64,
        });

        Ok(())
    }

    pub fn cancel_sponsored_match(ctx: Context<CancelMatch>, match_id: [u8; 32]) -> Result<()> {
        let match_config = &mut ctx.accounts.match_config;
        require!(match_config.initialized, MatchError::MatchNotFound);
        require!(!match_config.settled, MatchError::AlreadySettled);
        require!(!match_config.cancelled, MatchError::AlreadyCancelled);

        let clock = Clock::get()?;
        require!(
            clock.unix_timestamp < match_config.start_time,
            MatchError::MatchAlreadyStarted
        );

        require!(
            ctx.accounts.sponsor.key() == match_config.sponsor,
            MatchError::SponsorMismatch
        );

        match_config.cancelled = true;

        // Refund winner prize to sponsor
        let refund = match_config.winner_prize;
        if refund > 0 {
            let transfer_ix = system_program::Transfer {
                from: ctx.accounts.match_vault.to_account_info(),
                to: ctx.accounts.sponsor.to_account_info(),
            };
            let seeds: &[&[u8]] = &[b"match_vault", &match_id, &[ctx.bumps.match_vault]];
            let cpi_ctx = CpiContext::new_with_signer(
                ctx.accounts.system_program.to_account_info(),
                transfer_ix,
                &[seeds],
            );
            system_program::transfer(cpi_ctx, refund)?;
        }

        emit!(MatchCancelled {
            match_id,
            sponsor: ctx.accounts.sponsor.key(),
            amount_returned: refund,
        });

        Ok(())
    }

    pub fn withdraw_to_treasury(ctx: Context<WithdrawToTreasury>, match_id: [u8; 32]) -> Result<()> {
        require!(
            ctx.accounts.authority.key() == ctx.accounts.config.authority,
            MatchError::Unauthorized
        );

        let vault = &ctx.accounts.match_vault;
        let balance = vault.to_account_info().lamports();
        if balance > 0 {
            let transfer_ix = system_program::Transfer {
                from: ctx.accounts.match_vault.to_account_info(),
                to: ctx.accounts.treasury.to_account_info(),
            };
            let seeds: &[&[u8]] = &[b"match_vault", &match_id, &[ctx.bumps.match_vault]];
            let cpi_ctx = CpiContext::new_with_signer(
                ctx.accounts.system_program.to_account_info(),
                transfer_ix,
                &[seeds],
            );
            system_program::transfer(cpi_ctx, balance)?;
        }

        Ok(())
    }
}

#[account]
#[derive(InitSpace)]
pub struct Config {
    pub authority: Pubkey,
    pub trusted_authority: Pubkey,
    pub loot_box: Pubkey,
    pub xp_token: Pubkey,
    pub next_token_id: u64,
}

#[account]
#[derive(InitSpace)]
pub struct MatchConfig {
    pub match_id: [u8; 32],
    pub sponsor: Pubkey,
    pub winner_prize: u64,
    pub loot_box_pool: u64,
    pub expected_participants: u32,
    pub created_at: i64,
    pub start_time: i64,
    pub settled_at: i64,
    pub initialized: bool,
    pub settled: bool,
    pub cancelled: bool,
    #[max_len(256)]
    pub winner_token_uri: String,
    #[max_len(256)]
    pub participation_token_uri: String,
    #[max_len(256)]
    pub match_metadata_uri: String,
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(init, payer = payer, space = 8 + Config::INIT_SPACE)]
    pub config: Account<'info, Config>,
    /// CHECK: Loot box program ID
    pub loot_box_program: UncheckedAccount<'info>,
    /// CHECK: XP token program ID
    pub xp_token_program: UncheckedAccount<'info>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SetTrustedAuthority<'info> {
    #[account(mut)]
    pub config: Account<'info, Config>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct SetLootBox<'info> {
    #[account(mut)]
    pub config: Account<'info, Config>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct SetXpToken<'info> {
    #[account(mut)]
    pub config: Account<'info, Config>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(match_id: [u8; 32])]
pub struct CreateSponsoredMatch<'info> {
    #[account(
        init,
        payer = sponsor,
        space = 8 + MatchConfig::INIT_SPACE,
        seeds = [b"match", match_id.as_ref()],
        bump
    )]
    pub match_config: Account<'info, MatchConfig>,
    #[account(
        mut,
        seeds = [b"match_vault", match_id.as_ref()],
        bump
    )]
    /// CHECK: PDA vault for match prize
    pub match_vault: UncheckedAccount<'info>,
    #[account(mut)]
    pub sponsor: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(match_id: [u8; 32], winner: Pubkey, participants: Vec<Pubkey>)]
pub struct SettleMatch<'info> {
    pub config: Account<'info, Config>,
    #[account(
        mut,
        seeds = [b"match", match_id.as_ref()],
        bump
    )]
    pub match_config: Account<'info, MatchConfig>,
    #[account(
        mut,
        seeds = [b"match_vault", match_id.as_ref()],
        bump
    )]
    /// CHECK: PDA vault
    pub match_vault: UncheckedAccount<'info>,
    #[account(mut)]
    /// CHECK: Winner receiving prize
    pub winner_account: UncheckedAccount<'info>,
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(match_id: [u8; 32])]
pub struct CancelMatch<'info> {
    #[account(
        mut,
        seeds = [b"match", match_id.as_ref()],
        bump
    )]
    pub match_config: Account<'info, MatchConfig>,
    #[account(
        mut,
        seeds = [b"match_vault", match_id.as_ref()],
        bump
    )]
    /// CHECK: PDA vault
    pub match_vault: UncheckedAccount<'info>,
    #[account(mut)]
    pub sponsor: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(match_id: [u8; 32])]
pub struct WithdrawToTreasury<'info> {
    pub config: Account<'info, Config>,
    #[account(
        mut,
        seeds = [b"match_vault", match_id.as_ref()],
        bump
    )]
    /// CHECK: PDA vault
    pub match_vault: UncheckedAccount<'info>,
    #[account(mut)]
    /// CHECK: Treasury destination
    pub treasury: UncheckedAccount<'info>,
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[event]
pub struct MatchCreated {
    pub match_id: [u8; 32],
    pub sponsor: Pubkey,
    pub total_prize: u64,
    pub winner_prize: u64,
    pub loot_box_pool: u64,
    pub expected_participants: u32,
    pub start_time: i64,
    pub match_metadata_uri: String,
}

#[event]
pub struct MatchSettled {
    pub match_id: [u8; 32],
    pub winner: Pubkey,
    pub winner_prize: u64,
    pub participant_count: u64,
}

#[event]
pub struct MatchCancelled {
    pub match_id: [u8; 32],
    pub sponsor: Pubkey,
    pub amount_returned: u64,
}

#[error_code]
pub enum MatchError {
    #[msg("Not authorized")]
    Unauthorized,
    #[msg("Match already exists")]
    MatchAlreadyExists,
    #[msg("Match not found")]
    MatchNotFound,
    #[msg("Match already settled")]
    AlreadySettled,
    #[msg("Match already cancelled")]
    AlreadyCancelled,
    #[msg("Prize must be positive")]
    PrizeMustBePositive,
    #[msg("Invalid winner")]
    InvalidWinner,
    #[msg("Too many participants (max 64)")]
    TooManyParticipants,
    #[msg("Duplicate participant")]
    DuplicateParticipant,
    #[msg("Sponsor mismatch")]
    SponsorMismatch,
    #[msg("Share calculation mismatch")]
    ShareMismatch,
    #[msg("Match already started")]
    MatchAlreadyStarted,
}
