# Domi Smart Chain Architecture

## 1. System overview

Domi is an independently operated EVM blockchain. It uses BSC-compatible
execution and Parlia consensus implementations, but has its own chain ID,
genesis state, validator keys, system-contract state, and governance process.

```text
Wallet / RPC
    |
    v
EVM execution layer and system contracts
    |
    v
Parlia consensus layer
    |
    v
StakeHub registration, staking, and election
    |
    v
Periodic validator-set updates
```

## 2. Validator lifecycle

The initial validator set in genesis only enables initial block production.
After Feynman initialization, every validator must complete the official
`createValidator` flow, including:

- operator, consensus, and vote/BLS data registration;
- deployment of a StakeCredit proxy contract;
- locking the minimum self-delegation; and
- establishing voting power visible through `getValidatorElectionInfo`.

At each UTC breathe block, Parlia reads the StakeHub election set, removes
zero-power validators, sorts by voting power, and updates the system validator
set. If the two sets diverge, the chain may stop at the first breathe block.

## 3. System contracts and genesis

System contracts are versioned by fork and release under
`core/systemcontracts/`. Genesis is produced by the official generator and
Domi's versioned initialization scripts. Do not manually edit the final genesis
JSON after generation; express Domi-specific parameters through generator
arguments, input templates, or bootstrap transactions.

## 4. Project boundaries

This repository owns the public-chain client, genesis, system contracts,
validator nodes, P2P topology, and health checks.

The separate `domi-bridge` project owns BSC-to-Domi bridge contracts, Hyperlane
Mailbox/ISM/Validator/Relayer components, mapped assets, reserve accounting,
and bridge incident response.

Bridge services must not be dependencies of Domi block production, syncing, or
block validation. Bridge Validator keys, Relayer keys, and bridge governance
permissions must not be reused as Domi consensus validator keys.

## 5. Compatibility boundaries

“BSC-compatible” does not mean that Domi automatically connects to BNB Chain,
shares BNB Chain validators, or receives BSC assets. Every cross-chain asset
must define its source chain, source contract, reserve location, verification
threshold, and redemption conditions.
