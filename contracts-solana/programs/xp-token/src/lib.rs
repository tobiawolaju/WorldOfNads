use anchor_lang::prelude::*;
use anchor_lang::system_program;

declare_id!("WONsXP111111111111111111111111111111111111");

#[program]
pub mod xp_token {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>, authority: Pubkey) -> Result<()> {
        let config = &mut ctx.accounts.config;
        config.authority = authority;
        config.minter = authority;
        config.total_emitted = 0;
        Ok(())
    }

    pub fn set_minter(ctx: Context<SetMinter>, minter: Pubkey, active: bool) -> Result<()> {
        require!(
            ctx.accounts.authority.key() == ctx.accounts.config.authority,
            XpError::Unauthorized
        );

        if active {
            ctx.accounts.config.minter = minter;
        } else {
            ctx.accounts.config.minter = Pubkey::default();
        }
        Ok(())
    }

    pub fn mint_xp(ctx: Context<MintXp>, to: Pubkey, amount: u64) -> Result<()> {
        require!(
            ctx.accounts.signer.key() == ctx.accounts.config.minter,
            XpError::NotMinter
        );
        require!(amount > 0, XpError::ZeroAmount);

        let player_xp = &mut ctx.accounts.player_xp;
        player_xp.owner = to;
        player_xp.balance = player_xp.balance.checked_add(amount).unwrap();
        player_xp.last_updated = Clock::get()?.unix_timestamp;

        ctx.accounts.config.total_emitted = ctx
            .accounts
            .config
            .total_emitted
            .checked_add(amount as u64)
            .unwrap();

        emit!(XpMinted {
            to,
            amount,
            total: ctx.accounts.config.total_emitted,
        });

        Ok(())
    }

    pub fn balance_of(ctx: Context<BalanceOf>) -> Result<u64> {
        Ok(ctx.accounts.player_xp.balance)
    }
}

#[account]
#[derive(InitSpace)]
pub struct Config {
    pub authority: Pubkey,
    pub minter: Pubkey,
    pub total_emitted: u64,
}

#[account]
#[derive(InitSpace)]
pub struct PlayerXp {
    pub owner: Pubkey,
    pub balance: u64,
    pub last_updated: i64,
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(init, payer = payer, space = 8 + Config::INIT_SPACE)]
    pub config: Account<'info, Config>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SetMinter<'info> {
    #[account(mut)]
    pub config: Account<'info, Config>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct MintXp<'info> {
    #[account(mut)]
    pub config: Account<'info, Config>,
    #[account(
        init_if_needed,
        payer = signer,
        space = 8 + PlayerXp::INIT_SPACE,
        seeds = [b"player_xp", to.as_ref()],
        bump
    )]
    pub player_xp: Account<'info, PlayerXp>,
    #[account(mut)]
    pub signer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct BalanceOf<'info> {
    #[account(
        seeds = [b"player_xp", owner.key().as_ref()],
        bump
    )]
    pub player_xp: Account<'info, PlayerXp>,
    pub owner: Signer<'info>,
}

#[event]
pub struct XpMinted {
    pub to: Pubkey,
    pub amount: u64,
    pub total: u64,
}

#[error_code]
pub enum XpError {
    #[msg("Not authorized")]
    Unauthorized,
    #[msg("Caller is not the minter")]
    NotMinter,
    #[msg("Amount must be greater than zero")]
    ZeroAmount,
}
