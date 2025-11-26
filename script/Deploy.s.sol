// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/StomaTrade.sol";
import "../src/MockIDRX.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Nilai supply awal untuk MockIDRX (100 Juta Token, tanpa dikalikan 10^18 karena constructor MockIDRX sudah mengalikannya)
        uint256 initialSupplyIDRX = 100_000_000; 

        // 1. Deploy Mock IDRX Token. Membutuhkan initialSupply.
        // MockIDRX constructor akan mengalikan nilai ini dengan 10**decimals()
        MockIDRX idrxToken = new MockIDRX(initialSupplyIDRX);
        console.log("IDRX Token deployed at:", address(idrxToken));

        // 2. Deploy StomaTrade Contract. Membutuhkan address token IDRX.
        StomaTrade stomaTrade = new StomaTrade(address(idrxToken));
        console.log("StomaTrade deployed at:", address(stomaTrade));

        // Catatan: Token 10 juta (sudah ada di initialSupply) sudah otomatis di mint ke deployer
        // Jika Anda ingin mint tambahan (10 juta IDRX lagi), gunakan fungsi mint:
        // idrxToken.mint(msg.sender, 10_000_000);
        // console.log("Minted 10M IDRX (tambahan) to deployer:", msg.sender);
        
        vm.stopBroadcast();
    }
}