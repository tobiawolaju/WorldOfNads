use anchor_lang::prelude::*;

declare_id!("WONsSkins1111111111111111111111111111111111");

#[program]
pub mod skins {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>, authority: Pubkey) -> Result<()> {
        let config = &mut ctx.accounts.config;
        config.authority = authority;
        config.xp_token = ctx.accounts.xp_program.key();
        config.next_skin_id = 1;
        Ok(())
    }

    pub fn set_xp_token(ctx: Context<SetXpToken>, xp_token: Pubkey) -> Result<()> {
        require!(
            ctx.accounts.authority.key() == ctx.accounts.config.authority,
            SkinError::Unauthorized
        );
        ctx.accounts.config.xp_token = xp_token;
        Ok(())
    }

    pub fn create_skin(
        ctx: Context<CreateSkin>,
        max_supply: u64,
        mint_price: u64,
        required_xp: u64,
        tier: u8,
        uri: String,
    ) -> Result<()> {
        require!(
            ctx.accounts.authority.key() == ctx.accounts.config.authority,
            SkinError::Unauthorized
        );
        require!(tier <= 3, SkinError::InvalidTier);
        require!(uri.len() <= 256, SkinError::UriTooLong);

        let skin_id = ctx.accounts.config.next_skin_id;
        let skin = &mut ctx.accounts.skin;
        skin.skin_id = skin_id;
        skin.max_supply = max_supply;
        skin.minted = 0;
        skin.mint_price = mint_price;
        skin.required_xp = required_xp;
        skin.tier = tier;
        skin.uri = uri;
        skin.exists = true;

        ctx.accounts.config.next_skin_id = skin_id.checked_add(1).unwrap();

        emit!(SkinCreated {
            skin_id,
            max_supply,
            mint_price,
            required_xp,
            tier,
        });

        Ok(())
    }

    pub fn mint_skin(ctx: Context<MintSkin>, skin_id: u64, amount: u64) -> Result<()> {
        require!(amount > 0, SkinError::ZeroAmount);

        let skin = &mut ctx.accounts.skin;
        require!(skin.exists, SkinError::InvalidSkin);
        require!(
            skin.minted.checked_add(amount).unwrap() <= skin.max_supply,
            SkinError::SupplyExhausted
        );

        let total_price = skin.mint_price.checked_mul(amount).unwrap();
        require!(
            ctx.accounts.payer_lamports() >= total_price,
            SkinError::InsufficientPayment
        );

        require!(
            ctx.accounts.player_xp.balance >= skin.required_xp,
            SkinError::InsufficientXp
        );

        let transfer_ix = anchor_lang::system_program::Transfer {
            from: ctx.accounts.payer.to_account_info(),
            to: ctx.accounts.treasury.to_account_info(),
        };
        let cpi_ctx = CpiContext::new(
            ctx.accounts.system_program.to_account_info(),
            transfer_ix,
        );
        anchor_lang::system_program::transfer(cpi_ctx, total_price)?;

        skin.minted = skin.minted.checked_add(amount).unwrap();

        emit!(SkinMinted {
            skin_id,
            buyer: ctx.accounts.payer.key(),
            amount,
        });

        Ok(())
    }

    pub fn burn_skins(ctx: Context<BurnSkins>, skin_id: u64, amount: u64) -> Result<()> {
        let skin = &ctx.accounts.skin;
        require!(skin.exists, SkinError::InvalidSkin);
        require!(skin.tier == 0, SkinError::BurnNotAllowed);
        require!(amount >= 2, SkinError::InsufficientBurnQuantity);

        let burn_record = &mut ctx.accounts.burn_record;
        burn_record.burner = ctx.accounts.payer.key();
        burn_record.burned_skin_id = skin_id;
        burn_record.burned_amount = burn_record.burned_amount.checked_add(amount).unwrap();

        emit!(SkinBurned {
            skin_id,
            burner: ctx.accounts.payer.key(),
            amount,
        });

        Ok(())
    }

    pub fn mint_rare_from_burn(ctx: Context<MintRareFromBurn>, skin_id: u64, to: Pubkey) -> Result<()> {
        require!(
            ctx.accounts.authority.key() == ctx.accounts.config.authority,
            SkinError::Unauthorized
        );

        let rare_skin = &ctx.accounts.rare_skin;
        require!(rare_skin.exists, SkinError::InvalidSkin);
        require!(rare_skin.tier == 1, SkinError::InvalidTier);

        let burn_record = &mut ctx.accounts.burn_record;
        require!(
            burn_record.burned_amount >= 2,
            SkinError::InsufficientBurnQuantity
        );

        burn_record.burned_amount = burn_record.burned_amount.checked_sub(2).unwrap();
        burn_record.claimed = true;

        emit!(RareMintedFromBurn {
            to,
            skin_id,
            rare_skin_id: rare_skin.skin_id,
        });

        Ok(())
    }
}

#[account]
#[derive(InitSpace)]
pub struct Config {
    pub authority: Pubkey,
    pub xp_token: Pubkey,
    pub next_skin_id: u64,
}

#[account]
#[derive(InitSpace)]
pub struct Skin {
    pub skin_id: u64,
    pub max_supply: u64,
    pub minted: u64,
    pub mint_price: u64,
    pub required_xp: u64,
    pub tier: u8,
    #[max_len(256)]
    pub uri: String,
    pub exists: bool,
}

#[account]
#[derive(InitSpace)]
pub struct BurnRecord {
    pub burner: Pubkey,
    pub burned_skin_id: u64,
    pub burned_amount: u64,
    pub claimed: bool,
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(init, payer = payer, space = 8 + Config::INIT_SPACE)]
    pub config: Account<'info, Config>,
    pub xp_program: Program<'info, crate::xp_token::program::XpToken>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SetXpToken<'info> {
    #[account(mut)]
    pub config: Account<'info, Config>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(skin_id: u64, max_supply: u64, mint_price: u64, required_xp: u64, tier: u8, uri: String)]
pub struct CreateSkin<'info> {
    #[account(mut)]
    pub config: Account<'info, Config>,
    #[account(
        init,
        payer = authority,
        space = 8 + Skin::INIT_SPACE,
        seeds = [b"skin", skin_id.to_le_bytes().as_ref()],
        bump
    )]
    pub skin: Account<'info, Skin>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(skin_id: u64)]
pub struct MintSkin<'info> {
    #[account(
        seeds = [b"skin", skin_id.to_le_bytes().as_ref()],
        bump
    )]
    pub skin: Account<'info, Skin>,
    #[account(mut)]
    pub payer: Signer<'info>,
    /// CHECK: Treasury vault for skin sale proceeds
    #[account(mut)]
    pub treasury: AccountInfo<'info>,
    /// CHECK: XP token program account for balance verification
    pub player_xp: Account<'info, crate::xp_token::PlayerXp>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(skin_id: u64)]
pub struct BurnSkins<'info> {
    #[account(
        seeds = [b"skin", skin_id.to_le_bytes().as_ref()],
        bump
    )]
    pub skin: Account<'info, Skin>,
    #[account(
        init_if_needed,
        payer = payer,
        space = 8 + BurnRecord::INIT_SPACE,
        seeds = [b"burn_record", payer.key().as_ref()],
        bump
    )]
    pub burn_record: Account<'info, BurnRecord>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(skin_id: u64, to: Pubkey)]
pub struct MintRareFromBurn<'info> {
    pub config: Account<'info, Config>,
    #[account(
        seeds = [b"skin", skin_id.to_le_bytes().as_ref()],
        bump
    )]
    pub rare_skin: Account<'info, Skin>,
    #[account(
        mut,
        seeds = [b"burn_record", to.as_ref()],
        bump
    )]
    pub burn_record: Account<'info, BurnRecord>,
    pub authority: Signer<'info>,
}

#[event]
pub struct SkinCreated {
    pub skin_id: u64,
    pub max_supply: u64,
    pub mint_price: u64,
    pub required_xp: u64,
    pub tier: u8,
}

#[event]
pub struct SkinMinted {
    pub skin_id: u64,
    pub buyer: Pubkey,
    pub amount: u64,
}

#[event]
pub struct SkinBurned {
    pub skin_id: u64,
    pub burner: Pubkey,
    pub amount: u64,
}

#[event]
pub struct RareMintedFromBurn {
    pub to: Pubkey,
    pub skin_id: u64,
    pub rare_skin_id: u64,
}

#[error_code]
pub enum SkinError {
    #[msg("Not authorized")]
    Unauthorized,
    #[msg("Invalid skin")]
    InvalidSkin,
    #[msg("Supply exhausted")]
    SupplyExhausted,
    #[msg("Insufficient XP")]
    InsufficientXp,
    #[msg("Insufficient payment")]
    InsufficientPayment,
    #[msg("Invalid tier")]
    InvalidTier,
    #[msg("URI too long (max 256)")]
    UriTooLong,
    #[msg("Burn not allowed on this tier")]
    BurnNotAllowed,
    #[msg("Must burn at least 2 skins")]
    InsufficientBurnQuantity,
    #[msg("Amount must be greater than zero")]
    ZeroAmount,
}
