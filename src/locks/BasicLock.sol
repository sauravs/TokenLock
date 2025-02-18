// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../BaseLock.sol";

/// @title BasicLock Contract
/// @notice A simple lock contract that allows immediate token withdrawal by the owner
/// @dev Inherits from BaseLock for core locking functionality

contract BasicLock is BaseLock {
    /// @notice Withdraws the locked tokens
    /// @dev Transfers all locked tokens to the owner
    function withdraw() external override onlyOwner {
        IERC20(token).transfer(owner, amount);
    }
}
