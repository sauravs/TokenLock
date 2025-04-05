// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// TokenLockFactory specific errors

// @notice Thrown when amount is zero
error ZeroAmount();

/// @notice Thrown when caller is not fee admin
error NotFeeAdmin();

/// @notice Error thrown when contract deployment fails
error DeploymentFailed();

/// @notice Thrown when address provided is zero address
error ZeroAddress();

// BaseLock specific errors

/// @notice InvalidToken error message
error InvalidToken();

/// @notice InvalidOwner error message
error InvalidOwner();

// Normal Lock specific errors

/// @notice Thrown when trying to withdraw before unlock time
/// @param currentTime Current block timestamp
/// @param requiredTime Required unlock timestamp

error TokenStillLocked(uint256 currentTime, uint256 requiredTime);
