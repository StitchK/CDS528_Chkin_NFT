// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {RewardPool} from "./RewardPool.sol";
import {CheckInNFT} from "./CheckInNFT.sol";

/**
 * @title ChallengeManager
 * @notice Manages challenge creation, deposits, daily check-ins, settlement, refunds,
 *         failed-deposit handoff, and successful-participant NFT claims.
 * @dev The contract uses a pull-payment model:
 *      - Participants deposit CHECK when joining.
 *      - Successful participants claim their original deposit and NFT after finalization.
 *      - Failed deposits are sent to RewardPool during finalization.
 *      - RewardPool rewards are claimed separately from RewardPool.
 */
contract ChallengeManager is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum ChallengeStatus {
        Open,
        Finalized,
        Cancelled
    }

    struct Challenge {
        address author;
        uint256 depositAmount;
        uint64 startTime;
        uint64 endTime;
        uint32 durationDays;
        uint32 requiredCheckIns;
        uint32 maxParticipants;
        uint32 participantCount;
        ChallengeStatus status;
        string metadataURI;
    }

    struct Participant {
        bool joined;
        bool rewardClaimed;
        uint32 checkInCount;
        uint32 lastCheckInDayPlusOne;
    }

    uint32 public constant MAX_PARTICIPANTS = 50;
    uint32 public constant MAX_DURATION_DAYS = 365;

    IERC20 public immutable depositToken;
    RewardPool public immutable rewardPool;
    CheckInNFT public immutable rewardNft;

    uint256 public nextChallengeId = 1;

    mapping(uint256 challengeId => Challenge challenge) public challenges;
    mapping(uint256 challengeId => mapping(address participant => Participant data))
        public participants;

    mapping(uint256 challengeId => address[] participantAddresses)
        private _participantAddresses;

    event ChallengeCreated(
        uint256 indexed challengeId,
        address indexed author,
        uint256 depositAmount,
        uint64 startTime,
        uint64 endTime,
        uint32 requiredCheckIns,
        uint32 maxParticipants,
        string metadataURI
    );

    event ParticipantJoined(
        uint256 indexed challengeId,
        address indexed participant,
        uint256 depositAmount
    );

    event CheckedIn(
        uint256 indexed challengeId,
        address indexed participant,
        uint32 indexed dayIndex,
        uint32 checkInCount
    );

    event ChallengeFinalized(
        uint256 indexed challengeId,
        uint32 winnerCount,
        uint32 failedParticipantCount,
        uint256 failedDepositAmount
    );

    event ChallengeCancelled(uint256 indexed challengeId);

    event DepositRefunded(
        uint256 indexed challengeId,
        address indexed participant,
        uint256 amount
    );

    event RewardNftMinted(
        uint256 indexed challengeId,
        address indexed participant,
        uint256 indexed tokenId
    );

    error InvalidAddress(address account);
    error AddressIsNotContract(address account);
    error TokenMismatch();
    error ChallengeNotFound(uint256 challengeId);
    error InvalidDepositAmount();
    error InvalidStartTime();
    error InvalidDuration(uint32 durationDays);
    error InvalidRequiredCheckIns(uint32 requiredCheckIns);
    error InvalidMaxParticipants(uint32 maxParticipants);
    error InvalidMetadataURI();
    error ChallengeNotOpen(uint256 challengeId);
    error ChallengeNotFinalized(uint256 challengeId);
    error ChallengeNotCancelled(uint256 challengeId);
    error ChallengeAlreadyCancelled(uint256 challengeId);
    error JoinWindowClosed(uint256 challengeId);
    error ParticipantAlreadyJoined(uint256 challengeId, address participant);
    error ParticipantLimitReached(uint256 challengeId);
    error NotChallengeAuthor(uint256 challengeId, address caller);
    error NotJoined(uint256 challengeId, address participant);
    error CheckInNotOpen(uint256 challengeId);
    error AlreadyCheckedInToday(uint256 challengeId, address participant);
    error ChallengeNotEnded(uint256 challengeId);
    error ChallengeCannotBeCancelled(uint256 challengeId);
    error NotSuccessfulParticipant(uint256 challengeId, address participant);
    error RewardAlreadyClaimed(uint256 challengeId, address participant);
    error DepositAmountMismatch();

    /**
     * @dev Deployment order:
     *      1. Deploy MockDepositToken.
     *      2. Deploy RewardPool(token).
     *      3. Deploy CheckInNFT(baseURI).
     *      4. Deploy ChallengeManager(token, rewardPool, nft).
     *      5. rewardPool.setChallengeManager(challengeManager).
     *      6. nft.setManager(challengeManager).
     */
    constructor(
        address depositTokenAddress,
        address rewardPoolAddress,
        address rewardNftAddress
    ) {
        _requireContract(depositTokenAddress);
        _requireContract(rewardPoolAddress);
        _requireContract(rewardNftAddress);

        if (
            depositTokenAddress == rewardPoolAddress ||
            depositTokenAddress == rewardNftAddress ||
            rewardPoolAddress == rewardNftAddress
        ) {
            revert InvalidAddress(depositTokenAddress);
        }

        depositToken = IERC20(depositTokenAddress);
        rewardPool = RewardPool(rewardPoolAddress);
        rewardNft = CheckInNFT(rewardNftAddress);

        if (address(rewardPool.token()) != depositTokenAddress) {
            revert TokenMismatch();
        }
    }

    /**
     * @notice Creates a challenge whose enrollment window is now through startTime.
     * @param metadataURI NFT metadata shared by successful participants in this challenge.
     */
    function createChallenge(
        uint256 depositAmount,
        uint64 startTime,
        uint32 durationDays,
        uint32 requiredCheckIns,
        uint32 maxParticipants,
        string calldata metadataURI
    ) external returns (uint256 challengeId) {
        if (depositAmount == 0) revert InvalidDepositAmount();
        if (startTime <= block.timestamp) revert InvalidStartTime();
        if (durationDays == 0 || durationDays > MAX_DURATION_DAYS) {
            revert InvalidDuration(durationDays);
        }
        if (requiredCheckIns == 0 || requiredCheckIns > durationDays) {
            revert InvalidRequiredCheckIns(requiredCheckIns);
        }
        if (maxParticipants == 0 || maxParticipants > MAX_PARTICIPANTS) {
            revert InvalidMaxParticipants(maxParticipants);
        }
        if (bytes(metadataURI).length == 0) revert InvalidMetadataURI();

        challengeId = nextChallengeId++;
        uint64 endTime = startTime + uint64(durationDays) * 1 days;

        challenges[challengeId] = Challenge({
            author: msg.sender,
            depositAmount: depositAmount,
            startTime: startTime,
            endTime: endTime,
            durationDays: durationDays,
            requiredCheckIns: requiredCheckIns,
            maxParticipants: maxParticipants,
            participantCount: 0,
            status: ChallengeStatus.Open,
            metadataURI: metadataURI
        });

        emit ChallengeCreated(
            challengeId,
            msg.sender,
            depositAmount,
            startTime,
            endTime,
            requiredCheckIns,
            maxParticipants,
            metadataURI
        );
    }

    /**
     * @notice Joins an open challenge by transferring its fixed CHECK deposit.
     */
    function joinChallenge(uint256 challengeId) external nonReentrant {
        Challenge storage challenge = _challenge(challengeId);
        if (challenge.status != ChallengeStatus.Open) {
            revert ChallengeNotOpen(challengeId);
        }
        if (block.timestamp >= challenge.startTime) {
            revert JoinWindowClosed(challengeId);
        }

        Participant storage participant = participants[challengeId][msg.sender];
        if (participant.joined) {
            revert ParticipantAlreadyJoined(challengeId, msg.sender);
        }
        if (challenge.participantCount >= challenge.maxParticipants) {
            revert ParticipantLimitReached(challengeId);
        }

        participant.joined = true;
        challenge.participantCount += 1;
        _participantAddresses[challengeId].push(msg.sender);

        uint256 balanceBefore = depositToken.balanceOf(address(this));
        depositToken.safeTransferFrom(
            msg.sender,
            address(this),
            challenge.depositAmount
        );
        uint256 balanceAfter = depositToken.balanceOf(address(this));

        if (
            balanceAfter < balanceBefore ||
            balanceAfter - balanceBefore != challenge.depositAmount
        ) {
            revert DepositAmountMismatch();
        }

        emit ParticipantJoined(
            challengeId,
            msg.sender,
            challenge.depositAmount
        );
    }

    /**
     * @notice Records at most one check-in for a participant in each challenge day.
     */
    function checkIn(uint256 challengeId) external {
        Challenge storage challenge = _challenge(challengeId);
        if (challenge.status != ChallengeStatus.Open) {
            revert ChallengeNotOpen(challengeId);
        }
        if (
            block.timestamp < challenge.startTime ||
            block.timestamp >= challenge.endTime
        ) {
            revert CheckInNotOpen(challengeId);
        }

        Participant storage participant = participants[challengeId][msg.sender];
        if (!participant.joined) revert NotJoined(challengeId, msg.sender);

        uint256 elapsed = block.timestamp - challenge.startTime;
        uint32 dayIndex = uint32(elapsed / 1 days);
        uint32 dayPlusOne = dayIndex + 1;

        if (participant.lastCheckInDayPlusOne == dayPlusOne) {
            revert AlreadyCheckedInToday(challengeId, msg.sender);
        }

        participant.lastCheckInDayPlusOne = dayPlusOne;
        participant.checkInCount += 1;

        emit CheckedIn(
            challengeId,
            msg.sender,
            dayIndex,
            participant.checkInCount
        );
    }

    /**
     * @notice Finalizes the challenge and sends all failed deposits to RewardPool.
     * @dev Permissionless after endTime so the challenge cannot remain unsettled
     *      merely because its author is inactive.
     */
    function finalizeChallenge(
        uint256 challengeId
    ) external nonReentrant returns (uint32 winnerCount) {
        Challenge storage challenge = _challenge(challengeId);
        if (challenge.status != ChallengeStatus.Open) {
            revert ChallengeNotOpen(challengeId);
        }
        if (block.timestamp < challenge.endTime) {
            revert ChallengeNotEnded(challengeId);
        }

        address[] storage participantAddresses =
            _participantAddresses[challengeId];
        uint256 totalParticipants = participantAddresses.length;

        for (uint256 i = 0; i < totalParticipants; ++i) {
            Participant storage participant =
                participants[challengeId][participantAddresses[i]];
            if (participant.checkInCount >= challenge.requiredCheckIns) {
                winnerCount += 1;
            }
        }

        address[] memory winners = new address[](winnerCount);
        uint256 winnerIndex = 0;
        for (uint256 i = 0; i < totalParticipants; ++i) {
            address participantAddress = participantAddresses[i];
            Participant storage participant =
                participants[challengeId][participantAddress];
            if (participant.checkInCount >= challenge.requiredCheckIns) {
                winners[winnerIndex++] = participantAddress;
            }
        }

        uint32 failedParticipantCount =
            challenge.participantCount - winnerCount;
        uint256 failedDepositAmount =
            uint256(failedParticipantCount) * challenge.depositAmount;

        challenge.status = ChallengeStatus.Finalized;

        if (failedDepositAmount != 0) {
            depositToken.forceApprove(address(rewardPool), failedDepositAmount);
        }
        rewardPool.settleChallenge(
            challengeId,
            challenge.author,
            failedDepositAmount,
            winners
        );
        if (failedDepositAmount != 0) {
            depositToken.forceApprove(address(rewardPool), 0);
        }

        emit ChallengeFinalized(
            challengeId,
            winnerCount,
            failedParticipantCount,
            failedDepositAmount
        );
    }

    /**
     * @notice Successful participants claim their original deposit and NFT once.
     */
    function claimSuccessfulParticipant(
        uint256 challengeId
    ) external nonReentrant returns (uint256 tokenId) {
        Challenge storage challenge = _challenge(challengeId);
        if (challenge.status != ChallengeStatus.Finalized) {
            revert ChallengeNotFinalized(challengeId);
        }

        Participant storage participant = participants[challengeId][msg.sender];
        if (!participant.joined) revert NotJoined(challengeId, msg.sender);
        if (participant.checkInCount < challenge.requiredCheckIns) {
            revert NotSuccessfulParticipant(challengeId, msg.sender);
        }
        if (participant.rewardClaimed) {
            revert RewardAlreadyClaimed(challengeId, msg.sender);
        }

        participant.rewardClaimed = true;

        depositToken.safeTransfer(msg.sender, challenge.depositAmount);
        tokenId = rewardNft.mintReward(
            msg.sender,
            challengeId,
            challenge.metadataURI
        );

        emit DepositRefunded(
            challengeId,
            msg.sender,
            challenge.depositAmount
        );
        emit RewardNftMinted(challengeId, msg.sender, tokenId);
    }

    /**
     * @notice Cancels a challenge before it starts.
     */
    function cancelChallenge(uint256 challengeId) external {
        Challenge storage challenge = _challenge(challengeId);
        if (challenge.status == ChallengeStatus.Cancelled) {
            revert ChallengeAlreadyCancelled(challengeId);
        }
        if (challenge.status != ChallengeStatus.Open) {
            revert ChallengeNotOpen(challengeId);
        }
        if (msg.sender != challenge.author) {
            revert NotChallengeAuthor(challengeId, msg.sender);
        }
        if (block.timestamp >= challenge.startTime) {
            revert ChallengeCannotBeCancelled(challengeId);
        }

        challenge.status = ChallengeStatus.Cancelled;
        emit ChallengeCancelled(challengeId);
    }

    /**
     * @notice Returns a participant's deposit after the author cancels a challenge.
     */
    function claimCancellationRefund(
        uint256 challengeId
    ) external nonReentrant {
        Challenge storage challenge = _challenge(challengeId);
        if (challenge.status != ChallengeStatus.Cancelled) {
            revert ChallengeNotCancelled(challengeId);
        }

        Participant storage participant = participants[challengeId][msg.sender];
        if (!participant.joined) revert NotJoined(challengeId, msg.sender);
        if (participant.rewardClaimed) {
            revert RewardAlreadyClaimed(challengeId, msg.sender);
        }

        participant.rewardClaimed = true;
        depositToken.safeTransfer(msg.sender, challenge.depositAmount);

        emit DepositRefunded(
            challengeId,
            msg.sender,
            challenge.depositAmount
        );
    }

    function isWinner(
        uint256 challengeId,
        address participantAddress
    ) public view returns (bool) {
        Challenge storage challenge = _challenge(challengeId);
        if (challenge.status != ChallengeStatus.Finalized) return false;

        Participant storage participant =
            participants[challengeId][participantAddress];
        return
            participant.joined &&
            participant.checkInCount >= challenge.requiredCheckIns;
    }

    function canCheckIn(
        uint256 challengeId,
        address participantAddress
    ) external view returns (bool) {
        Challenge storage challenge = _challenge(challengeId);
        if (
            challenge.status != ChallengeStatus.Open ||
            block.timestamp < challenge.startTime ||
            block.timestamp >= challenge.endTime
        ) {
            return false;
        }

        Participant storage participant =
            participants[challengeId][participantAddress];
        if (!participant.joined) return false;

        uint32 dayIndex =
            uint32((block.timestamp - challenge.startTime) / 1 days);
        return participant.lastCheckInDayPlusOne != dayIndex + 1;
    }

    function getParticipantAddresses(
        uint256 challengeId
    ) external view returns (address[] memory) {
        _challenge(challengeId);
        return _participantAddresses[challengeId];
    }

    function getChallenge(
        uint256 challengeId
    ) external view returns (Challenge memory) {
        _challenge(challengeId);
        return challenges[challengeId];
    }

    function getParticipant(
        uint256 challengeId,
        address participantAddress
    ) external view returns (Participant memory) {
        _challenge(challengeId);
        return participants[challengeId][participantAddress];
    }

    function challengeCount() external view returns (uint256) {
        return nextChallengeId - 1;
    }

    function _challenge(
        uint256 challengeId
    ) private view returns (Challenge storage challenge) {
        if (challengeId == 0 || challengeId >= nextChallengeId) {
            revert ChallengeNotFound(challengeId);
        }
        return challenges[challengeId];
    }

    function _requireContract(address account) private view {
        if (account == address(0)) revert InvalidAddress(account);
        if (account.code.length == 0) {
            revert AddressIsNotContract(account);
        }
    }
}
