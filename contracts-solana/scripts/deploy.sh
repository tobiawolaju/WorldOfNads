#!/bin/bash
# World of Nads Solana Contracts - Deployment Script
# Requires: anchor-cli 0.30.1+, solana-cli 2.1.0+
#
# Usage:
#   ./scripts/deploy.sh devnet    # Deploy to devnet
#   ./scripts/deploy.sh mainnet   # Deploy to mainnet (not recommended until audit)

set -euo pipefail

CLUSTER="${1:-devnet}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Deploying World of Nads Solana Contracts ==="
echo "Cluster: $CLUSTER"
echo "Project: $PROJECT_DIR"
echo ""

# Build all programs
echo ">>> Building programs..."
cd "$PROJECT_DIR"
anchor build

# Deploy in order: xp-token -> loot-box -> match-engine -> skins -> treasury
echo ""
echo ">>> Deploying XP Token..."
anchor deploy --program-name xp-token --provider.cluster "$CLUSTER"

echo ""
echo ">>> Deploying Loot Box..."
anchor deploy --program-name loot-box --provider.cluster "$CLUSTER"

echo ""
echo ">>> Deploying Match Engine..."
anchor deploy --program-name match-engine --provider.cluster "$CLUSTER"

echo ""
echo ">>> Deploying Skins..."
anchor deploy --program-name skins --provider.cluster "$CLUSTER"

echo ""
echo ">>> Deploying Treasury..."
anchor deploy --program-name treasury --provider.cluster "$CLUSTER"

echo ""
echo "=== Deployment Complete ==="
echo "Save the deployed program IDs from the output above."
echo "Update Anchor.toml [programs.$CLUSTER] with the deployed IDs."
echo ""
echo "Next steps:"
echo "  1. Run: anchor run init-all --provider.cluster $CLUSTER"
echo "  2. Set trusted authority, minter roles, etc."
