#!/usr/bin/env bash
set -euo pipefail

rpc_url=${RPC_URL:-http://127.0.0.1:8545}
validator_set_selector=0x1e4c1524

rpc() {
  curl --silent --show-error --fail --connect-timeout 5 \
    -X POST "$rpc_url" --header 'content-type: application/json' --data "$1"
}

block_by_number() {
  rpc "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getBlockByNumber\",\"params\":[\"$1\",$2]}"
}

latest_hex=$(rpc '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' | jq -er '.result')
latest=$((latest_hex))
latest_block=$(block_by_number "$latest_hex" false)
latest_time=$(( $(jq -er '.result.timestamp' <<<"$latest_block") ))
latest_day=$((latest_time / 86400))

# Block rates vary by network. Locate the first block in the current UTC day
# by timestamp rather than assuming a fixed number of blocks per day.
lower=0
upper=$latest
while [ "$lower" -lt "$upper" ]; do
  middle=$((lower + (upper - lower) / 2))
  middle_hex=$(printf '0x%x' "$middle")
  middle_block=$(block_by_number "$middle_hex" false)
  middle_time=$(( $(jq -er '.result.timestamp' <<<"$middle_block") ))
  if [ $((middle_time / 86400)) -lt "$latest_day" ]; then
    lower=$((middle + 1))
  else
    upper=$middle
  fi
done
boundary=$lower
boundary_hex=$(printf '0x%x' "$boundary")
boundary_time=$(( $(jq -er '.result.timestamp' <<<"$(block_by_number "$boundary_hex" false)") ))
if [ $((boundary_time / 86400)) -ne "$latest_day" ]; then
  echo "could not locate the current UTC day boundary" >&2
  exit 1
fi

boundary_block=$(block_by_number "$boundary_hex" true)
system_tx_hash=$(jq -er --arg selector "$validator_set_selector" '
  first(.result.transactions[] | select((.input // "") | startswith($selector)) | .hash)
' <<<"$boundary_block")
receipt=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getTransactionReceipt\",\"params\":[\"$system_tx_hash\"]}")

if [ "$(jq -er '.result.status' <<<"$receipt")" != "0x1" ]; then
  echo "updateValidatorSetV2 failed in block $boundary" >&2
  exit 1
fi

echo "validator-set update verified: block=$boundary tx=$system_tx_hash"
