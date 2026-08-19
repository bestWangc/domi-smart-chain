# Domi Smart Chain

Domi Smart Chain is an independent EVM-compatible public blockchain using the
Parlia consensus engine and StakeHub validator management. This repository
contains the chain client, genesis configuration, system contracts, and testnet
node operations. It does not contain bridge implementation code.

## Project scope

“EVM/BSC-compatible” means compatibility with the selected EVM, JSON-RPC,
Parlia execution model, and related system-contract interfaces. It does not
mean that Domi is connected to BNB Chain or shares BNB Chain validators,
governance, or bridges.

Core responsibilities:

- execute EVM transactions and maintain chain state;
- produce and validate blocks through Parlia;
- register, stake, and elect validators through StakeHub;
- manage genesis files, system contracts, and fork configuration; and
- provide a reproducible three-validator Docker testnet.

Cross-chain contracts, Hyperlane configuration, bridge assets, and relayer
services belong in the separate `domi-bridge` project. Bridge services are not
required for Domi block production or consensus validation.

## Architecture overview

```text
Wallet / RPC client -> EVM execution layer -> Parlia consensus layer
                                                   |
                                                   v
                                      StakeHub registration, staking, election
                                                   |
                                                   v
                                      Periodic validator-set updates
```

### StakeHub initialization requirements

The legacy validator set in genesis only allows the chain to start. After
Feynman activation, StakeHub must also contain each validator's operator and
consensus addresses, vote/BLS public key and proof, StakeCredit contract,
minimum self-delegation, and positive `totalPooledBNB()` voting power.

Parlia reads the StakeHub election result at breathe blocks and updates the
validator set. StakeHub registration is therefore part of consensus bootstrap,
not ordinary application configuration.

## Testnet parameters

| Parameter | Current value |
| --- | --- |
| Chain ID | `9199` |
| Validators | 3 |
| P2P mode | Static peers |
| Target gas price | `1 gwei` |
| Gas limit | `55,000,000` |
| StakeHub validators | 3 registered and self-delegated validators |

The testnet is for development and integration testing only. It does not
represent production DMT value and must not hold real assets.

## Directory guide

- `consensus/parlia/` — Parlia consensus, breathe blocks, and validator-set updates.
- `core/systemcontracts/` — versioned system-contract bytecode and fork configuration.
- `scripts/` — genesis generation and testnet initialization scripts.
- `testnet/` — Docker Compose, node templates, and health checks.
- `genesis/` — local development and test genesis files.
- `docs/architecture.md` — detailed architecture and project boundaries.

## Operating principles

- Client binaries, genesis files, and validator keys must come from the same
  versioned initialization flow.
- Every genesis change must be validated in a new runtime directory.
- Consensus validator keys must not be reused for bridge Validators, Relayers,
  or administrator permissions.
- TokenHub or any system-contract balance must not be treated as a working bridge.
- Cross-chain assets must define their reserves, verification model, and
  redemption rules in the separate bridge project.

## Related documentation

- [Architecture and project boundaries](docs/architecture.md)
- [Testnet operations](docs/testnet-operations.md)
- [Security policy](SECURITY.md)
