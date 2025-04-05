// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/TokenLockFactory.sol";
import "../src/locks/BasicLock.sol";
import "../src/locks/NormalLock.sol";
import "../src/Errors.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// MockERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18); // 1 million tokens with 18 decimals
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract LockTest is Test {
    TokenLockFactory factory;
    MockERC20 mockToken;

    address user1;
    address user2;

    // USDC on Polygon mainnet
    address constant USDC_POLYGON = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address constant USDC_WHALE = 0x234bb412782E4E6Dd382e086c7622F5eE3F03Fe1;

    IERC20 usdc;

    uint256 mainnetFork;


event FeeAmountBasicUpdated(uint256 indexed newFee);
event FeeAmountNormalUpdated(uint256 indexed newFee);

event FeeTokenUpdated(IERC20 indexed newFeeToken);
event FeeAdminUpdated(address indexed newFeeAdmin);
event FeeCollectorUpdated(address indexed  newFeeCollector);
event TokenWhitelisted(address indexed token, bool status);

    function setUp() public {
        // create fork of Polygon mainnet
        string memory POLYGON_RPC_URL = vm.envString("POLYGON_RPC_URL");
        mainnetFork = vm.createFork(POLYGON_RPC_URL);
        vm.selectFork(mainnetFork);

        // setting up test accounts
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // deploy mock token and factory
        mockToken = new MockERC20("Mock Token", "MOCK");
        factory = new TokenLockFactory();

        // Set USDC fee token
        usdc = IERC20(USDC_POLYGON);

        // Fund users with mock tokens
        mockToken.transfer(user1, 100000 * 10 ** 18);
        mockToken.transfer(user2, 100000 * 10 ** 18);

        // Get USDC from a whale for testing fees
        vm.startPrank(USDC_WHALE);
        uint256 usdcAmount = 1000 * 10 ** 6; // 1000 USDC
        usdc.transfer(user1, usdcAmount);
        usdc.transfer(user2, usdcAmount);
        vm.stopPrank();
    }

    /* Basic Lock Tests */

    function testBasicLockCreationAndWithdrawal() public {
        uint256 lockAmount = 1000 * 10 ** 18; // 1000 tokens
        uint256 balanceBefore = mockToken.balanceOf(user1);

        // Approve tokens and fee for lock
        vm.startPrank(user1);
        mockToken.approve(address(factory), lockAmount);
        usdc.approve(address(factory), factory.lockFeeAmountBasic());

        // Create basic lock
        factory.lockBasic(address(mockToken), lockAmount);
        vm.stopPrank();

        // Verify lock creation
        TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
        assertEq(locks.length, 1);
        assertEq(uint256(locks[0].lockType), uint256(TokenLockFactory.LockType.BASIC));

        BasicLock lock = BasicLock(locks[0].lockAddress);
        assertEq(lock.getOwner(), user1);
        assertEq(lock.getAmount(), lockAmount);
        assertEq(lock.getToken(), address(mockToken));

        // Verify token transfer
        assertEq(mockToken.balanceOf(address(lock)), lockAmount);
        assertEq(mockToken.balanceOf(user1), balanceBefore - lockAmount);

        // Withdraw tokens
        vm.prank(user1);
        lock.withdraw();

        // Verify tokens returned to user
        assertEq(mockToken.balanceOf(user1), balanceBefore);
        assertEq(mockToken.balanceOf(address(lock)), 0);
        assertEq(lock.getReleasedAmount(), lockAmount);
    }

    function testBasicLockUnauthorizedWithdrawal() public {
        uint256 lockAmount = 1000 * 10 ** 18;

        // create lock as user1
        vm.startPrank(user1);
        mockToken.approve(address(factory), lockAmount);
        usdc.approve(address(factory), factory.lockFeeAmountBasic());
        factory.lockBasic(address(mockToken), lockAmount);
        vm.stopPrank();

        TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
        BasicLock lock = BasicLock(locks[0].lockAddress);

        // attempt unauthorized withdrawal as user2
        vm.prank(user2);
        vm.expectRevert(InvalidOwner.selector);
        lock.withdraw();
    }

    function testBasicLockFeePayout() public {
        uint256 lockAmount = 1000 * 10**18;
        address feeCollector = factory.feeCollector();
        uint256 feeCollectorBalanceBefore = usdc.balanceOf(feeCollector);
        uint256 expectedFee = factory.lockFeeAmountBasic();

        // create lock with fee
        vm.startPrank(user1);
        mockToken.approve(address(factory), lockAmount);
        usdc.approve(address(factory), expectedFee);
        factory.lockBasic(address(mockToken), lockAmount);
        vm.stopPrank();

        // verify fee paid correctly
        uint256 feeCollectorBalanceAfter = usdc.balanceOf(feeCollector);
        assertEq(feeCollectorBalanceAfter, feeCollectorBalanceBefore + expectedFee);
    }

    /* Normal Lock Tests */

    function testNormalLockCreationAndWithdrawal() public {
        uint256 lockAmount = 1000 * 10**18;
        uint256 unlockTime = block.timestamp + 7 days;
        uint256 balanceBefore = mockToken.balanceOf(user1);

        // create normal lock
        vm.startPrank(user1);
        mockToken.approve(address(factory), lockAmount);
        usdc.approve(address(factory), factory.lockFeeAmountNormal());
        factory.lockNormal(address(mockToken), lockAmount, unlockTime);
        vm.stopPrank();

        // verify lock creation
        TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
        assertEq(locks.length, 1);
        assertEq(uint256(locks[0].lockType), uint256(TokenLockFactory.LockType.NORMAL));

        NormalLock lock = NormalLock(locks[0].lockAddress);
        assertEq(lock.getOwner(), user1);
        assertEq(lock.getAmount(), lockAmount);
        assertEq(lock.getUnlockTime(), unlockTime);

        // try to withdraw early (should fail)
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TokenStillLocked.selector, block.timestamp, unlockTime));
        lock.withdraw();

        // advance time past unlock time
        vm.warp(unlockTime + 1);

        // now withdrawal should succeed
        vm.prank(user1);
        lock.withdraw();

        // verify tokens returned
        assertEq(mockToken.balanceOf(user1), balanceBefore);
        assertEq(lock.getReleasedAmount(), lockAmount);
    }

    function testNormalLockUnauthorizedWithdrawal() public {
        uint256 lockAmount = 1000 * 10**18;
        uint256 unlockTime = block.timestamp + 7 days;

        // create lock as user1
        vm.startPrank(user1);
        mockToken.approve(address(factory), lockAmount);
        usdc.approve(address(factory), factory.lockFeeAmountNormal());
        factory.lockNormal(address(mockToken), lockAmount, unlockTime);
        vm.stopPrank();

        TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
        NormalLock lock = NormalLock(locks[0].lockAddress);

        // skip to unlock time
        vm.warp(unlockTime + 1);

        // attempt unauthorized withdrawal as user2
        vm.prank(user2);
        vm.expectRevert(InvalidOwner.selector);
        lock.withdraw();
    }

    function testNormalLockWithFeeExemption() public {
        uint256 lockAmount = 1000 * 10**18;
        uint256 unlockTime = block.timestamp + 7 days;

        // whitelist the mock token to make it fee-exempt
        vm.prank(factory.feeAdmin());
        factory.setTokenWhitelist(address(mockToken), true);

        // create lock (should not require fee)
        vm.startPrank(user1);
        mockToken.approve(address(factory), lockAmount);
        factory.lockNormal(address(mockToken), lockAmount, unlockTime);
        vm.stopPrank();

        // verify lock creation successful without fee
        TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
        assertEq(locks.length, 1);
    }

    function testMultipleLockCreation() public {
        uint256 lockAmount = 1000 * 10**18;
        uint256 unlockTime = block.timestamp + 7 days;

        // approve tokens and fees
        vm.startPrank(user1);
        mockToken.approve(address(factory), lockAmount * 3);
        usdc.approve(address(factory),
            factory.lockFeeAmountBasic() +
            factory.lockFeeAmountNormal() * 2
        );

        // create multiple locks
        factory.lockBasic(address(mockToken), lockAmount);
        factory.lockNormal(address(mockToken), lockAmount, unlockTime);
        factory.lockNormal(address(mockToken), lockAmount, unlockTime + 30 days);
        vm.stopPrank();

        // verify all locks created
        TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
        assertEq(locks.length, 3);
        assertEq(uint256(locks[0].lockType), uint256(TokenLockFactory.LockType.BASIC));
        assertEq(uint256(locks[1].lockType), uint256(TokenLockFactory.LockType.NORMAL));
        assertEq(uint256(locks[2].lockType), uint256(TokenLockFactory.LockType.NORMAL));
    }

 

   function testFailInsufficientBalance() public {
    uint256 lockAmount = 1_000_00000_000 * 10**18; 

    vm.startPrank(user1);
    mockToken.approve(address(factory), lockAmount);
    usdc.approve(address(factory), factory.lockFeeAmountBasic());
    
    factory.lockBasic(address(mockToken), lockAmount);
    vm.stopPrank();
}


function testUpdateBasicFeeAmount() public {
    uint256 initialFee = factory.lockFeeAmountBasic();
    uint256 newFee = initialFee * 2; 
    
    // update fee as admin
    vm.prank(factory.feeAdmin());
    factory.updatelockFeeAmountBasic(newFee);
    
    // verify fee was updated correctly
    assertEq(factory.lockFeeAmountBasic(), newFee);
    
    // test creating a lock with the new fee
    vm.startPrank(user1);
    mockToken.approve(address(factory), 1000 * 10**18);
    usdc.approve(address(factory), newFee); 
    factory.lockBasic(address(mockToken), 1000 * 10**18);
    vm.stopPrank();
    
    // verify lock was created
    TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    assertEq(locks.length, 1);
}

function testUpdateNormalFeeAmount() public {
    uint256 initialFee = factory.lockFeeAmountNormal();
    uint256 newFee = initialFee * 2; 
    
    // update fee as admin
    vm.prank(factory.feeAdmin());
    factory.updatelockFeeAmountNormal(newFee);
    
    // verify fee was updated correctly
    assertEq(factory.lockFeeAmountNormal(), newFee);
    
    // test creating a lock with the new fee
    uint256 unlockTime = block.timestamp + 7 days;
    vm.startPrank(user1);
    mockToken.approve(address(factory), 1000 * 10**18);
    usdc.approve(address(factory), newFee); // Approve the new fee amount
    factory.lockNormal(address(mockToken), 1000 * 10**18, unlockTime);
    vm.stopPrank();
    
    // verify lock was created
    TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    assertEq(locks.length, 1);
}

function testUnauthorizedUpdateBasicFeeAmount() public {
    uint256 initialFee = factory.lockFeeAmountBasic();
    uint256 newFee = initialFee * 2;
    
    // Try to update fee as non-admin user
    vm.prank(user1);
    vm.expectRevert(NotFeeAdmin.selector);
    factory.updatelockFeeAmountBasic(newFee);
    
    // verify fee is not updated
    assertEq(factory.lockFeeAmountBasic(), initialFee);
}

function testUnauthorizedUpdateNormalFeeAmount() public {
    uint256 initialFee = factory.lockFeeAmountNormal();
    uint256 newFee = initialFee * 2;
    
    // try to update fee as non-admin user
    vm.prank(user2);
    vm.expectRevert(NotFeeAdmin.selector);
    factory.updatelockFeeAmountNormal(newFee);
    
    // verify fee is not updated
    assertEq(factory.lockFeeAmountNormal(), initialFee);
}

function testUpdateFeesToZero() public {
    // update basic fee to zero
    vm.startPrank(factory.feeAdmin());
    factory.updatelockFeeAmountBasic(0);
    assertEq(factory.lockFeeAmountBasic(), 0);
    
    // Update normal fee to zero
    factory.updatelockFeeAmountNormal(0);
    assertEq(factory.lockFeeAmountNormal(), 0);
    vm.stopPrank();
    
    // Test creating locks with zero fee
    vm.startPrank(user1);
    mockToken.approve(address(factory), 2000 * 10**18);
    
    // No need to approve USDC since fee is zero
    factory.lockBasic(address(mockToken), 1000 * 10**18);
    factory.lockNormal(address(mockToken), 1000 * 10**18, block.timestamp + 7 days);
    vm.stopPrank();
    
    // Verify locks were created
    TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    assertEq(locks.length, 2);
}

function testFeeUpdatedEvent() public {
    uint256 newBasicFee = 20 * 10**6; // 20 USDC
    uint256 newNormalFee = 30 * 10**6; // 30 USDC
    
    // test BasicFee update event
    vm.prank(factory.feeAdmin());
    vm.expectEmit(false, false, false, true);
    emit FeeAmountBasicUpdated(newBasicFee);
    factory.updatelockFeeAmountBasic(newBasicFee);
    
    // test NormalFee update event
    vm.prank(factory.feeAdmin());
    vm.expectEmit(false, false, false, true);
    emit FeeAmountNormalUpdated(newNormalFee);
    factory.updatelockFeeAmountNormal(newNormalFee);
}



function testUpdateLockFeeToken() public {
    // Create a new mock token to use as fee token
    MockERC20 newFeeToken = new MockERC20("New Fee Token", "NFT");
    
    // Update fee token as admin
    vm.prank(factory.feeAdmin());
    factory.updateLockFeeToken(IERC20(address(newFeeToken)));
    
    // Verify fee token was updated
    assertEq(address(factory.lockFeeToken()), address(newFeeToken));
    
    // Test creating a lock with the new fee token
    uint256 lockAmount = 1000 * 10**18;
    uint256 feeAmount = factory.lockFeeAmountBasic();
    
    // Transfer some new fee tokens to user1
    newFeeToken.transfer(user1, 10000 * 10**18);
    
    // Create a lock using the new fee token
    vm.startPrank(user1);
    mockToken.approve(address(factory), lockAmount);
    newFeeToken.approve(address(factory), feeAmount);
    factory.lockBasic(address(mockToken), lockAmount);
    vm.stopPrank();
    
    // Verify lock was created
    TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    assertEq(locks.length, 1);
    
    // Verify fee was paid in new token
    assertEq(newFeeToken.balanceOf(factory.feeAdmin()), feeAmount);
}

function testUnauthorizedUpdateLockFeeToken() public {
    MockERC20 newFeeToken = new MockERC20("New Fee Token", "NFT");
    address originalFeeToken = address(factory.lockFeeToken());
    
    // try to update fee token as non-admin
    vm.prank(user1);
    vm.expectRevert(NotFeeAdmin.selector);
    factory.updateLockFeeToken(IERC20(address(newFeeToken)));
    
    // verify fee token was not  updated
    assertEq(address(factory.lockFeeToken()), originalFeeToken);
}

function testUpdateFeeAdmin() public {
    address oldFeeAdmin = factory.feeAdmin();
    address newFeeAdmin = address(0x123); 
    
    // Update fee admin
    vm.prank(oldFeeAdmin);
    factory.updateFeeAdmin(newFeeAdmin);
    
    // Verify fee admin was updated
    assertEq(factory.feeAdmin(), newFeeAdmin);
    
    // Test that old admin no longer has privileges
    vm.prank(oldFeeAdmin);
    vm.expectRevert(NotFeeAdmin.selector);
    factory.updateFeeAdmin(address(0x456));
    
    // Test that new admin has privileges
    MockERC20 newFeeToken = new MockERC20("Newer Fee Token", "NFT2");
    vm.prank(newFeeAdmin);
    factory.updateLockFeeToken(IERC20(address(newFeeToken)));
    
    // Verify the change was successful
    assertEq(address(factory.lockFeeToken()), address(newFeeToken));
}

function testUnauthorizedUpdateFeeAdmin() public {
    address originalFeeAdmin = factory.feeAdmin();
    address newFeeAdmin = address(0x123);
    
    // try to update fee admin as non-admin
    vm.prank(user1);
    vm.expectRevert(NotFeeAdmin.selector);
    factory.updateFeeAdmin(newFeeAdmin);
    
    // verify fee admin was not updated
    assertEq(factory.feeAdmin(), originalFeeAdmin);
}

function testUpdateFeeCollector() public {
    address oldFeeCollector = factory.feeCollector();
    address newFeeCollector = address(0x789);
    
    // update fee collector
    vm.prank(factory.feeAdmin());
    factory.updateFeeCollector(newFeeCollector);
    
    // verify fee collector was updated
    assertEq(factory.feeCollector(), newFeeCollector);
    
    // test that fees now go to the new collector
    uint256 lockAmount = 1000 * 10**18;
    uint256 feeAmount = factory.lockFeeAmountBasic();
    
    uint256 collectorBalanceBefore = usdc.balanceOf(newFeeCollector);
    
    vm.startPrank(user1);
    mockToken.approve(address(factory), lockAmount);
    usdc.approve(address(factory), feeAmount);
    factory.lockBasic(address(mockToken), lockAmount);
    vm.stopPrank();
    
    // verify fee was sent to new collector
    assertEq(usdc.balanceOf(newFeeCollector), collectorBalanceBefore + feeAmount);
}

function testUnauthorizedUpdateFeeCollector() public {
    address originalFeeCollector = factory.feeCollector();
    address newFeeCollector = address(0x789);
    
    // try to update fee collector as non-admin
    vm.prank(user2);
    vm.expectRevert(NotFeeAdmin.selector);
    factory.updateFeeCollector(newFeeCollector);
    
    // verify fee collector was not updated
    assertEq(factory.feeCollector(), originalFeeCollector);
}

function testZeroAddressValidations() public {
    vm.startPrank(factory.feeAdmin());
    
    // try to set fee admin to zero address
    vm.expectRevert(ZeroAddress.selector);
    factory.updateFeeAdmin(address(0));
    
    // try to set fee collector to zero address
    vm.expectRevert(ZeroAddress.selector);
    factory.updateFeeCollector(address(0));
    
    // try to set fee token to zero address
    vm.expectRevert(ZeroAddress.selector);
    factory.updateLockFeeToken(IERC20(address(0)));
    
    vm.stopPrank();
}





function testSetTokenWhitelist() public {
    address tokenAddress = address(mockToken);
    
    // Verify token is not whitelisted initially
    assertEq(factory.whitelistedTokens(tokenAddress), false);
    
    // Whitelist token as admin
    vm.prank(factory.feeAdmin());
    factory.setTokenWhitelist(tokenAddress, true);
    
    // Verify token is now whitelisted
    assertEq(factory.whitelistedTokens(tokenAddress), true);
    
    // Test creating a lock with whitelisted token (no fee should be charged)
    uint256 lockAmount = 1000 * 10**18;
    
    // Record balances before
    uint256 user1UsdcBefore = usdc.balanceOf(user1);
    uint256 adminUsdcBefore = usdc.balanceOf(factory.feeAdmin());
    
    // Create lock without approving USDC (since no fee needed)
    vm.startPrank(user1);
    mockToken.approve(address(factory), lockAmount);
    factory.lockBasic(address(mockToken), lockAmount);
    vm.stopPrank();
    
    // Verify lock was created
    TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    assertEq(locks.length, 1);
    
    // Verify no USDC was charged
    assertEq(usdc.balanceOf(user1), user1UsdcBefore);
    assertEq(usdc.balanceOf(factory.feeAdmin()), adminUsdcBefore);
    
    // Un-whitelist the token
    vm.prank(factory.feeAdmin());
    factory.setTokenWhitelist(tokenAddress, false);
    
    // Verify token is no longer whitelisted
    assertEq(factory.whitelistedTokens(tokenAddress), false);
    
    // Try to create another lock (should require fee now)
    vm.startPrank(user1);
    mockToken.approve(address(factory), lockAmount);
    // Without USDC approval, this should revert
    vm.expectRevert();
    factory.lockBasic(address(mockToken), lockAmount);
    vm.stopPrank();
}

function testUnauthorizedSetTokenWhitelist() public {
    address tokenAddress = address(mockToken);
    
    // Try to whitelist token as non-admin
    vm.prank(user1);
    vm.expectRevert(NotFeeAdmin.selector);
    factory.setTokenWhitelist(tokenAddress, true);
    
    // Verify token is still not whitelisted
    assertEq(factory.whitelistedTokens(tokenAddress), false);
}



function testMultipleWhitelistedTokens() public {
    // Create additional test tokens
    MockERC20 token2 = new MockERC20("Token 2", "TK2");
    MockERC20 token3 = new MockERC20("Token 3", "TK3");
    
    // Transfer some tokens to users
    token2.transfer(user1, 10000 * 10**18);
    token3.transfer(user1, 10000 * 10**18);
    
    // Whitelist multiple tokens
    vm.startPrank(factory.feeAdmin());
    factory.setTokenWhitelist(address(mockToken), true);
    factory.setTokenWhitelist(address(token2), true);
    vm.stopPrank();
    
    // Verify whitelisting status
    assertEq(factory.whitelistedTokens(address(mockToken)), true);
    assertEq(factory.whitelistedTokens(address(token2)), true);
    assertEq(factory.whitelistedTokens(address(token3)), false);
    
    // Create locks with different tokens
    vm.startPrank(user1);
    
    // Should work without fee for whitelisted tokens
    mockToken.approve(address(factory), 1000 * 10**18);
    factory.lockBasic(address(mockToken), 1000 * 10**18);
    
    token2.approve(address(factory), 1000 * 10**18);
    factory.lockBasic(address(token2), 1000 * 10**18);
    
    // Non-whitelisted token should require fee
    token3.approve(address(factory), 1000 * 10**18);
    usdc.approve(address(factory), factory.lockFeeAmountBasic());
    factory.lockBasic(address(token3), 1000 * 10**18);
    
    vm.stopPrank();
    
    // Verify all locks were created
    TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    assertEq(locks.length, 3);
}
function testBasicLockGetters() public {
    uint256 lockAmount = 1000 * 10**18;
    
    // Create basic lock
    vm.startPrank(user1);
    mockToken.approve(address(factory), lockAmount);
    usdc.approve(address(factory), factory.lockFeeAmountBasic());
    factory.lockBasic(address(mockToken), lockAmount);
    vm.stopPrank();
    
    TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    BasicLock lock = BasicLock(locks[0].lockAddress);
    
    // Test all getter functions
    assertEq(lock.getOwner(), user1);
    assertEq(lock.getToken(), address(mockToken));
    assertEq(lock.getAmount(), lockAmount);
    assertEq(lock.getUnlockTime(), 0); 
    assertEq(lock.getReleasedAmount(), 0); 
    assertEq(lock.getStartTime(), block.timestamp); 
    
    // Withdraw tokens
    vm.prank(user1);
    lock.withdraw();
    
    assertEq(lock.getReleasedAmount(), lockAmount);
    
    assertEq(lock.getOwner(), user1);
    assertEq(lock.getToken(), address(mockToken));
    assertEq(lock.getAmount(), lockAmount);
    assertEq(lock.getUnlockTime(), 0);
    assertEq(lock.getStartTime(), block.timestamp);
}

function testNormalLockGetters() public {
    uint256 lockAmount = 1000 * 10**18;
    uint256 unlockTime = block.timestamp + 7 days;
    
    // Create normal lock
    vm.startPrank(user1);
    mockToken.approve(address(factory), lockAmount);
    usdc.approve(address(factory), factory.lockFeeAmountNormal());
    factory.lockNormal(address(mockToken), lockAmount, unlockTime);
    vm.stopPrank();
    
    TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    NormalLock lock = NormalLock(locks[0].lockAddress);
    
    // Test all getter functions
    assertEq(lock.getOwner(), user1);
    assertEq(lock.getToken(), address(mockToken));
    assertEq(lock.getAmount(), lockAmount);
    assertEq(lock.getUnlockTime(), unlockTime);
    assertEq(lock.getReleasedAmount(), 0); 
    
    // Fast forward past unlock time
    vm.warp(unlockTime + 1);
    
    // Withdraw tokens
    vm.prank(user1);
    lock.withdraw();
    
    // verify getReleasedAmount returns updated value
    assertEq(lock.getReleasedAmount(), lockAmount);
    // other getters should remain unchanged
    assertEq(lock.getOwner(), user1);
    assertEq(lock.getToken(), address(mockToken));
    assertEq(lock.getAmount(), lockAmount);
    assertEq(lock.getUnlockTime(), unlockTime);
}

function testGetterConsistencyAcrossLockTypes() public {
    // Create both lock types with the same parameters
    uint256 lockAmount = 1000 * 10**18;
    uint256 unlockTime = block.timestamp + 7 days;
    
    // Approve tokens and fees
    vm.startPrank(user1);
    mockToken.approve(address(factory), lockAmount * 2);
    usdc.approve(address(factory), 
        factory.lockFeeAmountBasic() +
        factory.lockFeeAmountNormal()
    );
    
    // Create locks
    factory.lockBasic(address(mockToken), lockAmount);
    factory.lockNormal(address(mockToken), lockAmount, unlockTime);
    vm.stopPrank();
    
    TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    BasicLock basicLock = BasicLock(locks[0].lockAddress);
    NormalLock normalLock = NormalLock(locks[1].lockAddress);
    
    assertEq(basicLock.getOwner(), normalLock.getOwner());
    assertEq(basicLock.getToken(), normalLock.getToken());
    assertEq(basicLock.getAmount(), normalLock.getAmount());
    assertEq(basicLock.getStartTime(), normalLock.getStartTime());
    assertEq(basicLock.getReleasedAmount(), normalLock.getReleasedAmount());
    
    assertEq(basicLock.getUnlockTime(), 0);
    assertEq(normalLock.getUnlockTime(), unlockTime);
}

//////////////////////////////////////////////FUZZ TESTS//////////////////////////////////////////////////////////



// fuzz test for BasicLock withdraw functionality

function testFuzz_BasicLockWithdraw(uint256 lockAmount) public {
    
    // bound lockAmount to reasonable values
    vm.assume(lockAmount > 0 && lockAmount <= 1_000_000 * 10**18);
    
    // ensure user has enough tokens
    if (mockToken.balanceOf(user1) < lockAmount) {
        mockToken.mint(user1, lockAmount);
    }
    
    // create basic lock
    vm.startPrank(user1);
    mockToken.approve(address(factory), lockAmount);
    usdc.approve(address(factory), factory.lockFeeAmountBasic());
    factory.lockBasic(address(mockToken), lockAmount);
    vm.stopPrank();
    
    TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    BasicLock lock = BasicLock(locks[0].lockAddress);
    
    // record balances before withdrawal
    uint256 userBalanceBefore = mockToken.balanceOf(user1);
    uint256 lockBalanceBefore = mockToken.balanceOf(address(lock));
    
    // withdraw tokens
    vm.prank(user1);
    lock.withdraw();
    
    // verify balances after withdrawal
    assertEq(mockToken.balanceOf(user1), userBalanceBefore + lockBalanceBefore);
    assertEq(mockToken.balanceOf(address(lock)), 0);
    assertEq(lock.getReleasedAmount(), lockAmount);
}

// fuzz test for NormalLock time-dependent withdraw

function testFuzz_NormalLockWithdraw(uint256 lockAmount, uint256 timePeriod) public {
    // bound inputs to reasonable values
    vm.assume(lockAmount > 0 && lockAmount <= 1_000_000 * 10**18);
    vm.assume(timePeriod >= 1 days && timePeriod <= 365 days);
    
    // ensure user has enough tokens
    if (mockToken.balanceOf(user1) < lockAmount) {
        mockToken.mint(user1, lockAmount);
    }
    
    uint256 unlockTime = block.timestamp + timePeriod;
    
    // create normal lock
    vm.startPrank(user1);
    mockToken.approve(address(factory), lockAmount);
    usdc.approve(address(factory), factory.lockFeeAmountNormal());
    factory.lockNormal(address(mockToken), lockAmount, unlockTime);
    vm.stopPrank();
    
    TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    NormalLock lock = NormalLock(locks[0].lockAddress);
    
    // try to withdraw before unlock time (should fail)
    vm.prank(user1);
    vm.expectRevert(abi.encodeWithSelector(TokenStillLocked.selector, block.timestamp, unlockTime));
    lock.withdraw();
    
    // fast forward to unlock time
    vm.warp(unlockTime + 1);
    
    // record balances before withdrawal
    uint256 userBalanceBefore = mockToken.balanceOf(user1);
    uint256 lockBalanceBefore = mockToken.balanceOf(address(lock));
    
    // withdraw tokens
    vm.prank(user1);
    lock.withdraw();
    
    // verify balances after withdrawal
    assertEq(mockToken.balanceOf(user1), userBalanceBefore + lockBalanceBefore);
    assertEq(mockToken.balanceOf(address(lock)), 0);
    assertEq(lock.getReleasedAmount(), lockAmount);
}

// fuzz test for unauthorized withdrawal attempts
function testFuzz_UnauthorizedWithdrawals(address nonOwner) public {
    // ensure nonOwner is not user1 and not address(0)
    vm.assume(nonOwner != user1);
    vm.assume(nonOwner != address(0));
    
    uint256 lockAmount = 1000 * 10**18;
    uint256 unlockTime = block.timestamp + 7 days;
    
    // create both types of locks
    vm.startPrank(user1);
    mockToken.approve(address(factory), lockAmount * 2);
    usdc.approve(address(factory), factory.lockFeeAmountBasic() + factory.lockFeeAmountNormal());
    factory.lockBasic(address(mockToken), lockAmount);
    factory.lockNormal(address(mockToken), lockAmount, unlockTime);
    vm.stopPrank();
    
    // get lock addresses
    TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    BasicLock basicLock = BasicLock(locks[0].lockAddress);
    NormalLock normalLock = NormalLock(locks[1].lockAddress);
    
    // test unauthorized withdrawal from BasicLock
    vm.prank(nonOwner);
    vm.expectRevert(InvalidOwner.selector);
    basicLock.withdraw();
    
    // test unauthorized withdrawal from NormalLock
    vm.prank(nonOwner);
    vm.expectRevert(InvalidOwner.selector);
    normalLock.withdraw();
}

// fuzz test for multiple locks with varying amounts

function testFuzz_MultipleLockCreation(uint256[] calldata amountsInput) public {
    vm.assume(amountsInput.length > 0 && amountsInput.length <= 5); // test up to 5 locks
    
    // copy calldata to memory so we can modify it
    uint256[] memory amounts = new uint256[](amountsInput.length);
    uint256 totalAmount = 0;
    
    for (uint256 i = 0; i < amountsInput.length; i++) {
        // bound each amount to reasonable values and avoid dust amounts
        amounts[i] = bound(amountsInput[i], 10**6, 1000 * 10**18);
        totalAmount += amounts[i];
    }
    
    // ensure user has enough tokens
    if (mockToken.balanceOf(user1) < totalAmount) {
        mockToken.mint(user1, totalAmount);
    }
    
    // create multiple basic locks
    vm.startPrank(user1);
    mockToken.approve(address(factory), totalAmount);
    usdc.approve(address(factory), factory.lockFeeAmountBasic() * amounts.length);
    
    for (uint256 i = 0; i < amounts.length; i++) {
        factory.lockBasic(address(mockToken), amounts[i]);
    }
    vm.stopPrank();
    
    // verify all locks were created correctly
    TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    assertEq(locks.length, amounts.length);
    
    // verify each lock has the correct amount
    for (uint256 i = 0; i < amounts.length; i++) {
        BasicLock lock = BasicLock(locks[i].lockAddress);
        assertEq(lock.getAmount(), amounts[i]);
        assertEq(mockToken.balanceOf(address(lock)), amounts[i]);
    }
}

// fuzz test for edge cases in NormalLock with varying unlock times
function testFuzz_NormalLockEdgeCases(uint256 lockAmount, uint256 unlockOffset) public {
    // bound to reasonable values
    lockAmount = bound(lockAmount, 10**6, 1000 * 10**18);
    unlockOffset = bound(unlockOffset, 1 minutes, 10 * 365 days); // between 1 minute and 10 years
    
    uint256 unlockTime = block.timestamp + unlockOffset;
    
    // ensure user has enough tokens
    if (mockToken.balanceOf(user1) < lockAmount) {
        mockToken.mint(user1, lockAmount);
    }
    
    // create normal lock
    vm.startPrank(user1);
    mockToken.approve(address(factory), lockAmount);
    usdc.approve(address(factory), factory.lockFeeAmountNormal());
    factory.lockNormal(address(mockToken), lockAmount, unlockTime);
    vm.stopPrank();
    
    TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    NormalLock lock = NormalLock(locks[0].lockAddress);
    
    // Fast-forward to 1 second before unlock time
    vm.warp(unlockTime - 1);
    
    // try to withdraw (should still fail)
    vm.prank(user1);
    vm.expectRevert(abi.encodeWithSelector(TokenStillLocked.selector, unlockTime - 1, unlockTime));
    lock.withdraw();
    
    // Fast-forward exactly to unlock time(should pass)
    vm.warp(unlockTime);
    
    // now withdrawal should succeed
    vm.prank(user1);
    lock.withdraw();
    
    // verify withdrawal
    assertEq(mockToken.balanceOf(address(lock)), 0);
    assertEq(lock.getReleasedAmount(), lockAmount);
}

// fuzz test for whitelisted token behavior
function testFuzz_WhitelistedTokenNoFee(uint256 lockAmount) public {
    // bound lockAmount
    lockAmount = bound(lockAmount, 10**6, 1000 * 10**18);
    
    // whitelist the token
    vm.prank(factory.feeAdmin());
    factory.setTokenWhitelist(address(mockToken), true);
    
    // ensure user has enough tokens
    if (mockToken.balanceOf(user1) < lockAmount) {
        mockToken.mint(user1, lockAmount);
    }
    
    uint256 userUsdcBefore = usdc.balanceOf(user1);
    uint256 feeCollectorUsdcBefore = usdc.balanceOf(factory.feeCollector());
    
    // create lock with whitelisted token (no fee should be charged)
    vm.startPrank(user1);
    mockToken.approve(address(factory), lockAmount);
    
    // no USDC approval needed since token is whitelisted
    factory.lockBasic(address(mockToken), lockAmount);
    vm.stopPrank();
    
    // verify lock was created and no fee was charged
    TokenLockFactory.LockInfo[] memory locks = factory.getUserLocks(user1);
    assertEq(locks.length, 1);
    
    // verify USDC balances remain unchanged
    assertEq(usdc.balanceOf(user1), userUsdcBefore);
    assertEq(usdc.balanceOf(factory.feeCollector()), feeCollectorUsdcBefore);
}




    
}
