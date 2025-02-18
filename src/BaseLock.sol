// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILock.sol";

/// @title Base Lock Contract
/// @notice Abstract contract implementing core locking functionality
/// @dev Base contract for all lock types (Basic, Normal, Vesting)

abstract contract BaseLock is ILock {
    /// @notice Owner of the lock contract
    /// @dev Address that can withdraw tokens
    address public owner;

    /// @notice Address of the locked token
    /// @dev ERC20 token contract address
    address public token;

    /// @notice Recipient of the locked tokens
    /// @dev Can be different from owner in vesting scenarios
    address public recipient;

    /// @notice Amount of tokens locked
    /// @dev Total number of tokens deposited
    uint256 public amount;

    /// @notice Timestamp when tokens unlock
    /// @dev Unix timestamp in seconds
    uint256 public unlockTime;

    /// @notice Duration of cliff period
    /// @dev Period before vesting begins
    uint256 public cliffPeriod;

    /// @notice Total number of vesting slots
    /// @dev Number of intervals for vesting

    uint256 public slots;

    /// @notice Current vesting slot
    /// @dev Index of the current vesting period

    uint256 public currentSlot;

    /// @notice Amount of tokens released
    /// @dev Total number of tokens withdrawn
    uint256 public releasedAmount;

    /// @notice Timestamp of last claim
    /// @dev Unix timestamp in seconds
    uint256 public lastClaimedTime;

    /// @notice Enable cliff period
    /// @dev Boolean to enable/disable cliff period
    bool public enableCliff;

    /// @notice Initialization status
    /// @dev Ensures contract is initialized only once
    bool private initialized;

    /// @notice NotOwner error message
    error NotOwner();

    /// @notice InvalidToken error message
    error InvalidToken();

    /// @notice InvalidOwner error message
    error InvalidOwner();

    /// @notice Restricts function to contract owner
    /// @dev Reverts if caller is not owner

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Initializes the lock contract
    /// @dev Can only be called once
    /// @param _owner Address that can withdraw tokens
    /// @param _token Address of token to lock
    /// @param _amount Total Number of tokens to lock
    /// @param _unlockTime When tokens become withdrawable
    /// @param _cliffPeriod Duration of cliff period (applicable in vesting)
    /// @param _recepeint Address to receive tokens (applicable in vesting)
    /// @param _slots Number of vesting periods  (applicable in vesting)
    /// @param _currentSlot Current vesting period  (applicable in vesting)
    /// @param _releasedAmount Amount already released (applicable in vesting)
    /// @param _lastClaimedTime Last claim timestamp  (applicable in vesting)
    /// @param _enableCliff Whether to enable cliff  (applicable in vesting)

    function initialize(
        address _owner,
        address _token,
        uint256 _amount,
        uint256 _unlockTime,
        uint256 _cliffPeriod,
        address _recepeint,
        uint256 _slots,
        uint256 _currentSlot,
        uint256 _releasedAmount,
        uint256 _lastClaimedTime,
        bool _enableCliff
    ) external virtual {
        require(!initialized, "Already initialized");

        if (_token == address(0)) revert InvalidToken();
        if (_owner == address(0)) revert InvalidOwner();

        owner = _owner;
        token = _token;
        amount = _amount;
        unlockTime = _unlockTime;
        cliffPeriod = _cliffPeriod;
        recipient = _recepeint;
        slots = _slots;
        currentSlot = _currentSlot;
        releasedAmount = _releasedAmount;
        lastClaimedTime = _lastClaimedTime;
        enableCliff = _enableCliff;
        initialized = true;
    }

    /// @notice Returns the owner of the lock contract
    /// @return Address of the owner

    function getOwner() external view returns (address) {
        return owner;
    }

    /// @notice Returns the locked token address
    /// @return Address of the token contract

    function getToken() external view returns (address) {
        return token;
    }

    /// @notice Returns the locked amount
    /// @return Number of tokens locked
    function getAmount() external view returns (uint256) {
        return amount;
    }

    /// @notice Returns the unlock time
    /// @return Unix timestamp when tokens unlock
    function getUnlockTime() external view returns (uint256) {
        return unlockTime;
    }

    /// @notice Returns the cliff period
    /// @return Duration of cliff period

    function getCliffPeriod() external view returns (uint256) {
        return cliffPeriod;
    }

    /// @notice Returns the recipient address
    /// @return Address of the recipient

    function getRecipient() external view returns (address) {
        return recipient;
    }

    /// @notice Returns the number of vesting slots
    /// @return Number of vesting periods

    function getSlots() external view returns (uint256) {
        return slots;
    }

    /// @notice Returns the current vesting slot
    /// @return Index of the current vesting period

    function getCurrentSlot() external view returns (uint256) {
        return currentSlot;
    }

    /// @notice Returns the released amount
    /// @return Number of tokens released

    function getReleasedAmount() external view returns (uint256) {
        return releasedAmount;
    }

    /// @notice Returns the last claimed time
    /// @return Unix timestamp of last claim

    function getLastClaimedTime() external view returns (uint256) {
        return lastClaimedTime;
    }

    /// @notice Returns the cliff status
    /// @return Boolean indicating cliff status

    function getEnableCliff() external view returns (bool) {
        return enableCliff;
    }

    /// @notice Function to withdraw tokens

    function withdraw() external virtual;
}
