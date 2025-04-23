// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { Swappee } from "src/Swappee.sol";
import { ISwappee } from "src/interfaces/ISwappee.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WithdrawFeesSwappee is Script {
    address payable internal constant SWAPPEE_PROXY = payable(0x072099d9e6be7977fB726a2F276987224044d74e);
    address internal constant HONEY = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;
    address internal constant BERA = address(0);

    function run() public pure {
        console2.log("Run specific function");
        console2.log("- withdrawAllFeesAndTransferToReceiver(address receiver)");
        console2.log("- withdrawAllFees()");
    }

    function withdrawAllFeesAndTransferToReceiver(address receiver) public {
        vm.startBroadcast();

        uint256 beraFees = Swappee(SWAPPEE_PROXY).accruedFees(BERA);
        uint256 honeyFees = Swappee(SWAPPEE_PROXY).accruedFees(HONEY);

        Swappee(SWAPPEE_PROXY).withdrawFees(BERA, beraFees);
        Swappee(SWAPPEE_PROXY).withdrawFees(HONEY, honeyFees);

        _withdrawFees(BERA, beraFees, receiver);
        _withdrawFees(HONEY, honeyFees, receiver);

        vm.stopBroadcast();
    }

    function withdrawAllFees() public {
        vm.startBroadcast();

        uint256 beraFees = Swappee(SWAPPEE_PROXY).accruedFees(BERA);
        uint256 honeyFees = Swappee(SWAPPEE_PROXY).accruedFees(HONEY);

        _withdrawFees(BERA, beraFees, msg.sender);
        _withdrawFees(HONEY, honeyFees, msg.sender);

        vm.stopBroadcast();
    }

    function _withdrawFees(address token, uint256 amount, address receiver) internal {
        Swappee(SWAPPEE_PROXY).withdrawFees(token, amount);

        if (receiver != msg.sender) {
            if (token == address(0)) {
                (bool success,) = payable(receiver).call{ value: amount }("");
                require(success, "WithdrawFeesSwappee | Failed to transfer BERA fees");
            } else {
                IERC20(token).transfer(receiver, amount);
            }
            console2.log("WithdrawFeesSwappee | Fees transferred to:", receiver);
        }
    }
}
