/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { Swappee } from "src/Swappee.sol";
import { ISwappee } from "src/interfaces/ISwappee.sol";
import { IOBRouter } from "src/interfaces/external/IOBRouter.sol";
import { IBGTIncentiveDistributor } from "src/interfaces/external/IBGTIncentiveDistributor.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// This is an e2e test template, leave it commented out to avoid running it on CI.
contract H01Test is Test {
    Swappee swappee;

    address internal bgtIncentiveDistributor = 0xBDDba144482049382eC79CadfA02f0fa0F462dE3;
    address internal obAggregator = 0xFd88aD4849BA0F729D6fF4bC27Ff948Ab1Ac3dE7;
    address internal userAddress = 0x7E8D41FFDbfB8Bdb5D3D4F74a9FC872496f9246e;

    function setUp() public {
        vm.createSelectFork("https://rpc.berachain.com", 4043475);

        address swappeeImplementation = address(new Swappee());
        bytes memory data = abi.encodeCall(Swappee.initialize, (bgtIncentiveDistributor, obAggregator));
        swappee = Swappee(payable(new ERC1967Proxy(swappeeImplementation, data)));

    }

    struct JsonClaims {
        IBGTIncentiveDistributor.Claim[] claims;
    }

    function test_claimAndSwapWBERAforBERA() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/test/integration/data/H-01_input.json");
        string memory json = vm.readFile(path);
        bytes memory input = vm.parseJson(json, ".claims");
        IBGTIncentiveDistributor.Claim[] memory claims = abi.decode(input, (IBGTIncentiveDistributor.Claim[]));

        bytes memory routerParamsInput = vm.parseJson(json, ".routerParams");
        ISwappee.RouterParams[] memory routerParams = abi.decode(routerParamsInput, (ISwappee.RouterParams[]));

        // address tokenOut = vm.parseJsonAddress(json, ".tokenOut");

        console2.log("Claimed amount and amount to swap:", routerParams[0].swapTokenInfo.inputAmount);

        uint256 nativeBalanceBefore = userAddress.balance;
        console2.log("nativeBalanceBefore", nativeBalanceBefore);
        uint256 wrappedBalanceBefore = IERC20(0x6969696969696969696969696969696969696969).balanceOf(userAddress);
        console2.log("wrappedBalanceBefore", wrappedBalanceBefore);

        vm.startPrank(userAddress);
        IERC20(0x6969696969696969696969696969696969696969).approve(address(swappee), type(uint256).max);
        swappee.swappee(claims, routerParams, address(0));
        vm.stopPrank();

        uint256 nativeBalanceAfter = userAddress.balance;
        console2.log("nativeBalanceAfter", nativeBalanceAfter);
        uint256 wrappedBalanceAfter = IERC20(0x6969696969696969696969696969696969696969).balanceOf(userAddress);
        console2.log("wrappedBalanceAfter", wrappedBalanceAfter);
        assertEq(nativeBalanceAfter - nativeBalanceBefore, 425442483921888960);
        console2.log("Native token earned (nativeBalanceAfter - nativeBalanceBefore):", nativeBalanceAfter - nativeBalanceBefore);
        assertEq(wrappedBalanceAfter, wrappedBalanceBefore);
    }
}
