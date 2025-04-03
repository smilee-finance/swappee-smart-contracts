// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IOBRouter} from "./external/IOBRouter.sol";
import {IBGTIncentiveDistributor} from "./external/IBGTIncentiveDistributor.sol";

interface IIncentivesDumper {
    struct RouterParams {
        IOBRouter.swapTokenInfo swaps;
        bytes pathDefinition;
        address executor;
        uint32 referralCode;
    }

    struct UserInfo {
        address user;
        uint256 amountIn;
    }

    struct SwapInfo {
        address inputToken;
        uint256 totalAmountIn;
        RouterParams routerParams;
        UserInfo[] userInfos;
    }

    struct ClaimAndSwap {
        IBGTIncentiveDistributor.Claim[] claims;
        SwapInfo[] swapInfos;
    }

    enum Type {
        CLAIM_INCENTIVES,
        SWAP_TOKENS
    }

    error AddressZero();
    error InvalidSwaps();
    error InvalidAmount();
    error InsufficientBalance();
    error TransferFailed();
    error InvalidPercentageFee();

    event BgtIncentivesDistributorUpdated(address indexed oldBgtIncentivesDistributor, address indexed newBgtIncentivesDistributor);
    event AggregatorUpdated(address indexed oldAggregator, address indexed newAggregator);
    event PercentageFeeUpdated(uint16 percentageFee);
    event Withdraw(address indexed user, uint256 amount);
    event WithdrawFees(address indexed user, uint256 amount);
    event Accounted(address indexed user, uint256 amount);

    function dumpIncentives(uint8 action, IBGTIncentiveDistributor.Claim[] calldata claims, SwapInfo[] calldata swapInfos) external;
    function withdraw(uint256 amount) external;
    function withdrawFees(uint256 amount) external;
}
