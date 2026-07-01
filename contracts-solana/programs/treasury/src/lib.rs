use anchor_lang::prelude::*;
use anchor_lang::system_program;

declare_id!("WONsTreasury111111111111111111111111111111");

pub const DAILY_WITHDRAWAL_LIMIT: u64 = 50_000_000_000; // 50 SOL in lamports
pub const WITHDRAWAL_COOLDOWN: i64 = 86400; // 1 day in seconds

#[program]
pub mod treasury {
    use super::*;

    /// Initialize the treasury with an authority.
    /// On Solana, this holds SOL for the protocol.
    /// On the frontend side, players can deposit SOL (Solana) or MON (Monad)
    /// and the system converts everything to $WON (internal unit) for gameplay.
    pub fn initialize(ctx: Context<Initialize>, authority: Pubkey) -> Result<()> {
        let config = &mut ctx.accounts.config;
        config.authority = authority;
        config.paused = false;
        config.total_deposited_sol = 0;
        config.total_withdrawn_sol = 0;
        Ok(())
    }

    /// Deposit SOL into the treasury.
    /// The frontend converts this deposit to $WON in the player's inventory.
    pub fn deposit(ctx: Context<Deposit>, amount: u64) -> Result<()> {
        require!(!ctx.accounts.config.paused, TreasuryError::Paused);
        require!(amount > 0, TreasuryError::ZeroAmount);

        let player = &mut ctx.accounts.player_balance;
        player.owner = ctx.accounts.payer.key();
        player.balance_won = player.balance_won.checked_add(amount).unwrap();
        player.last_deposit_time = Clock::get()?.unix_timestamp;

        ctx.accounts.config.total_deposited_sol = ctx
            .accounts
            .config
            .total_deposited_sol
            .checked_add(amount)
            .unwrap();

        // Transfer SOL from player to treasury vault
        let transfer_ix = system_program::Transfer {
            from: ctx.accounts.payer.to_account_info(),
            to: ctx.accounts.treasury_vault.to_account_info(),
        };
        let cpi_ctx = CpiContext::new(
            ctx.accounts.system_program.to_account_info(),
            transfer_ix,
        );
        system_program::transfer(cpi_ctx, amount)?;

        emit!(Deposited {
            user: ctx.accounts.payer.key(),
            amount,
            won_balance: player.balance_won,
        });

        Ok(())
    }

    /// Withdraw SOL from the treasury (up to player's $WON balance).
    /// Enforces daily limit and cooldown.
    pub fn withdraw(ctx: Context<Withdraw>, amount: u64) -> Result<()> {
        require!(!ctx.accounts.config.paused, TreasuryError::Paused);
        require!(amount > 0, TreasuryError::ZeroAmount);

        let player = &mut ctx.accounts.player_balance;
        require!(
            player.balance_won >= amount,
            TreasuryError::InsufficientBalance
        );

        let clock = Clock::get()?;

        // Enforce cooldown
        require!(
            clock.unix_timestamp >= player.last_withdrawal_time + WITHDRAWAL_COOLDOWN,
            TreasuryError::CooldownActive
        );

        // Enforce daily limit
        require!(
            player.withdrawn_today.checked_add(amount).unwrap() <= DAILY_WITHDRAWAL_LIMIT,
            TreasuryError::ExceedsDailyLimit
        );

        // Reset daily counter if a new day
        if clock.unix_timestamp >= player.last_withdrawal_day + WITHDRAWAL_COOLDOWN {
            player.withdrawn_today = 0;
            player.last_withdrawal_day = clock.unix_timestamp;
        }

        player.balance_won = player.balance_won.checked_sub(amount).unwrap();
        player.withdrawn_today = player.withdrawn_today.checked_add(amount).unwrap();
        player.last_withdrawal_time = clock.unix_timestamp;

        ctx.accounts.config.total_withdrawn_sol = ctx
            .accounts
            .config
            .total_withdrawn_sol
            .checked_add(amount)
            .unwrap();

        // Transfer SOL from treasury vault to player
        let seeds: &[&[u8]] = &[b"treasury_vault", &[ctx.bumps.treasury_vault]];
        let transfer_ix = system_program::Transfer {
            from: ctx.accounts.treasury_vault.to_account_info(),
            to: ctx.accounts.payer.to_account_info(),
        };
        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.system_program.to_account_info(),
            transfer_ix,
            &[seeds],
        );
        system_program::transfer(cpi_ctx, amount)?;

        emit!(Withdrawn {
            user: ctx.accounts.payer.key(),
            amount,
            won_balance: player.balance_won,
        });

        Ok(())
    }

    /// Admin: credit $WON to a player (for match rewards, XP conversion, etc.)
    pub fn credit_won(ctx: Context<CreditWon>, user: Pubkey, amount: u64) -> Result<()> {
        require!(
            ctx.accounts.authority.key() == ctx.accounts.config.authority,
            TreasuryError::Unauthorized
        );

        let player = &mut ctx.accounts.player_balance;
        player.owner = user;
        player.balance_won = player.balance_won.checked_add(amount).unwrap();

        emit!(WonCredited {
            user,
            amount,
            won_balance: player.balance_won,
        });

        Ok(())
    }

    /// Admin: spend $WON from a player (for skin purchases, match fees, etc.)
    pub fn spend_won(ctx: Context<SpendWon>, user: Pubkey, amount: u64) -> Result<()> {
        require!(
            ctx.accounts.authority.key() == ctx.accounts.config.authority,
            TreasuryError::Unauthorized
        );

        let player = &mut ctx.accounts.player_balance;
        require!(
            player.balance_won >= amount,
            TreasuryError::InsufficientBalance
        );

        player.balance_won = player.balance_won.checked_sub(amount).unwrap();

        emit!(WonSpent {
            user,
            amount,
            won_balance: player.balance_won,
        });

        Ok(())
    }

    /// Admin: emergency pause
    pub fn set_paused(ctx: Context<SetPaused>, paused: bool) -> Result<()> {
        require!(
            ctx.accounts.authority.key() == ctx.accounts.config.authority,
            TreasuryError::Unauthorized
        );
        ctx.accounts.config.paused = paused;
        emit!(Paused { paused });
        Ok(())
    }

    /// View: get player $WON balance
    pub fn get_won_balance(ctx: Context<GetWonBalance>) -> Result<u64> {
        Ok(ctx.accounts.player_balance.balance_won)
    }

    /// Cross-chain: credit $WON from Monad deposit
    /// Called by authority when a MON deposit is detected on the Monad bridge
    pub fn credit_from_monad(
        ctx: Context<CreditFromMonad>,
        user: Pubkey,
        mon_amount: u64,
        won_amount: u64,
        tx_hash: [u8; 32],
    ) -> Result<()> {
        require!(
            ctx.accounts.authority.key() == ctx.accounts.config.authority,
            TreasuryError::Unauthorized
        );

        let cross = &mut ctx.accounts.cross_chain_record;
        cross.monad_tx_hash = tx_hash;
        cross.user = user;
        cross.mon_amount = mon_amount;
        cross.won_amount = won_amount;
        cross.processed_at = Clock::get()?.unix_timestamp;

        let player = &mut ctx.accounts.player_balance;
        player.owner = user;
        player.balance_won = player.balance_won.checked_add(won_amount).unwrap();

        emit!(CrossChainDeposit {
            user,
            source_chain: "monad".to_string(),
            source_amount: mon_amount,
            won_credited: won_amount,
            tx_hash,
        });

        Ok(())
    }
}

#[account]
#[derive(InitSpace)]
pub struct Config {
    pub authority: Pubkey,
    pub paused: bool,
    pub total_deposited_sol: u64,
    pub total_withdrawn_sol: u64,
}

#[account]
#[derive(InitSpace)]
pub struct PlayerBalance {
    pub owner: Pubkey,
    pub balance_won: u64,
    pub last_deposit_time: i64,
    pub last_withdrawal_time: i64,
    pub last_withdrawal_day: i64,
    pub withdrawn_today: u64,
}

#[account]
#[derive(InitSpace)]
pub struct CrossChainRecord {
    pub monad_tx_hash: [u8; 32],
    pub user: Pubkey,
    pub mon_amount: u64,
    pub won_amount: u64,
    pub processed_at: i64,
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(init, payer = payer, space = 8 + Config::INIT_SPACE)]
    pub config: Account<'info, Config>,
    #[account(
        mut,
        seeds = [b"treasury_vault"],
        bump
    )]
    /// CHECK: Treasury vault PDA
    pub treasury_vault: UncheckedAccount<'info>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(mut)]
    pub config: Account<'info, Config>,
    #[account(
        init_if_needed,
        payer = payer,
        space = 8 + PlayerBalance::INIT_SPACE,
        seeds = [b"player_balance", payer.key().as_ref()],
        bump
    )]
    pub player_balance: Account<'info, PlayerBalance>,
    #[account(
        mut,
        seeds = [b"treasury_vault"],
        bump
    )]
    /// CHECK: Treasury vault PDA
    pub treasury_vault: UncheckedAccount<'info>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(mut)]
    pub config: Account<'info, Config>,
    #[account(
        mut,
        seeds = [b"player_balance", payer.key().as_ref()],
        bump
    )]
    pub player_balance: Account<'info, PlayerBalance>,
    #[account(
        mut,
        seeds = [b"treasury_vault"],
        bump
    )]
    /// CHECK: Treasury vault PDA
    pub treasury_vault: UncheckedAccount<'info>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct CreditWon<'info> {
    #[account(mut)]
    pub config: Account<'info, Config>,
    #[account(
        init_if_needed,
        payer = authority,
        space = 8 + PlayerBalance::INIT_SPACE,
        seeds = [b"player_balance", user.key().as_ref()],
        bump
    )]
    pub player_balance: Account<'info, PlayerBalance>,
    /// CHECK: User receiving credit
    pub user: UncheckedAccount<'info>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SpendWon<'info> {
    #[account(mut)]
    pub config: Account<'info, Config>,
    #[account(
        mut,
        seeds = [b"player_balance", user.key().as_ref()],
        bump
    )]
    pub player_balance: Account<'info, PlayerBalance>,
    /// CHECK: User spending
    pub user: UncheckedAccount<'info>,
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SetPaused<'info> {
    #[account(mut)]
    pub config: Account<'info, Config>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct GetWonBalance<'info> {
    #[account(
        seeds = [b"player_balance", owner.key().as_ref()],
        bump
    )]
    pub player_balance: Account<'info, PlayerBalance>,
    pub owner: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(user: Pubkey, mon_amount: u64, won_amount: u64, tx_hash: [u8; 32])]
pub struct CreditFromMonad<'info> {
    #[account(mut)]
    pub config: Account<'info, Config>,
    #[account(
        init_if_needed,
        payer = authority,
        space = 8 + PlayerBalance::INIT_SPACE,
        seeds = [b"player_balance", user.as_ref()],
        bump
    )]
    pub player_balance: Account<'info, PlayerBalance>,
    #[account(
        init,
        payer = authority,
        space = 8 + CrossChainRecord::INIT_SPACE,
        seeds = [b"cross_chain", tx_hash.as_ref()],
        bump
    )]
    pub cross_chain_record: Account<'info, CrossChainRecord>,
    /// CHECK: User receiving credit
    pub user: UncheckedAccount<'info>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[event]
pub struct Deposited {
    pub user: Pubkey,
    pub amount: u64,
    pub won_balance: u64,
}

#[event]
pub struct Withdrawn {
    pub user: Pubkey,
    pub amount: u64,
    pub won_balance: u64,
}

#[event]
pub struct WonCredited {
    pub user: Pubkey,
    pub amount: u64,
    pub won_balance: u64,
}

#[event]
pub struct WonSpent {
    pub user: Pubkey,
    pub amount: u64,
    pub won_balance: u64,
}

#[event]
pub struct Paused {
    pub paused: bool,
}

#[event]
pub struct CrossChainDeposit {
    pub user: Pubkey,
    pub source_chain: String,
    pub source_amount: u64,
    pub won_credited: u64,
    pub tx_hash: [u8; 32],
}

#[error_code]
pub enum TreasuryError {
    #[msg("Not authorized")]
    Unauthorized,
    #[msg("Insufficient balance")]
    InsufficientBalance,
    #[msg("Withdrawal cooldown active (1 day)")]
    CooldownActive,
    #[msg("Exceeds daily withdrawal limit")]
    ExceedsDailyLimit,
    #[msg("Treasury is paused")]
    Paused,
    #[msg("Amount must be greater than zero")]
    ZeroAmount,
}
