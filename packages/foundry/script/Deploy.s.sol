// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockDepositToken} from "../contracts/MockDepositToken.sol";
import {RewardPool} from "../contracts/RewardPool.sol";
import {CheckInNFT} from "../contracts/CheckInNFT.sol";
import {ChallengeManager} from "../contracts/ChallengeManager.sol";

interface VmDeploy {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Deploys all four contracts and binds their manager permissions.
/// @dev The CLI sender owns RewardPool and CheckInNFT; no private key is read here.
contract Deploy {
    VmDeploy private constant VM = VmDeploy(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run(string calldata baseURI)
        external
        returns (address tokenAddress, address poolAddress, address nftAddress, address managerAddress)
    {
        VM.startBroadcast();

        MockDepositToken token = new MockDepositToken();
        RewardPool pool = new RewardPool(address(token));
        CheckInNFT nft = new CheckInNFT(baseURI);
        ChallengeManager manager = new ChallengeManager(address(token), address(pool), address(nft));

        pool.setChallengeManager(address(manager));
        nft.setManager(address(manager));

        VM.stopBroadcast();

        require(pool.challengeManager() == address(manager), "pool binding failed");
        require(nft.manager() == address(manager), "NFT binding failed");

        return (address(token), address(pool), address(nft), address(manager));
    }
}
