import { ethers } from "ethers";
import * as dotenv from 'dotenv';
dotenv.config();

const SKINS_ABI = [
    "function createSkin(uint256 maxSupply, uint256 mintPrice, uint256 requiredXP, uint8 tier, string calldata uri) external",
    "function nextSkinId() external view returns (uint256)",
    "function updateSkinURI(uint256 skinId, string calldata uri) external",
];

const TEST_SKINS = [
    {
        name: "Sprout",
        tier: 0, // Common
        maxSupply: 1000,
        mintPrice: "5",
        requiredXP: 0,
        metadata: {
            name: "Sprout",
            description: "Fresh green skin. Common tier.",
            image: "ipfs://QmPlaceholderSprout/image.png",
            attributes: [
                { trait_type: "Tier", value: "Common" },
                { trait_type: "Shader", value: "default" },
            ],
            properties: {
                palette: {
                    body: [0.48, 0.78, 0.49, 1],
                    body_alt: [0.37, 0.66, 0.38, 1],
                    cheek: [0.37, 0.66, 0.38, 1],
                    eye: [1, 1, 1, 1],
                    skin: [0.85, 0.7, 0.45, 1],
                },
                outline_color: [0.48, 0.78, 0.49, 1],
                crown_color: [0.48, 0.78, 0.49, 1],
                face_texture: "",
                shader: "default",
                shader_targets: ["body", "cheek", "eye"],
                attachment: { shape: "box", color: [0.85, 0.7, 0.45, 1] },
            },
        },
    },
    {
        name: "Cobalt",
        tier: 1, // Rare
        maxSupply: 500,
        mintPrice: "10",
        requiredXP: 100,
        metadata: {
            name: "Cobalt",
            description: "Deep blue metallic skin. Rare tier.",
            image: "ipfs://QmPlaceholderCobalt/image.png",
            attributes: [
                { trait_type: "Tier", value: "Rare" },
                { trait_type: "Shader", value: "gold" },
            ],
            properties: {
                palette: {
                    body: [0.23, 0.49, 0.85, 1],
                    body_alt: [0.23, 0.49, 0.85, 1],
                    cheek: [0.23, 0.49, 0.85, 1],
                    eye: [1, 1, 1, 1],
                    skin: [0.54, 0.71, 0.97, 1],
                },
                outline_color: [0.23, 0.49, 0.85, 1],
                crown_color: [0.23, 0.49, 0.85, 1],
                face_texture: "",
                shader: "gold",
                shader_targets: ["body", "cheek"],
                attachment: { shape: "box", color: [0.54, 0.71, 0.97, 1] },
            },
        },
    },
    {
        name: "Magma",
        tier: 2, // Epic
        maxSupply: 100,
        mintPrice: "20",
        requiredXP: 500,
        metadata: {
            name: "Magma",
            description: "Volcanic orange skin with glow. Epic tier.",
            image: "ipfs://QmPlaceholderMagma/image.png",
            attributes: [
                { trait_type: "Tier", value: "Epic" },
                { trait_type: "Shader", value: "default" },
            ],
            properties: {
                palette: {
                    body: [1, 0.42, 0.21, 1],
                    body_alt: [1, 0.42, 0.21, 1],
                    cheek: [1, 0.42, 0.21, 1],
                    eye: [1, 1, 1, 1],
                    skin: [1, 0.61, 0.43, 1],
                },
                outline_color: [1, 0.27, 0, 1],
                crown_color: [1, 0.27, 0, 1],
                face_texture: "",
                shader: "default",
                shader_targets: ["body", "cheek", "eye"],
                attachment: { shape: "cone", color: [1, 0.27, 0, 1] },
            },
        },
    },
    {
        name: "Aether",
        tier: 3, // Legendary
        maxSupply: 50,
        mintPrice: "50",
        requiredXP: 2000,
        metadata: {
            name: "Aether",
            description: "Otherworldly violet skin. Legendary tier.",
            image: "ipfs://QmPlaceholderAether/image.png",
            attributes: [
                { trait_type: "Tier", value: "Legendary" },
                { trait_type: "Shader", value: "angel" },
            ],
            properties: {
                palette: {
                    body: [0.61, 0.35, 0.71, 1],
                    body_alt: [0.61, 0.35, 0.71, 1],
                    cheek: [0.61, 0.35, 0.71, 1],
                    eye: [0.95, 0.77, 0.06, 1],
                    skin: [0.76, 0.61, 0.83, 1],
                },
                outline_color: [0.95, 0.77, 0.06, 1],
                crown_color: [0.95, 0.77, 0.06, 1],
                face_texture: "",
                shader: "angel",
                shader_targets: ["body", "cheek", "eye"],
                attachment: { shape: "torus", color: [0.95, 0.77, 0.06, 1] },
            },
        },
    },
];

async function main() {
    const provider = new ethers.JsonRpcProvider(process.env.MN_RPC_URL || "https://testnet-rpc.monad.xyz");
    const wallet = new ethers.Wallet(process.env.TRUSTED_AUTHORITY_PRIVATE_KEY, provider);
    const skinsContract = new ethers.Contract(process.env.SKINS_ADDRESS, SKINS_ABI, wallet);

    console.log(`Seeding test skins from: ${wallet.address}`);
    console.log(`Contract: ${process.env.SKINS_ADDRESS}\n`);

    const nextId = await skinsContract.nextSkinId();
    console.log(`Current nextSkinId: ${nextId}\n`);

    for (const skin of TEST_SKINS) {
        const uri = `data:application/json,${encodeURIComponent(JSON.stringify(skin.metadata))}`;
        const priceWei = ethers.parseUnits(skin.mintPrice, 18);

        console.log(`Creating "${skin.name}" (tier ${skin.tier})...`);
        console.log(`  Supply: ${skin.maxSupply}, Price: ${skin.mintPrice} MON, XP: ${skin.requiredXP}`);

        const gasEst = await skinsContract.createSkin.estimateGas(
            BigInt(skin.maxSupply),
            priceWei,
            BigInt(skin.requiredXP),
            skin.tier,
            uri
        );
        console.log(`  Gas: ${gasEst} (using ${gasEst * 120n / 100n})`);
        const tx = await skinsContract.createSkin(
            BigInt(skin.maxSupply),
            priceWei,
            BigInt(skin.requiredXP),
            skin.tier,
            uri,
            { gasLimit: gasEst * 120n / 100n }
        );
        const receipt = await tx.wait();
        console.log(`  ✓ Tx: ${tx.hash} (block ${receipt.blockNumber})\n`);
    }

    const finalNextId = await skinsContract.nextSkinId();
    console.log(`Done! ${TEST_SKINS.length} skins created. nextSkinId: ${nextId} → ${finalNextId}`);
}

main().catch((err) => {
    console.error("Failed:", err);
    process.exit(1);
});
