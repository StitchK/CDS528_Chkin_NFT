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
  "event ChallengeCreated(uint256 indexed challengeId,address indexed author,uint256 depositAmount,uint64 startTime,uint64 endTime,uint32 requiredCheckIns,uint32 maxParticipants,string metadataURI)",
];

const REWARD_POOL_ABI = [
  "function token() view returns (address)",
  "function challengeManager() view returns (address)",
  "function getPoolInfo(uint256 challengeId) view returns (tuple(address author,uint256 totalDeposited,uint256 authorReward,uint256 winnerCount,uint256 rewardPerWinner,uint256 remainingRewards,bool settled,bool authorClaimed))",
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
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address tokenOwner) view returns (uint256)",
  "function rewardToken(address participant,uint256 challengeId) view returns (uint256)",
  "function tokenURI(uint256 tokenId) view returns (string)",
];

const STORAGE_KEY = "checkin.contracts.v1";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const state = {
  provider: null,
  signer: null,
  account: null,
  chainId: null,
  networkName: "未连接",
  contracts: {},
  config: null,
  decimals: 18,
  symbol: "CHECK",
  challenges: [],
  rewards: [],
  activeFilter: "all",
  currentChallengeId: null,
  loading: false,
};

const elements = {
  walletButton: document.querySelector("#walletButton"),
  walletButtonText: document.querySelector("#walletButtonText"),
  walletCardDot: document.querySelector("#walletCardDot"),
  walletCardBalance: document.querySelector("#walletCardBalance"),
  walletCardAddress: document.querySelector("#walletCardAddress"),
  challengeMetric: document.querySelector("#challengeMetric"),
  balanceMetric: document.querySelector("#balanceMetric"),
  nftMetric: document.querySelector("#nftMetric"),
  networkMetric: document.querySelector("#networkMetric"),
  networkStatusDot: document.querySelector("#networkStatusDot"),
  challengeCountBadge: document.querySelector("#challengeCountBadge"),
  challengeGrid: document.querySelector("#challengeGrid"),
  challengeEmpty: document.querySelector("#challengeEmpty"),
  mineGrid: document.querySelector("#mineGrid"),
  mineEmpty: document.querySelector("#mineEmpty"),
  rewardList: document.querySelector("#rewardList"),
  rewardEmpty: document.querySelector("#rewardEmpty"),
  claimableReward: document.querySelector("#claimableReward"),
  setupNotice: document.querySelector("#setupNotice"),
  settingsModal: document.querySelector("#settingsModal"),
  detailModal: document.querySelector("#detailModal"),
  detailKicker: document.querySelector("#detailKicker"),
  detailTitle: document.querySelector("#detailTitle"),
  detailContent: document.querySelector("#detailContent"),
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

function getStage(challenge) {
  const now = Math.floor(Date.now() / 1000);
  if (challenge.status === 1) return "settled";
  if (challenge.status === 2) return "cancelled";
  if (now < challenge.startTime) return "recruiting";
  if (now < challenge.endTime) return "active";
  return "ready";
}

const stageLabels = {
  recruiting: "招募中",
  active: "进行中",
  ready: "待结算",
  settled: "已结束",
  cancelled: "已取消",
};

function metadataFallback(uri, id) {
  if (!uri) return `挑战 #${id}`;
  try {
    const clean = uri.split("?")[0].replace(/\/$/, "");
    const segment = decodeURIComponent(clean.split("/").pop() || "");
    const title = segment.replace(/\.(json|metadata)$/i, "").replaceAll(/[-_]/g, " ").trim();
    if (title && !/^Qm[a-zA-Z0-9]{40,}$/.test(title) && !/^bafy/i.test(title)) {
      return title.slice(0, 48);
    }
  } catch {
    return `挑战 #${id}`;
  }
  return `挑战 #${id}`;
}

function metadataUrl(uri) {
  if (uri.startsWith("ipfs://")) return `https://ipfs.io/ipfs/${uri.slice(7)}`;
  if (/^https:\/\//i.test(uri)) return uri;
  return null;
}

async function fetchMetadata(uri, id) {
  const fallback = { name: metadataFallback(uri, id), description: "" };
  const url = metadataUrl(uri);
  if (!url) return fallback;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 3500);
  try {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) return fallback;
    const data = await response.json();
    return {
      name: typeof data.name === "string" && data.name.trim() ? data.name.trim().slice(0, 80) : fallback.name,
      description: typeof data.description === "string" ? data.description.trim().slice(0, 240) : "",
    };
  } catch {
    return fallback;
  } finally {
    clearTimeout(timeout);
  }
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
  if (message.includes("execution reverted")) {
    const reason = message.split("execution reverted")[1]?.replace(/^[: ]+/, "");
    return reason ? `合约拒绝了交易：${reason}` : "合约拒绝了这笔交易，请检查当前状态。";
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
    toast(success);
    hideTransaction();
    await refreshAll();
    return true;
  } catch (error) {
    hideTransaction();
    toast(readableError(error), "error");
    return false;
  }
}

function updateConnectionUI() {
  const connected = Boolean(state.account);
  elements.walletButton.classList.toggle("connected", connected);
  elements.walletButtonText.textContent = connected ? shortenAddress(state.account) : "连接钱包";
  elements.walletCardAddress.textContent = connected ? shortenAddress(state.account, 8, 6) : "尚未连接";
  elements.walletCardDot.classList.toggle("online", connected);
  elements.networkStatusDot.classList.toggle("online", connected);
  elements.networkMetric.textContent = connected ? state.networkName : "未连接";
  elements.setupNotice.hidden = !connected || Boolean(state.config);
}

function resetDataUI() {
  elements.challengeMetric.textContent = "—";
  elements.balanceMetric.textContent = "—";
  elements.nftMetric.textContent = "—";
  elements.walletCardBalance.textContent = "— CHECK";
  elements.challengeCountBadge.textContent = "0";
  state.challenges = [];
  state.rewards = [];
  renderChallenges();
  renderRewards();
}

async function connectWallet(requestAccess = true) {
  if (!window.ethereum) {
    toast("未检测到 EVM 钱包，请先安装 MetaMask 或兼容钱包。", "error");
    return false;
  }

  try {
    if (requestAccess) await window.ethereum.request({ method: "eth_requestAccounts" });
    const provider = new BrowserProvider(window.ethereum);
    const accounts = await provider.send("eth_accounts", []);
    if (!accounts.length) return false;

    state.provider = provider;
    state.signer = await provider.getSigner();
    state.account = getAddress(accounts[0]);
    const network = await provider.getNetwork();
    state.chainId = Number(network.chainId);
    state.networkName = network.name === "unknown" ? `Chain ${state.chainId}` : network.name;

    const config = getStoredConfigs()[String(state.chainId)] || null;
    state.config = config;
    updateConnectionUI();

    if (config?.manager) {
      try {
        await loadContracts(config.manager, false);
        await refreshAll();
      } catch (error) {
        state.config = null;
        state.contracts = {};
        resetDataUI();
        updateConnectionUI();
        toast(`已保存的合约配置不可用：${readableError(error)}`, "error");
        if (requestAccess) openSettings();
      }
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
  return true;
}

async function discoverContracts(managerAddress) {
  if (!state.provider) throw new Error("请先连接钱包。 ");
  if (!isAddress(managerAddress)) throw new Error("ChallengeManager 地址格式不正确。 ");

  const manager = new Contract(getAddress(managerAddress), MANAGER_ABI, state.provider);
  const [managerCode, rewardPoolAddress, tokenAddress, nftAddress] = await Promise.all([
    state.provider.getCode(manager.target),
    manager.rewardPool(),
    manager.depositToken(),
    manager.rewardNft(),
  ]);

  if (managerCode === "0x") throw new Error("该地址没有合约代码。 ");
  const addresses = [rewardPoolAddress, tokenAddress, nftAddress].map(getAddress);
  const codes = await Promise.all(addresses.map((address) => state.provider.getCode(address)));
  if (codes.some((code) => code === "0x")) throw new Error("关联地址中存在未部署的合约。 ");

  const rewardPool = new Contract(addresses[0], REWARD_POOL_ABI, state.provider);
  const [configuredManager, poolToken] = await Promise.all([rewardPool.challengeManager(), rewardPool.token()]);
  if (configuredManager.toLowerCase() !== manager.target.toLowerCase()) {
    throw new Error("RewardPool 尚未绑定到这个 ChallengeManager。 ");
  }
  if (poolToken.toLowerCase() !== addresses[1].toLowerCase()) {
    throw new Error("RewardPool 与 ChallengeManager 使用的代币不一致。 ");
  }

  return {
    manager: getAddress(manager.target),
    rewardPool: addresses[0],
    token: addresses[1],
    nft: addresses[2],
  };
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
    toast("合约检测通过，可以保存配置。 ");
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

  const [decimals, symbol] = await Promise.all([
    state.contracts.token.decimals(),
    state.contracts.token.symbol(),
  ]);
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
  const count = Number(await state.contracts.manager.challengeCount());
  const ids = Array.from({ length: count }, (_, index) => index + 1);

  const challenges = await Promise.all(ids.map(async (id) => {
    const [raw, participant] = await Promise.all([
      state.contracts.manager.getChallenge(id),
      state.account
        ? state.contracts.manager.getParticipant(id, state.account)
        : Promise.resolve({ joined: false, rewardClaimed: false, checkInCount: 0n, lastCheckInDayPlusOne: 0n }),
    ]);
    const metadata = await fetchMetadata(raw.metadataURI, id);
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
      name: metadata.name,
      description: metadata.description,
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
    challenge.canCheckIn = challenge.stage === "active"
      && challenge.participant.joined
      && challenge.participant.lastCheckInDayPlusOne !== Math.floor((Date.now() / 1000 - challenge.startTime) / 86400) + 1;
    return challenge;
  }));

  state.challenges = challenges.reverse();
  elements.challengeMetric.textContent = String(count);
  elements.challengeCountBadge.textContent = String(count);
}

async function loadWalletMetrics() {
  if (!state.account || !state.contracts.token) return;
  const [balance, nftBalance] = await Promise.all([
    state.contracts.token.balanceOf(state.account),
    state.contracts.nft.balanceOf(state.account),
  ]);
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
      if (userReward.isAuthor && userReward.authorReward > 0n && !userReward.authorClaimed) {
        rewards.push({ challenge, type: "author", amount: userReward.authorReward, label: "作者收益" });
      }
      if (userReward.isWinner && userReward.winnerReward > 0n && !userReward.winnerClaimed) {
        rewards.push({ challenge, type: "winner", amount: userReward.winnerReward, label: "成功者奖励" });
      }
      if (challenge.isWinner && !challenge.participant.rewardClaimed) {
        rewards.push({ challenge, type: "success", amount: challenge.depositAmount, label: "押金与完成 NFT" });
      }
    }

    if (challenge.status === 2 && challenge.participant.joined && !challenge.participant.rewardClaimed) {
      rewards.push({ challenge, type: "refund", amount: challenge.depositAmount, label: "取消退款" });
    }
  }));

  state.rewards = rewards.sort((a, b) => b.challenge.id - a.challenge.id);
}

async function refreshAll() {
  if (!state.config || !state.contracts.manager || state.loading) return;
  state.loading = true;
  document.querySelector("#refreshButton").disabled = true;
  try {
    await Promise.all([loadChallenges(), loadWalletMetrics()]);
    await loadRewards();
    renderChallenges();
    renderRewards();
    if (state.currentChallengeId && elements.detailModal.open) openChallengeDetail(state.currentChallengeId);
  } catch (error) {
    toast(`读取链上数据失败：${readableError(error)}`, "error");
  } finally {
    state.loading = false;
    document.querySelector("#refreshButton").disabled = false;
  }
}

function getCardAction(challenge) {
  if (!state.account) return "连接钱包";
  if (challenge.stage === "recruiting" && !challenge.participant.joined) return "查看并加入";
  if (challenge.stage === "active" && challenge.participant.joined && challenge.canCheckIn) return "立即打卡";
  if (challenge.stage === "active" && challenge.participant.joined) return "今日已打卡";
  if (challenge.stage === "ready") return "触发结算";
  if (challenge.stage === "settled" && challenge.isWinner && !challenge.participant.rewardClaimed) return "领取押金与 NFT";
  if (challenge.stage === "cancelled" && challenge.participant.joined && !challenge.participant.rewardClaimed) return "领取退款";
  return "查看详情";
}

function challengeCard(challenge) {
  const progress = Math.min(100, Math.round((challenge.participant.checkInCount / challenge.requiredCheckIns) * 100) || 0);
  const accent = ["#eae6ff", "#e9f5cf", "#ffe8d9", "#dfeff0"][challenge.id % 4];
  return `
    <article class="challenge-card" style="--card-accent:${accent}">
      <div class="challenge-card-top">
        <span class="challenge-number">CHALLENGE #${challenge.id}</span>
        <span class="status-pill ${challenge.stage}"><i></i>${stageLabels[challenge.stage]}</span>
      </div>
      <h3>${escapeHtml(challenge.name)}</h3>
      <span class="challenge-author">by ${shortenAddress(challenge.author, 7, 5)}</span>
      <div class="card-stats">
        <div><span>押金</span><strong>${formatToken(challenge.depositAmount)} ${escapeHtml(state.symbol)}</strong></div>
        <div><span>目标</span><strong>${challenge.requiredCheckIns} / ${challenge.durationDays} 天</strong></div>
        <div><span>参与</span><strong>${challenge.participantCount} / ${challenge.maxParticipants}</strong></div>
      </div>
      ${challenge.participant.joined ? `
        <div class="challenge-progress">
          <div class="progress-label"><span>我的打卡进度</span><strong>${challenge.participant.checkInCount} / ${challenge.requiredCheckIns}</strong></div>
          <div class="progress-track"><i style="width:${progress}%"></i></div>
        </div>` : ""}
      <button class="card-action" type="button" data-open-challenge="${challenge.id}">${getCardAction(challenge)}</button>
    </article>`;
}

function visibleChallenges() {
  const query = document.querySelector("#challengeSearch").value.trim().toLowerCase();
  return state.challenges.filter((challenge) => {
    const filterMatch = state.activeFilter === "all"
      || (state.activeFilter === "settled" && ["settled", "cancelled"].includes(challenge.stage))
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

  const mine = state.challenges.filter((challenge) => challenge.participant.joined || challenge.isAuthor);
  elements.mineGrid.innerHTML = mine.map(challengeCard).join("");
  elements.mineEmpty.hidden = mine.length > 0;
}

function rewardActionLabel(type) {
  if (type === "success") return "领取押金 + NFT";
  if (type === "refund") return "领取退款";
  return "领取奖励";
}

function renderRewards() {
  const total = state.rewards.reduce((sum, reward) => sum + reward.amount, 0n);
  elements.claimableReward.textContent = state.account ? formatToken(total) : "—";
  elements.rewardList.innerHTML = state.rewards.map((reward) => `
    <article class="reward-item">
      <span class="reward-item-icon">${reward.type === "author" ? "↗" : reward.type === "winner" ? "✦" : reward.type === "refund" ? "↩" : "◇"}</span>
      <div><h4>${escapeHtml(reward.label)} · 挑战 #${reward.challenge.id}</h4><p>${escapeHtml(reward.challenge.name)}</p></div>
      <div class="reward-amount">${formatToken(reward.amount)} <small>${escapeHtml(state.symbol)}</small></div>
      <button type="button" data-reward-action="${reward.type}" data-id="${reward.challenge.id}">${rewardActionLabel(reward.type)}</button>
    </article>`).join("");
  elements.rewardEmpty.hidden = state.rewards.length > 0;
}

function detailActionButtons(challenge) {
  if (!state.account) return `<button class="primary-button" type="button" data-detail-action="connect">连接钱包</button>`;
  const buttons = [];

  if (challenge.stage === "recruiting" && !challenge.participant.joined) {
    buttons.push(`<button class="primary-button" type="button" data-detail-action="join" data-id="${challenge.id}">授权并加入挑战</button>`);
  }
  if (challenge.stage === "recruiting" && challenge.isAuthor) {
    buttons.push(`<button class="outline-button" type="button" data-detail-action="cancel" data-id="${challenge.id}">取消挑战</button>`);
  }
  if (challenge.stage === "active" && challenge.participant.joined) {
    buttons.push(`<button class="primary-button" type="button" data-detail-action="checkin" data-id="${challenge.id}" ${challenge.canCheckIn ? "" : "disabled"}>${challenge.canCheckIn ? "完成今日打卡" : "今日已打卡"}</button>`);
  }
  if (challenge.stage === "ready") {
    buttons.push(`<button class="primary-button" type="button" data-detail-action="finalize" data-id="${challenge.id}">结算挑战</button>`);
  }
  if (challenge.stage === "settled" && challenge.isWinner && !challenge.participant.rewardClaimed) {
    buttons.push(`<button class="primary-button" type="button" data-detail-action="success" data-id="${challenge.id}">退回押金并铸造 NFT</button>`);
  }
  if (challenge.stage === "cancelled" && challenge.participant.joined && !challenge.participant.rewardClaimed) {
    buttons.push(`<button class="primary-button" type="button" data-detail-action="refund" data-id="${challenge.id}">领取取消退款</button>`);
  }
  if (!buttons.length) buttons.push(`<button class="outline-button" type="button" disabled>当前没有可执行操作</button>`);
  return buttons.join("");
}

function openChallengeDetail(id) {
  const challenge = state.challenges.find((item) => item.id === Number(id));
  if (!challenge) return;
  state.currentChallengeId = challenge.id;
  const progress = Math.min(100, Math.round((challenge.participant.checkInCount / challenge.requiredCheckIns) * 100) || 0);
  elements.detailKicker.textContent = `CHALLENGE #${challenge.id} · ${stageLabels[challenge.stage]}`;
  elements.detailTitle.textContent = challenge.name;
  elements.detailContent.innerHTML = `
    <div class="detail-banner">
      <div><span>每人押金</span><strong>${formatToken(challenge.depositAmount)} ${escapeHtml(state.symbol)}</strong></div>
      <div><span>打卡目标</span><strong>${challenge.requiredCheckIns} / ${challenge.durationDays} 天</strong></div>
      <div><span>参与人数</span><strong>${challenge.participantCount} / ${challenge.maxParticipants}</strong></div>
    </div>
    ${challenge.description ? `<p class="modal-intro">${escapeHtml(challenge.description)}</p>` : ""}
    <div class="detail-grid">
      <div class="detail-data"><span>开始时间</span><strong>${formatDate(challenge.startTime)}</strong></div>
      <div class="detail-data"><span>结束时间</span><strong>${formatDate(challenge.endTime)}</strong></div>
      <div class="detail-data"><span>创建者</span><strong>${escapeHtml(shortenAddress(challenge.author, 10, 8))}${challenge.isAuthor ? "（我）" : ""}</strong></div>
      <div class="detail-data"><span>我的身份</span><strong>${challenge.participant.joined ? "参与者" : "未参与"}${challenge.isWinner ? " · 已完成" : ""}</strong></div>
    </div>
    ${challenge.participant.joined ? `
      <div class="detail-progress">
        <div class="progress-label"><span>我的打卡进度</span><strong>${challenge.participant.checkInCount} / ${challenge.requiredCheckIns}</strong></div>
        <div class="progress-track"><i style="width:${progress}%"></i></div>
      </div>` : ""}
    <p class="detail-uri">Metadata URI · ${escapeHtml(challenge.metadataURI)}</p>
    <div class="detail-actions">${detailActionButtons(challenge)}</div>`;
  if (!elements.detailModal.open) elements.detailModal.showModal();
}

async function joinChallenge(id) {
  const challenge = state.challenges.find((item) => item.id === Number(id));
  if (!challenge) return;
  try {
    showTransaction("检查代币授权", "确认 ChallengeManager 是否可以扣取本次押金。 ");
    const allowance = await state.contracts.token.allowance(state.account, state.config.manager);
    if (allowance < challenge.depositAmount) {
      updateTransaction("授权 CHECK", "请在钱包中允许 ChallengeManager 使用本次押金。 ");
      const approval = await state.contracts.token.approve(state.config.manager, challenge.depositAmount);
      updateTransaction("等待授权确认", `授权交易：${shortenAddress(approval.hash, 10, 8)}`);
      await approval.wait();
    }
    updateTransaction("加入挑战", "请在钱包中确认报名交易。 ");
    const transaction = await state.contracts.manager.joinChallenge(challenge.id);
    updateTransaction("报名已提交", `正在等待区块确认：${shortenAddress(transaction.hash, 10, 8)}`);
    await transaction.wait();
    hideTransaction();
    toast(`已成功加入挑战 #${challenge.id}。`);
    elements.detailModal.close();
    await refreshAll();
  } catch (error) {
    hideTransaction();
    toast(readableError(error), "error");
  }
}

async function performChallengeAction(action, id) {
  if (action === "connect") {
    elements.detailModal.close();
    await connectWallet(true);
    return;
  }
  const connected = await requireConnection();
  if (!connected || !state.contracts.manager) return;
  if (action === "join") return joinChallenge(id);

  const actions = {
    checkin: { title: "提交今日打卡", send: () => state.contracts.manager.checkIn(id), success: `挑战 #${id} 今日打卡成功。` },
    finalize: { title: "结算挑战", send: () => state.contracts.manager.finalizeChallenge(id), success: `挑战 #${id} 已完成结算。` },
    success: { title: "领取押金与 NFT", send: () => state.contracts.manager.claimSuccessfulParticipant(id), success: `押金已退回，奖励 NFT 已铸造。` },
    cancel: { title: "取消挑战", send: () => state.contracts.manager.cancelChallenge(id), success: `挑战 #${id} 已取消。` },
    refund: { title: "领取取消退款", send: () => state.contracts.manager.claimCancellationRefund(id), success: `挑战 #${id} 的押金已退回。` },
  };
  const config = actions[action];
  if (!config) return;
  const completed = await runTransaction(config);
  if (completed && elements.detailModal.open) elements.detailModal.close();
}

async function performRewardAction(type, id) {
  const connected = await requireConnection();
  if (!connected) return;
  if (type === "success" || type === "refund") {
    return performChallengeAction(type, id);
  }
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
  const deposit = form.get("depositAmount");
  const startTimestamp = Math.floor(new Date(form.get("startTime")).getTime() / 1000);
  const durationDays = Number(form.get("durationDays"));
  const requiredCheckIns = Number(form.get("requiredCheckIns"));
  const maxParticipants = Number(form.get("maxParticipants"));
  const metadataURI = String(form.get("metadataURI")).trim();

  if (!Number.isFinite(startTimestamp) || startTimestamp <= Math.floor(Date.now() / 1000)) {
    toast("开始时间必须晚于当前时间。", "error");
    return;
  }
  if (requiredCheckIns > durationDays) {
    toast("需打卡天数不能超过挑战持续天数。", "error");
    return;
  }

  let depositAmount;
  try {
    depositAmount = parseUnits(String(deposit), state.decimals);
    if (depositAmount <= 0n) throw new Error();
  } catch {
    toast("请输入有效的押金数量。", "error");
    return;
  }

  const completed = await runTransaction({
    title: "发布挑战",
    send: () => state.contracts.manager.createChallenge(
      depositAmount,
      startTimestamp,
      durationDays,
      requiredCheckIns,
      maxParticipants,
      metadataURI,
    ),
    success: "新挑战已经发布到链上。",
  });
  if (completed) {
    elements.createForm.reset();
    setCreateDefaults();
    switchView("explore");
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
    title: "领取测试代币",
    send: () => state.contracts.token.claim(),
    success: `测试 ${state.symbol} 已到账。`,
  });
}

function switchView(view) {
  document.querySelectorAll(".view").forEach((item) => item.classList.toggle("active", item.id === `${view}View`));
  document.querySelectorAll("[data-view]").forEach((item) => item.classList.toggle("active", item.dataset.view === view));
  document.querySelector(".workspace").scrollIntoView({ behavior: "smooth", block: "start" });
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
  updateCreatePreview();
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
  document.querySelector(".preview-art > span").textContent = duration;
}

function bindEvents() {
  elements.walletButton.addEventListener("click", () => connectWallet(true));
  document.querySelector("#settingsButton").addEventListener("click", async () => {
    if (!state.account) await connectWallet(true);
    openSettings();
  });
  document.querySelector("#setupNoticeButton").addEventListener("click", openSettings);
  document.querySelector("#heroCreateButton").addEventListener("click", () => switchView("create"));
  document.querySelector("#howItWorksButton").addEventListener("click", () => document.querySelector("#howItWorks").scrollIntoView({ behavior: "smooth" }));
  document.querySelectorAll("[data-view]").forEach((button) => button.addEventListener("click", () => switchView(button.dataset.view)));
  document.querySelectorAll(".filter").forEach((button) => button.addEventListener("click", () => {
    state.activeFilter = button.dataset.filter;
    document.querySelectorAll(".filter").forEach((item) => item.classList.toggle("active", item === button));
    renderChallenges();
  }));
  document.querySelector("#challengeSearch").addEventListener("input", renderChallenges);
  document.querySelector("#refreshButton").addEventListener("click", refreshAll);
  document.querySelector("#refreshMineButton").addEventListener("click", refreshAll);
  document.querySelector("#refreshRewardsButton").addEventListener("click", refreshAll);
  document.querySelector("#claimTestTokenButton").addEventListener("click", claimTestTokens);

  document.addEventListener("click", (event) => {
    const challengeButton = event.target.closest("[data-open-challenge]");
    if (challengeButton) openChallengeDetail(challengeButton.dataset.openChallenge);
    const detailAction = event.target.closest("[data-detail-action]");
    if (detailAction) performChallengeAction(detailAction.dataset.detailAction, Number(detailAction.dataset.id));
    const rewardAction = event.target.closest("[data-reward-action]");
    if (rewardAction) performRewardAction(rewardAction.dataset.rewardAction, Number(rewardAction.dataset.id));
  });

  document.querySelector("#closeDetailButton").addEventListener("click", () => elements.detailModal.close());
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
      toast("合约配置已保存。 ");
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
    toast("当前网络的合约配置已清除。 ");
  });

  elements.createForm.addEventListener("submit", createChallenge);
  ["depositAmount", "durationDays", "requiredCheckIns", "maxParticipants"].forEach((id) => {
    document.querySelector(`#${id}`).addEventListener("input", updateCreatePreview);
  });

  elements.settingsModal.addEventListener("click", (event) => {
    if (event.target === elements.settingsModal) elements.settingsModal.close();
  });
  elements.detailModal.addEventListener("click", (event) => {
    if (event.target === elements.detailModal) elements.detailModal.close();
  });
}

async function initialize() {
  bindEvents();
  setCreateDefaults();
  updateConnectionUI();
  resetDataUI();

  if (window.ethereum) {
    window.ethereum.on?.("accountsChanged", async (accounts) => {
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
    window.ethereum.on?.("chainChanged", () => window.location.reload());
    await connectWallet(false);
  }
}

initialize();
