#!/usr/bin/env bash
set -euo pipefail

state_dir=${STATE_DIR:-/home/domi/domi-chain/testnet/runtime/healthcheck}
state_file="$state_dir/last-block"
rpc_url=${RPC_URL:-http://127.0.0.1:8545}
expected_chain_id=${EXPECTED_CHAIN_ID:-9199}
expected_gas_limit=${EXPECTED_GAS_LIMIT:-55000000}
minimum_gas_limit=${MINIMUM_GAS_LIMIT:-10000000}
expected_gas_price=${EXPECTED_GAS_PRICE:-1000000000}

mkdir -p "$state_dir"
response=$(curl --silent --show-error --fail --connect-timeout 5 \
  -X POST "$rpc_url" --header 'content-type: application/json' \
  --data '[{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]},{"jsonrpc":"2.0","id":2,"method":"net_peerCount","params":[]},{"jsonrpc":"2.0","id":3,"method":"eth_syncing","params":[]},{"jsonrpc":"2.0","id":4,"method":"eth_chainId","params":[]},{"jsonrpc":"2.0","id":5,"method":"eth_gasPrice","params":[]},{"jsonrpc":"2.0","id":6,"method":"eth_getBlockByNumber","params":["latest",false]}]')

block_hex=$(jq -er '.[] | select(.id == 1) | .result' <<<"$response")
peer_hex=$(jq -er '.[] | select(.id == 2) | .result' <<<"$response")
syncing=$(jq -r '.[] | select(.id == 3) | .result' <<<"$response")
chain_id_hex=$(jq -er '.[] | select(.id == 4) | .result' <<<"$response")
gas_price_hex=$(jq -er '.[] | select(.id == 5) | .result' <<<"$response")
gas_limit_hex=$(jq -er '.[] | select(.id == 6) | .result.gasLimit' <<<"$response")
block=$((block_hex))
peers=$((peer_hex))
chain_id=$((chain_id_hex))
gas_price=$((gas_price_hex))
gas_limit=$((gas_limit_hex))

if [ "$syncing" != false ]; then
  echo "testnet is syncing: $syncing" >&2
  exit 1
fi
if [ "$peers" -lt 2 ]; then
  echo "testnet has only $peers peers" >&2
  exit 1
fi
if [ "$chain_id" -ne "$expected_chain_id" ]; then
  echo "unexpected chain ID: $chain_id" >&2
  exit 1
fi
if [ "$gas_price" -ne "$expected_gas_price" ]; then
  echo "unexpected gas price: $gas_price" >&2
  exit 1
fi
if [ "$gas_limit" -lt "$minimum_gas_limit" ] || [ "$gas_limit" -gt "$expected_gas_limit" ]; then
  echo "gas limit outside range [$minimum_gas_limit, $expected_gas_limit]: $gas_limit" >&2
  exit 1
fi
if [ -f "$state_file" ] && [ "$block" -le "$(<"$state_file")" ]; then
  echo "testnet block height did not advance: $block" >&2
  exit 1
fi

printf '%s\n' "$block" > "$state_file"
echo "testnet healthy: block=$block peers=$peers"
