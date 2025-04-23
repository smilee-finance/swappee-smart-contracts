// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { Swappee } from "src/Swappee.sol";
import { ISwappee } from "src/interfaces/ISwappee.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SetFeesSwappee is Script {
    address payable internal constant SWAPPEE_PROXY = payable(0x072099d9e6be7977fB726a2F276987224044d74e);
    uint16 internal constant FEES = 169;

    function run() public {
        vm.startBroadcast();

        Swappee(SWAPPEE_PROXY).setPercentageFee(FEES);
        console2.log("SetFeesSwappee | Swappee percentage fee set to:", FEES);

        vm.stopBroadcast();
    }
}
