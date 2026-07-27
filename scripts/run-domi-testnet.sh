#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GETH="$ROOT/build/bin/geth"
DATA_DIR="$ROOT/.domi-testnet"
GENESIS="$ROOT/genesis/domi-testnet.json"
VALIDATOR="0x9C9B2D5982eD8b12Eb127f2358A734eB60271Dc0"

if [ ! -x "$GETH" ]; then
  echo "Build the node first: make geth" >&2
  exit 1
fi

if [ ! -f "$DATA_DIR/password.txt" ]; then
  echo "Missing $DATA_DIR/password.txt" >&2
  exit 1
fi

if [ ! -d "$DATA_DIR/geth/chaindata" ]; then
  "$GETH" --datadir "$DATA_DIR" init "$GENESIS"
fi

exec "$GETH" \
  --datadir "$DATA_DIR" \
  --networkid 9199 \
  --unlock "$VALIDATOR" \
  --password "$DATA_DIR/password.txt" \
  --mine \
  --miner.etherbase "$VALIDATOR" \
  --miner.gasprice 0 \
  --nat none \
  --nodiscover \
  --http \
  --http.addr 127.0.0.1 \
  --http.api eth,net,web3,txpool \
  --allow-insecure-unlock
