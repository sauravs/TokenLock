// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../BaseLock.sol";

/// @title Vesting Lock Contract
/// @notice Implements token vesting with configurable periods and cliff
/// @dev Extends BaseLock to add vesting functionality

contract VestingLock is BaseLock {
    /// @notice Thrown when trying to withdraw during cliff period
    error StillInCliffPeriod();

    /// @notice Thrown when trying to withdraw before next vesting period
    error NotClaimableYet();

    /// @notice Throws when all allocated tokens are claimed
    error YouClaimedAllAllocatedTokens();

    /// @notice Calculates the duration of each vesting period
    /// @dev Divides total unlock time by number of slots
    /// @return Duration of one vesting period in seconds
    function vestingInterval() public view returns (uint256) {
        return (unlockTime / slots);
    }

    /// @notice Calculates the amount of tokens for each vesting period
    /// @dev Divides total amount by number of slots
    /// @return Amount of tokens release per vesting period
    function vestingAmount() public view returns (uint256) {
        return (amount / slots);
    }

    /// @notice Withdraws vested tokens for the current period
    /// @dev Checks cliff period and vesting schedule before releasing tokens
    function withdraw() external override onlyOwner {
        if (enableCliff && block.timestamp < cliffPeriod) revert StillInCliffPeriod();
        if (block.timestamp < lastClaimedTime + (unlockTime / slots)) revert NotClaimableYet();

        uint256 claimableAmount = vestingAmount();

        if (releasedAmount == amount) revert YouClaimedAllAllocatedTokens();

        releasedAmount += claimableAmount;
        lastClaimedTime = block.timestamp;
        currentSlot++;
        IERC20(token).transfer(recipient, claimableAmount);
    }
}
