// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./locks/BasicLock.sol";
import "./locks/NormalLock.sol";
import "./Errors.sol";

/// @title Token Lock Factory Contract
/// @notice Factory contract for creating different types of token locks
/// @dev Uses OpenZeppelin's Clone factory pattern for gas efficient deployment

contract TokenLockFactory is ReentrancyGuard {
    using Clones for address;
    using SafeERC20 for IERC20;

    /// @notice Different types of locks available
    /// @dev Used to identify lock type in events and storage
    enum LockType {
        BASIC,
        NORMAL
    }

    /// @notice Structure to store lock information
    /// @dev Maps user address to their lock details
    /// @param lockAddress Address of the deployed lock contract
    /// @param lockType Type of the lock (BASIC, NORMAL)
    struct LockInfo {
        address lockAddress;
        LockType lockType;
    }

    /// @notice Address of the fee admin
    /// @dev Can update fee amounts and token
    address public feeAdmin = 0x80AB0Cb57106816b8eff9401418edB0Cb18ed5c7;

    /// @notice Address of the fee collector
    /// @dev Receives the lock creation fees
    address public feeCollector = 0x80AB0Cb57106816b8eff9401418edB0Cb18ed5c7;

    /// @notice Token used for lock creation fees
    /// @dev Can be any ERC20 token
    IERC20 public lockFeeToken = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174); // USDC on polygon mainnet

    /// @notice Fee amount for creating a basic lock
    /// @dev Can be updated by fee admin
    uint256 public lockFeeAmountBasic = 10 * 10 ** 6; // 10 USDC

    /// @notice Fee amount for creating a normal lock
    /// @dev Can be updated by fee admin
    uint256 public lockFeeAmountNormal = 20 * 10 ** 6; //20 USDC

    /// @notice Implementation address for basic lock
    /// @dev Used as template for cloning
    address public immutable basicImpl;

    /// @notice Implementation address for normal lock
    /// @dev Used as template for cloning
    address public immutable normalImpl;

    /// @notice Mapping of whitelisted tokens
    /// @dev No fee for whitelisted tokens

    mapping(address => bool) public whitelistedTokens;

    /// @notice Mapping of user address to their locks
    /// @dev One user can have multiple locks
    mapping(address => LockInfo[]) public userLocks;

    /// @notice Emitted when a new lock is created
    /// @param user Address of the lock creator
    /// @param lock Address of the created lock contract
    /// @param lockType Type of lock created
    event LockCreated(address indexed user, address indexed lock, LockType indexed lockType);

    /// @notice Emitted when Basic fee is updated
    /// @param newFee New fee amount
    event FeeAmountBasicUpdated(uint256 indexed newFee);

    /// @notice Emitted when Normal fee is updated
    /// @param newFee New fee amount
    event FeeAmountNormalUpdated(uint256 indexed newFee);

    /// @notice Emitted when fee token is updated
    /// @param newFeeToken New fee token address
    event FeeTokenUpdated(IERC20 indexed newFeeToken);

    /// @notice Emitted when fee admin is updated
    /// @param newFeeAdmin New fee admin address
    event FeeAdminUpdated(address indexed newFeeAdmin);

    /// @notice Emitted when fee collector is updated
    /// @param newFeeCollector New fee collector address
    event FeeCollectorUpdated(address indexed newFeeCollector);

    /// @notice Emitted when token is whitelisted
    /// @param token Address of the token
    /// @param status Whitelist status
    event TokenWhitelisted(address indexed  token, bool indexed status);

    /// @notice Modifier to restrict access to fee admin

    modifier onlyFeeAdmin() {
        if (msg.sender != feeAdmin) revert NotFeeAdmin();
        _;
    }

    /// @notice Initializes the factory with implementation contracts
    /// @dev Deploys implementation contracts that will be used as templates
    constructor() {
        basicImpl = address(new BasicLock());
        normalImpl = address(new NormalLock());
    }

    /// @notice Updates the fee amount for creating a basic lock
    /// @param _newFee New fee amount
    function updatelockFeeAmountBasic(uint256 _newFee) external onlyFeeAdmin {
        lockFeeAmountBasic = _newFee;
        emit FeeAmountBasicUpdated(_newFee);
    }

    /// @notice Updates the fee amount for creating a normal lock
    /// @param _newFee New fee amount
    /// @dev Can only be called by the fee admin

    function updatelockFeeAmountNormal(uint256 _newFee) external onlyFeeAdmin {
        lockFeeAmountNormal = _newFee;
        emit FeeAmountNormalUpdated(_newFee);
    }

    /// @notice Updates the fee token
    /// @param _newFeeToken New fee token address
    /// @dev Can only be called by the fee admin

    function updateLockFeeToken(IERC20 _newFeeToken) external onlyFeeAdmin {
        if (address(_newFeeToken) == address(0)) revert ZeroAddress();
        lockFeeToken = _newFeeToken;
        emit FeeTokenUpdated(_newFeeToken);
    }

    /// @notice Updates the fee admin address
    /// @param _newFeeAdmin New fee admin address
    /// @dev Can only be called by the current fee admin

    function updateFeeAdmin(address _newFeeAdmin) external onlyFeeAdmin {
        if (_newFeeAdmin == address(0)) revert ZeroAddress();
        feeAdmin = _newFeeAdmin;
        emit FeeAdminUpdated(_newFeeAdmin);
    }

    /// @notice Updates the fee collector address
    /// @param _newFeeCollector New fee collector address
    /// @dev Can only be called by the fee admin

    function updateFeeCollector(address _newFeeCollector) external onlyFeeAdmin {
        if (_newFeeCollector == address(0)) revert ZeroAddress();
        feeCollector = _newFeeCollector;
        emit FeeCollectorUpdated(_newFeeCollector);
    }

    /// @notice Sets the status of a token in whitelist
    /// @param _token Address of the token
    /// @param _status Whitelist status
    /// @dev Can only be called by the fee admin

   
    function setTokenWhitelist(address _token, bool _status) external onlyFeeAdmin {
        whitelistedTokens[_token] = _status;
        emit TokenWhitelisted(_token, _status);
    }

    /// @notice Creates a basic lock
    /// @dev Clones BasicLock implementation and initializes it
    /// @param token Address of the token to lock
    /// @param amount Amount of tokens to lock
    function lockBasic(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        address lock = basicImpl.clone();
        BasicLock(lock).initialize(msg.sender, token, amount, 0, 0);

        if (!isContractDeployed(address(lock))) {
            revert DeploymentFailed();
        }
        IERC20(token).safeTransferFrom(msg.sender, lock, amount);

        if (!whitelistedTokens[token]) {
            lockFeeToken.safeTransferFrom(msg.sender, feeCollector, lockFeeAmountBasic);
        }
        userLocks[msg.sender].push(LockInfo(lock, LockType.BASIC));
        emit LockCreated(msg.sender, lock, LockType.BASIC);
    }

    /// @notice Creates a time-locked token lock
    /// @dev Clones NormalLock implementation and initializes it
    /// @param token Address of the token to lock
    /// @param amount Amount of tokens to lock
    /// @param unlockTime Timestamp when tokens can be withdrawn
    function lockNormal(address token, uint256 amount, uint256 unlockTime) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        address lock = normalImpl.clone();
        NormalLock(lock).initialize(msg.sender, token, amount, unlockTime, 0);

        if (!isContractDeployed(address(lock))) {
            revert DeploymentFailed();
        }
        IERC20(token).safeTransferFrom(msg.sender, lock, amount);

        if (!whitelistedTokens[token]) {
            lockFeeToken.safeTransferFrom(msg.sender, feeCollector, lockFeeAmountNormal);
        }

        userLocks[msg.sender].push(LockInfo(lock, LockType.NORMAL));
        emit LockCreated(msg.sender, lock, LockType.NORMAL);
    }

    /// @notice Checks if a contract exists at the given address
    /// @param _contract Address to check
    /// @return bool True if contract exists, false otherwise
    /// @dev Uses assembly to check contract size

    function isContractDeployed(address _contract) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_contract)
        }
        return size > 0;
    }

    /// @notice Gets all locks created by a user
    /// @dev Returns empty array if user has no locks
    /// @param user Address of the user
    /// @return Array of LockInfo structs
    function getUserLocks(address user) external view returns (LockInfo[] memory) {
        return userLocks[user];
    }
}
