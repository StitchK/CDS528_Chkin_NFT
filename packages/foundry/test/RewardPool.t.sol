// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardPool} from "../contracts/RewardPool.sol";
import {MockDepositToken} from "../contracts/MockDepositToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * RewardPool 的四个分配测试：
 * 1. 50/50：作者与成功者总份额各占一半。
 * 2. 均分：多位成功者领取相同金额，领取顺序不影响结果。
 * 3. 余数：拆半和均分产生的所有余数都归作者。
 * 4. 无人成功：全部失败押金归作者。
 *
 * 本文件自带模拟代币、模拟 ChallengeManager 和模拟用户，
 * 不依赖其他同学尚未完成的合约，也不依赖 forge-std 或作弊码。
 * 所有检查都调用真正的 RewardPool，并验证 CHECK 的实际余额变化。
 * 这些辅助合约只供本地测试，不能作为正式项目合约使用。
 *
 * Foundry：在已配置 OpenZeppelin 导入路径的工程中运行：
 *     forge test --match-contract RewardPoolTest -vv
 * Foundry 会在每个 test_ 开头的测试执行前自动运行 setUp。
 *
 * Remix 手动验证：选择 Solidity 0.8.20，编译本文件，部署 RewardPoolTest。
 * Value 保持 0；Gas Limit 使用手动/Custom 模式并设为 10000000。
 * 未开启优化时，本测试合约部署约需 671 万 Gas，setUp 约需 363 万 Gas，
 * 默认的 300 万 Gas 不足；部署和后续 setUp 都应保持上述 Gas 上限。
 * 每个测试执行前先调用 setUp，再调用对应的 test_ 函数。
 * 测试交易成功表示全部断言通过；任意断言失败都会回滚。
 * setUp 每次创建一组全新的测试合约，避免上一个测试的余额影响下一个。
 */

// ==================== 一、模拟 CHECK 代币 ====================

/// @dev 使用标准 ERC20，默认 18 位小数。mint 仅为测试准备资金。
contract RewardPoolTestToken is ERC20 {
    constructor() ERC20("Test CHECK", "CHECK") {}

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

// ==================== 二、模拟 ChallengeManager ====================

/// @dev 只模拟“授权并调用奖励池”，不实现打卡和挑战结果判断。
contract RewardPoolTestChallengeManager {
    using SafeERC20 for IERC20;

    IERC20 private immutable _token;
    RewardPool private immutable _rewardPool;

    constructor(IERC20 token_, RewardPool rewardPool_) {
        _token = token_;
        _rewardPool = rewardPool_;
    }

    // 测试会先把 CHECK 铸造到这个模拟管理合约，再执行本函数。
    // RewardPool 看到的 msg.sender 因而是已绑定的 ChallengeManager。
    // 此函数为测试辅助入口，未设置真实项目所需的挑战结束条件或调用权限。
    function settleChallenge(
        uint256 challengeId,
        address author,
        uint256 failedDepositAmount,
        address[] calldata winners
    ) external {
        _token.forceApprove(address(_rewardPool), failedDepositAmount);
        _rewardPool.settleChallenge(
            challengeId,
            author,
            failedDepositAmount,
            winners
        );
    }
}

// ==================== 三、模拟作者和成功者 ====================

/// @dev 每个实例代表不同用户，用真实的合约调用模拟不同的 msg.sender。
contract RewardPoolTestUser {
    function call(address target, bytes calldata data) external returns (bool success) {
        (success,) = target.call(data);
    }

    function claimAuthorReward(
        RewardPool rewardPool,
        uint256 challengeId
    ) external {
        rewardPool.claimAuthorReward(challengeId);
    }

    function claimWinnerReward(
        RewardPool rewardPool,
        uint256 challengeId
    ) external {
        rewardPool.claimWinnerReward(challengeId);
    }

    function tryClaimAuthorReward(
        RewardPool rewardPool,
        uint256 challengeId
    ) external returns (bool) {
        try rewardPool.claimAuthorReward(challengeId) {
            return true;
        } catch {
            return false;
        }
    }

    function tryClaimWinnerReward(
        RewardPool rewardPool,
        uint256 challengeId
    ) external returns (bool) {
        try rewardPool.claimWinnerReward(challengeId) {
            return true;
        } catch {
            return false;
        }
    }
}

// ==================== 四、独立创建测试环境 ====================

/// @dev 将创建模拟合约的代码单独放在工厂中，控制测试合约的部署体积。
contract RewardPoolTestFixtureFactory {
    struct Environment {
        RewardPoolTestToken token;
        RewardPool rewardPool;
        RewardPoolTestChallengeManager challengeManager;
        RewardPoolTestUser author;
        RewardPoolTestUser winnerA;
        RewardPoolTestUser winnerB;
        RewardPoolTestUser winnerC;
    }

    function create() external returns (Environment memory env) {
        env.token = new RewardPoolTestToken();
        env.rewardPool = new RewardPool(address(env.token));
        env.challengeManager = new RewardPoolTestChallengeManager(
            IERC20(address(env.token)),
            env.rewardPool
        );

        // RewardPool 由本工厂直接部署，所以工厂是 owner，并在这里完成绑定。
        env.rewardPool.setChallengeManager(address(env.challengeManager));

        env.author = new RewardPoolTestUser();
        env.winnerA = new RewardPoolTestUser();
        env.winnerB = new RewardPoolTestUser();
        env.winnerC = new RewardPoolTestUser();
    }
}

// ==================== 五、正式测试用例 ====================

contract RewardPoolTest {
    // 测试代币为 18 位小数，ONE_CHECK 是 1 CHECK 的最小单位数量。
    uint256 private constant ONE_CHECK = 10 ** 18;

    RewardPoolTestFixtureFactory private immutable _fixtureFactory;
    RewardPoolTestToken private _token;
    RewardPool private _rewardPool;
    RewardPoolTestChallengeManager private _challengeManager;
    RewardPoolTestUser private _author;
    RewardPoolTestUser private _winnerA;
    RewardPoolTestUser private _winnerB;
    RewardPoolTestUser private _winnerC;

    constructor() {
        // 工厂只部署一次；每次 setUp 再由它创建全新的代币、奖励池和用户。
        _fixtureFactory = new RewardPoolTestFixtureFactory();
    }

    /// @notice 为每个测试创建独立环境，模拟实际部署和首次绑定。
    function setUp() public {
        RewardPoolTestFixtureFactory.Environment memory env =
            _fixtureFactory.create();
        _token = env.token;
        _rewardPool = env.rewardPool;
        _challengeManager = env.challengeManager;
        _author = env.author;
        _winnerA = env.winnerA;
        _winnerB = env.winnerB;
        _winnerC = env.winnerC;
    }

    /**
     * 测试 1：100 CHECK，1 位成功者。
     * 预期：作者 50 CHECK，成功者 50 CHECK，严格各占 50%。
     */
    function test_FiftyFiftySplit() public {
        uint256 challengeId = 1;
        uint256 amount = 100 * ONE_CHECK;
        address[] memory winners = new address[](1);
        winners[0] = address(_winnerA);

        _fundAndSettle(challengeId, amount, winners);

        // 先核对结算账本，预期金额使用固定值，不复制奖励池的计算公式。
        RewardPool.PoolInfo memory info = _rewardPool.getPoolInfo(challengeId);
        _assertEq(info.authorReward, 50 * ONE_CHECK, "Author must get 50 CHECK");
        _assertEq(info.winnerCount, 1, "Must have one winner");
        _assertEq(info.rewardPerWinner, 50 * ONE_CHECK, "Winner must get 50 CHECK");

        // 再由各自的地址领取，核对 CHECK 是否真的发出。
        _author.claimAuthorReward(_rewardPool, challengeId);
        _winnerA.claimWinnerReward(_rewardPool, challengeId);

        _assertEq(_token.balanceOf(address(_author)), 50 * ONE_CHECK, "Wrong author balance");
        _assertEq(_token.balanceOf(address(_winnerA)), 50 * ONE_CHECK, "Wrong winner balance");
        _assertFullyClaimed(challengeId, winners);
    }

    /**
     * 测试 2：120 CHECK，3 位成功者。
     * 预期：作者 60 CHECK，每位成功者 20 CHECK，成功者总共 60 CHECK。
     * 改变领取顺序，验证每个人的金额不会随奖励池余额变化。
     */
    function test_EqualSplitAmongWinners() public {
        uint256 challengeId = 2;
        uint256 amount = 120 * ONE_CHECK;
        address[] memory winners = _threeWinners();

        _fundAndSettle(challengeId, amount, winners);

        RewardPool.PoolInfo memory info = _rewardPool.getPoolInfo(challengeId);
        _assertEq(info.authorReward, 60 * ONE_CHECK, "Author must get 60 CHECK");
        _assertEq(info.winnerCount, 3, "Must have three winners");
        _assertEq(info.rewardPerWinner, 20 * ONE_CHECK, "Each winner must get 20 CHECK");

        _winnerB.claimWinnerReward(_rewardPool, challengeId);
        _author.claimAuthorReward(_rewardPool, challengeId);
        _winnerC.claimWinnerReward(_rewardPool, challengeId);
        _winnerA.claimWinnerReward(_rewardPool, challengeId);

        _assertEq(_token.balanceOf(address(_author)), 60 * ONE_CHECK, "Wrong author balance");
        for (uint256 i = 0; i < winners.length; ++i) {
            _assertEq(_token.balanceOf(winners[i]), 20 * ONE_CHECK, "Unequal winner payout");
        }
        _assertFullyClaimed(challengeId, winners);
    }

    /**
     * 测试 3：101 个最小单位，3 位成功者。
     * 注意：这里不是 101 CHECK，不乘 ONE_CHECK，故意使用很小的整数测试零头。
     * 拆半：101 / 2 = 50，留下 1；均分：50 / 3 = 16，再留下 2。
     * 预期：作者 53，每位成功者 16，合计 53 + 16 + 16 + 16 = 101。
     */
    function test_RemainderGoesToAuthor() public {
        uint256 challengeId = 3;
        uint256 amount = 101;
        address[] memory winners = _threeWinners();

        _fundAndSettle(challengeId, amount, winners);

        RewardPool.PoolInfo memory info = _rewardPool.getPoolInfo(challengeId);
        _assertEq(info.authorReward, 53, "Author must receive all remainders");
        _assertEq(info.winnerCount, 3, "Must have three winners");
        _assertEq(info.rewardPerWinner, 16, "Each winner must get 16 units");

        // 成功者先领、作者最后领，确认零头归属不依赖领取顺序。
        _winnerA.claimWinnerReward(_rewardPool, challengeId);
        _winnerB.claimWinnerReward(_rewardPool, challengeId);
        _winnerC.claimWinnerReward(_rewardPool, challengeId);
        _author.claimAuthorReward(_rewardPool, challengeId);

        uint256 totalPaid = _token.balanceOf(address(_author));
        _assertEq(totalPaid, 53, "Wrong author remainder payout");
        for (uint256 i = 0; i < winners.length; ++i) {
            uint256 winnerBalance = _token.balanceOf(winners[i]);
            _assertEq(winnerBalance, 16, "Wrong winner remainder payout");
            totalPaid += winnerBalance;
        }
        _assertEq(totalPaid, 101, "Some deposit units were lost or overpaid");
        _assertFullyClaimed(challengeId, winners);
    }

    /**
     * 测试 4：100 CHECK，成功者名单为空。
     * 预期：作者拿走全部 100 CHECK，没有除以零，也没有成功者奖励滞留。
     */
    function test_NoWinnersAllToAuthor() public {
        uint256 challengeId = 4;
        uint256 amount = 100 * ONE_CHECK;
        address[] memory winners = new address[](0);

        _fundAndSettle(challengeId, amount, winners);

        RewardPool.PoolInfo memory info = _rewardPool.getPoolInfo(challengeId);
        _assertEq(info.winnerCount, 0, "Winner count must be zero");
        _assertEq(info.rewardPerWinner, 0, "Winner reward must be zero");
        _assertEq(info.authorReward, 100 * ONE_CHECK, "Author must receive everything");

        _author.claimAuthorReward(_rewardPool, challengeId);

        _assertEq(_token.balanceOf(address(_author)), 100 * ONE_CHECK, "Wrong full payout");
        _assertFullyClaimed(challengeId, winners);
    }

    /**
     * 测试 5：只有已经绑定的 ChallengeManager 才能提交结算。
     */
    function test_OnlyChallengeManagerCanSettle() public {
        uint256 challengeId = 5;
        uint256 amount = 100 * ONE_CHECK;
        address[] memory winners = new address[](1);
        winners[0] = address(_winnerA);

        (bool success,) = address(_rewardPool).call(
            abi.encodeCall(
                RewardPool.settleChallenge,
                (challengeId, address(_author), amount, winners)
            )
        );

        require(!success, "non-manager settled a challenge");
        require(
            !_rewardPool.getPoolInfo(challengeId).settled,
            "unauthorized settlement changed state"
        );
    }

    /**
     * 测试 6：只有 owner 可以绑定 ChallengeManager。
     */
    function test_OnlyOwnerCanSetChallengeManager() public {
        RewardPool rewardPool = new RewardPool(address(_token));
        RewardPoolTestUser caller = new RewardPoolTestUser();

        bool success = caller.call(
            address(rewardPool),
            abi.encodeCall(
                RewardPool.setChallengeManager,
                (address(_challengeManager))
            )
        );

        require(!success, "non-owner bound the manager");
        require(
            rewardPool.challengeManager() == address(0),
            "unauthorized manager was saved"
        );
    }

    /**
     * 测试 7：ChallengeManager 只能绑定一次。
     */
    function test_ChallengeManagerCanOnlyBeSetOnce() public {
        RewardPool rewardPool = new RewardPool(address(_token));

        rewardPool.setChallengeManager(address(_challengeManager));
        (bool success,) = address(rewardPool).call(
            abi.encodeCall(
                RewardPool.setChallengeManager,
                (address(_challengeManager))
            )
        );

        require(!success, "manager was bound twice");
        require(
            rewardPool.challengeManager() == address(_challengeManager),
            "manager changed after second binding"
        );
    }

    /**
     * 测试 8：重复成功者地址会让整笔结算回滚。
     */
    function test_DuplicateWinnerIsRejected() public {
        uint256 challengeId = 8;
        uint256 amount = 100 * ONE_CHECK;
        address[] memory winners = new address[](2);
        winners[0] = address(_winnerA);
        winners[1] = address(_winnerA);
        _token.mint(address(_challengeManager), amount);

        (bool success,) = address(_challengeManager).call(
            abi.encodeCall(
                RewardPoolTestChallengeManager.settleChallenge,
                (
                    challengeId,
                    address(_author),
                    amount,
                    winners
                )
            )
        );

        require(!success, "duplicate winner was accepted");
        require(
            !_rewardPool.getPoolInfo(challengeId).settled,
            "failed settlement left a settled challenge"
        );
        _assertEq(
            _token.balanceOf(address(_challengeManager)),
            amount,
            "tokens moved during reverted settlement"
        );
    }

    /**
     * 测试 9：同一挑战不能重复提交结算。
     */
    function test_ChallengeCannotBeSettledTwice() public {
        uint256 challengeId = 9;
        uint256 amount = 100 * ONE_CHECK;
        address[] memory winners = new address[](1);
        winners[0] = address(_winnerA);
        _fundAndSettle(challengeId, amount, winners);

        (bool success,) = address(_challengeManager).call(
            abi.encodeCall(
                RewardPoolTestChallengeManager.settleChallenge,
                (
                    challengeId,
                    address(_author),
                    amount,
                    winners
                )
            )
        );

        require(!success, "challenge was settled twice");
        _assertEq(
            _rewardPool.getPoolInfo(challengeId).totalDeposited,
            amount,
            "second settlement changed deposit amount"
        );
    }

    /**
     * 测试 10：结算前不能领取作者或成功者奖励。
     */
    function test_CannotClaimBeforeSettlement() public {
        uint256 challengeId = 10;

        require(
            !_author.tryClaimAuthorReward(_rewardPool, challengeId),
            "author claimed before settlement"
        );
        require(
            !_winnerA.tryClaimWinnerReward(_rewardPool, challengeId),
            "winner claimed before settlement"
        );
    }

    /**
     * 测试 11：非作者不能领作者奖励，非成功者不能领成功者奖励。
     */
    function test_OnlyEligibleUsersCanClaim() public {
        uint256 challengeId = 11;
        uint256 amount = 100 * ONE_CHECK;
        address[] memory winners = new address[](1);
        winners[0] = address(_winnerA);
        _fundAndSettle(challengeId, amount, winners);

        require(
            !_winnerA.tryClaimAuthorReward(_rewardPool, challengeId),
            "winner claimed author reward"
        );
        require(
            !_author.tryClaimWinnerReward(_rewardPool, challengeId),
            "non-winner claimed winner reward"
        );
        require(
            !_winnerB.tryClaimWinnerReward(_rewardPool, challengeId),
            "non-winner claimed winner reward"
        );
    }

    /**
     * 测试 12：作者和各成功者都只能领取一次。
     */
    function test_RewardsCannotBeClaimedTwice() public {
        uint256 challengeId = 12;
        uint256 amount = 100 * ONE_CHECK;
        address[] memory winners = new address[](1);
        winners[0] = address(_winnerA);
        _fundAndSettle(challengeId, amount, winners);

        require(
            _author.tryClaimAuthorReward(_rewardPool, challengeId),
            "author first claim failed"
        );
        require(
            !_author.tryClaimAuthorReward(_rewardPool, challengeId),
            "author claimed twice"
        );
        require(
            _winnerA.tryClaimWinnerReward(_rewardPool, challengeId),
            "winner first claim failed"
        );
        require(
            !_winnerA.tryClaimWinnerReward(_rewardPool, challengeId),
            "winner claimed twice"
        );
        _assertFullyClaimed(challengeId, winners);
    }

    /**
     * 测试 13：作者也可以同时是成功者，并分别领取两份奖励。
     */
    function test_AuthorCanAlsoBeWinner() public {
        uint256 challengeId = 13;
        uint256 amount = 101;
        address[] memory winners = new address[](1);
        winners[0] = address(_author);
        _fundAndSettle(challengeId, amount, winners);

        RewardPool.PoolInfo memory info = _rewardPool.getPoolInfo(challengeId);
        _assertEq(info.authorReward, 51, "wrong author share");
        _assertEq(info.rewardPerWinner, 50, "wrong winner share");

        require(
            _author.tryClaimAuthorReward(_rewardPool, challengeId),
            "author share claim failed"
        );
        require(
            _author.tryClaimWinnerReward(_rewardPool, challengeId),
            "winner share claim failed"
        );

        _assertEq(_token.balanceOf(address(_author)), amount, "wrong combined payout");
        _assertFullyClaimed(challengeId, winners);
    }

    /**
     * 测试 14：零金额也可以完成结算，但没有奖励可以领取。
     */
    function test_ZeroAmountSettlementHasNoClaimableReward() public {
        uint256 challengeId = 14;
        uint256 amount = 0;
        address[] memory winners = new address[](1);
        winners[0] = address(_winnerA);
        _fundAndSettle(challengeId, amount, winners);

        require(
            !_author.tryClaimAuthorReward(_rewardPool, challengeId),
            "zero author reward was claimable"
        );
        require(
            !_winnerA.tryClaimWinnerReward(_rewardPool, challengeId),
            "zero winner reward was claimable"
        );
        _assertEq(
            _rewardPool.totalUnclaimedRewards(),
            0,
            "zero settlement created a liability"
        );
    }

    /**
     * 测试 15：Manager 余额不足时，结算不能留下部分账本。
     */
    function test_SettlementWithInsufficientBalanceReverts() public {
        uint256 challengeId = 15;
        uint256 amount = 100 * ONE_CHECK;
        address[] memory winners = new address[](1);
        winners[0] = address(_winnerA);
        _token.mint(address(_challengeManager), 1);

        (bool success,) = address(_challengeManager).call(
            abi.encodeCall(
                RewardPoolTestChallengeManager.settleChallenge,
                (
                    challengeId,
                    address(_author),
                    amount,
                    winners
                )
            )
        );

        require(!success, "underfunded settlement succeeded");
        require(
            !_rewardPool.getPoolInfo(challengeId).settled,
            "failed transfer left a settled challenge"
        );
        _assertEq(
            _rewardPool.totalUnclaimedRewards(),
            0,
            "failed transfer left a liability"
        );
    }

    /**
     * 测试 16：RewardPool 与项目实际的 MockDepositToken 兼容。
     */
    function test_WorksWithProjectMockDepositToken() public {
        uint256 challengeId = 16;
        uint256 amount = 100 * ONE_CHECK;
        MockDepositToken projectToken = new MockDepositToken();
        RewardPool rewardPool = new RewardPool(address(projectToken));
        RewardPoolTestChallengeManager manager = new RewardPoolTestChallengeManager(
            IERC20(address(projectToken)),
            rewardPool
        );
        rewardPool.setChallengeManager(address(manager));

        projectToken.claim();
        require(projectToken.transfer(address(manager), amount), "funding failed");

        address[] memory winners = new address[](1);
        winners[0] = address(_winnerA);
        manager.settleChallenge(challengeId, address(_author), amount, winners);

        require(
            _author.tryClaimAuthorReward(rewardPool, challengeId),
            "author claim failed with project token"
        );
        require(
            _winnerA.tryClaimWinnerReward(rewardPool, challengeId),
            "winner claim failed with project token"
        );

        _assertEq(projectToken.balanceOf(address(_author)), 50 * ONE_CHECK, "wrong author balance");
        _assertEq(projectToken.balanceOf(address(_winnerA)), 50 * ONE_CHECK, "wrong winner balance");
        _assertEq(projectToken.balanceOf(address(rewardPool)), 0, "project tokens left in pool");
    }

    // ==================== 六、测试辅助函数 ====================

    /// @dev 将测试代币先交给模拟 ChallengeManager，再走真正的授权和收款流程。
    function _fundAndSettle(
        uint256 challengeId,
        uint256 amount,
        address[] memory winners
    ) private {
        _token.mint(address(_challengeManager), amount);
        _challengeManager.settleChallenge(
            challengeId,
            address(_author),
            amount,
            winners
        );

        RewardPool.PoolInfo memory info = _rewardPool.getPoolInfo(challengeId);
        require(info.settled, "Challenge was not settled");
        require(info.author == address(_author), "Wrong challenge author");
        _assertEq(info.totalDeposited, amount, "Wrong recorded deposit");
        _assertEq(info.remainingRewards, amount, "Wrong initial remaining rewards");
        _assertEq(_token.balanceOf(address(_challengeManager)), 0, "Deposit not collected");
        _assertEq(_token.balanceOf(address(_rewardPool)), amount, "Wrong pool balance");
        _assertEq(_rewardPool.totalUnclaimedRewards(), amount, "Wrong total liability");
        _assertEq(_token.balanceOf(address(_author)), 0, "Author was paid before claiming");
        for (uint256 i = 0; i < winners.length; ++i) {
            _assertEq(_token.balanceOf(winners[i]), 0, "Winner was paid before claiming");
        }
    }

    /// @dev 返回三个不同用户的地址，避免成功者名单重复。
    function _threeWinners() private view returns (address[] memory winners) {
        winners = new address[](3);
        winners[0] = address(_winnerA);
        winners[1] = address(_winnerB);
        winners[2] = address(_winnerC);
    }

    /// @dev 核对钱已全部领完、账目同步清零、每个人的领取状态都已更新。
    function _assertFullyClaimed(
        uint256 challengeId,
        address[] memory winners
    ) private view {
        RewardPool.PoolInfo memory info = _rewardPool.getPoolInfo(challengeId);
        require(info.authorClaimed, "Author claim flag not saved");
        _assertEq(info.remainingRewards, 0, "Challenge has unpaid rewards");
        _assertEq(_rewardPool.totalUnclaimedRewards(), 0, "Total rewards not cleared");
        _assertEq(_token.balanceOf(address(_rewardPool)), 0, "Tokens left in reward pool");
        for (uint256 i = 0; i < winners.length; ++i) {
            RewardPool.UserReward memory reward = _rewardPool.getUserReward(
                challengeId,
                winners[i]
            );
            require(reward.isWinner, "Winner eligibility not saved");
            require(reward.winnerClaimed, "Winner claim flag not saved");
        }
    }

    /// @dev 不依赖测试框架的整数断言；失败时给出具体检查项。
    function _assertEq(
        uint256 actual,
        uint256 expected,
        string memory reason
    ) private pure {
        require(actual == expected, reason);
    }
}
