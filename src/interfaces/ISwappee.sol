// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IOBRouter } from "./external/IOBRouter.sol";
import { IBGTIncentiveDistributor } from "./external/IBGTIncentiveDistributor.sol";

/**
 * @title ISwappee
 * @notice Interface for the Swappee contract that handles PoL incentive claims and token swaps and
 */
interface ISwappee {
    /**
     * @notice Parameters required for OogaBooga integration
     * @param swapTokenInfo Information about the tokens to be swapped
     * @param pathDefinition The path definition for the swap
     * @param executor The address of the executor
     * @param referralCode The referral code for the swap
     */
    struct RouterParams {
        IOBRouter.swapTokenInfo swapTokenInfo;
        bytes pathDefinition;
        address executor;
        uint32 referralCode;
    }

    /**
     * @notice Information about a user's swap
     * @param user The address of the user
     * @param amountIn The amount of tokens being swapped
     */
    struct UserInfo {
        address user;
        uint256 amountIn;
    }

    /**
     * @notice Information about a swap operation
     * @param inputToken The address of the input token
     * @param totalAmountIn The total amount of input tokens
     * @param routerParams The router parameters for the swap
     * @param userInfos Array of user information for the swap
     */
    struct SwapInfo {
        RouterParams routerParams;
        UserInfo[] userInfos;
    }

    /**
     * @notice Combined structure for claiming incentives and performing swaps
     * @param claims Array of incentive claims
     * @param swapInfos Array of swap information
     */
    struct ClaimAndSwap {
        IBGTIncentiveDistributor.Claim[] claims;
        SwapInfo[] swapInfos;
    }

    /**
     * @notice Types of operations supported by the contract
     * @dev Use a bitmask to represent the operations
     */
    enum Type {
        CLAIM_INCENTIVES,
        SWAP_TOKENS
    }

    /// @notice Error thrown when an address is zero
    error AddressZero();
    /// @notice Error thrown when an amount is invalid
    error InvalidAmount();
    /// @notice Error thrown when there is insufficient balance
    error InsufficientBalance();
    /// @notice Error thrown when a transfer operation of native tokens fails
    error TransferFailed();
    /// @notice Error thrown when the percentage fee is invalid
    error InvalidPercentageFee();
    /// @notice Error thrown when a user is invalid
    error InvalidUser();
    /// @notice Error thrown when an invariant check fails
    error InvariantCheckFailed();

    /// @notice Emitted when the BGT incentives distributor is updated
    event BgtIncentivesDistributorUpdated(
        address indexed oldBgtIncentivesDistributor, address indexed newBgtIncentivesDistributor
    );
    /// @notice Emitted when the aggregator is updated
    event AggregatorUpdated(address indexed oldAggregator, address indexed newAggregator);
    /// @notice Emitted when the percentage fee is updated
    event PercentageFeeUpdated(uint16 percentageFee);
    /// @notice Emitted when a user withdraws tokens
    event Withdraw(address indexed user, uint256 amount);
    /// @notice Emitted when fees are withdrawn
    event WithdrawFees(address indexed token, address indexed user, uint256 amount);
    /// @notice Emitted when an amount is accounted for
    event Swappee(address indexed token, address indexed user, uint256 amount);

    /**
     * @notice Executes a swappee operation
     * @dev Use this function while doing a swap for a single user
     * @param claims Array of incentive claims to process
     * @param routerParams Array of router parameters for token swaps
     * @param tokenOut The address of the token to be received
     */
    function swappee(
        IBGTIncentiveDistributor.Claim[] calldata claims,
        RouterParams[] memory routerParams,
        address tokenOut
    )
        external;

    /**
     * @notice Withdraws fees from the contract
     * @param token The address of the token to withdraw
     * @param amount The amount of fees to withdraw
     * @dev Only the admin can call this function
     */
    function withdrawFees(address token, uint256 amount) external;
}
