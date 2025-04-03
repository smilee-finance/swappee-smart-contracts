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
        SWAP_TOKENS,
        CLAIM_AND_SWAP
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

    function dumpIncentives(Type _type, IBGTIncentiveDistributor.Claim[] calldata claims, SwapInfo[] calldata swapInfos) public onlyOwner {
        if (_type == Type.CLAIM_INCENTIVES) {
            _claimIncentives(claims);
        } else if (_type == Type.SWAP_TOKENS) {
            // TODO: Pull token from user and approve aggregator
            _swapTokens(swapInfos);
            // TODO: Account for the amount of tokens in the contract
        } else if (_type == Type.CLAIM_AND_SWAP) {
            _claimAndSwap(claims, swapInfos);
        }
    }

    function withdraw(uint256 amount) public {
        uint256 amountToWithdraw = amounts[msg.sender];
        if (amountToWithdraw < amount) revert InvalidAmount();
        if (amount > address(this).balance) revert InsufficientBalance();

        amounts[msg.sender] -= amount;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit Withdraw(msg.sender, amount);
    }

    function _claimAndSwap(IBGTIncentiveDistributor.Claim[] memory claims, SwapInfo[] memory swapInfos) internal onlyOwner {
        _claimIncentives(claims);
        _swapTokens(swapInfos);
    }

    function _claimIncentives(IBGTIncentiveDistributor.Claim[] memory claims) internal {
        IBGTIncentiveDistributor(bgtIncentivesDistributor).claim(claims);
    }

    function _swapTokens(SwapInfo[] memory swapInfos) internal onlyOwner {
        RouterParams memory routerParams;
        for (uint256 i = 0; i < swapInfos.length; i++) {
            routerParams = swapInfos[i].routerParams;
            uint256 amountOut = _swapToken(routerParams.swaps, routerParams.pathDefinition, routerParams.executor, routerParams.referralCode);

            UserInfo[] memory userInfos = swapInfos[i].userInfos;
            uint256 userPercentage;
            uint256 totalAmountIn = swapInfos[i].totalAmountIn;
            for (uint256 j = 0; j < userInfos.length; j++) {
                // accounting for user
                userPercentage = (userInfos[j].amountIn * 1e18 / totalAmountIn);
                amounts[userInfos[j].user] += amountOut * userPercentage / 100;
            }
        }
    }

    function _swapToken(IOBRouter.swapTokenInfo memory swap, bytes memory pathDefinition, address executor, uint32 referralCode) internal returns (uint256) {
        return IOBRouter(aggregator).swap(swap, pathDefinition, executor, referralCode);
    }

    function _isAddressZero(address _address) internal pure returns (bool) {
        return _address == address(0);
    }
}
