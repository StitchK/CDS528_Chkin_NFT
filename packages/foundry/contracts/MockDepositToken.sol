// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MockDepositToken
/// @notice Test ERC20 token used for challenge deposits and rewards.
contract MockDepositToken {
    string public constant name = "Mock Deposit Token";
    string public constant symbol = "CHECK";
    uint8 public constant decimals = 18;
    uint256 public constant CLAIM_AMOUNT = 1_000 ether;

    uint256 public totalSupply;
    mapping(address account => uint256 balance) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error InsufficientBalance(address account, uint256 balance, uint256 needed);
    error InsufficientAllowance(address owner, address spender, uint256 allowance, uint256 needed);
    error InvalidAddress();

    /// @notice Mints a fixed amount of CHECK to the caller.
    function claim() external {
        _mint(msg.sender, CLAIM_AMOUNT);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];

        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) {
                revert InsufficientAllowance(from, msg.sender, currentAllowance, amount);
            }
            _approve(from, msg.sender, currentAllowance - amount);
        }

        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (from == address(0) || to == address(0)) revert InvalidAddress();

        uint256 fromBalance = balanceOf[from];
        if (fromBalance < amount) {
            revert InsufficientBalance(from, fromBalance, amount);
        }

        balanceOf[from] = fromBalance - amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        if (owner == address(0) || spender == address(0)) revert InvalidAddress();

        allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _mint(address to, uint256 amount) private {
        if (to == address(0)) revert InvalidAddress();

        totalSupply += amount;
        balanceOf[to] += amount;

        emit Transfer(address(0), to, amount);
    }
}
