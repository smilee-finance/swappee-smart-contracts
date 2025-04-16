// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IOBRouter } from "../../src/interfaces/external/IOBRouter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

contract TestnetOBRouter is IOBRouter {
    uint256 public price;

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function swap(
        swapTokenInfo memory tokenInfo,
        bytes calldata, /*pathDefinition*/
        address, /*executor*/
        uint32 /*referralCode*/
    )
        external
        payable
        override
        returns (uint256 amountOut)
    {
        IERC20(tokenInfo.inputToken).transferFrom(msg.sender, address(this), tokenInfo.inputAmount);
        amountOut = (tokenInfo.outputQuote * price) / 1e18;
    }

    function swapPermit2(
        permit2Info memory permit2,
        swapTokenInfo memory tokenInfo,
        bytes calldata pathDefinition,
        address executor,
        uint32 referralCode
    )
        external
        override
        returns (uint256 amountOut)
    { }
}
