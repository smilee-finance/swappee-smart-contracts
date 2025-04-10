// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {TestnetIncetiveDistributor} from "src/testnet/TestnetIncetiveDistributor.sol";
import {TestnetOBRouter} from "src/testnet/TestnetOBRouter.sol";
import {Swappee} from "src/Swappee.sol";

contract TestnetDeploy is Script {
    function run() public {
        vm.startBroadcast();

        TestnetIncetiveDistributor testnetDistributor = new TestnetIncetiveDistributor();
        TestnetOBRouter testnetRouter = new TestnetOBRouter();

        console2.log("TestnetDeploy: TestnetIncetiveDistributor deployed at:", address(testnetDistributor));
        console2.log("TestnetDeploy: TestnetIncentiveToken deployed at:", testnetDistributor.getIncentiveToken());
        console2.log("TestnetDeploy: TestnetOBRouter deployed at:", address(testnetRouter));

        Swappee swappee = new Swappee(address(testnetDistributor), address(testnetRouter));
        console2.log("TestnetDeploy: Swappee deployed at:", address(swappee));

        vm.stopBroadcast();
    }
}
