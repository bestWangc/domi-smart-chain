#!/usr/bin/env bash
set -euo pipefail
umask 077

# Builds an independent BSC network from the official genesis-contract source.
# It intentionally refuses to reuse a datadir: changing genesis creates a new chain.
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
RUNTIME_DIR=${RUNTIME_DIR:-"$ROOT_DIR/testnet/runtime"}
CHAIN_ID=${CHAIN_ID:-9199}
VALIDATOR_COUNT=${VALIDATOR_COUNT:-3}
GENESIS_CONTRACT_REV=041881a02475638b19f3d840871b7621cdebd8f8
GENESIS_SOURCE="$RUNTIME_DIR/bsc-genesis-contract"
GENESIS_BUILDER_IMAGE=${GENESIS_BUILDER_IMAGE:-domi-bsc-genesis-builder:1.7.7}
INIT_HOLDERS_FILE=${INIT_HOLDERS_FILE:-"$ROOT_DIR/testnet/init_holders.js"}
SOURCE_CHAIN_ID=${SOURCE_CHAIN_ID:-Domi-Chain}
TOKEN_HUB_INITIAL_LOCKED_DMT=${TOKEN_HUB_INITIAL_LOCKED_DMT:-0}

exec 9>"$ROOT_DIR/testnet/.init.lock"
if ! flock -n 9; then
  echo "Another testnet initialization is already running." >&2
  exit 1
fi

if [ "$VALIDATOR_COUNT" -ne 3 ]; then
  echo "This Compose topology has exactly 3 validators; update compose and static IPs before changing VALIDATOR_COUNT." >&2
  exit 1
fi
if [ -e "$RUNTIME_DIR/nodes" ] || [ -e "$RUNTIME_DIR/genesis.json" ] || [ -e "$GENESIS_SOURCE" ]; then
  echo "Refusing to overwrite $RUNTIME_DIR. Back up or choose a new RUNTIME_DIR." >&2
  exit 1
fi
command -v docker >/dev/null
command -v git >/dev/null
command -v jq >/dev/null
command -v openssl >/dev/null
if [ ! -f "$INIT_HOLDERS_FILE" ]; then
  echo "Initial-holder file not found: $INIT_HOLDERS_FILE" >&2
  exit 1
fi
if ! [[ "$TOKEN_HUB_INITIAL_LOCKED_DMT" =~ ^[0-9]+$ ]]; then
  echo "TOKEN_HUB_INITIAL_LOCKED_DMT must be a non-negative integer in wei." >&2
  exit 1
fi

mkdir -p "$RUNTIME_DIR/nodes"
openssl rand -base64 32 > "$RUNTIME_DIR/password.txt"

# The image is built from this exact checkout, so validator binaries and the
# genesis generator are tied to the same BSC v1.7.7 source tree.
docker build -t domi-bsc:v1.7.7 -f "$ROOT_DIR/testnet/Dockerfile.validator" "$ROOT_DIR"

git clone https://github.com/bnb-chain/bsc-genesis-contract.git "$GENESIS_SOURCE"
git -C "$GENESIS_SOURCE" checkout --detach "$GENESIS_CONTRACT_REV"

# Generate node keys and static enodes with the BSC client's supported network
# bootstrap command. The provisional genesis is only parsed here; it is never
# initialized into a data directory.
cp "$ROOT_DIR/testnet/config.toml.template" "$RUNTIME_DIR/init-network.toml"
docker run --rm -v "$RUNTIME_DIR:/runtime" domi-bsc:v1.7.7 \
  init-network --init.dir /runtime/nodes --init.size 3 \
  --init.ips 172.30.0.11,172.30.0.12,172.30.0.13 --init.p2p-port 30303 \
  --config /runtime/init-network.toml /runtime/bsc-genesis-contract/genesis.json
docker run --rm -v "$RUNTIME_DIR:/runtime" --entrypoint /bin/sh domi-bsc:v1.7.7 \
  -c 'chown -R 1000:1000 /runtime/nodes'

# init-network creates both nodekeys and static enodes. Rebuild the latter from
# the saved nodekeys so the mounted /data directories use the exact same IDs.
node_enodes=()
for index in 0 1 2; do
  node_enodes[index]=$(docker run --rm --entrypoint /usr/local/bin/nodekey-enode \
    -v "$RUNTIME_DIR/nodes/node$index:/data:ro" domi-bsc:v1.7.7 \
    --key /data/geth/nodekey --ip "172.30.0.$((11 + index))" --port 30303)
done
for index in 0 1 2; do
  # init-network creates config.toml as a directory. The runtime config is
  # supplied by our versioned template and must be a regular file for Docker.
  rm -rf "$RUNTIME_DIR/nodes/node$index/config.toml"
  cp "$ROOT_DIR/testnet/config.toml.template" "$RUNTIME_DIR/nodes/node$index/config.toml"
  static_nodes=()
  for peer_index in 0 1 2; do
    if [ "$peer_index" -ne "$index" ]; then
      static_nodes+=("\"${node_enodes[peer_index]}\"")
    fi
  done
  static_nodes_toml="[$(IFS=,; printf '%s' "${static_nodes[*]}")]"
  sed -i.bak "s#^StaticNodes = .*#StaticNodes = $static_nodes_toml#" \
    "$RUNTIME_DIR/nodes/node$index/config.toml"
  rm "$RUNTIME_DIR/nodes/node$index/config.toml.bak"
done

for index in 0 1 2; do
  node_dir="$RUNTIME_DIR/nodes/node$index"
  cp "$RUNTIME_DIR/password.txt" "$node_dir/password.txt"
  cp "$RUNTIME_DIR/password.txt" "$node_dir/bls-password.txt"
  docker run --rm -v "$node_dir:/data" domi-bsc:v1.7.7 \
    account new --datadir /data --password /data/password.txt >/dev/null
  docker run --rm -v "$node_dir:/data" domi-bsc:v1.7.7 \
    bls account new --datadir /data --blspassword /data/bls-password.txt >/dev/null
done

# The official generator needs Forge, Node and Python/Poetry. Build its tools
# in a disposable image; generated source and output remain under runtime.
docker build -t "$GENESIS_BUILDER_IMAGE" -f - "$GENESIS_SOURCE" <<'EOF'
FROM node:18.17.1-bullseye AS node
FROM ghcr.io/foundry-rs/foundry:stable
USER root
COPY --from=node /usr/local /usr/local
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip python3-venv git && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /opt/venv && /opt/venv/bin/pip install --no-cache-dir poetry==1.8.5
ENV PATH="/opt/venv/bin:${PATH}"
WORKDIR /workspace
EOF
docker run --rm --entrypoint /bin/bash -v "$GENESIS_SOURCE:/workspace" -w /workspace "$GENESIS_BUILDER_IMAGE" \
  -lc 'npm ci'
docker run --rm --entrypoint /bin/bash -e POETRY_VIRTUALENVS_IN_PROJECT=true -v "$GENESIS_SOURCE:/workspace" -w /workspace "$GENESIS_BUILDER_IMAGE" \
  -lc 'poetry install --no-root'
docker run --rm --entrypoint /bin/bash -v "$GENESIS_SOURCE:/workspace" -w /workspace "$GENESIS_BUILDER_IMAGE" \
  -lc 'forge install --no-git foundry-rs/forge-std@v1.7.3'

validators_conf="$GENESIS_SOURCE/validators.conf"
: > "$validators_conf"
for index in 0 1 2; do
  node_dir="$RUNTIME_DIR/nodes/node$index"
  key_file=$(find "$node_dir/keystore" -maxdepth 1 -type f | head -1)
  address="0x${key_file##*--}"
  bls_key=$(docker run --rm -v "$node_dir:/data" domi-bsc:v1.7.7 \
    bls account list --datadir /data --blspassword /data/bls-password.txt | sed -n 's/.*\(0x[0-9a-fA-F]\{96\}\).*/\1/p' | head -1)
  if ! [[ "$address" =~ ^0x[0-9a-fA-F]{40}$ ]] || ! [[ "$bls_key" =~ ^0x[0-9a-fA-F]{96}$ ]]; then
    echo "Unable to read validator $index public keys" >&2
    exit 1
  fi
  printf '%s,%s,%s,0x0000000000000064,%s\n' "$address" "$address" "$address" "$bls_key" >> "$validators_conf"
  printf 'VALIDATOR_%s=%s\n' "$((index + 1))" "$address" >> "$RUNTIME_DIR/.env"
done

docker run --rm --entrypoint /bin/bash -e POETRY_VIRTUALENVS_IN_PROJECT=true -v "$GENESIS_SOURCE:/workspace" -w /workspace "$GENESIS_BUILDER_IMAGE" \
  -lc 'poetry run python -m scripts.generate generate-validators --file-path ./validators.conf'
# init_holders.js is consumed by the official generate-genesis.js program. It
# is mounted as an input before generation, never patched into the output JSON.
docker run --rm --entrypoint node -v "$INIT_HOLDERS_FILE:/holders.js:ro" \
  -e 'const holders = require("/holders.js"); const defaultDevHolder = "0x9fb29aac15b9a4b7f17c3385939b007540f4d791"; if (!Array.isArray(holders) || holders.length === 0) process.exit(1); for (const holder of holders) { if (!/^0x[0-9a-fA-F]{40}$/.test(holder.address) || typeof holder.balance !== "string" || !/^[0-9a-fA-F]+$/.test(holder.balance) || BigInt(`0x${holder.balance}`) <= 0n || holder.address.toLowerCase() === defaultDevHolder) process.exit(1); }' "$GENESIS_BUILDER_IMAGE"
docker run --rm --entrypoint /bin/bash -e POETRY_VIRTUALENVS_IN_PROJECT=true -e SOURCE_CHAIN_ID="$SOURCE_CHAIN_ID" -v "$GENESIS_SOURCE:/workspace" \
  -v "$INIT_HOLDERS_FILE:/workspace/scripts/init_holders.js:ro" -w /workspace "$GENESIS_BUILDER_IMAGE" \
  -lc "poetry run python -m scripts.generate dev --dev-chain-id $CHAIN_ID --source-chain-id \"\$SOURCE_CHAIN_ID\""
# The independent chain retains TokenHub bytecode for BSC compatibility but
# has no BNB Chain bridge reserve. Regenerate through the official program
# with the project-specific reserve rather than editing the generated JSON.
# The upstream template strips the 0x prefix from init-holder keys. BSC v1.7.7
# does not load those entries into state, so create a disposable generator
# input template with canonical JSON-RPC address keys.
sed "s#\"{{ v.address.replace('0x', '') }}\"#\"0x{{ v.address.replace('0x', '') }}\"#" \
  "$GENESIS_SOURCE/genesis-template.json" > "$GENESIS_SOURCE/genesis-domi-template.json"
if cmp -s "$GENESIS_SOURCE/genesis-template.json" "$GENESIS_SOURCE/genesis-domi-template.json"; then
  echo "Unable to apply the init-holder address template compatibility fix" >&2
  exit 1
fi
docker run --rm --entrypoint node -v "$GENESIS_SOURCE:/workspace" \
  -v "$INIT_HOLDERS_FILE:/workspace/scripts/init_holders.js:ro" -w /workspace "$GENESIS_BUILDER_IMAGE" \
  scripts/generate-genesis.js --chainId "$CHAIN_ID" --template ./genesis-domi-template.json --output ./genesis-dev.json \
  --initLockedBNBOnTokenHub "$TOKEN_HUB_INITIAL_LOCKED_DMT"
docker run --rm --entrypoint /bin/bash -e POETRY_VIRTUALENVS_IN_PROJECT=true -v "$GENESIS_SOURCE:/workspace" -w /workspace "$GENESIS_BUILDER_IMAGE" \
  -lc 'poetry run python -m scripts.generate recover'

# generate dev and recover produce the complete official development genesis,
# including the fork state required by the matching BSC client. Do not hand-edit
# fork times or contract allocations after this point.
jq -e --argjson chain_id "$CHAIN_ID" '.config.chainId == $chain_id' \
  "$GENESIS_SOURCE/genesis-dev.json" >/dev/null
# BSC v1.7.7 validates a blob schedule for every enabled fork. The generator
# revision predates its required Osaka entry; BSC uses the Cancun schedule here.
jq '.config.blobSchedule.osaka = {
  target: 3,
  max: 6,
  baseFeeUpdateFraction: 3338477
}' "$GENESIS_SOURCE/genesis-dev.json" > "$RUNTIME_DIR/genesis.json"

for index in 0 1 2; do
  node_dir="$RUNTIME_DIR/nodes/node$index"
  sed -i.bak \
    -e 's#DataDir = ".*"#DataDir = "/data"#' \
    -e 's#GasCeil = [0-9]*#GasCeil = 55000000#' \
    -e 's#GasPrice = .*#GasPrice = 1000000000#' \
    "$node_dir/config.toml"
  rm "$node_dir/config.toml.bak"
  docker run --rm -v "$node_dir:/data" -v "$RUNTIME_DIR/genesis.json:/genesis.json:ro" domi-bsc:v1.7.7 \
    --datadir /data init /genesis.json >/dev/null
done

cp "$RUNTIME_DIR/.env" "$ROOT_DIR/testnet/.env"
chmod 600 "$RUNTIME_DIR/.env" "$ROOT_DIR/testnet/.env"
echo "Initialized independent chain $CHAIN_ID with 3 validators from the official development genesis."
