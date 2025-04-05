# TokenLock Project Overview

## Introduction

The TokenLock project is a smart contract system designed to provide secure and flexible token locking mechanisms on the EVM compatible blockchain. It allows users to lock ERC20 tokens with different unlocking parameters, either for immediate withdrawal (BasicLock) or time-based withdrawal (NormalLock).

## Core Components

### TokenLockFactory

The factory contract serves as the entry point for users to create various types of token locks. It implements:

- **Minimal proxy pattern** for efficient lock deployment
- **Fee system** for lock creation with configurable parameters
- **Token whitelisting** to exempt certain tokens from fees
- **Administrative functions** for fee management and configuration
- **User lock tracking** to maintain records of all created locks

### BaseLock

An abstract contract that implements the core functionality shared across different lock types:

- **Token storage** for locked assets
- **Access control** limited to the lock owner
- **State tracking** for lock parameters and withdrawal history
- **Getter functions** for lock details
- **Event emissions** for key state changes

### BasicLock

A lock implementation that allows immediate withdrawal by the owner:

- **Inherits from BaseLock** for core functionality
- **No time restrictions** on withdrawals
- **Full withdrawals** of locked tokens
- **Event emissions** for withdrawal tracking

### NormalLock

A time-based lock implementation:

- **Inherits from BaseLock** for core functionality
- **Time-gated withdrawals** enforced by unlock time
- **Full withdrawals** once the unlock time is reached
- **Event emissions** for withdrawal tracking

## Key Features

1. **Gas Efficiency**
   - Utilizes the minimal proxy pattern (EIP-1167) for deploying lock contracts
   - Optimized storage layout in the BaseLock contract

2. **Security**
   - Implements access controls via modifiers
   - Uses SafeERC20 for token transfers
   - Includes reentrancy protection for lock creation
   - Validates parameters to prevent vulnerabilities

3. **Flexibility**
   - Supports different lock types for various use cases
   - Configurable fees for lock creation
   - Whitelisting mechanism for trusted tokens
   - Extensible architecture for adding new lock types

4. **Transparency**
   - Emits events for all significant state changes
   - Provides getter functions for all important contract state

## User Flow

1. User approves tokens to the factory contract
2. User approves fee tokens (if required) to the factory contract
3. User calls `lockBasic()` or `lockNormal()` with desired parameters
4. Factory deploys a new lock contract as a minimal proxy
5. Factory transfers tokens from user to the lock contract
6. Factory collects fees (if applicable)
7. Factory records the new lock in user's locks array
8. User can later withdraw tokens based on the lock type's rules

## Administrative Functions

The factory includes several administrative functions:
- Update fee amounts
- Change fee token
- Modify fee administrator
- Update fee collector
- Whitelist/unwhitelist tokens

## Technical Implementation Details

- **Solidity Version**: 0.8.24
- **Design Pattern**: Factory + Minimal Proxy
- **Libraries Used**: OpenZeppelin's Clones, ReentrancyGuard, SafeERC20
- **Event System**: Comprehensive events for off-chain tracking
- **Error Handling**: Custom error types for gas-efficient reverts

## Potential Use Cases

- Liquidity locking for new token projects
- Time-locked smart contract governance
- Simple escrow mechanisms
- Token distribution programs

---

This project provides a robust framework for token locking with a focus on security, gas efficiency, and flexibility, making it suitable for a variety of DeFi applications and token management scenarios.