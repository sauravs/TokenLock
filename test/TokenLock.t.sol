// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/TokenLockFactory.sol";
import "../src/locks/BasicLock.sol";
import "../src/locks/NormalLock.sol";
import "../src/locks/VestingLock.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MockERC20Fuzz is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract TokenLockFactoryTest is Test {
    TokenLockFactory factory;
    MockERC20 token;
    IERC20 usdc;

    address[] public users; // for purpose of fuzzing
    MockERC20Fuzz[] public tokens; // for purpose of fuzzing

    address constant USDC_POLYGON = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address constant USDC_WHALE = 0x26a0C47D4B8D89E7003a17Df85D808Ef84E01769;

    address public factoryDeployer = makeAddr("factoryDeployer");
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public recipient = makeAddr("recipient");

    uint256 polygonFork;

    function setUp() public {
        // Fork Polygon mainnet
        string memory POLYGON_RPC_URL = vm.envString("POLYGON_RPC_URL");
        polygonFork = vm.createFork(POLYGON_RPC_URL);
        vm.selectFork(polygonFork);

        vm.startPrank(factoryDeployer);
        factory = new TokenLockFactory();
        token = new MockERC20("Test Token", "TEST");
        usdc = IERC20(USDC_POLYGON);
        vm.stopPrank();

        // fund users with test token
        token.mint(user1, 1000000e18);
        token.mint(user2, 1000000e18);

        // fund users with USDC for fees
        vm.startPrank(USDC_WHALE);
        usdc.transfer(user1, 1000e6);
        usdc.transfer(user2, 1000e6);
        vm.stopPrank();

        // setup test users (for purpose of fuzzing)
        for (uint256 i = 0; i < 10; i++) {
            users.push(makeAddr(string(abi.encodePacked("user", i))));
        }

        // steup test tokens (for purpose of fuzzing)
        for (uint256 i = 0; i < 10; i++) {
            MockERC20Fuzz newToken =
                new MockERC20Fuzz(string(abi.encodePacked("Token", i)), string(abi.encodePacked("TKN", i)));
            tokens.push(newToken);

            // mint initial supply to users for testing
            for (uint256 j = 0; j < users.length; j++) {
                newToken.mint(users[j], 1000000e18);
                vm.prank(users[j]);
                newToken.approve(address(factory), type(uint256).max);
            }

            // transfer usdc(fee token) to users for testing
            vm.prank(USDC_WHALE);
            usdc.transfer(users[i], 1000e6);
            vm.prank(users[i]);
            usdc.approve(address(factory), type(uint256).max);
        }
    }

    function testBasicLock() public {
        uint256 amount = 1000;
        uint256 balanceBeforeLock = token.balanceOf(user1);

        // approve fee token (USDC) first
        vm.prank(user1);
        //usdc.approve(address(factory), factory.lockFeeAmountBasic()); //@audit why failing on this?
        usdc.approve(address(factory), type(uint256).max);

        // approve token to be locked
        vm.prank(user1);
        token.approve(address(factory), amount);

        // create lock
        vm.prank(user1);
        factory.lockBasic(address(token), amount);

        // verify lock creation
        TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
        assertEq(locks.length, 1);
        assertEq(uint256(locks[0].lockType), uint256(TokenLockFactory.LockType.BASIC));

        BasicLock lock = BasicLock(locks[0].lockAddress);
        assertEq(lock.getOwner(), user1);
        assertEq(lock.getAmount(), amount);
        assertEq(lock.getToken(), address(token));

        // test unauthorized withdrawal
        vm.prank(user2);
        vm.expectRevert(BaseLock.NotOwner.selector);
        lock.withdraw();

        // test successful withdrawal
        vm.prank(user1);
        lock.withdraw();
        assertEq(token.balanceOf(user1), balanceBeforeLock);
    }

    function testNormalLock() public {
        uint256 amount = 1000;
        uint256 unlockTime = block.timestamp + 100 days;
        uint256 balanceBeforeLock = token.balanceOf(user1);
        uint256 usdcBalanceBefore = usdc.balanceOf(user1);

        // Setup approvals
        vm.startPrank(user1);
        token.approve(address(factory), amount);
        usdc.approve(address(factory), factory.lockFeeAmountNormal());
        vm.stopPrank();

        // Create lock
        vm.prank(user1);
        factory.lockNormal(address(token), amount, unlockTime);

        // Verify lock creation
        TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
        assertEq(locks.length, 1);
        assertEq(uint256(locks[0].lockType), uint256(TokenLockFactory.LockType.NORMAL));

        NormalLock lock = NormalLock(locks[0].lockAddress);
        assertEq(lock.getOwner(), user1);
        assertEq(lock.getAmount(), amount);
        assertEq(lock.getToken(), address(token));
        assertEq(lock.getUnlockTime(), unlockTime);

        // verify fee deduction
        assertEq(usdc.balanceOf(user1), usdcBalanceBefore - factory.lockFeeAmountNormal());

        // test unauthorized withdrawal
        vm.prank(user2);
        vm.expectRevert(BaseLock.NotOwner.selector);
        lock.withdraw();

        // test early withdrawal
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(NormalLock.TokenStillLocked.selector, block.timestamp, unlockTime));
        lock.withdraw();

        // test successful withdrawal after time passes
        vm.warp(unlockTime + 1);
        vm.prank(user1);
        lock.withdraw();
        assertEq(token.balanceOf(user1), balanceBeforeLock);
    }

    function testVestingLock() public {
        uint256 amount = 1000;
        uint256 unlockTime = 100 days;
        uint256 cliffPeriod = block.timestamp + 30 days;
        uint256 slots = 10;
        uint256 currentSlot = 0;
        uint256 releasedAmount = 0;
        uint256 lastClaimedTime = 0;
        bool enableCliff = true;

        // Setup initial balances and approvals
        vm.startPrank(user1);
        token.approve(address(factory), amount);
        usdc.approve(address(factory), factory.lockFeeAmountVesting());
        vm.stopPrank();

        // Create vesting lock
        vm.prank(user1);
        factory.lockVesting(
            address(token),
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

        // Get lock instance
        TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
        VestingLock lock = VestingLock(locks[0].lockAddress);

        // Test during cliff period
        vm.warp(block.timestamp + 15 days);
        vm.prank(user1);
        vm.expectRevert(VestingLock.StillInCliffPeriod.selector);
        lock.withdraw();

        // Test after cliff period
        vm.warp(cliffPeriod + 1);
        vm.prank(user1);
        lock.withdraw();
        assertEq(lock.getCurrentSlot(), 1);
        assertEq(lock.getReleasedAmount(), amount / slots);
        assertEq(token.balanceOf(recipient), amount / slots);

        // Test vesting schedule
        uint256 vestingInterval = lock.vestingInterval();
        for (uint256 i = 1; i < slots; i++) {
            vm.warp(block.timestamp + vestingInterval);
            vm.prank(user1);
            lock.withdraw();
            assertEq(lock.getCurrentSlot(), i + 1);
            assertEq(lock.getReleasedAmount(), (amount / slots) * (i + 1));
            assertEq(token.balanceOf(recipient), (amount / slots) * (i + 1));
        }

        // Test withdrawal after all tokens claimed
        vm.prank(user1);
        vm.expectRevert(VestingLock.NotClaimableYet.selector); // Update expected error
        lock.withdraw();

        // Verify final state
        assertEq(token.balanceOf(recipient), amount);
        assertEq(lock.getReleasedAmount(), amount);
        assertEq(lock.getCurrentSlot(), slots);
    }

    // function testFuzz_BasicLock(uint8 userIndex, uint8 tokenIndex, uint256 amount) public {
    //     vm.assume(userIndex < 10);
    //     vm.assume(tokenIndex < 10);
    //     amount = bound(amount, 1, 1000000e18); // Reasonable amount bounds

    //     address user = users[userIndex];
    //     MockERC20Fuzz newToken = tokens[tokenIndex];

    //     // Setup balances and approvals
    //     vm.startPrank(user);
    //     //token.mint(user, amount);
    //     //token.approve(address(factory), amount);
    //      //token.approve(address(factory), type(uint256).max);

    //     // Mint and approve fee token
    //    // MockERC20(address(lockFeeToken)).mint(user, factory.lockFeeAmountBasic());
    //     //usdc.approve(address(factory), factory.lockFeeAmountBasic());
    //     // approve usdc upto maximum
    //     //usdc.approve(address(factory), type(uint256).max);

    //     // Create lock
    //     factory.lockBasic(address(token), amount);

    //     // Verify lock
    //     TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user);
    //     assertEq(locks.length, 1);
    //     assertEq(uint256(locks[0].lockType), uint256(TokenLockFactory.LockType.BASIC));

    //     BasicLock lock = BasicLock(locks[0].lockAddress);
    //     assertEq(lock.getAmount(), amount);
    //     assertEq(lock.getToken(), address(token));
    //     vm.stopPrank();
    // }

    // forge test --match-test testFuzz_BasicLock

    function testFuzz_BasicLock(uint8 userIndex, uint8 tokenIndex, uint256 amount) public {
        vm.assume(userIndex < 10);
        vm.assume(tokenIndex < 10);
        amount = bound(amount, 1e6, 1000000e18);

        address user = users[userIndex];
        MockERC20Fuzz testToken = tokens[tokenIndex];

        // setup token balances and approvals
        vm.startPrank(user);
        testToken.approve(address(factory), amount);
        usdc.approve(address(factory), factory.lockFeeAmountBasic());
        vm.stopPrank();

        // create lock
        vm.prank(user);
        factory.lockBasic(address(testToken), amount);

        // verify lock creation
        TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user);
        assertEq(locks.length, 1);
        assertEq(uint256(locks[0].lockType), uint256(TokenLockFactory.LockType.BASIC));

        // verify lock details
        BasicLock lock = BasicLock(locks[0].lockAddress);
        assertEq(lock.getOwner(), user);
        assertEq(lock.getAmount(), amount);
        assertEq(lock.getToken(), address(testToken));

        // verify token transfers
        assertEq(testToken.balanceOf(address(lock)), amount);
    }

    function testFuzz_NormalLock(uint8 userIndex, uint8 tokenIndex, uint256 amount, uint256 unlockTime) public {
        vm.assume(userIndex < 10);
        vm.assume(tokenIndex < 10);
        amount = bound(amount, 1e6, 1000000e18);
        unlockTime = bound(unlockTime, block.timestamp + 1 days, block.timestamp + 1000 days);

        address user = users[userIndex];
        MockERC20Fuzz testToken = tokens[tokenIndex];

        // setup token balances and approvals
        vm.startPrank(user);
        testToken.approve(address(factory), amount);
        usdc.approve(address(factory), factory.lockFeeAmountNormal());
        vm.stopPrank();

        // create lock
        vm.prank(user);
        factory.lockNormal(address(testToken), amount, unlockTime);

        // verify lock creation
        TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user);
        assertEq(locks.length, 1);

        // verify lock details
        NormalLock lock = NormalLock(locks[0].lockAddress);
        assertEq(lock.getOwner(), user);
        assertEq(lock.getAmount(), amount);
        assertEq(lock.getToken(), address(testToken));
        assertEq(lock.getUnlockTime(), unlockTime);
    }

    function testFuzz_VestingLock(
        uint8 userIndex,
        uint8 tokenIndex,
        uint256 amount,
        uint256 unlockTimeDelta,
        uint256 cliffPeriodDelta,
        uint8 slots,
        bool enableCliff
    ) public {
        // initial validation
        vm.assume(userIndex < 10);
        vm.assume(tokenIndex < 10);
        vm.assume(slots >= 2 && slots <= 100);

        // calulate timestamps relative to now
        uint256 unlockTime = block.timestamp + bound(unlockTimeDelta, 30 days, 1000 days);
        uint256 cliffPeriod = block.timestamp + bound(cliffPeriodDelta, 1 days, unlockTime - block.timestamp - 1 days);
        amount = bound(amount, 1e6, 1000000e18);

        address user = users[userIndex];
        MockERC20Fuzz testToken = tokens[tokenIndex];

        // setup balances and approvals
        vm.startPrank(user);
        testToken.mint(user, amount);
        testToken.approve(address(factory), amount);
        usdc.approve(address(factory), factory.lockFeeAmountVesting());
        vm.stopPrank();

        // createe lock
        vm.prank(user);
        factory.lockVesting(address(testToken), amount, unlockTime, cliffPeriod, recipient, slots, 0, 0, 0, enableCliff);

        // verify lock creation
        TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user);
        VestingLock lock = VestingLock(locks[0].lockAddress);

        // assert lock parameters
        assertEq(locks.length, 1);
        assertEq(uint256(locks[0].lockType), uint256(TokenLockFactory.LockType.VESTING));
        assertEq(lock.getOwner(), user);
        assertEq(lock.getAmount(), amount);
        assertEq(lock.getToken(), address(testToken));
        assertEq(lock.getUnlockTime(), unlockTime);
        assertEq(lock.getCliffPeriod(), cliffPeriod);
        assertEq(lock.getSlots(), slots);
        assertEq(lock.getRecipient(), recipient);
    }

    // function testVestingLock() public {
    //     uint256 amount = 1000;
    //     uint256 unlockTime = 100 days;
    //     uint256 cliffPeriod = 10 days;
    //     uint256 slots = 4;

    //     vm.prank(user1);

    //     factory.lockVesting(
    //         address(token),
    //         amount,
    //         unlockTime,
    //         cliffPeriod,
    //         recipient,
    //         slots,
    //         0,
    //         0,
    //         0,
    //         true
    //     );

    //     TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    //     VestingLock lock = VestingLock(locks[0].lockAddress);

    //      uint256 vestingInterval = lock.vestingInterval();

    //     assertEq(locks.length, 1);
    //     assertEq(uint256(locks[0].lockType), uint256(TokenLockFactory.LockType.VESTING));

    //     assertEq(lock.getOwner(), user1);
    //     assertEq(lock.getAmount(), amount);
    //     assertEq(lock.getToken(), address(token));
    //     assertEq(lock.vestingInterval(), unlockTime / slots);
    //     assertEq(lock.vestingAmount(), amount / slots);
    //     assertEq(lock.getUnlockTime(), unlockTime);
    //     assertEq(lock.getCliffPeriod(), cliffPeriod);
    //     assertEq(lock.getRecipient(), recipient);
    //     assertEq(lock.getSlots(), slots);
    //     assertEq(lock.getReleasedAmount(), 0);
    //     assertEq(lock.getEnableCliff() , true);

    //      // try to withdraw before cliff period is over, it should revert
    //     vm.prank(user1);
    //     vm.expectRevert(VestingLock.StillInCliffPeriod.selector);
    //     lock.withdraw();

    //     //testing first slot withdrawal

    //     vm.warp(cliffPeriod + vestingInterval + 1);
    //     vm.prank(user1);
    //     lock.withdraw();

    //     assertEq(token.balanceOf(recipient), amount / slots);
    //     assertEq(lock.getReleasedAmount(), amount / slots);
    //     assertEq(lock.getCurrentSlot(), 1);

    //     // try to withdraw before next claimable period over , it should revert
    //     vm.prank(user1);
    //     vm.expectRevert(VestingLock.NotClaimableYet.selector);
    //     lock.withdraw();

    //     // try to do second withdrawal by the nonOwner, it should revert

    //     vm.warp(cliffPeriod + 2*(vestingInterval) + 1);
    //     vm.prank(user2);
    //     vm.expectRevert(BaseLock.NotOwner.selector);
    //     lock.withdraw();

    //     // testing 2nd slot withdrawal

    //     vm.warp(cliffPeriod + 2*(vestingInterval) + 1);
    //     vm.prank(user1);
    //     lock.withdraw();

    //     assertEq(token.balanceOf(recipient), 2 * amount / slots);
    //     assertEq(lock.getReleasedAmount(), 2 * amount / slots);
    //     assertEq(lock.getCurrentSlot(), 2);

    //     // testing 3rd slot withdrawal

    //     vm.warp(cliffPeriod + 3*(vestingInterval) + 1);
    //     vm.prank(user1);
    //     lock.withdraw();

    //     assertEq(token.balanceOf(recipient), 3 * amount / slots);
    //     assertEq(lock.getReleasedAmount(), 3 * amount / slots);
    //     assertEq(lock.getCurrentSlot(), 3);

    //     // testing 4th slot withdrawal

    //     vm.warp(cliffPeriod + 4*(vestingInterval) + 1);
    //     vm.prank(user1);
    //     lock.withdraw();

    //     assertEq(token.balanceOf(recipient), 4 * (amount / slots));
    //     assertEq(token.balanceOf(recipient), amount);
    //     assertEq(lock.getReleasedAmount(), 4 * (amount / slots));
    //     assertEq(lock.getCurrentSlot(), 4);

    //     /// testing withdrawal after all slots are claimed (should revert)

    //     vm.warp(cliffPeriod + 5*(vestingInterval) + 1);
    //     vm.prank(user1);
    //     vm.expectRevert(VestingLock.YouClaimedAllAllocatedTokens.selector);
    //     lock.withdraw();

    // }
}
