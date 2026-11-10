// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ==================== 一、依赖库 ====================
// IERC20：调用 CHECK 的余额、授权和转账接口。
// SafeERC20：转账失败时回滚，避免把未成功的转账当成已完成。
// ReentrancyGuard：防止一次交易中嵌套进入结算或领取函数。
// 这三个 import 引入的是外部合约接口或库，不会创建新的 CHECK 代币。
// @5.4.0 固定 OpenZeppelin 版本；Remix 会把导入的源码缓存到 .deps 中。
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RewardPool
 * @notice 保管失败押金，并让作者和成功者分别领取 CHECK 奖励。
 * @dev 【本合约在项目中的职责】
 * 用户报名时，押金先由 ChallengeManager 保管。
 * 成功者原始押金的退款仍由 ChallengeManager 处理。
 * 挑战结束后，只有被没收的失败押金会转入 RewardPool。
 * RewardPool 接收这笔 CHECK、确定奖励份额，等待领取人主动发起交易。
 * 因此，成功者的“原始押金退款”和“成功者额外奖励”是两笔不同的资金。
 *
 * 【三个容易混淆的身份】
 * owner：部署 RewardPool 的地址，管理权限仅限绑定 ChallengeManager。
 * author：某个具体挑战的作者，是该挑战作者收益的领取人。
 * challengeManager：负责提交结算结果的 ChallengeManager 合约地址。
 * owner 不一定是 author；不同挑战的 author 也可以不同。
 * owner 如果同时具有某个挑战的作者或成功者资格，也能按该资格领取奖励。
 *
 * 【完整调用顺序】
 * 1. 部署时传入 CHECK 的代币合约地址。
 * 2. 部署者调用 setChallengeManager，绑定已部署的管理合约（只能绑定一次）。
 * 3. ChallengeManager 先给 RewardPool 授予 CHECK 扣款额度（示例使用 forceApprove），
 *    再调用 settleChallenge。金额大于 0 时，奖励池从 ChallengeManager 转入 CHECK。
 *    不要提前用 transfer 把同一笔押金转进来，否则会再次扣款。
 * 4. 作者调用 claimAuthorReward，成功者调用 claimWinnerReward。
 *
 * 【提供给负责 ChallengeManager 的同学】
 * 在 ChallengeManager 文件中导入：
 *     import {RewardPool} from "./RewardPool.sol";
 * 保存部署后的奖励池实例，例如：
 *     RewardPool public rewardPool;
 *     // 在 ChallengeManager 的初始化代码中赋值：
 *     rewardPool = RewardPool(rewardPoolAddress);
 * 挑战结束时，在 ChallengeManager 合约内部执行以下调用：
 *     // checkToken 是 IERC20 类型，且 ChallengeManager 配置了 using SafeERC20 for IERC20。
 *     checkToken.forceApprove(address(rewardPool), failedDepositAmount);
 *     rewardPool.settleChallenge(challengeId, author, failedDepositAmount, winners);
 * 失败押金为 0 时，settleChallenge 会跳过代币操作，调用方可以省略授权。
 * 上面两步建议放在 ChallengeManager 的同一笔结算交易中。
 * ChallengeManager 调用前必须验证挑战已到期，且本次提交的是最终结果。
 * CHECK 必须在 ChallengeManager 自己的地址里；个人钱包的余额和授权不能代替它。
 * forceApprove 只设置“允许奖励池扣多少”的额度，本身不会转移 CHECK。
 * CHECK 真正转入奖励池，发生在 settleChallenge 内部的 safeTransferFrom。
 * 外部用户可调用 ChallengeManager 的结束函数，由它再调用本合约；
 * 用户直接调用 RewardPool.settleChallenge 会被拒绝，即使用户就是挑战作者。
 *
 * 【参数从哪里来】
 * challengeId：使用 ChallengeManager 中原有的挑战编号，不在这里另建编号。
 * author：该编号对应的挑战作者地址。
 * failedDepositAmount：只统计失败者的没收押金，不含待退给成功者的押金。
 * winners：最终成功者的完整地址列表，名单顺序不影响均分结果。
 * 若任何参与者仍有可能完成挑战，就不应提前提交最终结算。
 *
 * 【提供给负责前端的同学】
 * 作者钱包发起交易：rewardPool.claimAuthorReward(challengeId)。
 * 成功者钱包发起交易：rewardPool.claimWinnerReward(challengeId)。
 * 查询：getPoolInfo(challengeId)、getUserReward(challengeId, userAddress)。
 * 领取函数按 msg.sender 识别领取人；若让 ChallengeManager 代调，识别到的将是 ChallengeManager。
 * 领取时无需用户再授权 CHECK，因为是奖励池向用户转账。
 * 设置地址、结算、领取都会修改链上状态，需要等待交易确认。
 * 查询函数可以直接读取链上数据；查询某人的奖励不需要使用这个人的钱包签名。
 * 用户主动领取仍需要支付交易 Gas；领取的 CHECK 和 Gas 使用的原生币不同。
 *
 * 【金额和精度约定】
 * 所有金额都是代币的最小单位，不要在本合约中乘除 10 ** decimals。
 * 若 CHECK 有 18 位小数，1 CHECK 应传入 10 ** 18。
 * 例如 100 CHECK 应传入 100000000000000000000，而不是整数 100。
 * 前端负责把用户看到的 CHECK 数量转换为最小单位，并在显示时转换回来。
 * Solidity 的 uint256 只能保存非负整数，因此按最小单位计算并向下取整。
 *
 * 【本合约采用的分配规则】
 * 有成功者：先取失败押金的一半，再按成功人数均分；所有余数归作者。
 * 无成功者：失败押金全部归作者，避免发生除以零或无人领取的情况。
 * 无失败押金：仍可结算，奖励均为 0；之后重复结算同样会被拒绝。
 * 奖励不足以给每位成功者分到 1 个最小单位时，每位成功者奖励为 0。
 *
 * 【支持范围和账目边界】
 * 只支持普通、无转账手续费且余额不会自动变化的 ERC20 测试代币。
 * ChallengeManager 负责保证挑战已结束、结果最终确定、成功者名单完整、失败押金正确。
 * RewardPool 不读取挑战时间、报名记录或打卡记录，也不验证 challengeId 是否存在；
 * 它只要求该编号在本奖励池中未结算，业务有效性由 ChallengeManager 保证。
 * 本合约不负责原始押金退款、打卡或 NFT。
 * 成功者名单在结算时循环保存，适合本课程项目的小规模挑战。
 * 结算不会自动发奖励，也不会在未来某个时间自动执行领取。
 * 本合约没有管理员随意提款或修改已结算份额的函数。
 * 直接 transfer 进来的额外 CHECK 不会自动成为任何挑战的奖励，
 * 本合约也未提供取回这类额外转账的专用函数，应按约定通过结算收款。
 */
contract RewardPool is ReentrancyGuard {
    // 这行让 IERC20 类型的 token 能使用 SafeERC20 的安全转账方法，
    // 例如 token.safeTransfer(...)、token.safeTransferFrom(...)。
    using SafeERC20 for IERC20;

    // ==================== 二、查询返回的数据结构 ====================

    /// @notice 每个挑战的奖励账本；分配金额保留，剩余金额和领取状态会更新。
    // struct 可以理解为“一张挑战奖励表”。每个 challengeId 都对应一张表。
    // 例如初始收到 100，作者分 50，两位成功者各分 25：
    // totalDeposited = 100，authorReward = 50，rewardPerWinner = 25。
    // 作者领完后 remainingRewards = 50，但 authorReward 仍然是 50，
    // 表示最初分配额；authorClaimed = true 表示这 50 已经发放。
    // 上述数字仅用于说明字段关系，实际调用必须使用代币最小单位。
    struct PoolInfo {
        address author;           // 作者地址。
        uint256 totalDeposited;   // 该挑战实际转入的失败押金总额。
        uint256 authorReward;     // 作者最初分配到的奖励，包含所有余数。
        uint256 winnerCount;      // 成功者人数。
        uint256 rewardPerWinner;  // 每位成功者最初分配到的奖励。
        uint256 remainingRewards; // 该挑战尚未领取的奖励总额。
        bool settled;             // 是否已完成结算；false 表示尚未结算。
        bool authorClaimed;       // 作者是否已经领取作者收益。
    }

    /// @notice 查询某个用户的两类奖励；同一人可以同时是作者和成功者。
    // 这是 getUserReward 返回的数据格式，不是一份独立保存的资金账户。
    // 查询时从挑战账本、成功者资格、领取记录中组合出这些字段。
    // 同时符合两种身份时，两个金额都可能大于 0，两个 claimed 独立变化。
    struct UserReward {
        bool isAuthor;         // 此地址是否为该挑战作者。
        bool isWinner;         // 此地址是否在该挑战的最终成功者名单里。
        uint256 authorReward;  // 此地址的作者收益；不是作者则为 0。
        uint256 winnerReward;  // 此地址的成功者奖励；不是成功者则为 0。
        bool authorClaimed;    // 此地址是否已领取作者收益。
        bool winnerClaimed;    // 此地址是否已领取成功者奖励。
    }

    // ==================== 三、合约配置和内部账本 ====================
    // public 变量会自动生成同名查询函数，例如 token()、challengeManager()。
    // immutable 表示只能在部署期间赋值，部署完成后不能再修改。
    // token 变量保存代币合约的引用，不是 RewardPool 的 CHECK 余额。
    // 实际余额需要通过 token.balanceOf(address(this)) 查询。
    IERC20 public immutable token;   // 固定的 CHECK 合约，部署后不能更换。
    address public immutable owner;  // 部署者，管理权限仅限绑定 ChallengeManager，无任意提款权。
    address public challengeManager; // 结算结果的唯一提交者，绑定后不能更换。

    /// @notice 所有挑战尚未领取的奖励总额，不包括直接转入合约的额外代币。
    // 每结算一个挑战就加上它的失败押金；每成功领取一笔就扣减该笔金额。
    // 对本合约支持的普通 ERC20，余额应当不小于这个数值。
    // 它等于各挑战 remainingRewards 的总和，但不需要每次遍历所有挑战求和。
    uint256 public totalUnclaimedRewards;

    // 所有挑战的 CHECK 都在同一合约地址，通过 challengeId 分别记账。
    // mapping 是通过“键”查记录的表：_pools[7] 就是挑战 7 的奖励账本。
    // 它不会为每个挑战另外生成一个钱包，也不会自动移动 CHECK。
    mapping(uint256 => PoolInfo) private _pools;
    // challengeId => 用户地址 => 是否为成功者。
    // 例如 _isWinner[7][用户地址] 为 true，表示该用户属于挑战 7 的成功者。
    // 不同挑战的同一用户使用不同记录，不会相互覆盖。
    mapping(uint256 => mapping(address => bool)) private _isWinner;
    // challengeId => 用户地址 => 是否已经领取成功者奖励。
    // 初始默认是 false，成功领取后才变为 true；作者收益状态另存于 PoolInfo。
    // private 限制其他合约直接调用这些变量，不代表链上数据保密。
    mapping(uint256 => mapping(address => bool)) private _winnerClaimed;

    // ==================== 四、异常和事件（供前端识别） ====================
    // 出现以下异常时，整笔交易回滚，不会留下扣款或部分修改的账目。
    // 这里的回滚针对合约状态和代币操作，已经消耗的交易 Gas 仍需支付。
    // 前端可以根据 ABI 解码自定义 error，将它们转换成中文提示。
    // SafeERC20、ReentrancyGuard 和 CHECK 合约本身也可能抛出各自的异常。
    error OnlyOwner();                                   // 非部署者尝试绑定 ChallengeManager。
    error OnlyChallengeManager();                        // 非 ChallengeManager 尝试结算。
    error InvalidAddress(address account);               // 零地址或不允许的自身地址。
    error AddressIsNotContract(address account);         // 需要合约地址，却传入普通地址。
    error ManagerAlreadySet();                           // ChallengeManager 已绑定，不能再次设置。
    error ChallengeAlreadySettled(uint256 challengeId);   // 此挑战已经结算过。
    error ChallengeNotSettled(uint256 challengeId);       // 此挑战尚未结算，不能领取。
    error DuplicateWinner(address winner);               // 成功者名单有重复地址。
    error DepositAmountMismatch();                       // 实际到账与声明的押金不一致。
    error NotChallengeAuthor();                          // 调用者不是该挑战作者。
    error NotChallengeWinner();                          // 调用者不是该挑战成功者。
    error RewardAlreadyClaimed();                        // 这份奖励已经领过。
    error NoRewardToClaim();                             // 这份奖励为 0，无法领取。

    // event 是写入交易日志的通知，不是自动执行下一步的函数。
    // 前端可在交易成功后解析事件，也可以按 indexed 字段筛选历史日志。
    // 查询当前可领取状态仍应使用下面的查询函数，不能仅看曾经发出的结算事件。
    // ChallengeManager 绑定完成事件，manager 字段是被绑定的完整合约地址。
    event ChallengeManagerSet(address indexed manager);
    // 挑战结算事件；前端可按 challengeId 筛选该挑战的结算结果。
    event ChallengeSettled(
        uint256 indexed challengeId,
        address indexed author,
        uint256 totalDeposited,
        uint256 authorReward,
        uint256 winnerCount,
        uint256 rewardPerWinner
    );
    // 作者领取成功事件，amount 为本次实际转出的奖励数量。
    event AuthorRewardClaimed(
        uint256 indexed challengeId,
        address indexed author,
        uint256 amount
    );
    // 成功者领取成功事件，amount 为本次实际转出的奖励数量。
    event WinnerRewardClaimed(
        uint256 indexed challengeId,
        address indexed winner,
        uint256 amount
    );

    // ==================== 五、调用权限 ====================
    // modifier 会在对应函数执行前检查调用者身份。
    // msg.sender 是“当前这次调用的直接发起地址”。
    // 用户调用 ChallengeManager，再由 ChallengeManager 调用 RewardPool 时，
    // RewardPool 看到的 msg.sender 是 ChallengeManager，而不是最初的用户。
    modifier onlyOwner() {
        // 仅部署者可以通过检查；owner 没有因此获得领取别人奖励的权限。
        if (msg.sender != owner) revert OnlyOwner();
        // _; 表示权限检查通过后，继续执行被修饰函数的主体。
        _;
    }

    modifier onlyChallengeManager() {
        // 尚未绑定时 challengeManager 为零地址，正常外部调用无法通过此检查。
        if (msg.sender != challengeManager) revert OnlyChallengeManager();
        _;
    }

    // ==================== 六、部署时初始化 ====================
    /**
     * @notice 仅在部署时执行一次，指定奖励池使用的 CHECK 代币。
     * @param tokenAddress 已部署的 MockDepositToken / CHECK 合约地址，非钱包地址。
     * @dev Remix 部署时只需在构造参数中填入 CHECK 地址，不需要附带 ETH。
     *      不需要附带 ETH 指 Value 为 0；部署交易本身仍需要支付 Gas。
     *      owner 是直接执行部署的地址；若通过工厂合约部署，owner 就是工厂。
     *      此处只记录 CHECK 合约引用，不会铸造代币，也不会收取任何押金。
     */
    constructor(address tokenAddress) {
        // address(0) 是全零地址，通常表示地址尚未设置，不能作为代币地址。
        if (tokenAddress == address(0)) {
            revert InvalidAddress(tokenAddress);
        }
        // code.length 检查地址上是否已经部署了代码，避免误填普通钱包地址。
        // 这不等于验证了所有 ERC20 行为；组员必须传入正确的 CHECK 合约。
        if (tokenAddress.code.length == 0) {
            revert AddressIsNotContract(tokenAddress);
        }

        // 类型转换使后续代码能够通过 IERC20 接口调用该地址上的代币合约。
        token = IERC20(tokenAddress);
        // 记录直接部署者，不是记录某个挑战的作者。
        owner = msg.sender;
    }

    // ==================== 七、绑定 ChallengeManager ====================
    /**
     * @notice 部署者只可绑定一次 ChallengeManager，之后不能替换结算权限。
     * @param managerAddress 已部署的 ChallengeManager 合约地址，非钱包地址。
     * @dev 调用者：owner。无返回值，成功时发出 ChallengeManagerSet 事件。
     *      对接调用：rewardPool.setChallengeManager(managerAddress)。
     *      先部署 ChallengeManager，再由奖励池的 owner 执行本函数。
     *      此函数不转移代币，也不发放奖励，只建立后续结算的调用权限。
     *      绑定后无更换接口，所以应先核对合约地址；并非填写组员的钱包地址。
     *      本函数只检查地址及其已部署代码，不验证对方是否实现完整挑战管理逻辑。
     */
    function setChallengeManager(address managerAddress) external onlyOwner {
        // 第一次绑定前是零地址；非零说明已经绑定过，即使传同一地址也拒绝。
        if (challengeManager != address(0)) revert ManagerAlreadySet();
        // 奖励池自身不能同时被当成 ChallengeManager，避免错误配置。
        if (managerAddress == address(0) || managerAddress == address(this)) {
            revert InvalidAddress(managerAddress);
        }
        // 要求 ChallengeManager 已部署完成，不能提前填入尚无代码的地址。
        if (managerAddress.code.length == 0) {
            revert AddressIsNotContract(managerAddress);
        }

        // 保存允许结算的地址，之后 onlyChallengeManager 都与这个地址比较。
        challengeManager = managerAddress;
        emit ChallengeManagerSet(managerAddress);
    }

    // ==================== 八、接收押金并结算（核心合约调用） ====================
    /**
     * @notice 转入某个挑战的失败押金，并一次性确定奖励分配。
     * @param challengeId ChallengeManager 中唯一的挑战编号，允许从 0 开始。
     * @param author 该挑战的作者，不能是零地址或奖励池自身。
     * @param failedDepositAmount 失败押金总额，单位是 CHECK 的最小单位。
     * @param winners 最终成功者名单，不能含零地址、奖励池自身或重复地址。
     * @dev 有成功者时：每人奖励 = (总额 / 2) / 成功人数（整数向下取整）；
     *      作者奖励 = 总额 - 每人奖励 * 成功人数，包含所有余数。
     *      无成功者时：全部归作者。总额为 0 时也允许完成结算。
     *      若金额过小，每位成功者的奖励可能为 0。
     *      正金额结算前，ChallengeManager 必须完成扣款授权；失败会回滚本次结算。
     *      调用者：已绑定的 ChallengeManager。无返回值，成功时发出 ChallengeSettled。
     *      示例：总额为 100 CHECK，winners 有 2 人，作者得 50，每人得 25。
     *      空名单传入长度为 0 的 address[]；不能用 [address(0)] 代替。
     *      一个 challengeId 只能完整结算一次，不支持分批追加押金或成功者。
     *
     *      调用前提：
     *      1. owner 已绑定正确的 ChallengeManager。
     *      2. ChallengeManager 已验证挑战结束，并确定最终作者、名单和失败押金。
     *      3. ChallengeManager 自己持有足够 CHECK，且给本奖励池足够的授权额度。
     *         金额为 0 时不需要代币余额或授权额度，但其他检查仍会执行。
     *      成功结果：账本保存，正金额时 CHECK 进入本合约，尚未向任何领取人发钱。
     *      失败结果：本次结算的状态和代币操作全部回滚，可更正原因后重新提交。
     *      RewardPool 不检查挑战是否到期、编号是否真实存在或名单是否符合打卡结果，
     *      这些业务条件由 ChallengeManager 检查；本合约检查权限、结算状态、
     *      地址、重复名单，以及正金额结算时的代币到账情况。
     */
    function settleChallenge(
        uint256 challengeId,
        address author,
        uint256 failedDepositAmount,
        address[] calldata winners
    ) external nonReentrant onlyChallengeManager {
        // external：从本合约外部调用；calldata：读取调用方传来的成功者地址数组。
        // onlyChallengeManager：限制提交结算结果的身份。
        // nonReentrant：执行期间禁止再次进入受保护的结算或领取函数。
        // 步骤 1：读取此挑战的账本，并检查是否已结算及作者地址是否有效。
        // storage 表示 pool 直接引用链上存储，修改 pool 就会修改 _pools 中的记录。
        // 尚未使用过的 challengeId 会读到默认值，其中 settled 默认为 false。
        PoolInfo storage pool = _pools[challengeId];

        // 用 settled 判断是否已经结算，而不用金额判断，因为零金额也允许结算。
        if (pool.settled) revert ChallengeAlreadySettled(challengeId);
        // 作者不能是零地址或奖励池自身，否则奖励无法通过正常调用领取。
        if (author == address(0) || author == address(this)) {
            revert InvalidAddress(author);
        }

        // 步骤 2：验证成功者名单并保存资格；重复地址会导致整笔结算回滚。
        // 数组长度就是成功人数；每位成功者占一份，不能重复占份额。
        uint256 winnerCount = winners.length;
        for (uint256 i = 0; i < winnerCount; ++i) {
            // 依次取出名单中的地址。名单顺序不会影响最终奖励金额。
            address winner = winners[i];
            if (winner == address(0) || winner == address(this)) {
                revert InvalidAddress(winner);
            }
            // 本挑战首次结算前全部默认为 false；遍历到一个地址后将其标为 true。
            // 如果同一列表后面又出现该地址，就能在这里识别出重复。
            if (_isWinner[challengeId][winner]) {
                revert DuplicateWinner(winner);
            }
            // 这只是保存领取资格，并没有发钱。后续领取时将查询这一项。
            // 后面任何一步失败，这里已设置的 true 也会一起回滚。
            // 允许 author 出现在名单中，此时他同时拥有作者收益和成功者奖励。
            _isWinner[challengeId][winner] = true;
        }

        // 步骤 3：按最小单位进行整数均分，所有余数归作者。
        // 无成功者时跳过除法，rewardPerWinner 保持 0，全部金额归作者。
        // 示例：总额为 101 个最小单位，有 3 位成功者：
        // 先计算 101 / 2 = 50，再计算 50 / 3 = 16，每位成功者得 16。
        // 作者得 101 - 16 * 3 = 53，合计 53 + 16 * 3 = 101，没有剩余未分配。
        // 这里的 101 是“最小单位数”，不能当作有 18 位小数的 101 CHECK。
        // 若总额是 100 CHECK、精度为 18、成功者有 3 人：
        // 每人得 16.666666666666666666 CHECK，作者得 50.000000000000000002 CHECK。
        // CHECK 精度由 MockDepositToken.sol 决定；这里统一计算最小单位整数。
        uint256 rewardPerWinner = 0;
        if (winnerCount != 0) {
            rewardPerWinner = (failedDepositAmount / 2) / winnerCount;
        }
        // 用“总额减去成功者实际分配总额”得到作者份额，一并收纳两次除法的余数。
        // 没有成功者时乘积为 0，作者自然得到全部；金额过小时也可能如此。
        uint256 authorReward =
            failedDepositAmount - rewardPerWinner * winnerCount;

        // 步骤 4：保存分配结果；此时只记账，不向作者和成功者发放奖励。
        // 先写状态再执行外部转账，若转账失败，这些状态也会全部回滚。
        // 以下赋值不会让“未收到的钱”变成真实余额；只有整笔交易成功，
        // 这些记录和后面的收款才会共同生效。转账失败不会留下已结算的空账本。
        pool.author = author;
        pool.totalDeposited = failedDepositAmount;
        pool.authorReward = authorReward;
        pool.winnerCount = winnerCount;
        pool.rewardPerWinner = rewardPerWinner;
        // 初始尚未发放任何奖励，所以剩余应付金额等于本次收到的总额。
        pool.remainingRewards = failedDepositAmount;
        pool.settled = true;
        // 同步增加所有挑战合计尚未支付的金额，领取时会相应扣减。
        totalUnclaimedRewards += failedDepositAmount;

        // 步骤 5：从 ChallengeManager 地址扣取 CHECK，并核对实际到账量。
        // msg.sender 是 ChallengeManager，address(this) 是当前 RewardPool 的地址。
        // 总额为 0 时跳过转账，但仍记录该挑战已结算。
        if (failedDepositAmount != 0) {
            // 先记录 RewardPool 的原有余额，其中可能包含其他挑战尚未领取的钱。
            uint256 balanceBefore = token.balanceOf(address(this));
            // transferFrom 的含义：本奖励池使用 ChallengeManager 授予的额度，
            // 把 CHECK 从 ChallengeManager 转到 RewardPool。
            // 不是从失败用户钱包再次扣款，他们报名时已经交过押金。
            // 余额不足、授权不足，或代币报告转账失败，都会使本次结算回滚。
            token.safeTransferFrom(
                msg.sender,
                address(this),
                failedDepositAmount
            );
            uint256 balanceAfter = token.balanceOf(address(this));

            // 拒绝少到账、收取转账手续费等情况，不能用其他挑战的钱补账。
            // 例如原来有 200，本次声明收 100，转账后应有 300，增量必须正好是 100。
            // 比较的是余额增量，不是合约总余额，因此以前存入的钱不能冒充本次到账。
            // 先检查余额是否下降，再做减法，避免异常代币导致无符号整数下溢。
            if (
                balanceAfter < balanceBefore ||
                balanceAfter - balanceBefore != failedDepositAmount
            ) {
                revert DepositAmountMismatch();
            }
        }

        // 步骤 6：发出结算事件，之后作者和成功者可以各自领取。
        // 事件金额仍然是最小单位，前端显示时需要按 CHECK 精度进行格式化。
        emit ChallengeSettled(
            challengeId,
            author,
            failedDepositAmount,
            authorReward,
            winnerCount,
            rewardPerWinner
        );
    }

    // ==================== 九、作者领取（作者钱包调用） ====================
    /**
     * @notice 作者领取自己的收益；作者同时为成功者时，还可以另领成功者奖励。
     * @param challengeId 要领取收益的挑战编号。
     * @dev 调用者：该挑战作者的钱包或具备调用能力的作者合约。
     *      对接调用：用作者的钱包签名调用 rewardPool.claimAuthorReward(challengeId)。
     *      CHECK 直接转给 msg.sender，无返回值，成功时发出 AuthorRewardClaimed。
     *      未结算、身份错误、已领取、金额为 0、发生受保护函数重入或转账失败都会回滚。
     *      领取金额由结算记录决定，调用方不能传入金额或指定其他收款地址。
     *      若作者也是成功者，本函数只领作者份额，成功者份额要另调领取函数。
     */
    function claimAuthorReward(uint256 challengeId) external nonReentrant {
        // 步骤 1：根据挑战编号读取账本。storage 引用保证下面的领取状态会被保存。
        PoolInfo storage pool = _pools[challengeId];

        // 步骤 2：依次确认已经结算、调用者就是作者、作者份额尚未领过。
        if (!pool.settled) revert ChallengeNotSettled(challengeId);
        if (msg.sender != pool.author) revert NotChallengeAuthor();
        if (pool.authorClaimed) revert RewardAlreadyClaimed();

        // 步骤 3：从可信账本读取金额，而不是相信调用者自己填写的金额。
        uint256 amount = pool.authorReward;
        // 零金额没有可领取资金；失败后领取状态仍保持原值。
        if (amount == 0) revert NoRewardToClaim();

        // 先标记领取并扣减账面余额，再转账，防止重复领取和重入。
        // 步骤 4：更新三项记录：作者已领取、此挑战待支付额、全合约待支付额。
        // 不把 authorReward 清零，让前端仍能查询作者最初分配到了多少。
        pool.authorClaimed = true;
        pool.remainingRewards -= amount;
        totalUnclaimedRewards -= amount;
        // 步骤 5：真正发钱，从 RewardPool 自己的 CHECK 余额转给作者。
        // safeTransfer 使用合约自己的余额，不需要作者或合约再执行 approve。
        // 如果这里失败，上面的 claimed 标记和两项金额扣减也会全部回滚，
        // 作者不会出现“没收到钱，却被记为已经领过”的状态。
        token.safeTransfer(msg.sender, amount);

        // 步骤 6：只有正常完成转账后，才发出本次领取事件。
        emit AuthorRewardClaimed(challengeId, msg.sender, amount);
    }

    // ==================== 十、成功者领取（成功者钱包调用） ====================
    /**
     * @notice 成功者领取自己的奖励，每人每个挑战最多领取一次。
     * @param challengeId 要领取奖励的挑战编号。
     * @dev 调用者：最终成功者名单中的用户。
     *      对接调用：用成功者的钱包签名调用 rewardPool.claimWinnerReward(challengeId)。
     *      CHECK 直接转给 msg.sender，无返回值，成功时发出 WinnerRewardClaimed。
     *      该奖励是额外奖励，不是用户原始押金的退款。
     *      未结算、身份错误、已领取、金额为 0、发生受保护函数重入或转账失败都会回滚。
     *      所有成功者领取相同的 rewardPerWinner，先领后领不影响每人金额。
     *      奖励是结算时固定的，不会根据当前剩余金额重新均分。
     */
    function claimWinnerReward(uint256 challengeId) external nonReentrant {
        // 步骤 1：读取该挑战的账本；一个挑战的领取不会扣减另一个挑战的账目。
        PoolInfo storage pool = _pools[challengeId];

        // 步骤 2：已经结算、在成功者名单内、该用户的成功者份额尚未领取。
        if (!pool.settled) revert ChallengeNotSettled(challengeId);
        if (!_isWinner[challengeId][msg.sender]) revert NotChallengeWinner();
        if (_winnerClaimed[challengeId][msg.sender]) {
            revert RewardAlreadyClaimed();
        }

        // 步骤 3：读取结算时确定的每人份额，名单中的所有人使用相同金额。
        uint256 amount = pool.rewardPerWinner;
        // 即使资格为 true，金额仍可能为 0，例如全部成功或资金小到无法均分。
        if (amount == 0) revert NoRewardToClaim();

        // 步骤 4：只标记当前用户在当前挑战的领取状态，不影响其他成功者。
        // 作者状态单独记录，因此同一个人领取作者收益后仍能领取成功者奖励。
        _winnerClaimed[challengeId][msg.sender] = true;
        // 同步扣减该挑战和全合约尚未支付的金额。
        pool.remainingRewards -= amount;
        totalUnclaimedRewards -= amount;
        // 步骤 5：把奖励直接转入当前调用者地址；失败时上述修改会全部回滚。
        token.safeTransfer(msg.sender, amount);

        // 步骤 6：记录这位成功者已完成领取，供前端刷新显示。
        emit WinnerRewardClaimed(challengeId, msg.sender, amount);
    }

    // ==================== 十一、查询挑战奖励池（任何人可查询） ====================
    /**
     * @notice 查询挑战账本；尚未结算时返回默认值，settled 为 false。
     * @param challengeId 要查询的挑战编号。
     * @return 该挑战的 PoolInfo，字段含义见上面的结构体定义。
     * @dev 无调用权限限制，不修改状态、不转账；前端普通读取无需发送交易。
     *      Solidity 调用示例：
     *      RewardPool.PoolInfo memory info = rewardPool.getPoolInfo(challengeId);
     *      info.totalDeposited 是最初到账金额，info.remainingRewards 是尚未领取金额。
     *      info.settled 为 false：RewardPool 中还没有这个挑战的最终结算记录。
     *      info.settled 为 true 且总额为 0：已结算，但没有失败押金可分。
     *      remainingRewards 为 0 不代表没人成功，也可能表示奖励已经全部领完。
     *      本函数只返回此编号的奖励记录，不返回 ChallengeManager 的打卡数据。
     */
    function getPoolInfo(
        uint256 challengeId
    ) external view returns (PoolInfo memory) {
        // memory 返回一份账本副本，调用者读取它不会修改本合约的存储。
        return _pools[challengeId];
    }

    // ==================== 十二、查询个人奖励（任何人可查询） ====================
    /**
     * @notice 查询个人奖励资格、初始分配金额和领取状态。
     * @param challengeId 要查询的挑战编号。
     * @param user 要查询的用户钱包或合约地址，不要求是当前调用者。
     * @return reward 该用户的 UserReward，字段含义见上面的结构体定义。
     * @dev authorReward / winnerReward 是原始应得金额，领取后仍保留。
     *      作者按钮可领取条件：isAuthor && !authorClaimed && authorReward > 0。
     *      成功者按钮可领取条件：isWinner && !winnerClaimed && winnerReward > 0。
     *      尚未结算或没有资格时，相应字段为默认值。
     *      Solidity 调用示例：
     *      RewardPool.UserReward memory info = rewardPool.getUserReward(challengeId, user);
     *      前端普通读取无需发送交易；显示金额时按 CHECK 的 decimals 格式化。
     *      查询时的 user 是被查询人，实际领取时的身份则由 msg.sender 决定。
     *      查询别人的可领取奖励，不代表查询者可以替别人领取。
     *      金额在领取后仍保留，例如 winnerReward = 25 且 winnerClaimed = true，
     *      表示该用户原来分到 25 且已经领过，不是现在还可以再领 25。
     *      user 同时为作者和成功者时，应分别检查两类金额和领取状态。
     */
    function getUserReward(
        uint256 challengeId,
        address user
    ) external view returns (UserReward memory reward) {
        // reward 是命名的返回变量，初始各字段均为默认值：false 或 0。
        // memory 表示只在本次查询中组装数据，不新增或修改链上奖励记录。
        PoolInfo storage pool = _pools[challengeId];
        // 尚未结算时直接返回默认结果，避免把未确定的数据当成可领取奖励。
        if (!pool.settled) return reward;

        // 两种身份独立判断，不用 if ... else，因为同一地址可以同时满足两种身份。
        reward.isAuthor = user == pool.author;
        reward.isWinner = _isWinner[challengeId][user];

        if (reward.isAuthor) {
            // 作者的分配额和领取状态保存在该挑战的 PoolInfo 中。
            reward.authorReward = pool.authorReward;
            reward.authorClaimed = pool.authorClaimed;
        }
        if (reward.isWinner) {
            // 成功者金额来自该挑战的每人份额，领取状态来自该用户自己的记录。
            reward.winnerReward = pool.rewardPerWinner;
            reward.winnerClaimed = _winnerClaimed[challengeId][user];
        }
        // 函数结束时会自动返回已组装的 reward，无需再显式写 return reward。
    }
}
