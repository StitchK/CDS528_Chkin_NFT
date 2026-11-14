# CDS528 Chkin NFT

Repository: <https://github.com/StitchK/CDS528_Chkin_NFT>

一个使用 Solidity、Foundry 与 ethers v6 实现的链上押金打卡挑战系统。参与者存入测试代币 CHECK，在挑战期间打卡；到期结算后，成功者主动领取原始押金与 NFT，并可另行领取失败押金产生的额外奖励。系统以合约托管押金和执行分配规则，用于 CDS528 课程的 DeFi 机制演示。

## 功能与资金规则

- 创建挑战：设置押金、未来开始时间、持续天数、所需打卡次数、人数上限和元数据 URI。
- 报名：开始前授权并存入 CHECK，同一地址不能重复报名。
- 打卡：按挑战开始时间划分连续 24 小时，每个挑战日最多一次。
- 结算：到期后任何人可调用 `finalizeChallenge`，需要交易触发，不会自动定时执行。
- 成功：通过 `claimSuccessfulParticipant` 一次领取原始押金和 NFT；额外代币奖励从 RewardPool 分开领取。
- 失败：押金转入 RewardPool。有成功者时，约一半均分给成功者，剩余及舍入余数归作者；无人成功时全部归作者。
- 取消：只有作者可在开始前取消，参与者随后主动领取退款。

设失败押金总额为 F（代币最小单位），成功人数为 W。当 W > 0 时，每位成功者额外奖励为 `floor(floor(F / 2) / W)`，作者奖励为 `F - 每人奖励 × W`。作者也可以参与并成为成功者，两种奖励分别计算和领取。

## 架构与目录

| 合约 | 职责 |
| --- | --- |
| `MockDepositToken` | ERC-20 测试代币 CHECK，18 位小数；每次 `claim()` 铸造 1,000 CHECK |
| `ChallengeManager` | 挑战、押金托管、打卡、结算、退款和 NFT 领取 |
| `RewardPool` | 接收失败押金、记录份额、发放作者和成功者奖励 |
| `CheckInNFT` | 奖励铸造、挑战关联、元数据、转移和枚举 |

```text
packages/
├── foundry/
│   ├── contracts/          # 四个业务合约
│   ├── test/               # 39 个单元测试
│   ├── script/Deploy.s.sol # 部署四个合约并绑定权限
│   ├── lib/               # 已随仓库提供的 OpenZeppelin 5.4.0 源码子集
│   ├── .env.example       # 测试网配置示例
│   └── foundry.toml       # Solidity 0.8.37 和导入映射
└── web/
    ├── index.html
    ├── styles.css
    ├── app.js             # 原生 JavaScript + ethers 6.15.0
    └── README.md
```

押金与打卡记录、资格、奖励和 NFT 所有权在链上；搜索筛选、钱包交互和元数据读取在浏览器中完成。前端直接连接钱包提供的 RPC，不需要独立后端服务。

## 1. 环境安装

需要 Git、Foundry（`forge`、`cast`、`anvil`）、Python 3（提供静态 HTTP 服务）和支持 EIP-1193 的浏览器钱包，例如 MetaMask。前端不需要 Node.js、npm 或打包步骤。Windows 建议在 WSL 中执行以下 Bash 命令。

按照 [Foundry 官方安装说明](https://getfoundry.sh/introduction/installation/) 安装。macOS/Linux 的常见方式：

```bash
curl -L https://foundry.paradigm.xyz | bash
```

按安装器提示重新打开终端或加载 shell 配置，然后运行：

```bash
foundryup
forge --version
cast --version
anvil --version
git --version
python3 --version
```

克隆仓库并进入合约目录：

```bash
git clone https://github.com/StitchK/CDS528_Chkin_NFT.git
cd CDS528_Chkin_NFT/packages/foundry
```

`lib/` 已包含本项目需要的 OpenZeppelin 源码，不需要再次运行 `forge install`。首次编译时 Foundry 按 `foundry.toml` 下载 Solidity 0.8.37，因此需要联网。前端运行时还需要访问 jsDelivr 加载 ethers；Google Fonts 不可达时使用字体回退。

## 2. 编译与测试

以下命令均在 `packages/foundry` 中执行：

```bash
forge build
forge test
forge test -vvv
```

可选的 Gas 报告：

```bash
forge test --gas-report
```

2026-11-14 使用 Foundry 1.8.5、Solidity 0.8.37 运行：**4 个测试套件，39 项通过，0 失败，0 跳过**。

同日还在临时 Anvil 链验证了部署脚本：四笔部署与两笔权限绑定交易均成功，并读回核对了 Token 地址、两项 manager 绑定及 owner。该检查不等于公开测试网部署。

| 测试套件 | 数量 | 覆盖内容 |
| --- | ---: | --- |
| ChallengeManagerTest | 15 | 参数、报名、时间窗口、打卡、结算、取消、退款和重复操作 |
| RewardPoolTest | 16 | 均分与余数、无人成功、零金额、权限、到账、重复结算和领取 |
| CheckInNFTTest | 5 | 铸造权限、唯一奖励、元数据、转移与枚举 |
| MockDepositTokenTest | 3 | 领取、转账和无限授权 |

测试通过不代表无漏洞。`forge build` 仍会给出时间戳、类型转换、重入/事件、舍入等 lint 提示，需要结合具体代码审查；本仓库没有提供已完成的 Slither 扫描或专业审计结论。

## 3. 本地链部署

在一个终端中启动 Anvil，保持进程运行：

```bash
anvil --host 127.0.0.1 --port 8545 --chain-id 31337
```

在另一个终端进入 `packages/foundry`，使用 Anvil 默认的第一个已解锁测试账户部署：

```bash
export LOCAL_RPC_URL=http://127.0.0.1:8545
export LOCAL_DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export NFT_BASE_URI=https://example.com/checkin/

forge script script/Deploy.s.sol:Deploy \
  --sig 'run(string)' "$NFT_BASE_URI" \
  --rpc-url "$LOCAL_RPC_URL" \
  --sender "$LOCAL_DEPLOYER" --unlocked --broadcast
```

`example.com` 仅为 URI 示例，不包含实际 NFT 元数据；演示元数据展示时应替换为自己托管的地址。部署脚本按顺序部署 Token → RewardPool → NFT → ChallengeManager，并由部署账户执行 `setChallengeManager` 与 `setManager`。四个返回地址的顺序为 `tokenAddress`、`poolAddress`、`nftAddress`、`managerAddress`。

交易记录保存在 `broadcast/Deploy.s.sol/31337/run-latest.json`，该生成目录已被 Git 忽略。每次重新执行脚本会部署一组新合约；重启无持久化的 Anvil 会清除链上状态，需要重新部署并更新前端配置。`--unlocked` 仅用于本地 Anvil。

## 4. Sepolia 部署与源码验证

使用一个只用于测试网的钱包，并准备 Sepolia 测试 ETH、Sepolia RPC URL 以及 Etherscan API key。CHECK 不是 Gas 代币，不能替代测试 ETH。

在 `packages/foundry` 中创建本地环境文件：

```bash
cp .env.example .env
```

编辑 `.env`，填写 `SEPOLIA_RPC_URL`、`ETHERSCAN_API_KEY`、`DEPLOYER_ADDRESS` 和 `NFT_BASE_URI`。`.env` 被忽略；私钥不要写入该文件、README 或 Git 仓库。用加密 keystore 导入测试钱包，命令会交互询问私钥和加密密码：

```bash
cast wallet import checkin-deployer --interactive
```

加载自己填写的 `.env`，确认链 ID 为 Sepolia 的 `11155111`，并确认部署地址有测试 ETH：

```bash
set -a
source .env
set +a
cast chain-id --rpc-url "$SEPOLIA_RPC_URL"
cast balance "$DEPLOYER_ADDRESS" --rpc-url "$SEPOLIA_RPC_URL"
```

先模拟，再部署。`DEPLOYER_ADDRESS` 必须与 `checkin-deployer` keystore 的公钥地址一致：

```bash
forge script script/Deploy.s.sol:Deploy \
  --sig 'run(string)' "$NFT_BASE_URI" \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --sender "$DEPLOYER_ADDRESS" --account checkin-deployer

forge script script/Deploy.s.sol:Deploy \
  --sig 'run(string)' "$NFT_BASE_URI" \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --sender "$DEPLOYER_ADDRESS" --account checkin-deployer \
  --broadcast --verify
```

第二个命令部署并向 Etherscan 提交源码验证，API key 从环境变量读取。部署与验证是不同步骤：若交易已成功但验证失败，不要为了重试验证重新部署；使用下方命令验证已有地址。若广播被中断，先核对 `broadcast/Deploy.s.sol/11155111/run-latest.json` 与链上交易状态，再按 Foundry 的 `--resume` 流程处理，避免重复部署。

将本次返回的地址填入变量，然后检查绑定：

```bash
export TOKEN_ADDRESS=0xYourTokenAddress
export POOL_ADDRESS=0xYourPoolAddress
export NFT_ADDRESS=0xYourNFTAddress
export MANAGER_ADDRESS=0xYourManagerAddress

cast call "$POOL_ADDRESS" 'challengeManager()(address)' --rpc-url "$SEPOLIA_RPC_URL"
cast call "$NFT_ADDRESS" 'manager()(address)' --rpc-url "$SEPOLIA_RPC_URL"
cast call "$MANAGER_ADDRESS" 'depositToken()(address)' --rpc-url "$SEPOLIA_RPC_URL"
```

前两项应返回 `MANAGER_ADDRESS`，第三项应返回 `TOKEN_ADDRESS`。这些 `0xYour...` 是必须替换的占位符，不能直接执行。单独验证四个已有合约：

```bash
forge verify-contract "$TOKEN_ADDRESS" contracts/MockDepositToken.sol:MockDepositToken \
  --chain sepolia --watch

forge verify-contract "$POOL_ADDRESS" contracts/RewardPool.sol:RewardPool \
  --constructor-args "$(cast abi-encode 'constructor(address)' "$TOKEN_ADDRESS")" \
  --chain sepolia --watch

forge verify-contract "$NFT_ADDRESS" contracts/CheckInNFT.sol:CheckInNFT \
  --constructor-args "$(cast abi-encode 'constructor(string)' "$NFT_BASE_URI")" \
  --chain sepolia --watch

forge verify-contract "$MANAGER_ADDRESS" contracts/ChallengeManager.sol:ChallengeManager \
  --constructor-args "$(cast abi-encode 'constructor(address,address,address)' "$TOKEN_ADDRESS" "$POOL_ADDRESS" "$NFT_ADDRESS")" \
  --chain sepolia --watch
```

保留原始编译设置及 NFT 构造参数，避免源码验证不匹配。完成后，把四个实际地址、部署交易及 `https://sepolia.etherscan.io/address/<实际地址>#code` 链接写入下表，报告引用相同记录。

| 网络 | 合约 | 地址与源码验证链接 |
| --- | --- | --- |
| Sepolia (11155111) | MockDepositToken | 尚未记录公开测试网部署 |
| Sepolia (11155111) | RewardPool | 尚未记录公开测试网部署 |
| Sepolia (11155111) | CheckInNFT | 尚未记录公开测试网部署 |
| Sepolia (11155111) | ChallengeManager | 尚未记录公开测试网部署 |

以上提供可复现部署方法，不表示已经完成公开测试网部署或源码验证。

## 5. 启动前端与使用

从仓库根目录运行：

```bash
python3 -m http.server 4173 --bind 127.0.0.1 --directory packages/web
```

访问 <http://localhost:4173>，不要直接打开 `file://.../index.html`。

1. 钱包切换到部署所在网络。Sepolia chain ID 为 `11155111`；本地 Anvil 为 `31337`，RPC 为 `http://127.0.0.1:8545`。
2. 本地演示时可导入 Anvil 输出的开发账户到专用测试钱包；这些默认账户的私钥是公开的，只能用于本地测试。
3. 连接钱包，点击设置，输入本次部署的 `managerAddress`，检测合约后保存。前端自动读取关联地址，配置按 chain ID 存储于浏览器 localStorage。
4. 领取测试 CHECK，创建未来开始的挑战，或在开始前加入已有挑战。报名时前端检查并请求 ERC-20 授权。
5. 挑战期间每日打卡；结束后发起结算，分别领取押金/NFT、成功者额外奖励或作者收益。取消挑战后走取消退款流程。

创建挑战的 `metadataURI` 应指向可公开读取的 HTTPS/IPFS JSON，至少可包含 `name`、`description`、`image`；HTTPS 服务需允许浏览器跨域读取。示例结构如下，URL 均需替换为真实资源：

```json
{
  "name": "Seven Day CheckIn",
  "description": "Complete the required daily on-chain check-ins.",
  "image": "https://example.com/checkin/reward.png"
}
```

可将 `packages/web` 作为站点根目录发布到静态托管服务；仓库根目录不是网页入口。详细前端说明见 [packages/web/README.md](packages/web/README.md)。

## 安全设计、权限与限制

- 使用 OpenZeppelin `SafeERC20`、`ReentrancyGuard` 和主动领取模式。状态与资格检查防止重复报名、重复领取、重复结算和越权操作。
- 挑战最多 50 人、最长 365 天；结算需要遍历参与者，规模受限，但仍需考虑 Gas。
- RewardPool 的 owner 只能绑定 ChallengeManager 一次，无任意提款功能。NFT owner 可更改 manager 和基础 URI，因此奖励铸造与元数据仍有管理信任假设。
- 没有紧急暂停或代理升级功能，选择简单的直接部署以减少配置复杂度；发现问题时需要停止使用旧部署并部署新实例，不能原地修复旧合约或暂停操作。
- CHECK 是可重复领取的测试代币；只支持普通、无转账手续费、非 rebasing 的 ERC-20。直接误转到奖励池的代币不会自动分配，也没有专用追回功能。
- 打卡证明的是链上交互，不能证明现实活动。NFT 可以转移，当前持有人未必是原完成者。多地址参与与作者激励属于经济机制限制。
- 本项目仅用于课程和测试网，不用于托管真实资产。

## 常见问题

| 问题 | 检查方式 |
| --- | --- |
| `forge` 找不到 | 重新打开 shell，确认 Foundry 的 bin 目录已加入 PATH |
| 编译器首次下载失败 | 检查网络以及 `foundry.toml` 中 Solidity 版本，保留部署时使用的设置 |
| 页面空白或 ethers 加载失败 | 用 HTTP 启动，检查浏览器控制台和 jsDelivr 网络访问 |
| 地址没有代码、合约检测失败 | 检查钱包网络、部署地址、Anvil 是否重启，以及 RewardPool 的绑定 |
| 报名失败 | 检查 CHECK 余额、授权、开始时间、人数限制和是否重复报名 |
| 打卡/结算失败 | 对照链上时间窗口；同一挑战日仅一次，结算必须在结束后 |
| 领取失败 | 检查资格、结算/取消状态、是否已领取；零额外奖励无需领取 |
| 元数据显示失败 | 检查 JSON、HTTPS/CORS 或 IPFS 网关可用性 |

## 来源、许可证与 AI 使用

项目 Solidity 源码以 SPDX `MIT` 声明许可证。随仓库提供的 OpenZeppelin 源码子集版本为 5.4.0，使用 MIT 许可证；保留源码头部声明，参见 [上游许可证](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.4.0/LICENSE)。前端从 CDN 加载的 ethers 6.15.0 使用 [MIT 许可证](https://github.com/ethers-io/ethers.js/blob/v6.15.0/LICENSE.md)。

本次仓库维护使用 OpenAI Codex 辅助比较目录、同步已有前端、编写 README 与部署脚本，并执行编译、测试和本地部署检查。此说明只覆盖本次维护，团队应在最终报告中补充此前实际的 AI 使用情况与人工复核记录。

参考资料（APA）：

- OpenZeppelin. (n.d.). *OpenZeppelin Contracts 5.x*. https://docs.openzeppelin.com/contracts/5.x/
- Foundry. (n.d.). *Foundry documentation*. https://getfoundry.sh/
- ethers. (n.d.). *ethers documentation v6*. https://docs.ethers.org/v6/
- Ethereum.org. (n.d.). *Ethereum development documentation*. https://ethereum.org/en/developers/docs/
- Solidity. (n.d.). *Solidity documentation*. https://docs.soliditylang.org/
