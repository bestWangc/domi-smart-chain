# Domi Smart Chain 架构说明

## 1. 总体结构

Domi 是独立运行的 EVM 公链。它使用 BSC 兼容的执行和 Parlia 共识实现，
但拥有自己的 chain ID、创世状态、验证者密钥、系统合约状态和治理流程。

```text
钱包 / RPC
    |
    v
EVM 执行层与系统合约
    |
    v
Parlia 共识层
    |
    v
StakeHub 注册、质押与选举
    |
    v
周期性 validator-set 更新
```

## 2. 验证者生命周期

创世中的初始 validator set 只保证最初的区块生产。Feynman 初始化后，
每个验证者还必须通过官方 `createValidator` 流程完成：

- operator、consensus 和 vote/BLS 数据登记；
- StakeCredit 代理合约部署；
- 最低自委托质押锁定；
- 投票权形成并进入 `getValidatorElectionInfo` 返回值。

每个 UTC breathe block，Parlia 从 StakeHub 读取候选集合，过滤零投票权
节点，按投票权排序并更新系统 validator set。两套集合不一致时，链可能
在首次 breathe block 停止。

## 3. 系统合约与创世

系统合约按 fork/version 存放在 `core/systemcontracts/`。创世由官方生成器
和 Domi 的版本化初始化脚本共同产生。不要在生成结束后手工编辑最终
genesis JSON；Domi 特有参数应通过生成器参数、输入模板或引导交易表达。

## 4. 项目边界

本仓库负责公链客户端、创世、系统合约、验证者节点、P2P 拓扑和健康检查。

独立的 `domi-bridge` 项目负责 BSC 与 Domi 的跨链资产合约、Hyperlane
Mailbox/ISM/Validator/Relayer、映射资产、储备对账和桥接事故响应。

桥接服务不得成为 Domi 出块、同步或验证区块的依赖。桥 Validator 私钥、
Relayer 私钥和桥治理权限也不得与 Domi 共识验证者密钥复用。

## 5. 兼容性边界

“BSC-compatible”不代表 Domi 自动连接 BNB Chain、共享 BNB Chain 验证者
或自动获得 BSC 资产。所有跨链资产都必须明确来源链、来源合约、储备
位置、验证阈值和赎回条件。
