// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IBGTIncentiveDistributor} from "./interfaces/external/IBGTIncentiveDistributor.sol";
import {IOBRouter} from "./interfaces/external/IOBRouter.sol";
import {ISwappee} from "./interfaces/ISwappee.sol";

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

contract Swappee is ISwappee, Ownable {
    uint16 public constant ONE_HUNDRED_PERCENT = 1e4;

    address public bgtIncentivesDistributor;
    address public aggregator;
    uint16 public percentageFee;

    /// @dev token => amount
    mapping(address => uint256) public accruedFees;

    /// @dev token => user => amount
    mapping(address => mapping(address => uint256)) public amounts;

    receive() external payable {}

    constructor(
        address _bgtIncentivesDistributor,
        address _aggregator
    ) Ownable(msg.sender) {
        if (_isAddressZero(_bgtIncentivesDistributor)) revert AddressZero();
        if (_isAddressZero(_aggregator)) revert AddressZero();

        bgtIncentivesDistributor = _bgtIncentivesDistributor;
        aggregator = _aggregator;
    }

    /// @notice Sets the BGT incentives distributor
    /// @param _bgtIncentivesDistributor The address of the new BGT incentives distributor
    function setBgtIncentivesDistributor(
        address _bgtIncentivesDistributor
    ) public onlyOwner {
        if (_isAddressZero(_bgtIncentivesDistributor)) revert AddressZero();
        address oldBgtIncentivesDistributor = bgtIncentivesDistributor;
        bgtIncentivesDistributor = _bgtIncentivesDistributor;

        emit BgtIncentivesDistributorUpdated(
            oldBgtIncentivesDistributor,
            _bgtIncentivesDistributor
        );
    }

    /// @notice Sets the aggregator
    /// @param _aggregator The address of the new aggregator
    function setAggregator(address _aggregator) public onlyOwner {
        if (_isAddressZero(_aggregator)) revert AddressZero();
        address oldAggregator = aggregator;
        aggregator = _aggregator;

        emit AggregatorUpdated(oldAggregator, _aggregator);
    }

    /// @notice Sets the percentage fee
    /// @param _percentageFee The new percentage fee
    function setPercentageFee(uint16 _percentageFee) public onlyOwner {
        if (_percentageFee > ONE_HUNDRED_PERCENT) revert InvalidPercentageFee();
        percentageFee = _percentageFee;

        emit PercentageFeeUpdated(_percentageFee);
    }

    /// @inheritdoc ISwappee
    function swappee(
        IBGTIncentiveDistributor.Claim[] calldata claims,
        SwapInfo[] calldata swapInfos
    ) public {
        _claimIncentives(claims);
        // Pull tokens from users after claim
        for (uint256 i = 0; i < claims.length; i++) {
            address token = _getClaimToken(claims[i].identifier);
            IERC20(token).transferFrom(
                claims[i].account,
                address(this),
                claims[i].amount
            );
        }
        _swapTokens(swapInfos);
    }

    /// @inheritdoc ISwappee
    function withdraw(address token, uint256 amount) public {
        uint256 amountToWithdraw = amounts[token][msg.sender];
        if (amountToWithdraw < amount) revert InvalidAmount();
        if (amount > address(this).balance) revert InsufficientBalance();

        unchecked {
            amounts[token][msg.sender] -= amount;
        }

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit Withdraw(msg.sender, amount);
    }

    /// @inheritdoc ISwappee
    function withdrawFees(address token, uint256 amount) public onlyOwner {
        if (accruedFees[token] < amount) revert InvalidAmount();

        unchecked {
            accruedFees[token] -= amount;
        }

        if (token == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).transfer(msg.sender, amount);
        }

        emit WithdrawFees(token, msg.sender, amount);
    }

    function _claimIncentives(
        IBGTIncentiveDistributor.Claim[] memory claims
    ) internal {
        IBGTIncentiveDistributor(bgtIncentivesDistributor).claim(claims);
    }

    function _swapTokens(SwapInfo[] memory swapInfos) internal {
        RouterParams memory routerParams;
        for (uint256 i = 0; i < swapInfos.length; i++) {
            routerParams = swapInfos[i].routerParams;
            IERC20(swapInfos[i].inputToken).approve(
                aggregator,
                swapInfos[i].totalAmountIn
            );
            uint256 amountOut = _swapToken(
                routerParams.swapTokenInfo,
                routerParams.pathDefinition,
                routerParams.executor,
                routerParams.referralCode
            );
            uint256 fee = FixedPointMathLib.fullMulDiv(
                amountOut,
                percentageFee,
                ONE_HUNDRED_PERCENT
            );
            accruedFees[routerParams.swapTokenInfo.outputToken] += fee;

            _accountPerUser(
                swapInfos[i].userInfos,
                swapInfos[i].totalAmountIn,
                routerParams.swapTokenInfo.outputToken,
                amountOut - fee
            );
        }
    }

    function _accountPerUser(
        UserInfo[] memory userInfos,
        uint256 totalAmountIn,
        address outputToken,
        uint256 amountOut
    ) internal {
        uint256 userPercentage;
        uint256 userAmount;
        for (uint256 i = 0; i < userInfos.length; i++) {
            // Scale by WAD^2 (1e36) to maintain precision for very small percentages
            // WAD is the standard scaling factor (1e18) used in FixedPointMathLib
            userPercentage = FixedPointMathLib.fullMulDiv(
                userInfos[i].amountIn,
                1e36,
                totalAmountIn
            );
            userAmount = FixedPointMathLib.fullMulDiv(
                amountOut,
                userPercentage,
                1e36
            );
            amounts[outputToken][userInfos[i].user] += userAmount;

            emit Accounted(outputToken, userInfos[i].user, userAmount);
        }
    }

    function _getClaimToken(
        bytes32 identifier
    ) internal view returns (address) {
        (address token, , , , ) = IBGTIncentiveDistributor(
            bgtIncentivesDistributor
        ).rewards(identifier);
        return token;
    }

    function _swapToken(
        IOBRouter.swapTokenInfo memory swap,
        bytes memory pathDefinition,
        address executor,
        uint32 referralCode
    ) internal returns (uint256) {
        return
            IOBRouter(aggregator).swap(
                swap,
                pathDefinition,
                executor,
                referralCode
            );
    }

    function _isAddressZero(address _address) internal pure returns (bool) {
        return _address == address(0);
    }
}
