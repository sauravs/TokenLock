// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILock.sol";
import "./Errors.sol";


/// @title Base Lock Contract
/// @notice Abstract contract implementing core locking functionality
/// @dev Base contract for all lock types (Basic, Normal, Vesting)

abstract contract BaseLock is ILock {
    /// @notice Owner of the lock contract
    /// @dev Address that can withdraw tokens 
    address private owner;

    /// @notice Address of the locked token
    /// @dev ERC20 token contract address
    address private token;

    /// @notice Amount of tokens locked
    /// @dev Total number of tokens deposited
    uint256 private amount;

    /// @notice Timestamp when total amount of tokens unlock
    /// @dev Unix timestamp in seconds
    uint256 private unlockTime;

    /// @notice Amount of tokens released
    /// @dev Total number of tokens withdrawn
    uint256 private releasedAmount;

    /// @notice Start time of the lock contract
    /// @dev Unix timestamp in seconds
    uint256 private startTime;

    /// @notice Initialization status
    /// @dev Ensures contract is initialized only once
    bool private initialized;

    /// @notice Restricts function to contract owner
    /// @dev Reverts if caller is not owner

    modifier onlyOwner() {
        if (msg.sender != owner) revert InvalidOwner();
        _;
    }


     /// @notice Emitted when a lock is initialized
    event LockInitialized(
        address indexed owner,
        address indexed token,
        uint256 indexed amount,
        uint256 unlockTime,
        uint256 startTime
    );

    /// @notice Emitted when tokens are withdrawn
    event TokensWithdrawn(address indexed owner, uint256 indexed amount);
    
    /// @notice Emitted when lock state is updated
    event StateUpdated(uint256 indexed releasedAmount);


    /// @notice Initializes the lock contract
    /// @dev Can only be called once
    /// @param _owner Address that can withdraw tokens
    /// @param _token Address of token to lock
    /// @param _amount Total Number of tokens to lock
    /// @param _unlockTime When total amount of tokens become withdrawable
    /// @param _releasedAmount Amount released

    function initialize(address _owner, address _token, uint256 _amount, uint256 _unlockTime, uint256 _releasedAmount)
        external
        virtual
    {
        require(!initialized, "Already initialized");

        if (_token == address(0)) revert InvalidToken();
        if (_owner == address(0)) revert InvalidOwner();

        owner = _owner;
        token = _token;
        amount = _amount;
        unlockTime = _unlockTime;
        releasedAmount = _releasedAmount;
        startTime = block.timestamp;
        initialized = true;

    emit LockInitialized(_owner, _token, _amount, _unlockTime, startTime);

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

    /// @notice Returns the released amount
    /// @return Number of tokens released

    function getReleasedAmount() external view returns (uint256) {
        return releasedAmount;
    }

    /// @notice Returns the start time
    /// @return Unix timestamp of contract start

    function getStartTime() external view returns (uint256) {
        return startTime;
    }

    /// @notice Function to withdraw tokens
    function withdraw() external virtual;

    // @notice Updates the lock state
    /// @param _releasedAmount Amount of tokens released
    function _updateState(uint256 _releasedAmount) internal {
        releasedAmount = _releasedAmount;
        emit StateUpdated(_releasedAmount);

    }
}
