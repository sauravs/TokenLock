// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../BaseLock.sol";
import "../Errors.sol";

/// @title BasicLock Contract
/// @notice A simple lock contract that allows immediate token withdrawal by the owner
/// @dev Inherits from BaseLock for core locking functionality

contract BasicLock is BaseLock {

       using SafeERC20 for IERC20; 
    
    /// @notice Withdraws the locked tokens
    /// @dev Transfers all locked tokens to the owner
    function withdraw() external override onlyOwner {
        uint256 withdrawAmount = this.getAmount();
        IERC20(this.getToken()).safeTransfer(this.getOwner(), withdrawAmount);
        _updateState(withdrawAmount);

        emit TokensWithdrawn(this.getOwner(), withdrawAmount);

    }
}
