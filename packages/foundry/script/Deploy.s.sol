// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockDepositToken} from "../contracts/MockDepositToken.sol";
import {RewardPool} from "../contracts/RewardPool.sol";
import {CheckInNFT} from "../contracts/CheckInNFT.sol";
import {ChallengeManager} from "../contracts/ChallengeManager.sol";

interface Vm {
    function envOr(string calldata name, string calldata defaultValue) external returns (string memory value);

    function startBroadcast() external;
    function stopBroadcast() external;
}

contract Deploy {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    event DeploymentCompleted(
        uint256 indexed chainId,
        address depositToken,
        address rewardPool,
        address checkInNFT,
        address challengeManager
    );

    function run()
        external
        returns (
            MockDepositToken depositToken,
            RewardPool rewardPool,
            CheckInNFT checkInNFT,
            ChallengeManager challengeManager
        )
    {
        string memory nftBaseURI = vm.envOr("NFT_BASE_URI", string(""));

        vm.startBroadcast();

        depositToken = new MockDepositToken();
        rewardPool = new RewardPool(address(depositToken));
        checkInNFT = new CheckInNFT(nftBaseURI);
        challengeManager = new ChallengeManager(address(depositToken), address(rewardPool), address(checkInNFT));

        rewardPool.setChallengeManager(address(challengeManager));
        checkInNFT.setManager(address(challengeManager));

        require(rewardPool.challengeManager() == address(challengeManager), "Pool binding failed");
        require(checkInNFT.manager() == address(challengeManager), "NFT binding failed");

        emit DeploymentCompleted(
            block.chainid,
            address(depositToken),
            address(rewardPool),
            address(checkInNFT),
            address(challengeManager)
        );

        vm.stopBroadcast();
    }
}
