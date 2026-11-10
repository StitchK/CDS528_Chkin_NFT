// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ChallengeManager} from "../contracts/ChallengeManager.sol";
import {CheckInNFT} from "../contracts/CheckInNFT.sol";
import {MockDepositToken} from "../contracts/MockDepositToken.sol";
import {RewardPool} from "../contracts/RewardPool.sol";

interface Vm {
    function warp(uint256 newTimestamp) external;
    function prank(address sender) external;
}

contract ChallengeManagerTest {
    Vm private constant VM =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant DEPOSIT = 10 ether;
    uint256 private constant ONE_DAY = 1 days;
    uint256 private constant INITIAL_TIME = 1_800_000_000;

    address private constant AUTHOR = address(0xA11CE);
    address private constant ALICE = address(0xB0B);
    address private constant BOB = address(0xCA401);
    address private constant CAROL = address(0xDA4E);
    address private constant DAVE = address(0xE4E);

    string private constant METADATA_URI =
        "ipfs://checkin-rewards/challenge.json";

    MockDepositToken private token;
    RewardPool private rewardPool;
    CheckInNFT private nft;
    ChallengeManager private manager;

    uint64 private startTime;
    uint256 private challengeId;

    function setUp() public {
        VM.warp(INITIAL_TIME);

        token = new MockDepositToken();
        rewardPool = new RewardPool(address(token));
        nft = new CheckInNFT("ipfs://checkin-rewards/");
        manager = new ChallengeManager(
            address(token),
            address(rewardPool),
            address(nft)
        );

        rewardPool.setChallengeManager(address(manager));
        nft.setManager(address(manager));

        _fundAndApprove(AUTHOR);
        _fundAndApprove(ALICE);
        _fundAndApprove(BOB);
        _fundAndApprove(CAROL);
        _fundAndApprove(DAVE);

        startTime = uint64(block.timestamp + ONE_DAY);
        challengeId = _createChallenge(
            DEPOSIT,
            startTime,
            3,
            3,
            3,
            METADATA_URI
        );
    }

    function testCreateChallengeStoresConfiguration() public view {
        ChallengeManager.Challenge memory challenge =
            manager.getChallenge(challengeId);

        require(challenge.author == AUTHOR, "wrong author");
        _assertEq(challenge.depositAmount, DEPOSIT, "wrong deposit");
        _assertEq(challenge.startTime, startTime, "wrong start");
        _assertEq(
            challenge.endTime,
            startTime + 3 days,
            "wrong end time"
        );
        _assertEq(challenge.durationDays, 3, "wrong duration");
        _assertEq(challenge.requiredCheckIns, 3, "wrong required check-ins");
        _assertEq(challenge.maxParticipants, 3, "wrong participant limit");
        _assertEq(challenge.participantCount, 0, "wrong initial participant count");
        require(
            challenge.status == ChallengeManager.ChallengeStatus.Open,
            "wrong initial status"
        );
        require(
            keccak256(bytes(challenge.metadataURI)) ==
                keccak256(bytes(METADATA_URI)),
            "wrong metadata URI"
        );
        _assertEq(manager.challengeCount(), 1, "wrong challenge count");
    }

    function testCreateChallengeRejectsInvalidParameters() public {
        require(
            !_callAs(
                AUTHOR,
                address(manager),
                abi.encodeCall(
                    ChallengeManager.createChallenge,
                    (0, startTime, 3, 3, 3, METADATA_URI)
                )
            ),
            "zero deposit accepted"
        );
        require(
            !_callAs(
                AUTHOR,
                address(manager),
                abi.encodeCall(
                    ChallengeManager.createChallenge,
                    (
                        DEPOSIT,
                        uint64(block.timestamp),
                        3,
                        3,
                        3,
                        METADATA_URI
                    )
                )
            ),
            "past start time accepted"
        );
        require(
            !_callAs(
                AUTHOR,
                address(manager),
                abi.encodeCall(
                    ChallengeManager.createChallenge,
                    (DEPOSIT, startTime, 0, 0, 3, METADATA_URI)
                )
            ),
            "zero duration accepted"
        );
        require(
            !_callAs(
                AUTHOR,
                address(manager),
                abi.encodeCall(
                    ChallengeManager.createChallenge,
                    (DEPOSIT, startTime, 3, 4, 3, METADATA_URI)
                )
            ),
            "required check-ins above duration accepted"
        );
        require(
            !_callAs(
                AUTHOR,
                address(manager),
                abi.encodeCall(
                    ChallengeManager.createChallenge,
                    (DEPOSIT, startTime, 3, 3, 51, METADATA_URI)
                )
            ),
            "participant limit above maximum accepted"
        );
        require(
            !_callAs(
                AUTHOR,
                address(manager),
                abi.encodeCall(
                    ChallengeManager.createChallenge,
                    (DEPOSIT, startTime, 3, 3, 3, "")
                )
            ),
            "empty metadata accepted"
        );

        _assertEq(manager.challengeCount(), 1, "invalid calls created challenges");
    }

    function testJoinTransfersDepositAndRecordsParticipant() public {
        uint256 balanceBefore = token.balanceOf(ALICE);

        _join(ALICE);

        _assertEq(
            token.balanceOf(ALICE),
            balanceBefore - DEPOSIT,
            "deposit was not transferred"
        );
        _assertEq(
            token.balanceOf(address(manager)),
            DEPOSIT,
            "manager did not receive deposit"
        );

        ChallengeManager.Challenge memory challenge =
            manager.getChallenge(challengeId);
        ChallengeManager.Participant memory participant =
            manager.getParticipant(challengeId, ALICE);

        _assertEq(challenge.participantCount, 1, "participant count not updated");
        require(participant.joined, "participant not recorded");
        require(!participant.rewardClaimed, "participant marked as claimed");
        _assertEq(participant.checkInCount, 0, "unexpected check-ins");

        address[] memory addresses = manager.getParticipantAddresses(challengeId);
        _assertEq(addresses.length, 1, "participant address not stored");
        require(addresses[0] == ALICE, "wrong participant address");
    }

    function testCannotJoinTwiceOrAfterStart() public {
        _join(ALICE);

        require(
            !_callAs(
                ALICE,
                address(manager),
                abi.encodeCall(ChallengeManager.joinChallenge, (challengeId))
            ),
            "duplicate join succeeded"
        );

        VM.warp(startTime);
        require(
            !_callAs(
                BOB,
                address(manager),
                abi.encodeCall(ChallengeManager.joinChallenge, (challengeId))
            ),
            "joined after start"
        );

        _assertEq(
            manager.getChallenge(challengeId).participantCount,
            1,
            "failed joins changed participant count"
        );
    }

    function testParticipantLimitIsEnforced() public {
        uint256 limitedId = _createChallenge(
            DEPOSIT,
            startTime,
            2,
            2,
            2,
            METADATA_URI
        );

        _join(limitedId, ALICE);
        _join(limitedId, BOB);
        require(
            !_callAs(
                CAROL,
                address(manager),
                abi.encodeCall(ChallengeManager.joinChallenge, (limitedId))
            ),
            "participant limit was exceeded"
        );

        _assertEq(
            manager.getChallenge(limitedId).participantCount,
            2,
            "wrong participant count after rejection"
        );
    }

    function testOneCheckInPerChallengeDay() public {
        _join(ALICE);

        require(
            !_callAs(
                ALICE,
                address(manager),
                abi.encodeCall(ChallengeManager.checkIn, (challengeId))
            ),
            "checked in before start"
        );

        VM.warp(startTime);
        require(
            manager.canCheckIn(challengeId, ALICE),
            "participant should be able to check in"
        );
        _checkIn(ALICE);
        require(
            !_callAs(
                ALICE,
                address(manager),
                abi.encodeCall(ChallengeManager.checkIn, (challengeId))
            ),
            "checked in twice on the same day"
        );

        ChallengeManager.Participant memory afterFirst =
            manager.getParticipant(challengeId, ALICE);
        _assertEq(afterFirst.checkInCount, 1, "first check-in not counted");
        require(
            !manager.canCheckIn(challengeId, ALICE),
            "canCheckIn remained true after daily check-in"
        );

        VM.warp(startTime + ONE_DAY);
        require(
            manager.canCheckIn(challengeId, ALICE),
            "participant cannot check in on the next day"
        );
        _checkIn(ALICE);

        ChallengeManager.Participant memory afterSecond =
            manager.getParticipant(challengeId, ALICE);
        _assertEq(afterSecond.checkInCount, 2, "second check-in not counted");
    }

    function testCheckInRequiresParticipantAndActiveWindow() public {
        require(
            !_callAs(
                ALICE,
                address(manager),
                abi.encodeCall(ChallengeManager.checkIn, (challengeId))
            ),
            "non-participant checked in"
        );

        _join(ALICE);
        VM.warp(startTime + 3 days);
        require(
            !_callAs(
                ALICE,
                address(manager),
                abi.encodeCall(ChallengeManager.checkIn, (challengeId))
            ),
            "checked in at or after end time"
        );
    }

    function testFinalizeSplitsWinnersAndTransfersFailedDeposit() public {
        _join(ALICE);
        _join(BOB);
        _join(CAROL);

        VM.warp(startTime);
        _checkIn(ALICE);
        _checkIn(BOB);
        _checkIn(CAROL);
        VM.warp(startTime + ONE_DAY);
        _checkIn(ALICE);
        _checkIn(BOB);
        _checkIn(CAROL);
        VM.warp(startTime + 2 * ONE_DAY);
        _checkIn(ALICE);
        _checkIn(BOB);

        ChallengeManager.Challenge memory challenge =
            manager.getChallenge(challengeId);
        require(
            !_callAs(
                DAVE,
                address(manager),
                abi.encodeCall(ChallengeManager.finalizeChallenge, (challengeId))
            ),
            "finalized before end time"
        );

        VM.warp(challenge.endTime);
        _finalize(challengeId);

        require(manager.isWinner(challengeId, ALICE), "Alice should be a winner");
        require(manager.isWinner(challengeId, BOB), "Bob should be a winner");
        require(!manager.isWinner(challengeId, CAROL), "Carol should have failed");

        _assertEq(
            token.balanceOf(address(rewardPool)),
            DEPOSIT,
            "failed deposit not transferred to RewardPool"
        );
        _assertEq(
            token.balanceOf(address(manager)),
            2 * DEPOSIT,
            "successful deposits should remain for refunds"
        );
        _assertEq(
            token.allowance(address(manager), address(rewardPool)),
            0,
            "RewardPool allowance was not cleared"
        );

        RewardPool.PoolInfo memory poolInfo =
            rewardPool.getPoolInfo(challengeId);
        require(poolInfo.settled, "RewardPool not settled");
        _assertEq(poolInfo.winnerCount, 2, "wrong RewardPool winner count");
        _assertEq(
            poolInfo.totalDeposited,
            DEPOSIT,
            "wrong failed deposit total"
        );

        uint256 aliceBefore = token.balanceOf(ALICE);
        uint256 tokenId = _claimSuccess(ALICE);
        _assertEq(
            token.balanceOf(ALICE),
            aliceBefore + DEPOSIT,
            "winner deposit not refunded"
        );
        require(nft.ownerOf(tokenId) == ALICE, "winner did not receive NFT");
        _assertEq(
            nft.rewardToken(ALICE, challengeId),
            tokenId,
            "NFT reward mapping not stored"
        );

        _claimSuccess(BOB);
        _assertEq(
            token.balanceOf(address(manager)),
            0,
            "winner refunds were not fully claimed"
        );
        require(
            !_callAs(
                CAROL,
                address(manager),
                abi.encodeCall(
                    ChallengeManager.claimSuccessfulParticipant,
                    (challengeId)
                )
            ),
            "failed participant claimed a refund"
        );
        _assertEq(nft.totalSupply(), 2, "wrong NFT supply");
    }

    function testNoWinnerSendsAllDepositsToRewardPool() public {
        _join(ALICE);
        _join(BOB);

        VM.warp(manager.getChallenge(challengeId).endTime);
        _finalize(challengeId);

        require(!manager.isWinner(challengeId, ALICE), "Alice should have failed");
        require(!manager.isWinner(challengeId, BOB), "Bob should have failed");
        _assertEq(
            token.balanceOf(address(rewardPool)),
            2 * DEPOSIT,
            "all deposits should be in RewardPool"
        );
        _assertEq(token.balanceOf(address(manager)), 0, "manager retained deposits");
        _assertEq(nft.totalSupply(), 0, "unexpected NFT mint");

        uint256 authorBefore = token.balanceOf(AUTHOR);
        VM.prank(AUTHOR);
        rewardPool.claimAuthorReward(challengeId);
        _assertEq(
            token.balanceOf(AUTHOR),
            authorBefore + 2 * DEPOSIT,
            "author did not receive all failed deposits"
        );
    }

    function testAllWinnersCreateZeroDepositRewardPoolSettlement() public {
        _join(ALICE);
        _join(BOB);

        VM.warp(startTime);
        _checkIn(ALICE);
        _checkIn(BOB);
        VM.warp(startTime + ONE_DAY);
        _checkIn(ALICE);
        _checkIn(BOB);
        VM.warp(startTime + 2 * ONE_DAY);
        _checkIn(ALICE);
        _checkIn(BOB);

        VM.warp(manager.getChallenge(challengeId).endTime);
        _finalize(challengeId);

        RewardPool.PoolInfo memory poolInfo =
            rewardPool.getPoolInfo(challengeId);
        require(poolInfo.settled, "zero-amount settlement not recorded");
        _assertEq(poolInfo.totalDeposited, 0, "unexpected failed deposit");
        _assertEq(token.balanceOf(address(rewardPool)), 0, "tokens moved to pool");
        _assertEq(
            token.balanceOf(address(manager)),
            2 * DEPOSIT,
            "winner deposits missing"
        );
        _claimSuccess(ALICE);
        _claimSuccess(BOB);
        _assertEq(nft.totalSupply(), 2, "wrong NFT supply for all winners");
    }

    function testSuccessfulClaimCannotBeRepeated() public {
        _join(ALICE);
        VM.warp(startTime);
        _checkIn(ALICE);
        VM.warp(startTime + ONE_DAY);
        _checkIn(ALICE);
        VM.warp(startTime + 2 * ONE_DAY);
        _checkIn(ALICE);
        VM.warp(manager.getChallenge(challengeId).endTime);
        _finalize(challengeId);

        uint256 tokenId = _claimSuccess(ALICE);
        require(nft.ownerOf(tokenId) == ALICE, "NFT not minted");
        require(
            !_callAs(
                ALICE,
                address(manager),
                abi.encodeCall(
                    ChallengeManager.claimSuccessfulParticipant,
                    (challengeId)
                )
            ),
            "successful claim repeated"
        );
        _assertEq(nft.totalSupply(), 1, "duplicate NFT minted");
    }

    function testFinalizeCannotBeRepeated() public {
        _join(ALICE);
        VM.warp(manager.getChallenge(challengeId).endTime);
        _finalize(challengeId);

        require(
            !_callAs(
                DAVE,
                address(manager),
                abi.encodeCall(ChallengeManager.finalizeChallenge, (challengeId))
            ),
            "challenge finalized twice"
        );
    }

    function testCancelBeforeStartRefundsParticipantsOnce() public {
        _join(ALICE);
        _join(BOB);

        VM.prank(AUTHOR);
        manager.cancelChallenge(challengeId);

        require(
            manager.getChallenge(challengeId).status ==
                ChallengeManager.ChallengeStatus.Cancelled,
            "challenge not cancelled"
        );
        _assertEq(nft.totalSupply(), 0, "NFT minted for cancelled challenge");

        uint256 aliceBefore = token.balanceOf(ALICE);
        VM.prank(ALICE);
        manager.claimCancellationRefund(challengeId);
        _assertEq(
            token.balanceOf(ALICE),
            aliceBefore + DEPOSIT,
            "cancelled challenge did not refund deposit"
        );

        require(
            !_callAs(
                ALICE,
                address(manager),
                abi.encodeCall(
                    ChallengeManager.claimCancellationRefund,
                    (challengeId)
                )
            ),
            "cancellation refund repeated"
        );

        VM.prank(BOB);
        manager.claimCancellationRefund(challengeId);
        _assertEq(token.balanceOf(address(manager)), 0, "refunds not fully claimed");
    }

    function testCancellationRequiresAuthorAndMustPrecedeStart() public {
        _join(ALICE);

        require(
            !_callAs(
                ALICE,
                address(manager),
                abi.encodeCall(ChallengeManager.cancelChallenge, (challengeId))
            ),
            "non-author cancelled challenge"
        );

        VM.warp(startTime);
        require(
            !_callAs(
                AUTHOR,
                address(manager),
                abi.encodeCall(ChallengeManager.cancelChallenge, (challengeId))
            ),
            "author cancelled after start"
        );
    }

    function testAuthorCanParticipateAndWin() public {
        _join(AUTHOR);
        VM.warp(startTime);
        _checkIn(AUTHOR);
        VM.warp(startTime + ONE_DAY);
        _checkIn(AUTHOR);
        VM.warp(startTime + 2 * ONE_DAY);
        _checkIn(AUTHOR);
        VM.warp(manager.getChallenge(challengeId).endTime);
        _finalize(challengeId);

        require(manager.isWinner(challengeId, AUTHOR), "author should win");
        uint256 tokenId = _claimSuccess(AUTHOR);
        require(nft.ownerOf(tokenId) == AUTHOR, "author did not receive NFT");

        uint256 expectedAuthorReward = 0;
        RewardPool.PoolInfo memory poolInfo =
            rewardPool.getPoolInfo(challengeId);
        _assertEq(
            poolInfo.authorReward,
            expectedAuthorReward,
            "all-winner challenge should have no author reward"
        );
    }

    function _fundAndApprove(address user) private {
        VM.prank(user);
        token.claim();

        VM.prank(user);
        require(
            token.approve(address(manager), type(uint256).max),
            "approval failed"
        );
    }

    function _createChallenge(
        uint256 depositAmount,
        uint64 challengeStart,
        uint32 durationDays,
        uint32 requiredCheckIns,
        uint32 maxParticipants,
        string memory metadataURI
    ) private returns (uint256 createdId) {
        VM.prank(AUTHOR);
        createdId = manager.createChallenge(
            depositAmount,
            challengeStart,
            durationDays,
            requiredCheckIns,
            maxParticipants,
            metadataURI
        );
    }

    function _join(uint256 id, address user) private {
        VM.prank(user);
        manager.joinChallenge(id);
    }

    function _join(address user) private {
        _join(challengeId, user);
    }

    function _checkIn(address user) private {
        VM.prank(user);
        manager.checkIn(challengeId);
    }

    function _finalize(uint256 id) private {
        VM.prank(DAVE);
        manager.finalizeChallenge(id);
    }

    function _claimSuccess(address user) private returns (uint256 tokenId) {
        VM.prank(user);
        tokenId = manager.claimSuccessfulParticipant(challengeId);
    }

    function _callAs(
        address caller,
        address target,
        bytes memory data
    ) private returns (bool success) {
        VM.prank(caller);
        (success,) = target.call(data);
    }

    function _assertEq(
        uint256 actual,
        uint256 expected,
        string memory reason
    ) private pure {
        require(actual == expected, reason);
    }
}
