// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./locks/BasicLock.sol";
import "./locks/NormalLock.sol";
import "./locks/VestingLock.sol";

/// @title Token Lock Factory Contract
/// @notice Factory contract for creating different types of token locks
/// @dev Uses OpenZeppelin's Clone factory pattern for gas efficient deployment

contract TokenLockFactory is ReentrancyGuard {
    using Clones for address;

    /// @notice Different types of locks available
    /// @dev Used to identify lock type in events and storage
    enum LockType {
        BASIC,
        NORMAL,
        VESTING
    }

    /// @notice Structure to store lock information
    /// @dev Maps user address to their lock details
    /// @param lockAddress Address of the deployed lock contract
    /// @param lockType Type of the lock (BASIC, NORMAL, VESTING)
    struct LockInfo {
        address lockAddress;
        LockType lockType;
    }

    address public feeAdmin = 0x80AB0Cb57106816b8eff9401418edB0Cb18ed5c7;
    address public feeCollector = 0x80AB0Cb57106816b8eff9401418edB0Cb18ed5c7;

    IERC20 public lockFeeToken = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174); // USDC

    uint256 public lockFeeAmountBasic = 10 * 10 ** 6; // 10 USDC
    uint256 public lockFeeAmountNormal = 20 * 10 ** 6; //20 USDC
    uint256 public lockFeeAmountVesting = 50 * 10 ** 6; //50 USDC

    /// @notice Implementation address for basic lock
    /// @dev Used as template for cloning
    address public immutable basicImpl;

    /// @notice Implementation address for normal lock
    /// @dev Used as template for cloning
    address public immutable normalImpl;

    /// @notice Implementation address for vesting lock
    /// @dev Used as template for cloning
    address public immutable vestingImpl;

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
    event LockCreated(address indexed user, address lock, LockType lockType);

    /// @notice Emitted when Basic fee is updated
    /// @param newFee New fee amount
    event FeeAmountBasicUpdated(uint256 newFee);

    /// @notice Emitted when Normal fee is updated
    /// @param newFee New fee amount
    event FeeAmountNormalUpdated(uint256 newFee);

    /// @notice Emitted when Vesting fee is updated
    /// @param newFee New fee amount
    event FeeAmountVestingUpdated(uint256 newFee);

    /// @notice Emitted when fee token is updated
    /// @param newFeeToken New fee token address
    event FeeTokenUpdated(IERC20 newFeeToken);

    /// @notice Emitted when fee admin is updated
    /// @param newFeeAdmin New fee admin address
    event FeeAdminUpdated(address newFeeAdmin);

    /// @notice Emitted when fee collector is updated
    /// @param newFeeCollector New fee collector address
    event FeeCollectorUpdated(address newFeeCollector);

    /// @notice Emitted when token is whitelisted
    /// @param token Address of the token
    /// @param status Whitelist status
    event TokenWhitelisted(address token, bool status);

    /// @notice Thrown when amount is zero
    error ZeroAmount();

    /// @notice Thrown when vesting slots are invalid
    error InvalidSlots();

    /// @notice Thrown when recipient address is invalid
    error InvalidRecipient();

    /// @notice Thrown when caller is not fee admin
    error NotFeeAdmin();

    /// @notice Error thrown when contract deployment fails
    error DeploymentFailed();

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
        vestingImpl = address(new VestingLock());
    }

    /// @notice Updates the fee amount for creating a basic lock
    /// @param _newFee New fee amount
    function updatelockFeeAmountBasic(uint256 _newFee) external onlyFeeAdmin {
        lockFeeAmountBasic = _newFee;
        emit FeeAmountBasicUpdated(_newFee);
    }

    /// @notice Updates the fee amount for creating a normal lock
    /// @param _newFee New fee amount

    function updatelockFeeAmountNormal(uint256 _newFee) external onlyFeeAdmin {
        lockFeeAmountNormal = _newFee;
        emit FeeAmountNormalUpdated(_newFee);
    }

    /// @notice Updates the fee amount for creating a vesting lock
    /// @param _newFee New fee amount
    function updatelockFeeAmountVesting(uint256 _newFee) external onlyFeeAdmin {
        lockFeeAmountVesting = _newFee;
        emit FeeAmountVestingUpdated(_newFee);
    }

    /// @notice Updates the fee token
    /// @param _newFeeToken New fee token address

    function updateLockFeeToken(IERC20 _newFeeToken) external onlyFeeAdmin {
        lockFeeToken = _newFeeToken;
        emit FeeTokenUpdated(_newFeeToken);
    }

    /// @notice Updates the fee admin address
    /// @param _newFeeAdmin New fee admin address

    function updateFeeAdmin(address _newFeeAdmin) external onlyFeeAdmin {
        feeAdmin = _newFeeAdmin;
        emit FeeAdminUpdated(_newFeeAdmin);
    }

    /// @notice Updates the fee collector address
    /// @param _newFeeCollector New fee collector address

    function updateFeeCollector(address _newFeeCollector) external onlyFeeAdmin {
        feeCollector = _newFeeCollector;
        emit FeeCollectorUpdated(_newFeeCollector);
    }

    /// @notice Sets the status of a token in whitelist
    /// @param _token Address of the token
    /// @param _status Whitelist status

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
        BasicLock(lock).initialize(msg.sender, token, amount, 0, 0, address(0), 0, 0, 0, 0, false);

        if (!isContractDeployed(address(lock))) {
            revert DeploymentFailed();
        }
        IERC20(token).transferFrom(msg.sender, lock, amount);

        if (!whitelistedTokens[token]) {
            lockFeeToken.transferFrom(msg.sender, feeAdmin, lockFeeAmountBasic);
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
        NormalLock(lock).initialize(msg.sender, token, amount, unlockTime, 0, address(0), 0, 0, 0, 0, false);

        if (!isContractDeployed(address(lock))) {
            revert DeploymentFailed();
        }
        IERC20(token).transferFrom(msg.sender, lock, amount);

        if (!whitelistedTokens[token]) {
            lockFeeToken.transferFrom(msg.sender, feeAdmin, lockFeeAmountNormal);
        }

        userLocks[msg.sender].push(LockInfo(lock, LockType.NORMAL));
        emit LockCreated(msg.sender, lock, LockType.NORMAL);
    }

    /// @notice Creates a vesting lock with optional cliff
    /// @dev Clones VestingLock implementation and initializes it
    /// @param token Address of the token to lock
    /// @param amount Total amount of tokens to vest
    /// @param unlockTime Duration of the vesting period
    /// @param cliffPeriod Duration of the cliff period
    /// @param recipient Address that will receive the vested tokens
    /// @param slots Number of vesting periods
    /// @param releasedAmount Amount already released (for migrations)
    /// @param lastClaimedTime Last claim timestamp (for migrations)
    /// @param enableCliff Whether to enable cliff period
    function lockVesting(
        address token,
        uint256 amount,
        uint256 unlockTime,
        uint256 cliffPeriod,
        address recipient,
        uint256 slots,
        uint256 currentSlot,
        uint256 releasedAmount,
        uint256 lastClaimedTime,
        bool enableCliff
    ) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert InvalidRecipient();
        if (slots == 0 || slots < 2) revert InvalidSlots();

        address lock = vestingImpl.clone();
        VestingLock(lock).initialize(
            msg.sender,
            token,
            amount,
            unlockTime,
            cliffPeriod,
            recipient,
            slots,
            currentSlot,
            releasedAmount,
            lastClaimedTime,
            enableCliff
        );

        if (!isContractDeployed(address(lock))) {
            revert DeploymentFailed();
        }
        IERC20(token).transferFrom(msg.sender, lock, amount);

        if (!whitelistedTokens[token]) {
            lockFeeToken.transferFrom(msg.sender, feeAdmin, lockFeeAmountVesting);
        }
        userLocks[msg.sender].push(LockInfo(lock, LockType.VESTING));
        emit LockCreated(msg.sender, lock, LockType.VESTING);
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
