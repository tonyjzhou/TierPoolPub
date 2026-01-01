# TierPool - Hackathon Submission

## Overview

**TierPool** is a trust-minimized group-buy escrow with vendor attestation and exit protection, built for the MNEE ecosystem.

## Links

| Resource | Link |
|----------|------|
| GitHub Repo | https://github.com/tonyjzhou/TierPoolPub |
| README | [README.md](./README.md) |

## Quick Demo

```bash
# Clone and test
git clone https://github.com/tonyjzhou/TierPoolPub.git
cd TierPoolPub
forge install
forge test

# Run live demo (requires Foundry)
anvil --fork-url https://ethereum-rpc.publicnode.com
# In new terminal:
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
export TIERPOOL=<deployed_address>
./script/demo.sh
```

## Quality Results

| Metric | Result |
|--------|--------|
| Tests | 55/55 passing |
| Test Coverage | Core flows, edge cases, security attacks |
| Slither | No high/medium severity findings |
| Gas (contribute) | ~98k avg |
| Gas (finalize) | ~75k avg |

## Key Innovation

Traditional group buys fail due to:
1. **Treasurer Risk** - Organizer disappears with funds
2. **Terms Mutation** - Deal changes after commitment
3. **Vendor Ghost** - No formal vendor commitment

TierPool solves all three through:
- **Escrow by Code** - Funds held by immutable contract
- **Attestation Gate** - Vendor must commit on-chain before contributions accepted
- **Exit Window** - Contributors can withdraw during cooldown
- **Automatic Refunds** - Failed pools refund without coordinator action

## Technical Highlights

- **Single Contract**: 482 lines of Solidity (TierPool.sol)
- **No Admin Keys**: Fully trustless, no upgrade mechanism
- **Dynamic State**: State evaluated on-chain based on current conditions
- **Fee-on-Transfer Safe**: Balance delta accounting handles FOT tokens
- **Reentrancy Protected**: ReentrancyGuard on all state-changing functions

## State Machine

```
PENDING → ACTIVE → COOLDOWN → PAYABLE → PAID
                      ↓
                  REFUNDING
```

See [PRD.md Section 6.4](./PRD.md) for detailed state diagram.

## Files

| File | Description |
|------|-------------|
| `src/TierPool.sol` | Main contract |
| `script/Deploy.s.sol` | Deployment script |
| `script/demo.sh` | Interactive demo |
| `test/*.t.sol` | 55 comprehensive tests |
| `README.md` | Full documentation |

## Target Network

- **Token**: MNEE (`0x8ccedbAe4916b79da7F3F612EfB2EB93A2bFD6cF`)
- **Demo**: Local Anvil fork of Ethereum mainnet (free, full functionality)
