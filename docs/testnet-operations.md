# Domi 测试网运行说明

## 拓扑

测试网固定运行三个 Docker 验证者：

| 服务 | 容器地址 | 角色 |
| --- | --- | --- |
| `validator-1` | `172.30.0.11` | 出块、公开 RPC |
| `validator-2` | `172.30.0.12` | 出块、静态 P2P |
| `validator-3` | `172.30.0.13` | 出块、静态 P2P |

每个节点都应连接另外两个节点。健康状态要求 `peerCount=2`、
`eth_syncing=false`、区块高度持续增长，且三个节点在共同高度拥有相同
区块哈希。

## 初始化原则

初始化脚本拒绝覆盖已有 runtime。修改创世、验证者或系统合约后必须使用
新的 runtime 目录重新初始化。运行目录中的密码文件、账户 keystore、
BLS keystore 和 nodekey 都是敏感材料，不得提交到 Git。

## 健康检查

```bash
./testnet/domi-healthcheck.sh
./testnet/domi-daily-validator-check.sh
```

健康检查会验证 chain ID、peer 数量、同步状态、gas price、gas limit 和
StakeHub 验证者数量。每日检查会在三个节点之间比较 validator set 和
共同高度的区块哈希。

## 停链排查顺序

1. 保存三个节点日志、当前高度、genesis hash 和 RPC 返回值；
2. 检查是否发生在 Feynman 初始化或首次 breathe block；
3. 查询 StakeHub 是否有三个注册验证者及正的 pooled stake；
4. 对比三个节点的二进制、配置、创世文件和 nodekey；
5. 检查静态 enode、Docker 网络和 peer count；
6. 原因明确后再使用新 runtime 重建，不要先删除旧数据。

常见的 `apply message failed` 或 `INVALID`，通常表示 fork 配置、系统合约
状态或 StakeHub election set 不一致，应按共识故障处理。
