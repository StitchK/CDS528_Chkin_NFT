import { BrowserProvider, Contract, formatUnits, getAddress, isAddress, parseUnits } from "https://cdn.jsdelivr.net/npm/ethers@6.15.0/+esm";

const MANAGER_ABI = [
  "function depositToken() view returns (address)",
  "function rewardPool() view returns (address)",
  "function rewardNft() view returns (address)",
  "function challengeCount() view returns (uint256)",
  "function getChallenge(uint256 challengeId) view returns (tuple(address author,uint256 depositAmount,uint64 startTime,uint64 endTime,uint32 durationDays,uint32 requiredCheckIns,uint32 maxParticipants,uint32 participantCount,uint8 status,string metadataURI))",
  "function getParticipant(uint256 challengeId,address participantAddress) view returns (tuple(bool joined,bool rewardClaimed,uint32 checkInCount,uint32 lastCheckInDayPlusOne))",
  "function canCheckIn(uint256 challengeId,address participantAddress) view returns (bool)",
  "function createChallenge(uint256 depositAmount,uint64 startTime,uint32 durationDays,uint32 requiredCheckIns,uint32 maxParticipants,string metadataURI) returns (uint256 challengeId)",
  "function joinChallenge(uint256 challengeId)",
  "function checkIn(uint256 challengeId)",
  "function finalizeChallenge(uint256 challengeId) returns (uint32 winnerCount)",
  "function claimSuccessfulParticipant(uint256 challengeId) returns (uint256 tokenId)",
  "function cancelChallenge(uint256 challengeId)",
  "function claimCancellationRefund(uint256 challengeId)",
];

const REWARD_POOL_ABI = [
  "function token() view returns (address)",
  "function challengeManager() view returns (address)",
  "function getUserReward(uint256 challengeId,address user) view returns (tuple(bool isAuthor,bool isWinner,uint256 authorReward,uint256 winnerReward,bool authorClaimed,bool winnerClaimed))",
  "function claimAuthorReward(uint256 challengeId)",
  "function claimWinnerReward(uint256 challengeId)",
];

const TOKEN_ABI = [
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function balanceOf(address account) view returns (uint256)",
  "function allowance(address owner,address spender) view returns (uint256)",
  "function approve(address spender,uint256 amount) returns (bool)",
  "function claim()",
];

const NFT_ABI = [
  "function manager() view returns (address)",
  "function balanceOf(address tokenOwner) view returns (uint256)",
  "function tokensOfOwner(address tokenOwner) view returns (uint256[])",
  "function challengeOfToken(uint256 tokenId) view returns (uint256)",
  "function tokenURI(uint256 tokenId) view returns (string)",
];

const STORAGE_KEY = "checkin.contracts.v1";
const LOCAL_CHAIN_ID = 31337;
const SEPOLIA_CHAIN_ID = 11155111;
const LOCAL_MANAGER_ADDRESS = "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9";
const SEPOLIA_MANAGER_ADDRESS = "0xDd265997a497Bc315136a958b6b7724dE0675Ed9";
const DEFAULT_MANAGER_ADDRESSES = {
  [LOCAL_CHAIN_ID]: LOCAL_MANAGER_ADDRESS,
  [SEPOLIA_CHAIN_ID]: SEPOLIA_MANAGER_ADDRESS,
};
const SUPPORTED_CHAIN_IDS = new Set(Object.keys(DEFAULT_MANAGER_ADDRESSES).map(Number));
const announcedWallets = [];

const state = {
  walletProvider: null,
  provider: null,
  signer: null,
  account: null,
  chainId: null,
  chainTimestamp: null,
  networkName: "未连接",
  contracts: {},
  config: null,
  decimals: 18,
  symbol: "CHECK",
  tokenBalance: 0n,
  challenges: [],
  rewards: [],
  nfts: [],
  activeFilter: "all",
  dashboardTab: "joined",
  route: { name: "explore", path: "/", challengeId: null },
  loading: false,
  refreshQueued: false,
};

const elements = {
  walletButton: document.querySelector("#walletButton"),
  walletButtonText: document.querySelector("#walletButtonText"),
  walletCardDot: document.querySelector("#walletCardDot"),
  walletCardBalance: document.querySelector("#walletCardBalance"),
  walletCardAddress: document.querySelector("#walletCardAddress"),
  walletDockChain: document.querySelector("#walletDockChain"),
  walletNetworkError: document.querySelector("#walletNetworkError"),
  challengeMetric: document.querySelector("#challengeMetric"),
  balanceMetric: document.querySelector("#balanceMetric"),
  nftMetric: document.querySelector("#nftMetric"),
  networkMetric: document.querySelector("#networkMetric"),
  networkStatusDot: document.querySelector("#networkStatusDot"),
  challengeCountBadge: document.querySelector("#challengeCountBadge"),
  refreshButton: document.querySelector("#refreshButton"),
  challengeGrid: document.querySelector("#challengeGrid"),
  challengeEmpty: document.querySelector("#challengeEmpty"),
  joinedGrid: document.querySelector("#joinedGrid"),
  joinedEmpty: document.querySelector("#joinedEmpty"),
  createdGrid: document.querySelector("#createdGrid"),
  createdEmpty: document.querySelector("#createdEmpty"),
  rewardList: document.querySelector("#rewardList"),
  rewardEmpty: document.querySelector("#rewardEmpty"),
  rewardCountBadge: document.querySelector("#rewardCountBadge"),
  claimableReward: document.querySelector("#claimableReward"),
  nftGrid: document.querySelector("#nftGrid"),
  nftEmpty: document.querySelector("#nftEmpty"),
  detailContent: document.querySelector("#detailContent"),
  setupNotice: document.querySelector("#setupNotice"),
  settingsModal: document.querySelector("#settingsModal"),
  managerAddress: document.querySelector("#managerAddress"),
  rewardPoolAddress: document.querySelector("#rewardPoolAddress"),
  tokenAddress: document.querySelector("#tokenAddress"),
  nftAddress: document.querySelector("#nftAddress"),
  transactionOverlay: document.querySelector("#transactionOverlay"),
  transactionTitle: document.querySelector("#transactionTitle"),
  transactionMessage: document.querySelector("#transactionMessage"),
  toastRegion: document.querySelector("#toastRegion"),
  createForm: document.querySelector("#createChallengeForm"),
};

window.addEventListener("eip6963:announceProvider", (event) => {
  const detail = event.detail;
  if (!detail?.provider || announcedWallets.some((wallet) => wallet.provider === detail.provider)) return;
  announcedWallets.push(detail);
});
window.dispatchEvent(new Event("eip6963:requestProvider"));

function shortenAddress(address, head = 6, tail = 4) {
  if (!address) return "—";
  return `${address.slice(0, head)}…${address.slice(-tail)}`;
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function formatDate(timestamp) {
  if (!timestamp) return "—";
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(Number(timestamp) * 1000));
}

function formatToken(value, maximumFractionDigits = 3) {
  if (value === null || value === undefined) return "—";
  const raw = formatUnits(value, state.decimals);
  const number = Number(raw);
  if (!Number.isFinite(number) || Math.abs(number) >= 1e12) return raw;
  return new Intl.NumberFormat("zh-CN", { maximumFractionDigits }).format(number);
}

function getStage(challenge) {
  const now = state.chainTimestamp || Math.floor(Date.now() / 1000);
  if (challenge.status === 1) return "settled";
  if (challenge.status === 2) return "cancelled";
  if (now < challenge.startTime) return "recruiting";
  if (now < challenge.endTime) return "active";
  return "ready";
}

const stageLabels = {
  recruiting: "未开始 · 可加入",
  active: "进行中",
  ready: "已结束 · 待结算",
  settled: "已结算",
  cancelled: "已取消",
};

function metadataFallback(uri, id) {
  if (!uri) return `挑战 #${id}`;
  try {
    const segment = decodeURIComponent(uri.split("?")[0].replace(/\/$/, "").split("/").pop() || "");
    const title = segment.replace(/\.(json|metadata)$/i, "").replaceAll(/[-_]/g, " ").trim();
    if (title && !/^Qm[a-zA-Z0-9]{40,}$/.test(title) && !/^bafy/i.test(title)) return title.slice(0, 48);
  } catch {
    return `挑战 #${id}`;
  }
  return `挑战 #${id}`;
}

function ipfsUrl(uri) {
  if (!uri) return null;
  if (uri.startsWith("ipfs://")) return `https://ipfs.io/ipfs/${uri.slice(7)}`;
  if (/^https?:\/\//i.test(uri)) return uri;
  return null;
}

async function fetchMetadata(uri, id) {
  const fallback = { name: metadataFallback(uri, id), description: "", image: null, loaded: false };
  const url = ipfsUrl(uri);
  if (!url) return fallback;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 4500);
  try {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) return fallback;
    const data = await response.json();
    return {
      name: typeof data.name === "string" && data.name.trim() ? data.name.trim().slice(0, 80) : fallback.name,
      description: typeof data.description === "string" ? data.description.trim().slice(0, 300) : "",
      image: typeof data.image === "string" ? ipfsUrl(data.image) : null,
      loaded: true,
    };
  } catch {
    return fallback;
  } finally {
    clearTimeout(timeout);
  }
}

function getStoredConfigs() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
  } catch {
    return {};
  }
}

function saveStoredConfig(config) {
  const configs = getStoredConfigs();
  configs[String(state.chainId)] = config;
  localStorage.setItem(STORAGE_KEY, JSON.stringify(configs));
}

function clearStoredConfig() {
  const configs = getStoredConfigs();
  delete configs[String(state.chainId)];
  localStorage.setItem(STORAGE_KEY, JSON.stringify(configs));
}

function toast(message, type = "success") {
  const item = document.createElement("div");
  item.className = `toast ${type}`;
  item.innerHTML = `<span>${type === "success" ? "✓" : "!"}</span><p>${escapeHtml(message)}</p>`;
  elements.toastRegion.append(item);
  setTimeout(() => item.remove(), 5200);
}

function readableError(error) {
  if (error?.code === 4001 || error?.code === "ACTION_REJECTED") return "你取消了钱包操作。";
  const message = error?.shortMessage || error?.reason || error?.info?.error?.message || error?.message || "未知错误";
  if (message.includes("user rejected")) return "你取消了钱包操作。";
  if (message.includes("insufficient funds")) return "钱包原生代币不足，无法支付 Gas。";
  if (message.includes("InsufficientAllowance")) return "CHECK 授权额度不足，请先完成第 1 步授权。";
  if (message.includes("InsufficientBalance")) return "CHECK 余额不足，请先从左下角水龙头领取。";
  if (message.includes("execution reverted")) {
    const reason = message.split("execution reverted")[1]?.replace(/^[: ]+/, "");
    return reason ? `合约拒绝了交易：${reason}` : "合约拒绝了这笔交易，请刷新并检查挑战状态。";
  }
  return message.length > 180 ? `${message.slice(0, 177)}…` : message;
}

function showTransaction(title, message = "请在钱包中检查并确认交易。") {
  elements.transactionTitle.textContent = title;
  elements.transactionMessage.textContent = message;
  elements.transactionOverlay.hidden = false;
}

function updateTransaction(title, message) {
  elements.transactionTitle.textContent = title;
  elements.transactionMessage.textContent = message;
}

function hideTransaction() {
  elements.transactionOverlay.hidden = true;
}

async function runTransaction({ title, send, success }) {
  try {
    showTransaction(title);
    const transaction = await send();
    updateTransaction("交易已提交", `正在等待区块确认：${shortenAddress(transaction.hash, 10, 8)}`);
    await transaction.wait();
    hideTransaction();
    toast(success);
    await refreshAll();
    return true;
  } catch (error) {
    hideTransaction();
    toast(readableError(error), "error");
    return false;
  }
}

async function getInjectedWallet() {
  window.dispatchEvent(new Event("eip6963:requestProvider"));
  await new Promise((resolve) => setTimeout(resolve, 150));
  const legacyProviders = Array.isArray(window.ethereum?.providers)
    ? window.ethereum.providers
    : window.ethereum
      ? [window.ethereum]
      : [];
  const candidates = [
    ...announcedWallets,
    ...legacyProviders.map((provider) => ({ provider, info: null })),
  ].filter((candidate, index, all) => all.findIndex((item) => item.provider === candidate.provider) === index);
  const inspected = await Promise.all(candidates.map(async (candidate) => {
    try {
      return { ...candidate, chainId: Number(await candidate.provider.request({ method: "eth_chainId" })) };
    } catch {
      return { ...candidate, chainId: null };
    }
  }));
  const isMetaMask = ({ provider, info }) => info?.rdns === "io.metamask" || (provider?.isMetaMask && !provider?.isBraveWallet);
  const selected = inspected.find((wallet) => isMetaMask(wallet) && SUPPORTED_CHAIN_IDS.has(wallet.chainId))
    || inspected.find((wallet) => SUPPORTED_CHAIN_IDS.has(wallet.chainId))
    || inspected.find(isMetaMask)
    || inspected[0];
  return selected?.provider || null;
}

function getNetworkLabel(chainId, fallbackName) {
  if (chainId === LOCAL_CHAIN_ID) return `Anvil Local · Chain ID ${LOCAL_CHAIN_ID}`;
  if (chainId === SEPOLIA_CHAIN_ID) return `Sepolia · Chain ID ${SEPOLIA_CHAIN_ID}`;
  if (chainId === 1) return "Ethereum Mainnet · Chain ID 1";
  const name = fallbackName === "unknown" ? "自定义网络" : fallbackName;
  return `${name} · Chain ID ${chainId}`;
}

async function switchToSepoliaNetwork() {
  if (!state.walletProvider) throw new Error("请先连接 MetaMask。");
  const chainId = `0x${SEPOLIA_CHAIN_ID.toString(16)}`;
  try {
    await state.walletProvider.request({ method: "wallet_switchEthereumChain", params: [{ chainId }] });
  } catch (error) {
    const errorCode = error?.code ?? error?.data?.originalError?.code;
    if (errorCode !== 4902) throw error;
    await state.walletProvider.request({
      method: "wallet_addEthereumChain",
      params: [{
        chainId,
        chainName: "Sepolia",
        nativeCurrency: { name: "Sepolia Ether", symbol: "ETH", decimals: 18 },
        rpcUrls: ["https://ethereum-sepolia-rpc.publicnode.com"],
        blockExplorerUrls: ["https://sepolia.etherscan.io"],
      }],
    });
  }
}

async function ensureSupportedNetwork() {
  if (SUPPORTED_CHAIN_IDS.has(state.chainId)) return true;
  showTransaction("切换到 Sepolia", `请在 MetaMask 中确认切换到 Chain ID ${SEPOLIA_CHAIN_ID}。`);
  await switchToSepoliaNetwork();
  await connectWallet(false);
  hideTransaction();
  return SUPPORTED_CHAIN_IDS.has(state.chainId);
}

function updateConnectionUI() {
  const connected = Boolean(state.account);
  const supported = connected && SUPPORTED_CHAIN_IDS.has(state.chainId);
  elements.walletButton.classList.toggle("connected", connected);
  elements.walletButtonText.textContent = connected ? shortenAddress(state.account) : "连接钱包";
  elements.walletCardAddress.textContent = connected ? shortenAddress(state.account, 8, 6) : "尚未连接";
  elements.walletCardDot.classList.toggle("online", connected);
  elements.networkStatusDot.classList.toggle("online", supported);
  elements.networkMetric.textContent = connected ? state.networkName : "未连接";
  elements.walletDockChain.textContent = connected ? `Chain ID ${state.chainId}` : "Chain ID —";
  elements.setupNotice.hidden = !connected || Boolean(state.config);
  elements.walletNetworkError.hidden = !connected || supported;
  elements.walletNetworkError.textContent = supported ? "" : `网络错误：请切换到 Sepolia（${SEPOLIA_CHAIN_ID}）或 Anvil Local（${LOCAL_CHAIN_ID}）`;
}

function resetDataUI() {
  elements.challengeMetric.textContent = "—";
  elements.balanceMetric.textContent = "—";
  elements.nftMetric.textContent = "—";
  elements.walletCardBalance.textContent = "— CHECK";
  elements.challengeCountBadge.textContent = "0";
  state.tokenBalance = 0n;
  state.challenges = [];
  state.rewards = [];
  state.nfts = [];
  renderChallenges();
  renderRewards();
  renderNfts();
  if (state.route.name === "detail") renderDetail();
}

async function connectWallet(requestAccess = true) {
  const walletProvider = await getInjectedWallet();
  if (!walletProvider) {
    toast("未检测到 EVM 钱包，请先安装 MetaMask 或兼容钱包。", "error");
    return false;
  }
  try {
    if (requestAccess) await walletProvider.request({ method: "eth_requestAccounts" });
    const provider = new BrowserProvider(walletProvider, "any");
    const accounts = await provider.send("eth_accounts", []);
    if (!accounts.length) return false;
    state.walletProvider = walletProvider;
    state.provider = provider;
    state.signer = await provider.getSigner();
    state.account = getAddress(accounts[0]);
    const network = await provider.getNetwork();
    state.chainId = Number(network.chainId);
    state.networkName = getNetworkLabel(state.chainId, network.name);
    const defaultManager = DEFAULT_MANAGER_ADDRESSES[state.chainId];
    state.config = getStoredConfigs()[String(state.chainId)]
      || (defaultManager ? { manager: defaultManager } : null);
    updateConnectionUI();
    if (state.config?.manager) {
      try {
        await loadContracts(state.config.manager, false);
      } catch (error) {
        state.config = null;
        state.contracts = {};
        resetDataUI();
        updateConnectionUI();
        toast(`已保存的合约配置不可用：${readableError(error)}`, "error");
        if (requestAccess) openSettings();
        return true;
      }
      await refreshAll();
    } else {
      resetDataUI();
      if (requestAccess) openSettings();
    }
    return true;
  } catch (error) {
    toast(readableError(error), "error");
    return false;
  }
}

async function requireConnection() {
  if (!state.account) return connectWallet(true);
  if (!SUPPORTED_CHAIN_IDS.has(state.chainId)) {
    try {
      return await ensureSupportedNetwork();
    } catch (error) {
      toast(readableError(error), "error");
      return false;
    }
  }
  return true;
}

async function discoverContracts(managerAddress) {
  if (!state.provider) throw new Error("请先连接钱包。");
  if (!isAddress(managerAddress)) throw new Error("ChallengeManager 地址格式不正确。");
  const managerTarget = getAddress(managerAddress);
  const managerCode = await state.provider.getCode(managerTarget);
  if (managerCode === "0x") throw new Error(`当前网络（Chain ID ${state.chainId}）在该地址没有合约代码。`);
  const manager = new Contract(managerTarget, MANAGER_ABI, state.provider);
  const [rewardPoolAddress, tokenAddress, nftAddress] = await Promise.all([
    manager.rewardPool(),
    manager.depositToken(),
    manager.rewardNft(),
  ]);
  const addresses = [rewardPoolAddress, tokenAddress, nftAddress].map(getAddress);
  const codes = await Promise.all(addresses.map((address) => state.provider.getCode(address)));
  if (codes.some((code) => code === "0x")) throw new Error("关联地址中存在未部署的合约。");
  const rewardPool = new Contract(addresses[0], REWARD_POOL_ABI, state.provider);
  const nft = new Contract(addresses[2], NFT_ABI, state.provider);
  const [configuredManager, poolToken, nftManager] = await Promise.all([
    rewardPool.challengeManager(),
    rewardPool.token(),
    nft.manager(),
  ]);
  if (configuredManager.toLowerCase() !== managerTarget.toLowerCase()) throw new Error("RewardPool 尚未绑定到这个 ChallengeManager。");
  if (poolToken.toLowerCase() !== addresses[1].toLowerCase()) throw new Error("RewardPool 与 ChallengeManager 使用的代币不一致。");
  if (nftManager.toLowerCase() !== managerTarget.toLowerCase()) throw new Error("CheckInNFT 尚未绑定到这个 ChallengeManager。");
  return { manager: managerTarget, rewardPool: addresses[0], token: addresses[1], nft: addresses[2] };
}

function displayDetectedConfig(config) {
  elements.rewardPoolAddress.textContent = config?.rewardPool || "等待读取";
  elements.tokenAddress.textContent = config?.token || "等待读取";
  elements.nftAddress.textContent = config?.nft || "等待读取";
}

async function detectFromSettings() {
  try {
    const connected = await requireConnection();
    if (!connected) return null;
    showTransaction("正在检测合约", "读取 ChallengeManager 及其关联地址…");
    const config = await discoverContracts(elements.managerAddress.value.trim());
    displayDetectedConfig(config);
    hideTransaction();
    toast("合约检测通过，可以保存配置。");
    return config;
  } catch (error) {
    hideTransaction();
    toast(readableError(error), "error");
    return null;
  }
}

async function loadContracts(managerAddress, persist = true) {
  const config = await discoverContracts(managerAddress);
  const runner = state.signer || state.provider;
  state.config = config;
  state.contracts = {
    manager: new Contract(config.manager, MANAGER_ABI, runner),
    rewardPool: new Contract(config.rewardPool, REWARD_POOL_ABI, runner),
    token: new Contract(config.token, TOKEN_ABI, runner),
    nft: new Contract(config.nft, NFT_ABI, runner),
  };
  const [decimals, symbol] = await Promise.all([state.contracts.token.decimals(), state.contracts.token.symbol()]);
  state.decimals = Number(decimals);
  state.symbol = symbol;
  if (persist) saveStoredConfig(config);
  elements.managerAddress.value = config.manager;
  displayDetectedConfig(config);
  elements.setupNotice.hidden = true;
  return config;
}

async function loadChallenges() {
  if (!state.contracts.manager) return;
  const [countValue, latestBlock] = await Promise.all([
    state.contracts.manager.challengeCount(),
    state.provider.getBlock("latest"),
  ]);
  const count = Number(countValue);
  state.chainTimestamp = Number(latestBlock.timestamp);
  const ids = Array.from({ length: count }, (_, index) => index + 1);
  const challenges = await Promise.all(ids.map(async (id) => {
    const [raw, participant] = await Promise.all([
      state.contracts.manager.getChallenge(id),
      state.account
        ? state.contracts.manager.getParticipant(id, state.account)
        : Promise.resolve({ joined: false, rewardClaimed: false, checkInCount: 0n, lastCheckInDayPlusOne: 0n }),
    ]);
    const challenge = {
      id,
      author: getAddress(raw.author),
      depositAmount: raw.depositAmount,
      startTime: Number(raw.startTime),
      endTime: Number(raw.endTime),
      durationDays: Number(raw.durationDays),
      requiredCheckIns: Number(raw.requiredCheckIns),
      maxParticipants: Number(raw.maxParticipants),
      participantCount: Number(raw.participantCount),
      status: Number(raw.status),
      metadataURI: raw.metadataURI,
      name: metadataFallback(raw.metadataURI, id),
      description: "",
      image: null,
      loaded: false,
      participant: {
        joined: participant.joined,
        rewardClaimed: participant.rewardClaimed,
        checkInCount: Number(participant.checkInCount),
        lastCheckInDayPlusOne: Number(participant.lastCheckInDayPlusOne),
      },
    };
    challenge.stage = getStage(challenge);
    challenge.isAuthor = state.account?.toLowerCase() === challenge.author.toLowerCase();
    challenge.isWinner = challenge.status === 1
      && challenge.participant.joined
      && challenge.participant.checkInCount >= challenge.requiredCheckIns;
    challenge.canCheckIn = false;
    if (state.account && challenge.stage === "active" && challenge.participant.joined) {
      try {
        challenge.canCheckIn = await state.contracts.manager.canCheckIn(id, state.account);
      } catch {
        challenge.canCheckIn = false;
      }
    }
    return challenge;
  }));
  state.challenges = challenges.reverse();
  elements.challengeMetric.textContent = String(count);
  elements.challengeCountBadge.textContent = String(count);
  challenges.forEach((challenge) => {
    fetchMetadata(challenge.metadataURI, challenge.id).then((metadata) => {
      Object.assign(challenge, metadata);
      renderChallenges();
      if (state.route.name === "detail" && state.route.challengeId === challenge.id) renderDetail();
    });
  });
}

async function loadWalletMetrics() {
  if (!state.account || !state.contracts.token) return;
  const [balance, nftBalance] = await Promise.all([
    state.contracts.token.balanceOf(state.account),
    state.contracts.nft.balanceOf(state.account),
  ]);
  state.tokenBalance = balance;
  const balanceText = formatToken(balance);
  elements.balanceMetric.textContent = `${balanceText} ${state.symbol}`;
  elements.walletCardBalance.textContent = `${balanceText} ${state.symbol}`;
  elements.nftMetric.textContent = String(nftBalance);
}

async function loadRewards() {
  if (!state.account || !state.contracts.rewardPool) return;
  const candidates = state.challenges.filter((challenge) => challenge.status === 1 || challenge.status === 2);
  const rewards = [];
  await Promise.all(candidates.map(async (challenge) => {
    if (challenge.status === 1) {
      const userReward = await state.contracts.rewardPool.getUserReward(challenge.id, state.account);
      if (userReward.isAuthor && userReward.authorReward > 0n && !userReward.authorClaimed) rewards.push({ challenge, type: "author", amount: userReward.authorReward, label: "作者收益" });
      if (userReward.isWinner && userReward.winnerReward > 0n && !userReward.winnerClaimed) rewards.push({ challenge, type: "winner", amount: userReward.winnerReward, label: "成功者额外奖励" });
      if (challenge.isWinner && !challenge.participant.rewardClaimed) rewards.push({ challenge, type: "success", amount: challenge.depositAmount, label: "押金与完成 NFT" });
    }
    if (challenge.status === 2 && challenge.participant.joined && !challenge.participant.rewardClaimed) rewards.push({ challenge, type: "refund", amount: challenge.depositAmount, label: "取消退款" });
  }));
  state.rewards = rewards.sort((a, b) => b.challenge.id - a.challenge.id);
}

async function loadNfts() {
  if (!state.account || !state.contracts.nft) {
    state.nfts = [];
    renderNfts();
    return;
  }
  const tokenIds = await state.contracts.nft.tokensOfOwner(state.account);
  state.nfts = await Promise.all([...tokenIds].reverse().map(async (tokenIdValue) => {
    const tokenId = Number(tokenIdValue);
    const [challengeIdValue, uri] = await Promise.all([
      state.contracts.nft.challengeOfToken(tokenId),
      state.contracts.nft.tokenURI(tokenId),
    ]);
    const challengeId = Number(challengeIdValue);
    const metadata = await fetchMetadata(uri, challengeId);
    return {
      tokenId,
      challengeId,
      uri,
      challenge: state.challenges.find((item) => item.id === challengeId) || null,
      ...metadata,
    };
  }));
  renderNfts();
}

async function refreshAll() {
  if (!state.config || !state.contracts.manager) return;
  if (state.loading) {
    state.refreshQueued = true;
    return;
  }
  state.loading = true;
  elements.refreshButton.disabled = true;
  try {
    const [challengesResult, metricsResult] = await Promise.allSettled([
      loadChallenges(),
      loadWalletMetrics(),
    ]);
    const errors = [];
    if (challengesResult.status === "rejected") errors.push(`挑战列表：${readableError(challengesResult.reason)}`);
    if (metricsResult.status === "rejected") errors.push(`钱包余额：${readableError(metricsResult.reason)}`);
    if (challengesResult.status === "fulfilled") {
      try {
        await loadRewards();
      } catch (error) {
        errors.push(`奖励：${readableError(error)}`);
      }
    }
    if (state.route.name === "nfts") {
      try {
        await loadNfts();
      } catch (error) {
        errors.push(`NFT：${readableError(error)}`);
      }
    }
    renderChallenges();
    renderRewards();
    if (state.route.name === "detail") await renderDetail();
    if (errors.length) {
      elements.walletNetworkError.hidden = false;
      elements.walletNetworkError.textContent = errors[0];
      toast(`部分链上数据读取失败：${errors.join("；")}`, "error");
    } else if (SUPPORTED_CHAIN_IDS.has(state.chainId)) {
      elements.walletNetworkError.hidden = true;
      elements.walletNetworkError.textContent = "";
    }
  } finally {
    state.loading = false;
    elements.refreshButton.disabled = false;
    if (state.refreshQueued) {
      state.refreshQueued = false;
      await refreshAll();
    }
  }
}

function challengeCard(challenge) {
  const progress = Math.min(100, Math.round((challenge.participant.checkInCount / challenge.requiredCheckIns) * 100) || 0);
  const accent = ["#eae6ff", "#e9f5cf", "#ffe8d9", "#dfeff0"][challenge.id % 4];
  return `
    <article class="challenge-card" style="--card-accent:${accent}">
      <div class="challenge-card-top"><span class="challenge-number">CHALLENGE #${challenge.id}</span><span class="status-pill ${challenge.stage}"><i></i>${stageLabels[challenge.stage]}</span></div>
      <h3>${escapeHtml(challenge.name)}</h3>
      <span class="challenge-author">by ${shortenAddress(challenge.author, 7, 5)}</span>
      <div class="card-stats">
        <div><span>押金</span><strong>${formatToken(challenge.depositAmount)} ${escapeHtml(state.symbol)}</strong></div>
        <div><span>目标</span><strong>${challenge.requiredCheckIns} / ${challenge.durationDays} 天</strong></div>
        <div><span>参与</span><strong>${challenge.participantCount} / ${challenge.maxParticipants}</strong></div>
      </div>
      <div class="card-dates"><span>${formatDate(challenge.startTime)}</span><i>→</i><span>${formatDate(challenge.endTime)}</span></div>
      ${challenge.participant.joined ? `<div class="challenge-progress"><div class="progress-label"><span>我的打卡进度</span><strong>${challenge.participant.checkInCount} / ${challenge.requiredCheckIns}</strong></div><div class="progress-track"><i style="width:${progress}%"></i></div></div>` : ""}
      <a class="card-action" href="/challenges/${challenge.id}" data-route="/challenges/${challenge.id}">查看详情</a>
    </article>`;
}

function visibleChallenges() {
  const query = document.querySelector("#challengeSearch").value.trim().toLowerCase();
  return state.challenges.filter((challenge) => {
    const filterMatch = state.activeFilter === "all"
      || (state.activeFilter === "settled" && ["ready", "settled", "cancelled"].includes(challenge.stage))
      || challenge.stage === state.activeFilter;
    const searchMatch = !query
      || String(challenge.id).includes(query)
      || challenge.author.toLowerCase().includes(query)
      || challenge.name.toLowerCase().includes(query);
    return filterMatch && searchMatch;
  });
}

function renderChallenges() {
  const publicChallenges = visibleChallenges();
  elements.challengeGrid.innerHTML = publicChallenges.map(challengeCard).join("");
  elements.challengeEmpty.hidden = publicChallenges.length > 0;
  const joined = state.challenges.filter((challenge) => challenge.participant.joined);
  const created = state.challenges.filter((challenge) => challenge.isAuthor);
  elements.joinedGrid.innerHTML = joined.map(challengeCard).join("");
  elements.joinedEmpty.hidden = joined.length > 0;
  elements.createdGrid.innerHTML = created.map(challengeCard).join("");
  elements.createdEmpty.hidden = created.length > 0;
}

function rewardActionLabel(type) {
  if (type === "success") return "领取押金 + NFT";
  if (type === "refund") return "领取退款";
  return "领取奖励";
}

function renderRewards() {
  const total = state.rewards.reduce((sum, reward) => sum + reward.amount, 0n);
  elements.claimableReward.textContent = state.account ? formatToken(total) : "—";
  elements.rewardCountBadge.textContent = String(state.rewards.length);
  elements.rewardList.innerHTML = state.rewards.map((reward) => `
    <article class="reward-item">
      <span class="reward-item-icon">${reward.type === "author" ? "↗" : reward.type === "winner" ? "✦" : reward.type === "refund" ? "↩" : "◇"}</span>
      <div><h4>${escapeHtml(reward.label)} · 挑战 #${reward.challenge.id}</h4><p>${escapeHtml(reward.challenge.name)}</p></div>
      <div class="reward-amount">${formatToken(reward.amount)} <small>${escapeHtml(state.symbol)}</small></div>
      <button type="button" data-reward-action="${reward.type}" data-id="${reward.challenge.id}">${rewardActionLabel(reward.type)}</button>
    </article>`).join("");
  elements.rewardEmpty.hidden = state.rewards.length > 0;
}

function renderNfts() {
  elements.nftGrid.innerHTML = state.nfts.map((nft) => {
    const duration = nft.challenge ? `${nft.challenge.durationDays} 天挑战` : "挑战信息不可用";
    const art = nft.image
      ? `<img src="${escapeHtml(nft.image)}" alt="${escapeHtml(nft.name)}" loading="lazy" />`
      : `<div class="nft-placeholder"><span>${String(nft.tokenId).padStart(2, "0")}</span><small>CHECKIN<br />REWARD</small></div>`;
    return `
      <article class="nft-card">
        <div class="nft-art">${art}<b>#${nft.tokenId}</b></div>
        <div class="nft-copy"><span>CHALLENGE #${nft.challengeId}</span><h3>${escapeHtml(nft.name)}</h3><p>${duration}</p><small class="${nft.loaded ? "loaded" : "failed"}">${nft.loaded ? "Metadata 已加载" : "Metadata 未加载，显示链上后备信息"}</small></div>
      </article>`;
  }).join("");
  elements.nftEmpty.hidden = state.nfts.length > 0;
}

function nextCheckInText(challenge) {
  if (!challenge.participant.joined || challenge.canCheckIn || !challenge.participant.lastCheckInDayPlusOne) return "";
  const nextTimestamp = challenge.startTime + challenge.participant.lastCheckInDayPlusOne * 86400;
  return `下一次可打卡：${formatDate(nextTimestamp)}`;
}

function checkedInCurrentDay(challenge) {
  if (challenge.stage !== "active" || !challenge.participant.lastCheckInDayPlusOne) return false;
  const dayPlusOne = Math.floor((state.chainTimestamp - challenge.startTime) / 86400) + 1;
  return challenge.participant.lastCheckInDayPlusOne === dayPlusOne;
}

function checkInStatusText(challenge) {
  if (challenge.stage === "recruiting") return "等待链上开始时间";
  if (challenge.stage !== "active" || !challenge.participant.joined) return "—";
  if (challenge.canCheckIn) return "今日可以打卡";
  if (checkedInCurrentDay(challenge)) return "今日已打卡";
  return "当前不可打卡";
}

function rewardButtonsForChallenge(challenge) {
  return state.rewards.filter((reward) => reward.challenge.id === challenge.id && ["author", "winner"].includes(reward.type)).map((reward) => `
    <button class="outline-button" type="button" data-reward-action="${reward.type}" data-id="${challenge.id}">${rewardActionLabel(reward.type)} · ${escapeHtml(reward.label)}</button>
  `).join("");
}

async function renderDetail() {
  const challenge = state.challenges.find((item) => item.id === Number(state.route.challengeId));
  if (!challenge) {
    elements.detailContent.innerHTML = `<div class="empty-state"><span class="empty-orbit">!</span><h3>没有找到挑战 #${escapeHtml(state.route.challengeId || "—")}</h3><p>请返回挑战大厅刷新链上数据。</p><a class="outline-button" href="/" data-route="/">返回大厅</a></div>`;
    return;
  }
  let allowance = 0n;
  if (state.account && state.contracts.token) {
    try {
      allowance = await state.contracts.token.allowance(state.account, state.config.manager);
    } catch {
      allowance = 0n;
    }
  }
  if (state.route.name !== "detail" || state.route.challengeId !== challenge.id) return;
  const hasBalance = state.tokenBalance >= challenge.depositAmount;
  const hasAllowance = allowance >= challenge.depositAmount;
  const progress = Math.min(100, Math.round((challenge.participant.checkInCount / challenge.requiredCheckIns) * 100) || 0);
  const actions = [];
  if (!state.account) {
    actions.push('<button class="primary-button" type="button" data-detail-action="connect">连接钱包</button>');
  } else if (challenge.stage === "recruiting" && !challenge.participant.joined) {
    actions.push(`
      <div class="join-flow">
        <div class="join-step ${hasAllowance ? "complete" : ""}"><span>1</span><div><strong>授权 ${formatToken(challenge.depositAmount)} ${escapeHtml(state.symbol)}</strong><small>${hasAllowance ? "授权额度已满足" : `当前 allowance：${formatToken(allowance)} ${escapeHtml(state.symbol)}`}</small></div><button class="outline-button" type="button" data-detail-action="approve" data-id="${challenge.id}" ${hasAllowance ? "disabled" : ""}>${hasAllowance ? "已授权" : "授权 CHECK"}</button></div>
        <div class="join-step ${challenge.participant.joined ? "complete" : ""}"><span>2</span><div><strong>支付押金并加入</strong><small>${hasBalance ? `余额：${formatToken(state.tokenBalance)} ${escapeHtml(state.symbol)}` : "余额不足，请先领取测试 CHECK"}</small></div><button class="primary-button small" type="button" data-detail-action="join" data-id="${challenge.id}" ${hasBalance && hasAllowance ? "" : "disabled"}>加入挑战</button></div>
        ${hasBalance ? "" : '<button class="faucet-inline" type="button" data-detail-action="faucet">领取 1,000 CHECK</button>'}
      </div>`);
  }
  if (challenge.stage === "recruiting" && challenge.participant.joined) actions.push('<button class="outline-button" type="button" disabled>已加入，等待挑战开始</button>');
  if (challenge.stage === "recruiting" && challenge.isAuthor) actions.push(`<button class="outline-button danger-border" type="button" data-detail-action="cancel" data-id="${challenge.id}">取消挑战</button>`);
  if (challenge.stage === "active" && challenge.participant.joined) actions.push(`<button class="primary-button" type="button" data-detail-action="checkin" data-id="${challenge.id}" ${challenge.canCheckIn ? "" : "disabled"}>${challenge.canCheckIn ? "立即打卡" : checkedInCurrentDay(challenge) ? "今日已打卡" : "当前不可打卡"}</button>`);
  if (challenge.stage === "active" && !challenge.participant.joined) actions.push('<button class="outline-button" type="button" disabled>加入窗口已关闭</button>');
  if (challenge.stage === "ready") actions.push(`<button class="primary-button" type="button" data-detail-action="finalize" data-id="${challenge.id}">结算挑战</button>`);
  if (challenge.stage === "settled" && challenge.isWinner && !challenge.participant.rewardClaimed) actions.push(`<button class="primary-button" type="button" data-detail-action="success" data-id="${challenge.id}">领取押金与奖励 NFT</button>`);
  if (challenge.stage === "cancelled" && challenge.participant.joined && !challenge.participant.rewardClaimed) actions.push(`<button class="primary-button" type="button" data-detail-action="refund" data-id="${challenge.id}">领取取消退款</button>`);
  actions.push(rewardButtonsForChallenge(challenge));
  elements.detailContent.innerHTML = `
    <div class="detail-page-head"><a href="/" data-route="/">← 返回挑战大厅</a><span class="status-pill ${challenge.stage}"><i></i>${stageLabels[challenge.stage]}</span></div>
    <div class="detail-title"><div><span>CHALLENGE #${challenge.id}</span><h2>${escapeHtml(challenge.name)}</h2><p>${challenge.description ? escapeHtml(challenge.description) : "这项挑战的目标与完成规则全部记录在链上。"}</p></div><div class="detail-author"><span>创建者</span><strong>${escapeHtml(shortenAddress(challenge.author, 10, 8))}${challenge.isAuthor ? "（我）" : ""}</strong></div></div>
    <div class="detail-banner"><div><span>每人押金</span><strong>${formatToken(challenge.depositAmount)} ${escapeHtml(state.symbol)}</strong></div><div><span>打卡目标</span><strong>${challenge.requiredCheckIns} / ${challenge.durationDays} 天</strong></div><div><span>参与人数</span><strong>${challenge.participantCount} / ${challenge.maxParticipants}</strong></div></div>
    <div class="detail-grid"><div class="detail-data"><span>开始时间</span><strong>${formatDate(challenge.startTime)}</strong></div><div class="detail-data"><span>结束时间</span><strong>${formatDate(challenge.endTime)}</strong></div><div class="detail-data"><span>我的身份</span><strong>${challenge.participant.joined ? "参与者" : "未参与"}${challenge.isAuthor ? " · 作者" : ""}</strong></div><div class="detail-data"><span>合约判断</span><strong>${checkInStatusText(challenge)}</strong><small>链上时间：${formatDate(state.chainTimestamp)}</small></div></div>
    ${challenge.participant.joined ? `<div class="detail-progress"><div class="progress-label"><span>我的挑战进度</span><strong>${challenge.participant.checkInCount} / ${challenge.requiredCheckIns} 天</strong></div><div class="progress-track"><i style="width:${progress}%"></i></div><small>${nextCheckInText(challenge)}</small></div>` : ""}
    <div class="detail-actions">${actions.filter(Boolean).join("") || '<button class="outline-button" type="button" disabled>当前没有可执行操作</button>'}</div>
    <p class="detail-uri">Metadata URI · ${escapeHtml(challenge.metadataURI)}</p>`;
}

async function approveChallenge(id) {
  const challenge = state.challenges.find((item) => item.id === Number(id));
  if (!challenge) return;
  await runTransaction({
    title: "授权 CHECK",
    send: () => state.contracts.token.approve(state.config.manager, challenge.depositAmount),
    success: `已授权挑战 #${id} 所需的 CHECK。`,
  });
}

async function joinChallenge(id) {
  const challenge = state.challenges.find((item) => item.id === Number(id));
  if (!challenge) return;
  try {
    const [balance, allowance] = await Promise.all([
      state.contracts.token.balanceOf(state.account),
      state.contracts.token.allowance(state.account, state.config.manager),
    ]);
    if (balance < challenge.depositAmount) throw new Error("CHECK 余额不足，请先从水龙头领取。");
    if (allowance < challenge.depositAmount) throw new Error("CHECK 授权额度不足，请先完成第 1 步授权。");
    await runTransaction({
      title: "支付押金并加入挑战",
      send: () => state.contracts.manager.joinChallenge(id),
      success: `已成功加入挑战 #${id}。`,
    });
  } catch (error) {
    toast(readableError(error), "error");
  }
}

async function performChallengeAction(action, id) {
  if (action === "connect") return connectWallet(true);
  if (action === "faucet") return claimTestTokens();
  const connected = await requireConnection();
  if (!connected || !state.contracts.manager) return;
  if (action === "approve") return approveChallenge(id);
  if (action === "join") return joinChallenge(id);
  const actions = {
    checkin: { title: "提交今日打卡", send: () => state.contracts.manager.checkIn(id), success: `挑战 #${id} 今日打卡成功。` },
    finalize: { title: "结算挑战", send: () => state.contracts.manager.finalizeChallenge(id), success: `挑战 #${id} 已完成结算。` },
    success: { title: "领取押金与 NFT", send: () => state.contracts.manager.claimSuccessfulParticipant(id), success: "押金已退回，奖励 NFT 已铸造。" },
    cancel: { title: "取消挑战", send: () => state.contracts.manager.cancelChallenge(id), success: `挑战 #${id} 已取消。` },
    refund: { title: "领取取消退款", send: () => state.contracts.manager.claimCancellationRefund(id), success: `挑战 #${id} 的押金已退回。` },
  };
  if (actions[action]) await runTransaction(actions[action]);
}

async function performRewardAction(type, id) {
  const connected = await requireConnection();
  if (!connected) return;
  if (type === "success" || type === "refund") return performChallengeAction(type, id);
  const config = type === "author"
    ? { title: "领取作者收益", send: () => state.contracts.rewardPool.claimAuthorReward(id), success: `挑战 #${id} 的作者收益已到账。` }
    : { title: "领取成功者奖励", send: () => state.contracts.rewardPool.claimWinnerReward(id), success: `挑战 #${id} 的成功者奖励已到账。` };
  await runTransaction(config);
}

async function createChallenge(event) {
  event.preventDefault();
  const connected = await requireConnection();
  if (!connected || !state.contracts.manager) {
    if (connected) openSettings();
    return;
  }
  const form = new FormData(elements.createForm);
  const metadataURI = String(form.get("metadataURI")).trim();
  const startTimestamp = Math.floor(new Date(form.get("startTime")).getTime() / 1000);
  const durationDays = Number(form.get("durationDays"));
  const requiredCheckIns = Number(form.get("requiredCheckIns"));
  const maxParticipants = Number(form.get("maxParticipants"));
  if (!metadataURI) return toast("Metadata URI 不能为空。", "error");
  if (!Number.isFinite(startTimestamp) || startTimestamp <= Math.floor(Date.now() / 1000)) return toast("开始时间必须晚于当前时间。", "error");
  if (!Number.isInteger(durationDays) || durationDays < 1 || durationDays > 365) return toast("持续天数必须在 1 到 365 之间。", "error");
  if (!Number.isInteger(requiredCheckIns) || requiredCheckIns < 1 || requiredCheckIns > durationDays) return toast("打卡天数必须在 1 到持续天数之间。", "error");
  if (!Number.isInteger(maxParticipants) || maxParticipants < 1 || maxParticipants > 50) return toast("参与人数必须在 1 到 50 之间。", "error");
  let depositAmount;
  try {
    depositAmount = parseUnits(String(form.get("depositAmount")), state.decimals);
    if (depositAmount <= 0n) throw new Error();
  } catch {
    return toast("押金必须大于 0。", "error");
  }
  const completed = await runTransaction({
    title: "发布挑战",
    send: () => state.contracts.manager.createChallenge(depositAmount, startTimestamp, durationDays, requiredCheckIns, maxParticipants, metadataURI),
    success: "新挑战已经发布到链上。",
  });
  if (completed) {
    elements.createForm.reset();
    setCreateDefaults();
    navigate("/");
  }
}

async function claimTestTokens() {
  const connected = await requireConnection();
  if (!connected) return;
  if (!state.contracts.token) {
    openSettings();
    return;
  }
  await runTransaction({
    title: "领取 1,000 CHECK",
    send: () => state.contracts.token.claim(),
    success: `1,000 ${state.symbol} 已到账。`,
  });
}

function parseRoute(pathname = window.location.pathname) {
  const normalized = pathname.length > 1 ? pathname.replace(/\/$/, "") : "/";
  const detailMatch = normalized.match(/^\/challenges\/(\d+)$/);
  if (detailMatch) return { name: "detail", path: normalized, challengeId: Number(detailMatch[1]) };
  if (normalized === "/create") return { name: "create", path: normalized, challengeId: null };
  if (normalized === "/dashboard") return { name: "dashboard", path: normalized, challengeId: null };
  if (normalized === "/my-nfts") return { name: "nfts", path: normalized, challengeId: null };
  return { name: "explore", path: "/", challengeId: null };
}

async function applyRoute() {
  state.route = parseRoute();
  const viewId = {
    explore: "exploreView",
    create: "createView",
    dashboard: "dashboardView",
    detail: "detailView",
    nfts: "nftsView",
  }[state.route.name];
  document.querySelectorAll(".view").forEach((view) => view.classList.toggle("active", view.id === viewId));
  document.body.classList.toggle("route-home", state.route.name === "explore");
  document.querySelectorAll("[data-route]").forEach((link) => {
    const route = link.dataset.route;
    const active = route === state.route.path || (state.route.name === "detail" && route === "/");
    link.classList.toggle("active", active);
  });
  if (state.route.name === "detail") await renderDetail();
  if (state.route.name === "nfts" && state.contracts.nft) await loadNfts();
  window.scrollTo({ top: state.route.name === "explore" ? 0 : document.querySelector(".protocol-strip").offsetTop, behavior: "smooth" });
}

function navigate(path) {
  if (window.location.pathname !== path) history.pushState({}, "", path);
  applyRoute();
}

function openSettings() {
  if (state.config) {
    elements.managerAddress.value = state.config.manager;
    displayDetectedConfig(state.config);
  }
  if (!elements.settingsModal.open) elements.settingsModal.showModal();
}

function setCreateDefaults() {
  const start = new Date(Date.now() + 60 * 60 * 1000);
  start.setMinutes(start.getMinutes() - start.getTimezoneOffset());
  document.querySelector("#startTime").value = start.toISOString().slice(0, 16);
  document.querySelector("#durationDays").value = "21";
  document.querySelector("#requiredCheckIns").value = "18";
  document.querySelector("#maxParticipants").value = "20";
  const defaultReward = document.querySelector('[name="rewardTemplate"][value="wave"]');
  if (defaultReward) {
    defaultReward.checked = true;
    applyRewardTemplate(defaultReward);
  }
  updateCreatePreview();
}

function applyRewardTemplate(input) {
  if (!input) return;
  const metadataInput = document.querySelector("#metadataURI");
  const previewImage = document.querySelector("#previewRewardImage");
  metadataInput.value = new URL(input.dataset.metadata, window.location.origin).href;
  previewImage.src = new URL(input.dataset.image, window.location.origin).href;
}

function updateCreatePreview() {
  const deposit = document.querySelector("#depositAmount").value || "—";
  const duration = document.querySelector("#durationDays").value || "—";
  const required = document.querySelector("#requiredCheckIns").value || "—";
  const people = document.querySelector("#maxParticipants").value || "—";
  document.querySelector("#previewDeposit").textContent = `${deposit} ${state.symbol}`;
  document.querySelector("#previewDays").textContent = `${required} / ${duration} 天`;
  document.querySelector("#previewPeople").textContent = `最多 ${people} 人`;
  document.querySelector("#maxParticipantsOutput").textContent = `${people} 人`;
  document.querySelector("#previewDuration").textContent = duration;
}

function switchDashboardTab(tab) {
  state.dashboardTab = tab;
  document.querySelectorAll("[data-dashboard-tab]").forEach((button) => button.classList.toggle("active", button.dataset.dashboardTab === tab));
  document.querySelectorAll(".dashboard-panel").forEach((panel) => panel.classList.toggle("active", panel.id === `${tab}Panel`));
}

function bindEvents() {
  elements.walletButton.addEventListener("click", () => connectWallet(true));
  document.querySelector("#settingsButton").addEventListener("click", async () => {
    if (!state.account) await connectWallet(true);
    openSettings();
  });
  document.querySelector("#walletDockSettings").addEventListener("click", openSettings);
  document.querySelector("#setupNoticeButton").addEventListener("click", openSettings);
  document.querySelector("#howItWorksButton").addEventListener("click", () => document.querySelector("#howItWorks").scrollIntoView({ behavior: "smooth" }));
  document.querySelector("#challengeSearch").addEventListener("input", renderChallenges);
  document.querySelector("#refreshButton").addEventListener("click", refreshAll);
  document.querySelector("#refreshDashboardButton").addEventListener("click", refreshAll);
  document.querySelector("#refreshNftsButton").addEventListener("click", loadNfts);
  document.querySelector("#claimTestTokenButton").addEventListener("click", claimTestTokens);
  document.querySelectorAll(".filter").forEach((button) => button.addEventListener("click", () => {
    state.activeFilter = button.dataset.filter;
    document.querySelectorAll(".filter").forEach((item) => item.classList.toggle("active", item === button));
    renderChallenges();
  }));
  document.querySelectorAll("[data-dashboard-tab]").forEach((button) => button.addEventListener("click", () => switchDashboardTab(button.dataset.dashboardTab)));
  document.addEventListener("click", (event) => {
    const routeLink = event.target.closest("[data-route]");
    if (routeLink) {
      event.preventDefault();
      navigate(routeLink.dataset.route);
      return;
    }
    const detailAction = event.target.closest("[data-detail-action]");
    if (detailAction) performChallengeAction(detailAction.dataset.detailAction, Number(detailAction.dataset.id));
    const rewardAction = event.target.closest("[data-reward-action]");
    if (rewardAction) performRewardAction(rewardAction.dataset.rewardAction, Number(rewardAction.dataset.id));
  });
  window.addEventListener("popstate", applyRoute);
  document.querySelector("#detectContractsButton").addEventListener("click", detectFromSettings);
  document.querySelector("#saveConfigButton").addEventListener("click", async () => {
    try {
      const connected = await requireConnection();
      if (!connected) return;
      showTransaction("保存合约配置", "正在验证并读取合约…");
      await loadContracts(elements.managerAddress.value.trim(), true);
      await refreshAll();
      hideTransaction();
      elements.settingsModal.close();
      toast("合约配置已保存。");
    } catch (error) {
      hideTransaction();
      toast(readableError(error), "error");
    }
  });
  document.querySelector("#clearConfigButton").addEventListener("click", () => {
    clearStoredConfig();
    state.config = null;
    state.contracts = {};
    elements.managerAddress.value = "";
    displayDetectedConfig(null);
    resetDataUI();
    updateConnectionUI();
    toast("当前网络的合约配置已清除。");
  });
  elements.createForm.addEventListener("submit", createChallenge);
  ["depositAmount", "durationDays", "requiredCheckIns", "maxParticipants"].forEach((id) => document.querySelector(`#${id}`).addEventListener("input", updateCreatePreview));
  document.querySelectorAll('[name="rewardTemplate"]').forEach((input) => input.addEventListener("change", () => applyRewardTemplate(input)));
  document.querySelector("#metadataURI").addEventListener("input", (event) => {
    const selected = document.querySelector('[name="rewardTemplate"]:checked');
    if (!selected) return;
    const selectedUri = new URL(selected.dataset.metadata, window.location.origin).href;
    if (event.target.value !== selectedUri) selected.checked = false;
  });
  elements.settingsModal.addEventListener("click", (event) => {
    if (event.target === elements.settingsModal) elements.settingsModal.close();
  });
}

async function initialize() {
  bindEvents();
  setCreateDefaults();
  updateConnectionUI();
  resetDataUI();
  await applyRoute();
  const walletProvider = await getInjectedWallet();
  if (walletProvider) {
    walletProvider.on?.("accountsChanged", async (accounts) => {
      if (!accounts.length) {
        state.account = null;
        state.signer = null;
        state.contracts = {};
        updateConnectionUI();
        resetDataUI();
        return;
      }
      await connectWallet(false);
    });
    walletProvider.on?.("chainChanged", () => window.location.reload());
    await connectWallet(false);
  }
}

initialize();
