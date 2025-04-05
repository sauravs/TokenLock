// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface ILock {
    function initialize(address owner, address token, uint256 amount, uint256 unlockTime, uint256 releaseAmount)
        external;
    function withdraw() external;
    function getOwner() external view returns (address);
    function getToken() external view returns (address);
    function getAmount() external view returns (uint256);
    function getUnlockTime() external view returns (uint256);
    function getReleasedAmount() external view returns (uint256);
    function getStartTime() external view returns (uint256);
}
