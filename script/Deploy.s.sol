// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../src/TokenLockFactory.sol";

// forge script script/Deploy.s.sol:DeployTokenLock --rpc-url $POL_AMOY_RPC_URL --private-key $DEPLOYER_PVT_KEY --broadcast -vvvv
// After contracts got deployed, run the following command to verify the contracts:
// forge verify-contract <contract_address> <contract_name> --chain-id 80002 --verifier-url https://api-amoy.polygonscan.com/api --etherscan-api-key $POLYGONSCAN_API_KEY
// # Verify TokenLockFactory
// forge verify-contract 0xCea3abe2f1A1E392C2E950aAbE9FCd61183A79a9 src/TokenLockFactory.sol:TokenLockFactory --chain-id 80002 --verifier-url https://api-amoy.polygonscan.com/api --etherscan-api-key $POLYGONSCAN_API_KEY

// # Verify BasicLock
// forge verify-contract 0x71E1FfF59a3516CbDd8D84a5d78AF7657df12c69 src/locks/BasicLock.sol:BasicLock --chain-id 80002 --verifier-url https://api-amoy.polygonscan.com/api --etherscan-api-key $POLYGONSCAN_API_KEY

// # Verify NormalLock
// forge verify-contract 0xa7F37A775a73D1CFFEF61624EE8D00b3536Bdc29 src/locks/NormalLock.sol:NormalLock --chain-id 80002 --verifier-url https://api-amoy.polygonscan.com/api --etherscan-api-key $POLYGONSCAN_API_KEY



contract DeployTokenLock is Script {
    function setUp() public {}

    function run() public {
        // Load deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PVT_KEY");
        
        // Start broadcasting transactions from the deployer account
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy TokenLockFactory
        TokenLockFactory factory = new TokenLockFactory();
        
        // Get implementation addresses
        address basicImpl = factory.basicImpl();
        address normalImpl = factory.normalImpl();
        
        // Log deployment information
        console.log("Deployment Information:");
        console.log("----------------------");
        console.log("Network: Polygon Amoy");
        console.log("TokenLockFactory deployed at:", address(factory));
        console.log("BasicLock implementation at:", basicImpl);
        console.log("NormalLock implementation at:", normalImpl);
        console.log("Fee Admin:", factory.feeAdmin());
        console.log("Fee Collector:", factory.feeCollector());
        console.log("Fee Token:", address(factory.lockFeeToken()));
        console.log("Basic Lock Fee:", factory.lockFeeAmountBasic());
        console.log("Normal Lock Fee:", factory.lockFeeAmountNormal());
        
        
        vm.stopBroadcast();
    }
}