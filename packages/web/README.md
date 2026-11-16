# CheckIn Web

无需构建工具的 CheckIn 智能合约前端，使用原生 HTML、CSS、JavaScript 与 ethers v6。

## 本地启动

请通过 HTTP 服务访问，不要直接双击 `index.html`：

```bash
cd packages/web
python3 serve.py
```

然后打开 `http://127.0.0.1:4173`。这个启动脚本支持 `/create`、`/dashboard`、`/my-nfts` 和 `/challenges/:id` 的 SPA 路由回退。

## 首次配置

1. 在钱包中切换到 Sepolia（Chain ID `11155111`）或本地 Anvil（Chain ID `31337`）。
2. 点击右上角设置按钮。
3. 输入已部署的 `ChallengeManager` 地址。
4. 点击“检测合约”；页面会自动读取并验证 `RewardPool`、`MockDepositToken` 和 `CheckInNFT`。
5. 保存配置。配置按 chain ID 保存在浏览器 `localStorage` 中。

Sepolia 已内置正式的 `ChallengeManager` 地址：`0xDd265997a497Bc315136a958b6b7724dE0675Ed9`。连接 Sepolia 后页面会自动检测并加载整套合约。

## Sepolia 部署

| Contract | Address |
| --- | --- |
| CHECK Token | `0xAeDf8c2A37AceE087204d754DB44896703D8D7F2` |
| RewardPool | `0xC937e3Bae96d86C5E90DF2f14e47a9Fc0420a453` |
| CheckInNFT | `0xEcc6d8Ce6A99adFBe2dF576084967b2E0E7F65fB` |
| ChallengeManager | `0xDd265997a497Bc315136a958b6b7724dE0675Ed9` |

完整交易哈希和区块号记录在 `../foundry/deployments/11155111.json`。

## 已实现功能

- 钱包连接、网络和 CHECK/NFT 余额展示
- 挑战大厅、挑战详情、创建挑战、我的挑战和 My NFTs 路由
- 浏览、搜索、筛选、创建和取消链上挑战
- 在详情页分步完成 ERC-20 授权和加入挑战
- 使用合约 `canCheckIn()` 判断每日打卡状态，并显示下一次可打卡时间
- 到期公开结算、领取成功押金和奖励 NFT
- 领取成功押金和奖励 NFT
- 领取取消退款
- 作者收益和成功者额外奖励领取
- 固定钱包面板与 1,000 CHECK 测试代币水龙头
- NFT 枚举、IPFS/HTTPS 元数据和图片读取

## 部署

目录内全是静态文件，可部署到 Cloudflare Pages、Netlify、Vercel 或任意静态服务器。部署平台需要配置 SPA fallback，将未知路径重写到 `index.html`。线上页面还需要能够访问 `https://cdn.jsdelivr.net` 以加载 ethers v6。

## 注意事项

- 当前测试代币开放 `claim()`，只应在本地或测试网使用。
- 浏览器需要安装 MetaMask 或其他支持 EIP-1193 的 EVM 钱包。
- 合约中的“一天”从挑战开始时间起按连续 24 小时计算，不是本地自然日。
