pragma solidity 0.8.24;

import "../BaseLock.sol";

/// @title Normal Lock Contract
/// @notice Implements time-locked token locking functionality
/// @dev Extends BaseLock to add time-based unlocking

contract NormalLock is BaseLock {
    /// @notice Thrown when trying to withdraw before unlock time
    /// @param currentTime Current block timestamp
    /// @param requiredTime Required unlock timestamp

    error TokenStillLocked(uint256 currentTime, uint256 requiredTime);

    /// @notice Withdraws locked tokens after unlock time
    /// @dev Reverts if called before unlock time
    function withdraw() external override onlyOwner {
        if (block.timestamp < unlockTime) {
            revert TokenStillLocked(block.timestamp, unlockTime);
        }
        IERC20(token).transfer(owner, amount);
    }
}
