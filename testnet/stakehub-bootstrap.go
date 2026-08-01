package main

import (
	"context"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"math/big"
	"os"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum/rpc"
)

const stakeHub = "0x0000000000000000000000000000000000002002"

var stakeHubABI = mustABI(`[ {"type":"function","name":"maxElectedValidators","inputs":[],"outputs":[{"type":"uint256"}],"stateMutability":"view"}, {"type":"function","name":"getValidatorConsensusAddress","inputs":[{"type":"address"}],"outputs":[{"type":"address"}],"stateMutability":"view"}, {"type":"function","name":"createValidator","inputs":[{"name":"consensusAddress","type":"address"},{"name":"voteAddress","type":"bytes"},{"name":"blsProof","type":"bytes"},{"name":"commission","type":"tuple","components":[{"name":"rate","type":"uint64"},{"name":"maxRate","type":"uint64"},{"name":"maxChangeRate","type":"uint64"}]},{"name":"description","type":"tuple","components":[{"name":"moniker","type":"string"},{"name":"identity","type":"string"},{"name":"website","type":"string"},{"name":"details","type":"string"}]}],"outputs":[],"stateMutability":"payable"} ]`)

type rpcTx struct {
	From  common.Address `json:"from"`
	To    common.Address `json:"to"`
	Gas   string         `json:"gas"`
	Value string         `json:"value"`
	Data  string         `json:"data"`
}

type commission struct{ Rate, MaxRate, MaxChangeRate uint64 }
type description struct{ Moniker, Identity, Website, Details string }

func mustABI(raw string) abi.ABI {
	a, err := abi.JSON(strings.NewReader(raw))
	if err != nil {
		panic(err)
	}
	return a
}

func readHex(path string) ([]byte, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	s := strings.TrimSpace(string(b))
	s = strings.TrimPrefix(s, "0x")
	return hex.DecodeString(s)
}

func main() {
	var operators, dir string
	flag.StringVar(&operators, "operators", "", "comma-separated operator addresses")
	flag.StringVar(&dir, "bootstrap-dir", "/bootstrap", "BLS public keys and proofs directory")
	flag.Parse()
	addrs := strings.Split(operators, ",")
	if len(addrs) != 3 {
		fatal(errors.New("exactly three operators are required"))
	}
	for i := range addrs {
		addrs[i] = strings.TrimSpace(addrs[i])
		if len(addrs[i]) != 42 || !common.IsHexAddress(addrs[i]) {
			fatal(fmt.Errorf("invalid operator address: %q", addrs[i]))
		}
	}

	ctx := context.Background()
	for i := 0; i < 3; i++ {
		rpcURL := fmt.Sprintf("http://validator-%d:8545", i+1)
		client, err := waitForRPC(ctx, rpcURL)
		if err != nil {
			fatal(err)
		}
		defer client.Close()
		from := common.HexToAddress(addrs[i])
		waitInitialized(ctx, client)
		registered, err := validatorRegistered(ctx, client, from)
		if err != nil {
			fatal(err)
		}
		if registered {
			fmt.Printf("validator %s is already registered\n", from.Hex())
			continue
		}
		pub, err := readHex(fmt.Sprintf("%s/node%d.pub", dir, i))
		if err != nil {
			fatal(err)
		}
		proof, err := readHex(fmt.Sprintf("%s/node%d.proof", dir, i))
		if err != nil {
			fatal(err)
		}
		data, err := stakeHubABI.Pack("createValidator", from, pub, proof,
			commission{Rate: 10, MaxRate: 100, MaxChangeRate: 5},
			description{Moniker: fmt.Sprintf("DomiVal%d", i+1), Identity: from.Hex(), Website: "", Details: "Independent Domi validator"})
		if err != nil {
			fatal(err)
		}
		value := new(big.Int).Mul(big.NewInt(2001), big.NewInt(1e18))
		c, err := rpc.DialHTTP(rpcURL)
		if err != nil {
			fatal(err)
		}
		defer c.Close()
		var txHash common.Hash
		tx := rpcTx{From: from, To: common.HexToAddress(stakeHub), Gas: "0x989680", Value: "0x" + value.Text(16), Data: "0x" + hex.EncodeToString(data)}
		if err := c.CallContext(ctx, &txHash, "eth_sendTransaction", tx); err != nil {
			fatal(fmt.Errorf("validator %d createValidator: %w", i+1, err))
		}
		waitReceipt(ctx, client, txHash)
		fmt.Printf("registered validator %s tx=%s\n", from.Hex(), txHash.Hex())
	}
}

func waitForRPC(ctx context.Context, rpcURL string) (*ethclient.Client, error) {
	deadline := time.Now().Add(10 * time.Minute)
	var lastErr error
	for time.Now().Before(deadline) {
		client, err := ethclient.DialContext(ctx, rpcURL)
		if err == nil {
			_, err = client.BlockNumber(ctx)
			if err == nil {
				return client, nil
			}
			client.Close()
		}
		lastErr = err
		time.Sleep(2 * time.Second)
	}
	return nil, fmt.Errorf("RPC %s was not ready within timeout: %w", rpcURL, lastErr)
}

func validatorRegistered(ctx context.Context, c *ethclient.Client, operator common.Address) (bool, error) {
	data, err := stakeHubABI.Pack("getValidatorConsensusAddress", operator)
	if err != nil {
		return false, err
	}
	out, err := c.CallContract(ctx, ethereumCall(common.HexToAddress(stakeHub), data), nil)
	if err != nil {
		return false, err
	}
	var consensus common.Address
	if err := stakeHubABI.UnpackIntoInterface(&consensus, "getValidatorConsensusAddress", out); err != nil {
		return false, err
	}
	return consensus != (common.Address{}), nil
}

func waitInitialized(ctx context.Context, c *ethclient.Client) {
	data, _ := stakeHubABI.Pack("maxElectedValidators")
	for deadline := time.Now().Add(10 * time.Minute); time.Now().Before(deadline); {
		out, err := c.CallContract(ctx, ethereumCall(common.HexToAddress(stakeHub), data), nil)
		if err == nil && len(out) > 0 && new(big.Int).SetBytes(out).Sign() > 0 {
			return
		}
		time.Sleep(2 * time.Second)
	}
	fatal(errors.New("StakeHub was not initialized within timeout"))
}

func ethereumCall(to common.Address, data []byte) ethereum.CallMsg {
	return ethereum.CallMsg{To: &to, Data: data}
}

func waitReceipt(ctx context.Context, c *ethclient.Client, hash common.Hash) {
	for deadline := time.Now().Add(10 * time.Minute); time.Now().Before(deadline); {
		r, err := c.TransactionReceipt(ctx, hash)
		if err == nil {
			if r.Status != 1 {
				fatal(fmt.Errorf("bootstrap tx reverted: %s", hash.Hex()))
			}
			return
		}
		time.Sleep(2 * time.Second)
	}
	fatal(errors.New("bootstrap transaction receipt timeout"))
}

func fatal(err error) { fmt.Fprintln(os.Stderr, err); os.Exit(1) }
