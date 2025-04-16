// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { TestnetIncetiveDistributor } from "src/testnet/TestnetIncetiveDistributor.sol";
import { TestnetOBRouter } from "src/testnet/TestnetOBRouter.sol";
import { Swappee } from "src/Swappee.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TestnetDeploy is Script {
    function run() public {
        vm.startBroadcast();

        TestnetIncetiveDistributor testnetDistributor = new TestnetIncetiveDistributor();
        TestnetOBRouter testnetRouter = new TestnetOBRouter();

        console2.log("TestnetDeploy: TestnetIncetiveDistributor deployed at:", address(testnetDistributor));
        console2.log("TestnetDeploy: TestnetIncentiveToken deployed at:", testnetDistributor.getIncentiveToken());
        console2.log("TestnetDeploy: TestnetOBRouter deployed at:", address(testnetRouter));

        address swappeeImplementation = address(new Swappee());
        console2.log("TestnetDeploy: Swappee implementation deployed at:", address(swappeeImplementation));

        bytes memory data = abi.encodeCall(Swappee.initialize, (address(testnetDistributor), address(testnetRouter)));
        address payable swappeeProxy = payable(new ERC1967Proxy(swappeeImplementation, data));
        console2.log("TestnetDeploy: Swappee proxy deployed at:", address(swappeeProxy));

        vm.stopBroadcast();
    }
}
