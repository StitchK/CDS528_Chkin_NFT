# CDS528 Chkin NFT

一个基于 Solidity 与 Foundry 构建的去中心化挑战打卡系统。参与者使用测试代币 `CHECK` 作为押金加入挑战，在规定时间内完成每日打卡；挑战结束后，成功者可取回押金并领取纪念 NFT，未完成者的押金则进入奖励池，由挑战作者和成功者共同分享。

## 核心功能

- **创建挑战**：设置押金、开始时间、持续天数、所需打卡次数和参与人数上限。
- **押金报名**：参与者授权并存入 `CHECK` 代币后加入挑战。
- **每日打卡**：每个挑战日最多打卡一次，合约自动记录完成进度。
- **挑战结算**：区分成功者与未完成者，退还成功者的原始押金。
- **奖励分配**：失败者押金进入奖励池；有成功者时，一半用于奖励成功者，余下部分归挑战作者；没有成功者时全部归作者。
- **NFT 奖励**：成功者在结算后可领取与挑战关联的 ERC-721 纪念 NFT。
- **挑战取消**：作者可在挑战开始前取消，参与者随后自行领取退款。

## 合约架构

| 合约 | 作用 |
| --- | --- |
| `ChallengeManager.sol` | 管理挑战创建、报名、打卡、取消、结算、押金退款和 NFT 领取 |
| `RewardPool.sol` | 接收失败者押金，记录并发放作者奖励与成功者奖励 |
| `CheckInNFT.sol` | 为完成挑战的参与者铸造和管理纪念 NFT |
| `MockDepositToken.sol` | 用于课程项目和测试的 ERC-20 `CHECK` 代币 |

主要流程：

```text
领取 CHECK → 创建/加入挑战 → 每日打卡 → 结算挑战
                                      ├─ 成功：退回押金 + 领取 NFT + 领取奖励
                                      └─ 失败：押金进入 RewardPool
```

## 项目结构

```text
chkin_nft/
├── packages/
│   └── foundry/
│       ├── contracts/       # Solidity 合约
│       ├── test/            # Foundry 单元测试
│       ├── lib/             # OpenZeppelin 依赖
│       └── foundry.toml     # Foundry 配置
├── .gitignore
└── README.md
```

## 环境要求

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Solidity `0.8.37`（Foundry 会根据配置自动使用）

## 本地运行

克隆仓库并进入 Foundry 包：

```bash
git clone https://github.com/StitchK/CDS528_Chkin_NFT.git
cd CDS528_Chkin_NFT/packages/foundry
```

编译合约：

```bash
forge build
```

运行全部测试：

```bash
forge test
```

查看更详细的测试输出：

```bash
forge test -vvv
```

## 合约部署顺序

部署时需要按以下顺序创建并绑定合约：

1. 部署 `MockDepositToken`。
2. 使用代币地址部署 `RewardPool`。
3. 使用 NFT 基础 URI 部署 `CheckInNFT`。
4. 使用代币、奖励池和 NFT 地址部署 `ChallengeManager`。
5. 调用 `RewardPool.setChallengeManager(challengeManagerAddress)`。
6. 调用 `CheckInNFT.setManager(challengeManagerAddress)`。

部署完成后，参与者先调用 `MockDepositToken.claim()` 获取测试代币，再授权 `ChallengeManager` 使用相应押金，即可加入挑战。

## 测试覆盖

测试套件覆盖以下场景：

- 挑战参数校验、创建、报名和人数限制
- 每日打卡规则与挑战时间窗口
- 成功/失败参与者的结算和押金流转
- 挑战取消与退款
- 奖励池分配、领取权限及防重复领取
- NFT 铸造、元数据、转移和枚举
- CHECK 代币领取、转账与授权

## 安全设计

- 使用 OpenZeppelin `SafeERC20` 处理代币转账。
- 使用 `ReentrancyGuard` 保护涉及资金的关键函数。
- 采用主动领取（pull payment）模式，避免结算时向大量地址批量转账。
- 对重复打卡、重复结算、重复领取和无权限调用进行显式校验。

> 本项目用于 CDS528 课程学习与演示，尚未经过专业安全审计，请勿直接用于生产环境或管理真实资产。

## License

合约源码使用 MIT License。
