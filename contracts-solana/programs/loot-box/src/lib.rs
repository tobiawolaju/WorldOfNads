use anchor_lang::prelude::*;
use anchor_lang::system_program;

declare_id!("WONsLootBox11111111111111111111111111111111");

pub const GAS_PER_STEAL: u64 = 1_000_000; // 0.001 SOL in lamports
pub const STREAM_BATCH_LIMIT: u64 = 50;

#[program]
pub mod loot_box {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>, authority: Pubkey) -> Result<()> {
        let config = &mut ctx.accounts.config;
        config.authority = authority;
        config.match_engine = ctx.accounts.match_engine.key();
        config.trusted_caller = authority;
        Ok(())
    }

    pub fn set_match_engine(ctx: Context<SetMatchEngine>, match_engine: Pubkey) -> Result<()> {
        require!(
            ctx.accounts.authority.key() == ctx.accounts.config.authority,
            LootError::Unauthorized
        );
        ctx.accounts.config.match_engine = match_engine;
        Ok(())
    }

    pub fn set_trusted_caller(ctx: Context<SetTrustedCaller>, caller: Pubkey) -> Result<()> {
        require!(
            ctx.accounts.authority.key() == ctx.accounts.config.authority,
            LootError::Unauthorized
        );
        ctx.accounts.config.trusted_caller = caller;
        Ok(())
    }

    pub fn fund_pool(ctx: Context<FundPool>, match_id: [u8; 32], amount: u64) -> Result<()> {
        require!(
            ctx.accounts.signer.key() == ctx.accounts.config.match_engine
                || ctx.accounts.signer.key() == ctx.accounts.config.trusted_caller,
            LootError::NotAuthorized
        );
        require!(amount > 0, LootError::ZeroAmount);

        let pool = &mut ctx.accounts.pool;
        pool.remaining_value = pool.remaining_value.checked_add(amount).unwrap();

        emit!(PoolFunded {
            match_id,
            amount,
            pool_remaining: pool.remaining_value,
        });

        Ok(())
    }

    pub fn stream_mon(
        ctx: Context<StreamMon>,
        match_id: [u8; 32],
        amount: u64,
    ) -> Result<()> {
        require!(
            ctx.accounts.signer.key() == ctx.accounts.config.trusted_caller,
            LootError::NotTrustedCaller
        );
        require!(
            ctx.accounts.pool.remaining_value >= amount,
            LootError::PoolDepleted
        );

        let pool = &mut ctx.accounts.pool;
        pool.remaining_value = pool.remaining_value.checked_sub(amount).unwrap();

        let transfer_ix = system_program::Transfer {
            from: ctx.accounts.pool_vault.to_account_info(),
            to: ctx.accounts.player.to_account_info(),
        };
        let seeds: &[&[u8]] = &[b"pool_vault", &match_id, &[ctx.bumps.pool_vault]];
        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.system_program.to_account_info(),
            transfer_ix,
            &[seeds],
        );
        system_program::transfer(cpi_ctx, amount)?;

        emit!(MonStreamed {
            match_id,
            player: ctx.accounts.player.key(),
            amount,
            pool_remaining: pool.remaining_value,
        });

        Ok(())
    }

    pub fn batch_stream(
        ctx: Context<BatchStream>,
        match_id: [u8; 32],
        amounts: Vec<u64>,
    ) -> Result<()> {
        require!(
            ctx.accounts.signer.key() == ctx.accounts.config.trusted_caller,
            LootError::NotTrustedCaller
        );
        require!(
            (amounts.len() as u64) <= STREAM_BATCH_LIMIT,
            LootError::BatchLimitExceeded
        );

        let pool = &mut ctx.accounts.pool;
        let total: u64 = amounts.iter().sum();
        require!(pool.remaining_value >= total, LootError::PoolDepleted);

        pool.remaining_value = pool.remaining_value.checked_sub(total).unwrap();

        let transfer_ix = system_program::Transfer {
            from: ctx.accounts.pool_vault.to_account_info(),
            to: ctx.accounts.player.to_account_info(),
        };
        let seeds: &[&[u8]] = &[b"pool_vault", &match_id, &[ctx.bumps.pool_vault]];
        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.system_program.to_account_info(),
            transfer_ix,
            &[seeds],
        );
        system_program::transfer(cpi_ctx, total)?;

        emit!(MonStreamed {
            match_id,
            player: ctx.accounts.player.key(),
            amount: total,
            pool_remaining: pool.remaining_value,
        });

        Ok(())
    }

    pub fn steal(ctx: Context<Steal>, match_id: [u8; 32]) -> Result<()> {
        require!(
            ctx.accounts.signer.key() == ctx.accounts.config.trusted_caller,
            LootError::NotTrustedCaller
        );

        let pool = &mut ctx.accounts.pool;
        require!(pool.remaining_value >= GAS_PER_STEAL, LootError::PoolDepleted);

        pool.remaining_value = pool.remaining_value.checked_sub(GAS_PER_STEAL).unwrap();

        let burn_ix = system_program::Transfer {
            from: ctx.accounts.pool_vault.to_account_info(),
            to: ctx.accounts.burn_address.to_account_info(),
        };
        let seeds: &[&[u8]] = &[b"pool_vault", &match_id, &[ctx.bumps.pool_vault]];
        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.system_program.to_account_info(),
            burn_ix,
            &[seeds],
        );
        system_program::transfer(cpi_ctx, GAS_PER_STEAL)?;

        emit!(LootBoxStolen {
            match_id,
            new_holder: ctx.accounts.new_holder.key(),
            pool_remaining: pool.remaining_value,
        });

        Ok(())
    }

    pub fn settle(ctx: Context<Settle>, match_id: [u8; 32]) -> Result<()> {
        require!(
            ctx.accounts.signer.key() == ctx.accounts.config.match_engine,
            LootError::NotMatchEngine
        );

        let pool = &mut ctx.accounts.pool;
        require!(!pool.settled, LootError::AlreadySettled);

        let payout = pool.remaining_value;
        pool.remaining_value = 0;
        pool.settled = true;

        if payout > 0 {
            let transfer_ix = system_program::Transfer {
                from: ctx.accounts.pool_vault.to_account_info(),
                to: ctx.accounts.final_holder.to_account_info(),
            };
            let seeds: &[&[u8]] = &[b"pool_vault", &match_id, &[ctx.bumps.pool_vault]];
            let cpi_ctx = CpiContext::new_with_signer(
                ctx.accounts.system_program.to_account_info(),
                transfer_ix,
                &[seeds],
            );
            system_program::transfer(cpi_ctx, payout)?;
        }

        emit!(PoolSettled {
            match_id,
            final_holder: ctx.accounts.final_holder.key(),
            payout,
        });

        Ok(())
    }

    pub fn drain_pool(ctx: Context<DrainPool>, match_id: [u8; 32]) -> Result<()> {
        require!(
            ctx.accounts.signer.key() == ctx.accounts.config.match_engine,
            LootError::NotMatchEngine
        );

        let pool = &mut ctx.accounts.pool;
        let amount = pool.remaining_value;
        pool.remaining_value = 0;

        if amount > 0 {
            let transfer_ix = system_program::Transfer {
                from: ctx.accounts.pool_vault.to_account_info(),
                to: ctx.accounts.to.to_account_info(),
            };
            let seeds: &[&[u8]] = &[b"pool_vault", &match_id, &[ctx.bumps.pool_vault]];
            let cpi_ctx = CpiContext::new_with_signer(
                ctx.accounts.system_program.to_account_info(),
                transfer_ix,
                &[seeds],
            );
            system_program::transfer(cpi_ctx, amount)?;
        }

        emit!(PoolDrained {
            match_id,
            to: ctx.accounts.to.key(),
            amount,
        });

        Ok(())
    }

    pub fn get_pool_value(ctx: Context<GetPoolValue>) -> Result<u64> {
        Ok(ctx.accounts.pool.remaining_value)
    }
}

#[account]
#[derive(InitSpace)]
pub struct Config {
    pub authority: Pubkey,
    pub match_engine: Pubkey,
    pub trusted_caller: Pubkey,
}

#[account]
#[derive(InitSpace)]
pub struct Pool {
    pub remaining_value: u64,
    pub final_holder: Pubkey,
    pub settled: bool,
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(init, payer = payer, space = 8 + Config::INIT_SPACE)]
    pub config: Account<'info, Config>,
    /// CHECK: Match engine program ID
    pub match_engine: UncheckedAccount<'info>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SetMatchEngine<'info> {
    #[account(mut)]
    pub config: Account<'info, Config>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct SetTrustedCaller<'info> {
    #[account(mut)]
    pub config: Account<'info, Config>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(match_id: [u8; 32], amount: u64)]
pub struct FundPool<'info> {
    pub config: Account<'info, Config>,
    #[account(
        init_if_needed,
        payer = signer,
        space = 8 + Pool::INIT_SPACE,
        seeds = [b"pool", match_id.as_ref()],
        bump
    )]
    pub pool: Account<'info, Pool>,
    #[account(
        mut,
        seeds = [b"pool_vault", match_id.as_ref()],
        bump
    )]
    /// CHECK: PDA vault holding pool funds
    pub pool_vault: UncheckedAccount<'info>,
    #[account(mut)]
    pub signer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(match_id: [u8; 32], amount: u64)]
pub struct StreamMon<'info> {
    pub config: Account<'info, Config>,
    #[account(
        mut,
        seeds = [b"pool", match_id.as_ref()],
        bump
    )]
    pub pool: Account<'info, Pool>,
    #[account(
        mut,
        seeds = [b"pool_vault", match_id.as_ref()],
        bump
    )]
    /// CHECK: PDA vault
    pub pool_vault: UncheckedAccount<'info>,
    #[account(mut)]
    /// CHECK: Player receiving stream
    pub player: UncheckedAccount<'info>,
    pub signer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(match_id: [u8; 32], amounts: Vec<u64>)]
pub struct BatchStream<'info> {
    pub config: Account<'info, Config>,
    #[account(
        mut,
        seeds = [b"pool", match_id.as_ref()],
        bump
    )]
    pub pool: Account<'info, Pool>,
    #[account(
        mut,
        seeds = [b"pool_vault", match_id.as_ref()],
        bump
    )]
    /// CHECK: PDA vault
    pub pool_vault: UncheckedAccount<'info>,
    #[account(mut)]
    /// CHECK: Player receiving stream
    pub player: UncheckedAccount<'info>,
    pub signer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(match_id: [u8; 32])]
pub struct Steal<'info> {
    pub config: Account<'info, Config>,
    #[account(
        mut,
        seeds = [b"pool", match_id.as_ref()],
        bump
    )]
    pub pool: Account<'info, Pool>,
    #[account(
        mut,
        seeds = [b"pool_vault", match_id.as_ref()],
        bump
    )]
    /// CHECK: PDA vault
    pub pool_vault: UncheckedAccount<'info>,
    /// CHECK: New holder of the loot box
    pub new_holder: UncheckedAccount<'info>,
    /// CHECK: SOL burn address
    #[account(mut)]
    pub burn_address: UncheckedAccount<'info>,
    pub signer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(match_id: [u8; 32])]
pub struct Settle<'info> {
    pub config: Account<'info, Config>,
    #[account(
        mut,
        seeds = [b"pool", match_id.as_ref()],
        bump
    )]
    pub pool: Account<'info, Pool>,
    #[account(
        mut,
        seeds = [b"pool_vault", match_id.as_ref()],
        bump
    )]
    /// CHECK: PDA vault
    pub pool_vault: UncheckedAccount<'info>,
    #[account(mut)]
    /// CHECK: Final holder receiving remaining pool
    pub final_holder: UncheckedAccount<'info>,
    pub signer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(match_id: [u8; 32])]
pub struct DrainPool<'info> {
    pub config: Account<'info, Config>,
    #[account(
        mut,
        seeds = [b"pool", match_id.as_ref()],
        bump
    )]
    pub pool: Account<'info, Pool>,
    #[account(
        mut,
        seeds = [b"pool_vault", match_id.as_ref()],
        bump
    )]
    /// CHECK: PDA vault
    pub pool_vault: UncheckedAccount<'info>,
    #[account(mut)]
    /// CHECK: Address receiving drained funds
    pub to: UncheckedAccount<'info>,
    pub signer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct GetPoolValue<'info> {
    #[account(
        seeds = [b"pool", match_id.as_ref()],
        bump
    )]
    pub pool: Account<'info, Pool>,
    pub match_id: [u8; 32],
}

#[event]
pub struct PoolFunded {
    pub match_id: [u8; 32],
    pub amount: u64,
    pub pool_remaining: u64,
}

#[event]
pub struct MonStreamed {
    pub match_id: [u8; 32],
    pub player: Pubkey,
    pub amount: u64,
    pub pool_remaining: u64,
}

#[event]
pub struct LootBoxStolen {
    pub match_id: [u8; 32],
    pub new_holder: Pubkey,
    pub pool_remaining: u64,
}

#[event]
pub struct PoolSettled {
    pub match_id: [u8; 32],
    pub final_holder: Pubkey,
    pub payout: u64,
}

#[event]
pub struct PoolDrained {
    pub match_id: [u8; 32],
    pub to: Pubkey,
    pub amount: u64,
}

#[error_code]
pub enum LootError {
    #[msg("Not authorized")]
    Unauthorized,
    #[msg("Caller is not the match engine")]
    NotMatchEngine,
    #[msg("Caller is not the trusted caller")]
    NotTrustedCaller,
    #[msg("Not authorized for this action")]
    NotAuthorized,
    #[msg("Pool depleted")]
    PoolDepleted,
    #[msg("Pool already settled")]
    AlreadySettled,
    #[msg("Amount must be greater than zero")]
    ZeroAmount,
    #[msg("Batch limit exceeded (max 50)")]
    BatchLimitExceeded,
}
