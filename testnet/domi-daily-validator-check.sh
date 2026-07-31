#!/usr/bin/env bash
set -euo pipefail

rpc_url=${RPC_URL:-http://127.0.0.1:8545}
max_backscan=${MAX_BACKSCAN:-1200}
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

boundary=-1
for ((number = latest - 1; number >= 0 && number > latest - max_backscan; number--)); do
  number_hex=$(printf '0x%x' "$number")
  block=$(block_by_number "$number_hex" false)
  block_time=$(( $(jq -er '.result.timestamp' <<<"$block") ))
  if [ $((block_time / 86400)) -lt "$latest_day" ]; then
    boundary=$((number + 1))
    break
  fi
done

if [ "$boundary" -lt 0 ]; then
  echo "could not find the UTC day boundary within $max_backscan blocks" >&2
  exit 1
fi

boundary_hex=$(printf '0x%x' "$boundary")
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
