pragma solidity 0.8.24;


import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


import "../BaseLock.sol";
import "../Errors.sol";


/// @title Normal Lock Contract
/// @notice Implements time-locked token locking functionality
/// @dev Extends BaseLock to add time-based unlocking

contract NormalLock is BaseLock {

      using SafeERC20 for IERC20; 
    /// @notice Withdraws locked tokens after unlock time
    /// @dev Reverts if called before unlock time
    function withdraw() external override onlyOwner {
        if (block.timestamp < this.getUnlockTime()) {
            revert TokenStillLocked(block.timestamp, this.getUnlockTime());
        }

        uint256 withdrawAmount = this.getAmount();
        IERC20(this.getToken()).safeTransfer(this.getOwner(), withdrawAmount);

        _updateState(withdrawAmount);
        emit TokensWithdrawn(this.getOwner(), withdrawAmount);

    }
}
