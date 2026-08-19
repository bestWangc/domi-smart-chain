# Domi Testnet Operations

## Topology

The testnet runs three fixed Docker validators:

| Service | Container address | Role |
| --- | --- | --- |
| `validator-1` | `172.30.0.11` | Block production and public RPC |
| `validator-2` | `172.30.0.12` | Block production and static P2P |
| `validator-3` | `172.30.0.13` | Block production and static P2P |

Each node should connect to the other two. A healthy network reports
`peerCount=2`, `eth_syncing=false`, continuously increasing block height, and
matching block hashes across all three nodes at a common height.

## Initialization principles

The initializer refuses to overwrite an existing runtime directory. After
changing genesis, validators, or system contracts, initialize a new runtime
directory. Password files, account keystores, BLS keystores, and nodekeys in a
runtime directory are sensitive and must not be committed to Git.

## Health checks

```bash
./testnet/domi-healthcheck.sh
./testnet/domi-daily-validator-check.sh
```

The health check validates chain ID, peer count, sync status, gas price, gas
limit, and the number of StakeHub validators. The daily check compares the
validator set and common-height block hashes across all three nodes.

## Halt investigation order

1. Preserve logs, current height, genesis hash, and RPC responses from all nodes.
2. Check whether the halt occurred during Feynman initialization or the first
   breathe block.
3. Confirm that StakeHub contains three registered validators with positive
   pooled stake.
4. Compare binaries, configuration, genesis files, and nodekeys.
5. Check static enodes, the Docker network, and peer count.
6. Rebuild with a new runtime only after the cause is understood.

`apply message failed` or `INVALID` errors commonly indicate inconsistent fork
configuration, system-contract state, or StakeHub election state and should be
handled as consensus incidents.
