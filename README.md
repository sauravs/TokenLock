# Token & Liquidity Locking System

## Overview
A comprehensive smart contract system for locking ERC20 tokens.
The project supports three types of locks: Basic, Normal (time-locked), and Vesting.

## Architecture

### Core Contracts
- `TokenLockFactory`: Main factory contract for deploying lock instances
- `BaseLock`: Abstract base contract implementing core locking functionality
- `ILock`: Interface defining lock contract requirements

### Lock Types
1. **Basic Lock**
   - Immediate withdrawal by owner
   - Simplest locking mechanism
   - Requires basic fee (10 USDC)

2. **Normal Lock**
   - Time-based locking
   - Tokens locked until specified timestamp
   - Requires normal fee (20 USDC)

3. **Vesting Lock**
   - Advanced vesting schedule
   - Configurable cliff period
   - Multiple release slots
   - Requires vesting fee (50 USDC)

## Key Features

- **Gas Efficient**: Uses Clone Factory pattern for deploying new locks
- **Flexible Locking**: Multiple locking mechanisms for different needs
- **Fee System**: 
  - USDC-based fee structure
  - Whitelisted tokens exempt from fees
  - Configurable fee amounts
- **Security**:
  - Reentrancy protection
  - Owner-based access control
  - Initialization guards

## Usage

### Creating Locks

```solidity
// Basic Lock
factory.lockBasic(tokenAddress, amount);

// Normal Lock
factory.lockNormal(tokenAddress, amount, unlockTime);

// Vesting Lock
factory.lockVesting(
    tokenAddress, 
    amount, 
    unlockTime, 
    cliffPeriod,
    recipient,
    slots
);

```
## Admin Functions
 - Set fee amounts
 - Update fee token
 - Manage token whitelist
 - Update fee admin/collector

## Fee Structure
 - Basic Lock: 10 USDC
 - Normal Lock: 20 USDC
 - Vesting Lock: 50 USDC
 - Whitelisted tokens: No fee


## Security Considerations
 - All contracts use OpenZeppelin's secure base contracts
 -Functions protected against reentrancy
 - Initialization can only happen once
 -Owner-based access control for withdrawals
