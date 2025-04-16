// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { Swappee } from "src/Swappee.sol";
import { ISwappee } from "src/interfaces/ISwappee.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeploySwappee is Script {
    address internal bgtIncentiveDistributor = 0xBDDba144482049382eC79CadfA02f0fa0F462dE3;
    address internal obAggregator = 0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7;

    function run() public {
        vm.startBroadcast();

        address swappeeImplementation = address(new Swappee());
        console2.log("DeploySwappee | Swappee implementation deployed at:", address(swappeeImplementation));

        bytes memory data = abi.encodeCall(Swappee.initialize, (bgtIncentiveDistributor, obAggregator));
        address payable swappeeProxy = payable(new ERC1967Proxy(swappeeImplementation, data));
        console2.log("DeploySwappee | Swappee proxy deployed at:", address(swappeeProxy));

        vm.stopBroadcast();
    }
}
