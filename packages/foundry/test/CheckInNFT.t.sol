// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CheckInNFT} from "../contracts/CheckInNFT.sol";

contract ExternalCaller {
    function call(address target, bytes calldata data) external returns (bool success) {
        (success,) = target.call(data);
    }
}

contract CheckInNFTTest {
    CheckInNFT private nft;

    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    function setUp() public {
        nft = new CheckInNFT("ipfs://checkin-rewards/");
    }

    function testOnlyManagerCanMint() public {
        ExternalCaller caller = new ExternalCaller();

        bool success = caller.call(
            address(nft),
            abi.encodeCall(CheckInNFT.mintReward, (ALICE, 1, ""))
        );

        require(!success, "non-manager minted a reward");
        require(nft.totalSupply() == 0, "unexpected reward supply");
    }

    function testMintRecordsChallengeAndMetadata() public {
        string memory metadataURI = "ipfs://checkin-rewards/challenge-7.json";

        uint256 tokenId = nft.mintReward(ALICE, 7, metadataURI);

        require(tokenId == 1, "unexpected token ID");
        require(nft.ownerOf(tokenId) == ALICE, "unexpected token owner");
        require(nft.challengeOfToken(tokenId) == 7, "unexpected challenge ID");
        require(nft.rewardToken(ALICE, 7) == tokenId, "reward lookup failed");
        require(
            keccak256(bytes(nft.tokenURI(tokenId))) == keccak256(bytes(metadataURI)),
            "unexpected token URI"
        );
    }

    function testParticipantCannotReceiveTwoRewardsForSameChallenge() public {
        nft.mintReward(ALICE, 7, "");

        (bool success,) = address(nft).call(
            abi.encodeCall(CheckInNFT.mintReward, (ALICE, 7, ""))
        );

        require(!success, "duplicate challenge reward was minted");
        require(nft.totalSupply() == 1, "unexpected reward supply");
    }

    function testTransferUpdatesOwnershipAndEnumeration() public {
        uint256 tokenId = nft.mintReward(address(this), 11, "");

        require(nft.balanceOf(address(this)) == 1, "unexpected initial balance");
        require(nft.tokenOfOwnerByIndex(address(this), 0) == tokenId, "initial enumeration failed");

        nft.transferFrom(address(this), BOB, tokenId);

        require(nft.ownerOf(tokenId) == BOB, "unexpected new owner");
        require(nft.balanceOf(address(this)) == 0, "sender balance was not reduced");
        require(nft.balanceOf(BOB) == 1, "recipient balance was not increased");
        require(nft.tokenOfOwnerByIndex(BOB, 0) == tokenId, "recipient enumeration failed");
    }

    function testBaseURIAppendsTokenId() public {
        uint256 tokenId = nft.mintReward(ALICE, 9, "");
        string memory expectedURI = string.concat("ipfs://checkin-rewards/", "1");

        require(tokenId == 1, "unexpected token ID");
        require(
            keccak256(bytes(nft.tokenURI(tokenId))) == keccak256(bytes(expectedURI)),
            "base URI was not applied"
        );
    }
}
