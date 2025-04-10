// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Swappee} from "src/Swappee.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBGTIncentiveDistributor} from "src/interfaces/external/IBGTIncentiveDistributor.sol";
import {IOBRouter} from "src/interfaces/external/IOBRouter.sol";
import {Swappee} from "src/Swappee.sol";
import {ISwappee} from "src/interfaces/ISwappee.sol";

contract DeploySwappee is Script {
    address internal bgtIncentiveDistributor = 0xBDDba144482049382eC79CadfA02f0fa0F462dE3;
    address internal obAggregator = 0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7;

    function run() public {
        vm.startBroadcast();
        Swappee swappee = new Swappee(bgtIncentiveDistributor, obAggregator);
        console2.log("DeploySwappee | Swappee deployed at:", address(swappee));
        vm.stopBroadcast();
    }
}
