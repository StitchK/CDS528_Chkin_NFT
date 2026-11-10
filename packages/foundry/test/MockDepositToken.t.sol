// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockDepositToken} from "../contracts/MockDepositToken.sol";

contract MockDepositTokenTest {
    function testClaimMintsFixedAmount() public {
        MockDepositToken token = new MockDepositToken();

        token.claim();

        require(token.totalSupply() == token.CLAIM_AMOUNT(), "unexpected total supply");
        require(token.balanceOf(address(this)) == token.CLAIM_AMOUNT(), "unexpected caller balance");
    }

    function testTransferMovesTokens() public {
        MockDepositToken token = new MockDepositToken();
        address recipient = address(0xBEEF);

        token.claim();
        require(token.transfer(recipient, 250 ether), "transfer returned false");

        require(token.balanceOf(recipient) == 250 ether, "unexpected recipient balance");
        require(
            token.balanceOf(address(this)) == token.CLAIM_AMOUNT() - 250 ether,
            "unexpected sender balance"
        );
    }

    function testInfiniteAllowanceIsNotReduced() public {
        MockDepositToken token = new MockDepositToken();
        address recipient = address(0xBEEF);

        token.claim();
        token.approve(address(this), type(uint256).max);
        token.transferFrom(address(this), recipient, 100 ether);

        require(token.balanceOf(recipient) == 100 ether, "unexpected recipient balance");
        require(
            token.allowance(address(this), address(this)) == type(uint256).max,
            "infinite allowance was reduced"
        );
    }
}
