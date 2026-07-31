package main

import (
	"flag"
	"fmt"
	"net"

	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/p2p/enode"
)

func main() {
	keyPath := flag.String("key", "", "nodekey file")
	ip := flag.String("ip", "", "advertised IP")
	port := flag.Int("port", 30303, "P2P port")
	flag.Parse()
	if *keyPath == "" || *ip == "" {
		panic("--key and --ip are required")
	}
	key, err := crypto.LoadECDSA(*keyPath)
	if err != nil {
		panic(err)
	}
	fmt.Print(enode.NewV4(&key.PublicKey, net.ParseIP(*ip), *port, *port).URLv4())
}
