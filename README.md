# CheckIn NFT

CheckIn 是一个基于 EVM 的押金式打卡挑战 DApp。用户锁定 CHECK 代币参与挑战，完成打卡后取回押金、分享奖励，并获得完成 NFT。

## Sepolia 部署

项目已部署到 Sepolia（Chain ID `11155111`）：

| Contract | Address |
| --- | --- |
| CHECK Token | [`0xAeDf8c2A37AceE087204d754DB44896703D8D7F2`](https://sepolia.etherscan.io/address/0xAeDf8c2A37AceE087204d754DB44896703D8D7F2) |
| RewardPool | [`0xC937e3Bae96d86C5E90DF2f14e47a9Fc0420a453`](https://sepolia.etherscan.io/address/0xC937e3Bae96d86C5E90DF2f14e47a9Fc0420a453) |
| CheckInNFT | [`0xEcc6d8Ce6A99adFBe2dF576084967b2E0E7F65fB`](https://sepolia.etherscan.io/address/0xEcc6d8Ce6A99adFBe2dF576084967b2E0E7F65fB) |
| ChallengeManager | [`0xDd265997a497Bc315136a958b6b7724dE0675Ed9`](https://sepolia.etherscan.io/address/0xDd265997a497Bc315136a958b6b7724dE0675Ed9) |

部署记录位于 `packages/foundry/deployments/11155111.json`。

## 前端

静态前端位于 `packages/web`，无需构建步骤。它支持钱包连接、挑战创建与报名、每日打卡、结算、押金/NFT 领取和奖励领取。

本地预览：

```bash
cd packages/web
python3 serve.py
```

打开 `http://127.0.0.1:4173`。连接 Sepolia 后，网页会自动载入已部署的合约。

## 合约开发

```bash
cd packages/foundry
forge build --optimize --optimizer-runs 200
forge test --optimize --optimizer-runs 200
```

合约使用 Solidity `0.8.37`，完整测试覆盖挑战生命周期、奖励分配、NFT 和测试代币功能。
