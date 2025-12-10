// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Stomatrade} from "../src/Stomatrade.sol";
import {MockIDRX} from "../src/MockIDRX.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MockIDRX token
        MockIDRX idrx = new MockIDRX(1_000_000); // initial supply 1,000,000 IDRX

        // Deploy Stomatrade dengan IDRX token address
        Stomatrade stomatrade = new Stomatrade(address(idrx));

        vm.stopBroadcast();
        console.log("\n=========================================");
        console.log("          VERIFY CONTRACT COMMANDS");
        console.log("=========================================");

        verify("IDRX", address(idrx), "src/MockIDRX.sol:MockIDRX", abi.encode(1_000_000));
        verify("STOMATRADE", address(stomatrade), "src/Stomatrade.sol:Stomatrade", abi.encode(address(idrx)));

    }

    function verify(string memory name, address c, string memory path, bytes memory args) internal view {
            console.log(
                string.concat(
                    "[VERIFY] ", name,
                    ": forge verify-contract ",
                    vm.toString(c),
                    " ", path,
                    " --verifier blockscout",
                    " --verifier-url https://sepolia-blockscout.lisk.com/api",
                    " --constructor-args ", vm.toString(args),
                    " --chain-id ", vm.toString(block.chainid),
                    " --watch"
                )
            );
        }

}
