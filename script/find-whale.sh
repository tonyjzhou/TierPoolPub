#!/bin/bash
# Helper script to find a current MNEE whale address
# Usage: ./script/find-whale.sh

MNEE=0x8ccedbAe4916b79da7F3F612EfB2EB93A2bFD6cF

echo "Finding MNEE token holders..."
echo ""
echo "Option 1: Manual lookup (most reliable)"
echo "  1. Visit: https://etherscan.io/token/${MNEE}#balances"
echo "  2. Find an address with 100k+ MNEE balance"
echo "  3. Copy the address"
echo "  4. Run: export MNEE_WHALE=<address>"
echo ""
echo "Option 2: Check known addresses"
echo ""

# List of potential whale addresses (updated 2024-12-30)
# Source: https://etherscan.io/token/0x8ccedbAe4916b79da7F3F612EfB2EB93A2bFD6cF#balances
KNOWN_ADDRESSES=(
    0x5f652cb470818ca2dc69031b68b5f02bf3b71e94  # #1  ~1.48M MNEE
    0xbec28c9d802ae3a01cf42bbac021280121c0cacb  # #2  ~1.15M MNEE
    0x15d9ae537d1d1bf2a0a52246bdba81a3572d92bc  # #3  ~1.08M MNEE
    0x7b6646f71a1f3d4fb310eb0ba27df40e42bb8380  # #4  ~998K MNEE
    0xaf5ba45abfbb87bc868eaf65b63f38aeb670dfb8  # #5  ~974K MNEE
)

if command -v cast &> /dev/null; then
    RPC=${RPC:-https://ethereum-rpc.publicnode.com}
    echo "Checking known addresses against RPC: $RPC"
    echo ""

    for addr in "${KNOWN_ADDRESSES[@]}"; do
        echo -n "  $addr ... "
        balance=$(cast call $MNEE "balanceOf(address)(uint256)" $addr --rpc-url $RPC 2>/dev/null || echo "0")
        if [ "$balance" != "0" ] && [ "$balance" != "" ]; then
            # Convert to decimal with 18 decimals
            balance_readable=$(echo "scale=2; $balance / 1000000000000000000" | bc)
            echo "✓ ${balance_readable} MNEE"
            echo ""
            echo "Found working whale! Run:"
            echo "  export MNEE_WHALE=$addr"
        else
            echo "✗ No balance"
        fi
    done
else
    echo "cast not found. Install Foundry to check balances automatically."
    echo "  https://book.getfoundry.sh/getting-started/installation"
fi

echo ""
echo "Once you have a whale address, run the demo with:"
echo "  TIERPOOL=<deployed_address> ./script/demo.sh"
