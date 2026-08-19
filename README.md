# Domi Smart Chain

Domi Smart Chain 是一条独立的 EVM 兼容公链，使用 Parlia 共识引擎和
StakeHub 验证者管理机制。该仓库负责链客户端、创世配置、系统合约和
测试网节点运行，不负责跨链桥业务。

## 项目定位

“EVM/BSC 兼容”表示 Domi 兼容选定的 EVM、JSON-RPC、Parlia 执行模型和
相关系统合约接口；它不表示 Domi 接入了 BNB Chain，也不表示 Domi 共享
BNB Chain 的验证者、治理或资产桥。

核心职责包括：

- 执行 EVM 交易并维护链上状态；
- 通过 Parlia 产生和验证区块；
- 通过 StakeHub 注册、质押和选举验证者；
- 管理创世文件、系统合约和硬分叉配置；
- 提供可重复初始化的三验证者 Docker 测试网。

跨链桥、Hyperlane 配置、桥接资产和中继服务属于独立的 `domi-bridge`
项目。桥服务不是 Domi 出块和共识验证的前置依赖。

## 架构概览

```text
钱包 / RPC 客户端 -> EVM 执行层 -> Parlia 共识层
                                      |
                                      v
                         StakeHub 验证者注册、质押与选举
                                      |
                                      v
                         周期性 validator-set 更新
```

### StakeHub 初始化要求

创世中的 legacy validator set 只能保证链启动。Feynman 启用后，StakeHub
还必须包含每个验证者的 operator/consensus 地址、vote/BLS 公钥及证明、
StakeCredit 合约、最低自委托质押和正的 `totalPooledBNB()` 投票权。

Parlia 在 breathe block 读取 StakeHub 选举结果并更新 validator set，
因此 StakeHub 注册状态是共识启动流程的一部分，而不是普通业务配置。

## 测试网参数

| 参数 | 当前值 |
| --- | --- |
| Chain ID | `9199` |
| 验证者数量 | 3 |
| P2P 模式 | 静态节点 |
| 目标 Gas Price | `1 gwei` |
| Gas Limit | `55,000,000` |
| StakeHub 验证者 | 3 个已注册并完成自委托的节点 |

测试网只用于开发和集成测试，不代表 DMT 具有生产价值，也不得用于
托管真实资产。

## 目录说明

- `consensus/parlia/`：Parlia 共识、breathe block 和验证者集合更新。
- `core/systemcontracts/`：版本化系统合约字节码和升级配置。
- `scripts/`：创世生成和测试网初始化脚本。
- `testnet/`：Docker Compose、节点模板和健康检查脚本。
- `genesis/`：本地开发与测试使用的创世文件。
- `docs/architecture.md`：详细架构和项目边界。

## 运行原则

- 链客户端、创世和验证者密钥必须来自同一版本化初始化流程；
- 任何创世变更都应使用新的 runtime 目录验证；
- 共识验证者密钥不得复用于桥 Validator、Relayer 或管理员权限；
- 不能把 TokenHub 或任意系统合约余额误认为可用跨链桥；
- 跨链资产必须由独立桥项目定义储备、验证和赎回规则。

## 相关文档

- [架构与项目边界](docs/architecture.md)
- [测试网运行说明](docs/testnet-operations.md)
- [安全策略](SECURITY.md)
