// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IXPBalance {
    function balanceOf(address account) external view returns (uint256);
}

contract WONsSkins is ERC1155, Ownable, ReentrancyGuard {
    error SupplyExhausted();
    error InsufficientBurnQuantity();
    error BurnNotAllowed();
    error InvalidSkin();
    error InsufficientXP();
    error InsufficientPayment();

    enum Tier { Common, Rare, Epic, Legendary }

    struct Skin {
        uint256 maxSupply;
        uint256 minted;
        uint256 mintPrice;
        uint256 requiredXP;
        Tier tier;
        bool exists;
    }

    uint256 public constant BURN_RATE = 2;
    uint256 public constant RARE_MINT_PRICE = 5 ether;

    uint256 public nextSkinId = 1;
    address public xpToken;

    mapping(uint256 => Skin) public skins;
    mapping(uint256 => string) private skinURIs;

    event SkinMinted(uint256 indexed skinId, address indexed buyer, uint256 amount);
    event SkinBurned(uint256 indexed skinId, address indexed burner, uint256 amount);
    event SkinCreated(uint256 indexed skinId, uint256 maxSupply, uint256 mintPrice, uint256 requiredXP, Tier tier);
    event XPTokenUpdated(address indexed xpToken);

    constructor(address initialOwner, string memory uri, address _xpToken) ERC1155(uri) Ownable(initialOwner) {
        xpToken = _xpToken;
    }

    function setXPToken(address _xpToken) external onlyOwner {
        xpToken = _xpToken;
        emit XPTokenUpdated(_xpToken);
    }

    function createSkin(uint256 maxSupply, uint256 mintPrice, uint256 requiredXP, Tier tier, string calldata uri) external onlyOwner {
        uint256 skinId = nextSkinId++;
        skins[skinId] = Skin({
            maxSupply: maxSupply,
            minted: 0,
            mintPrice: mintPrice,
            requiredXP: requiredXP,
            tier: tier,
            exists: true
        });
        skinURIs[skinId] = uri;
        emit SkinCreated(skinId, maxSupply, mintPrice, requiredXP, tier);
    }

    function mintSkin(uint256 skinId, uint256 amount) external payable nonReentrant {
        Skin storage skin = skins[skinId];
        if (!skin.exists) revert InvalidSkin();
        if (skin.minted + amount > skin.maxSupply) revert SupplyExhausted();
        if (msg.value < skin.mintPrice * amount) revert InsufficientPayment();
        if (xpToken != address(0) && IXPBalance(xpToken).balanceOf(msg.sender) < skin.requiredXP) revert InsufficientXP();

        skin.minted += amount;
        _mint(msg.sender, skinId, amount, "");

        emit SkinMinted(skinId, msg.sender, amount);
    }

    function burnSkins(uint256 skinId, uint256 amount) external {
        Skin storage skin = skins[skinId];
        if (!skin.exists) revert InvalidSkin();
        if (amount < BURN_RATE) revert InsufficientBurnQuantity();
        if (skin.tier != Tier.Common) revert BurnNotAllowed();

        _burn(msg.sender, skinId, amount);
        emit SkinBurned(skinId, msg.sender, amount);
    }

    /**
     * Burns exactly BURN_RATE common skins and mints one rare skin.
     *
     * This is the rule the store advertises. It used to be a dead promise:
     * `burnSkins` destroyed the tokens and paid nothing back, and the only way
     * to get a rare was an owner-only mint. The rare handed out is the first
     * one with supply left, which keeps the outcome deterministic instead of
     * depending on a block variable the caller could grind.
     */
    function burnForRare(uint256[] calldata tokenIds) external nonReentrant {
        if (tokenIds.length != BURN_RATE) revert InsufficientBurnQuantity();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            Skin storage burned = skins[tokenIds[i]];
            if (!burned.exists) revert InvalidSkin();
            if (burned.tier != Tier.Common) revert BurnNotAllowed();

            _burn(msg.sender, tokenIds[i], 1);
            emit SkinBurned(tokenIds[i], msg.sender, 1);
        }

        uint256 rareSkinId = _findAvailableSkin(Tier.Rare);
        if (rareSkinId == 0) revert SupplyExhausted();

        Skin storage rareSkin = skins[rareSkinId];
        rareSkin.minted += 1;
        _mint(msg.sender, rareSkinId, 1, "");

        emit SkinMinted(rareSkinId, msg.sender, 1);
    }

    function mintRareFromBurn(address to) external onlyOwner nonReentrant {
        uint256 rareSkinId = _findAvailableSkin(Tier.Rare);
        if (rareSkinId == 0) revert SupplyExhausted();

        Skin storage rareSkin = skins[rareSkinId];
        if (rareSkin.minted + 1 > rareSkin.maxSupply) revert SupplyExhausted();

        rareSkin.minted += 1;
        _mint(to, rareSkinId, 1, "");

        emit SkinMinted(rareSkinId, to, 1);
    }

    function getRequiredXPForSkin(uint256 skinId) external view returns (uint256) {
        Skin storage skin = skins[skinId];
        if (!skin.exists) revert InvalidSkin();
        return skin.requiredXP;
    }

    function _findAvailableSkin(Tier tier) internal view returns (uint256) {
        for (uint256 i = 1; i < nextSkinId; i++) {
            if (skins[i].exists && skins[i].tier == tier && skins[i].minted < skins[i].maxSupply) {
                return i;
            }
        }
        return 0;
    }

    function skinURI(uint256 skinId) external view returns (string memory) {
        return skinURIs[skinId];
    }

    function updateSkinURI(uint256 skinId, string calldata uri) external onlyOwner {
        skinURIs[skinId] = uri;
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(owner()).call{value: balance}("");
            require(success, "Transfer failed");
        }
    }
}
