// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBGTIncentiveDistributor} from "./interfaces/external/IBGTIncentiveDistributor.sol";
import {IOBRouter} from "./interfaces/external/IOBRouter.sol";

contract IncentivesDumper is Ownable {
    uint16 public constant ONE_HUNDRED_PERCENT = 1e4;

    address public bgtIncentivesDistributor;
    address public aggregator;
    uint16 public percentageFee;
    uint256 public accruedFees;

    mapping(address => uint256) public amounts;

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
    enum Type {
        CLAIM_INCENTIVES,
        SWAP_TOKENS
    }

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
        uint256 totalAmountIn;
        RouterParams routerParams;
        UserInfo[] userInfos;
    }

    struct ClaimAndSwap {
        IBGTIncentiveDistributor.Claim[] claims;
        SwapInfo[] swapInfos;
    }

    constructor(address _bgtIncentivesDistributor, address _aggregator) Ownable(msg.sender) {
        if (_isAddressZero(_bgtIncentivesDistributor)) revert AddressZero();
        if (_isAddressZero(_aggregator)) revert AddressZero();

        bgtIncentivesDistributor = _bgtIncentivesDistributor;
        aggregator = _aggregator;
    }

    function setBgtIncentivesDistributor(address _bgtIncentivesDistributor) public onlyOwner {
        if (_isAddressZero(_bgtIncentivesDistributor)) revert AddressZero();
        address oldBgtIncentivesDistributor = bgtIncentivesDistributor;
        bgtIncentivesDistributor = _bgtIncentivesDistributor;

        emit BgtIncentivesDistributorUpdated(oldBgtIncentivesDistributor, _bgtIncentivesDistributor);
    }

    function setAggregator(address _aggregator) public onlyOwner {
        if (_isAddressZero(_aggregator)) revert AddressZero();
        address oldAggregator = aggregator;
        aggregator = _aggregator;

        emit AggregatorUpdated(oldAggregator, _aggregator);
    }

    function setPercentageFee(uint16 _percentageFee) public onlyOwner {
        if (_percentageFee > ONE_HUNDRED_PERCENT) revert InvalidPercentageFee();
        percentageFee = _percentageFee;

        emit PercentageFeeUpdated(_percentageFee);
    }

    function dumpIncentives(uint8 action, IBGTIncentiveDistributor.Claim[] calldata claims, SwapInfo[] calldata swapInfos) public onlyOwner {
        if (_shouldDo(action, Type.CLAIM_INCENTIVES)) {
            _claimIncentives(claims);
            // TBD: As soon as the claim is done, we should pull the tokens from the user and approve the aggregator
        }

        if (_shouldDo(action, Type.SWAP_TOKENS)) {
            _swapTokens(swapInfos);
        }
    }

    function withdraw(uint256 amount) public {
        uint256 amountToWithdraw = amounts[msg.sender];
        if (amountToWithdraw < amount) revert InvalidAmount();
        if (amount > address(this).balance) revert InsufficientBalance();

        unchecked {
            amounts[msg.sender] -= amount;
        }

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit Withdraw(msg.sender, amount);
    }

    function withdrawFees(uint256 amount) public onlyOwner {
        if (accruedFees < amount) revert InvalidAmount();

        unchecked {
            accruedFees -= amount;
        }

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit WithdrawFees(msg.sender, amount);
    }

    function _claimIncentives(IBGTIncentiveDistributor.Claim[] memory claims) internal {
        IBGTIncentiveDistributor(bgtIncentivesDistributor).claim(claims);
    }

    function _swapTokens(SwapInfo[] memory swapInfos) internal onlyOwner {
        RouterParams memory routerParams;
        for (uint256 i = 0; i < swapInfos.length; i++) {
            routerParams = swapInfos[i].routerParams;
            uint256 amountOut = _swapToken(routerParams.swaps, routerParams.pathDefinition, routerParams.executor, routerParams.referralCode);
            uint256 fee = amountOut * (percentageFee) / ONE_HUNDRED_PERCENT;
            accruedFees += fee;

            _accountPerUser(swapInfos[i].userInfos, swapInfos[i].totalAmountIn, amountOut - fee);
        }
    }

    function _accountPerUser(UserInfo[] memory userInfos, uint256 totalAmountIn, uint256 amountOut) internal {
        uint256 userPercentage;
        uint256 userAmount;
        for (uint256 i = 0; i < userInfos.length; i++) {
            userPercentage = userInfos[i].amountIn * 1e18 / totalAmountIn;
            userAmount = (amountOut * userPercentage) / 1e18;
            amounts[userInfos[i].user] += userAmount;

            emit Accounted(userInfos[i].user, userAmount);
        }
    }

    function _shouldDo(uint8 input, Type action) internal pure returns (bool) {
        return (input & (1 << uint8(action))) != 0;
    }

    function _swapToken(IOBRouter.swapTokenInfo memory swap, bytes memory pathDefinition, address executor, uint32 referralCode) internal returns (uint256) {
        return IOBRouter(aggregator).swap(swap, pathDefinition, executor, referralCode);
    }

    function _isAddressZero(address _address) internal pure returns (bool) {
        return _address == address(0);
    }
}
