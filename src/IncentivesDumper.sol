// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

    function claimIncentives(IBGTIncentiveDistributor.Claim[] memory claims) public onlyOwner {
        IBGTIncentiveDistributor(bgtIncentivesDistributor).claim(claims);
    }

    function swapTokens(IOBRouter.swapTokenInfo[] calldata swaps, bytes[] calldata pathDefinition, address[] calldata executor, uint32[] calldata referralCode) public onlyOwner {
        if (swaps.length == pathDefinition.length && swaps.length == executor.length && swaps.length == referralCode.length) revert InvalidSwaps();

        for (uint256 i = 0; i < swaps.length; i++) {
            _swapToken(swaps[i], pathDefinition[i], executor[i], referralCode[i]);
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

    function _swapToken(IOBRouter.swapTokenInfo memory swap, bytes calldata pathDefinition, address executor, uint32 referralCode) internal {
        IOBRouter(aggregator).swap(swap, pathDefinition, executor, referralCode);
    }

    function _isAddressZero(address _address) internal pure returns (bool) {
        return _address == address(0);
    }
}
