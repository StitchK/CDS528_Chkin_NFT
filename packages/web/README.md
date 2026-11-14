# CheckIn Web

无需构建工具的 CheckIn 智能合约前端，使用原生 HTML、CSS、JavaScript 与 ethers v6。

## 本地启动

请通过 HTTP 服务访问，不要直接双击 `index.html`：

```bash
cd packages/web
python3 -m http.server 4173
```

然后打开 `http://localhost:4173`。

## 首次配置

1. 在钱包中切换到合约部署所在网络。
2. 点击右上角设置按钮。
3. 输入已部署的 `ChallengeManager` 地址。
4. 点击“检测合约”；页面会自动读取并验证 `RewardPool`、`MockDepositToken` 和 `CheckInNFT`。
5. 保存配置。配置按 chain ID 保存在浏览器 `localStorage` 中。

## 已实现功能

- 钱包连接、网络和 CHECK/NFT 余额展示
- 浏览、搜索和筛选链上挑战
- 创建、取消、报名挑战
- 自动检查并发起 ERC-20 押金授权
- 每日打卡、到期公开结算
- 领取成功押金和奖励 NFT
- 领取取消退款
- 作者收益和成功者额外奖励领取
- 测试 CHECK 代币领取
- IPFS/HTTPS 元数据名称和描述读取

## 部署

目录内全是静态文件，可直接部署到 GitHub Pages、Cloudflare Pages、Netlify、Vercel 或任意静态服务器。线上页面需要能够访问 `https://cdn.jsdelivr.net` 以加载 ethers v6。

## 注意事项

- 当前测试代币开放 `claim()`，只应在本地或测试网使用。
- 浏览器需要安装 MetaMask 或其他支持 EIP-1193 的 EVM 钱包。
- 合约中的“一天”从挑战开始时间起按连续 24 小时计算，不是本地自然日。
