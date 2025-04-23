// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { Swappee } from "src/Swappee.sol";
import { ISwappee } from "src/interfaces/ISwappee.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TransferOwnershipSwappee is Script {
    address payable internal constant SWAPPEE_PROXY = payable(0x072099d9e6be7977fB726a2F276987224044d74e);
    address internal constant OLD_OWNER = 0x6276aDf21EB3e484e4BB5ce59C99a48F5D093b9D;
    address internal constant NEW_OWNER = 0x2d6a4D5CAC28E6eAFb4a2d5720c40fe979fB4507;

    function run() public {
        vm.startBroadcast();

        Swappee swappee = Swappee(SWAPPEE_PROXY);

        bytes32 role = swappee.DEFAULT_ADMIN_ROLE();
        swappee.grantRole(role, NEW_OWNER);

        require(swappee.hasRole(role, NEW_OWNER), "TransferOwnershipSwappee | Swappee ownership transfer failed");
        console2.log("TransferOwnershipSwappee | Swappee ownership transferred to:", NEW_OWNER);

        swappee.renounceRole(role, OLD_OWNER);
        require(!swappee.hasRole(role, OLD_OWNER), "TransferOwnershipSwappee | Swappee ownership transfer failed");
        console2.log("TransferOwnershipSwappee | Swappee ownership transferred from:", OLD_OWNER);

        vm.stopBroadcast();
    }
}
