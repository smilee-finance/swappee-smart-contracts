// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBGTIncentiveDistributor} from "./interfaces/external/IBGTIncentiveDistributor.sol";
import {IOBRouter} from "./interfaces/external/IOBRouter.sol";

contract IncentivesDumper is Ownable {
    address public bgtIncentivesDistributor;
    address public aggregator;

    mapping(address => uint256) public amounts;

    error AddressZero();
    error InvalidSwaps();
    error InvalidAmount();
    error InsufficientBalance();
    error TransferFailed();

    event Withdraw(address indexed user, uint256 amount);

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
        bgtIncentivesDistributor = _bgtIncentivesDistributor;
    }

    function setAggregator(address _aggregator) public onlyOwner {
        if (_isAddressZero(_aggregator)) revert AddressZero();
        aggregator = _aggregator;
    }

    function dumpIncentives(uint8 action, IBGTIncentiveDistributor.Claim[] calldata claims, SwapInfo[] calldata swapInfos) public onlyOwner {
        if (_shouldDo(action, Type.CLAIM_INCENTIVES)) {
            _claimIncentives(claims);
        }

        if (_shouldDo(action, Type.SWAP_TOKENS)) {
            // TODO: Pull token from user and approve aggregator
            _swapTokens(swapInfos);
            // TODO: Account for the amount of tokens in the contract
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

    function _claimIncentives(IBGTIncentiveDistributor.Claim[] memory claims) internal {
        IBGTIncentiveDistributor(bgtIncentivesDistributor).claim(claims);
    }

    function _swapTokens(SwapInfo[] memory swapInfos) internal onlyOwner {
        RouterParams memory routerParams;
        for (uint256 i = 0; i < swapInfos.length; i++) {
            routerParams = swapInfos[i].routerParams;
            uint256 amountOut = _swapToken(routerParams.swaps, routerParams.pathDefinition, routerParams.executor, routerParams.referralCode);
            _accountPerUser(swapInfos[i].userInfos, swapInfos[i].totalAmountIn, amountOut);
        }
    }

    function _accountPerUser(UserInfo[] memory userInfos, uint256 totalAmountIn, uint256 amountOut) internal {
        uint256 userPercentage;
        for (uint256 i = 0; i < userInfos.length; i++) {
            userPercentage = userInfos[i].amountIn * 1e18 / totalAmountIn;
            amounts[userInfos[i].user] += (amountOut * userPercentage) / 1e18;
        }
    }

    function _shouldDo(uint8 input, Type action) internal pure returns (bool) {
        return (input & (input << uint8(action))) != 0;
    }

    function _swapToken(IOBRouter.swapTokenInfo memory swap, bytes memory pathDefinition, address executor, uint32 referralCode) internal returns (uint256) {
        return IOBRouter(aggregator).swap(swap, pathDefinition, executor, referralCode);
    }

    function _isAddressZero(address _address) internal pure returns (bool) {
        return _address == address(0);
    }
}
