// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBGTIncentiveDistributor } from "src/interfaces/external/IBGTIncentiveDistributor.sol";
import { IOBRouter } from "src/interfaces/external/IOBRouter.sol";
import { ISwappee } from "src/interfaces/ISwappee.sol";

contract Swappee is ISwappee, AccessControlUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    uint16 public constant ONE_HUNDRED_PERCENT = 1e4;

    address public bgtIncentivesDistributor;
    address public aggregator;
    uint16 public percentageFee;

    /// @dev token => amount
    mapping(address => uint256) public accruedFees;

    // Following variables are used to prevent tampered inputs (at the end of the swap they should return to the
    // initial state)
    /// @dev token => user => amount
    mapping(address => mapping(address => uint256)) internal amountsClaimedPerWallet;

    EnumerableSet.AddressSet internal tokensToSwap;

    modifier invariantCheck() {
        _;
        _invariantCheck();
    }

    receive() external payable { }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _bgtIncentivesDistributor, address _aggregator) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();

        if (_isAddressZero(_bgtIncentivesDistributor)) revert AddressZero();
        if (_isAddressZero(_aggregator)) revert AddressZero();

        bgtIncentivesDistributor = _bgtIncentivesDistributor;
        aggregator = _aggregator;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @notice Sets the BGT incentives distributor
    /// @param _bgtIncentivesDistributor The address of the new BGT incentives distributor
    function setBgtIncentivesDistributor(address _bgtIncentivesDistributor) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_isAddressZero(_bgtIncentivesDistributor)) revert AddressZero();
        address oldBgtIncentivesDistributor = bgtIncentivesDistributor;
        bgtIncentivesDistributor = _bgtIncentivesDistributor;

        emit BgtIncentivesDistributorUpdated(oldBgtIncentivesDistributor, _bgtIncentivesDistributor);
    }

    /// @notice Sets the aggregator
    /// @param _aggregator The address of the new aggregator
    function setAggregator(address _aggregator) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_isAddressZero(_aggregator)) revert AddressZero();
        address oldAggregator = aggregator;
        aggregator = _aggregator;

        emit AggregatorUpdated(oldAggregator, _aggregator);
    }

    /// @notice Sets the percentage fee
    /// @param _percentageFee The new percentage fee
    function setPercentageFee(uint16 _percentageFee) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_percentageFee > ONE_HUNDRED_PERCENT) revert InvalidPercentageFee();
        percentageFee = _percentageFee;

        emit PercentageFeeUpdated(_percentageFee);
    }

    function swappee(
        IBGTIncentiveDistributor.Claim[] calldata claims,
        RouterParams[] memory routerParams,
        address tokenOut
    )
        public
        invariantCheck
    {
        for (uint256 i; i < claims.length; i++) {
            // User can only claim for themselves
            if (claims[i].account != msg.sender) {
                revert InvalidUser();
            }

            address token = _getClaimToken(claims[i].identifier);
            // If token in and token out are the same skip accounting
            if (token == tokenOut) {
                continue;
            }

            tokensToSwap.add(token);
            amountsClaimedPerWallet[token][claims[i].account] += claims[i].amount;
        }

        _claimIncentives(claims);

        for (uint256 i; i < routerParams.length; i++) {
            RouterParams memory routerParam = routerParams[i];
            address inputToken = routerParam.swapTokenInfo.inputToken;
            address outputToken = routerParam.swapTokenInfo.outputToken;

            uint256 amount = amountsClaimedPerWallet[inputToken][msg.sender];
            IERC20(inputToken).safeTransferFrom(msg.sender, address(this), amount);

            unchecked {
                amountsClaimedPerWallet[inputToken][msg.sender] -= amount;
            }

            if (routerParam.swapTokenInfo.inputAmount != amount) {
                revert InvalidAmount();
            }

            IERC20(inputToken).approve(aggregator, routerParam.swapTokenInfo.inputAmount);

            // Override router params to avoid tempered inputs
            routerParam.swapTokenInfo.outputReceiver = address(this);
            routerParam.swapTokenInfo.outputToken = tokenOut;

            uint256 amountOut = _swapToken(
                routerParam.swapTokenInfo,
                routerParam.pathDefinition,
                routerParam.executor,
                routerParam.referralCode
            );

            if (amountOut > 0) {
                uint256 fee = FixedPointMathLib.fullMulDiv(amountOut, percentageFee, ONE_HUNDRED_PERCENT);
                // Account for the fee
                accruedFees[outputToken] += fee;

                if (amountOut > fee) {
                    unchecked {
                        amountOut = amountOut - fee;
                    }

                    if (outputToken == address(0)) {
                        (bool success,) = payable(msg.sender).call{ value: amountOut }("");
                        if (!success) revert TransferFailed();
                    } else {
                        IERC20(outputToken).safeTransfer(msg.sender, amountOut);
                    }

                    emit Swappee(outputToken, msg.sender, amountOut);
                }
            }
        }
    }

    /// @inheritdoc ISwappee
    function withdrawFees(address token, uint256 amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (accruedFees[token] < amount) revert InvalidAmount();

        unchecked {
            accruedFees[token] -= amount;
        }

        if (token == address(0)) {
            (bool success,) = payable(msg.sender).call{ value: amount }("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit WithdrawFees(token, msg.sender, amount);
    }

    function _claimIncentives(IBGTIncentiveDistributor.Claim[] memory claims) internal {
        IBGTIncentiveDistributor(bgtIncentivesDistributor).claim(claims);
    }

    function _getClaimToken(bytes32 identifier) internal view returns (address) {
        (address token,,,,) = IBGTIncentiveDistributor(bgtIncentivesDistributor).rewards(identifier);
        return token;
    }

    function _swapToken(
        IOBRouter.swapTokenInfo memory swap,
        bytes memory pathDefinition,
        address executor,
        uint32 referralCode
    )
        internal
        returns (uint256)
    {
        return IOBRouter(aggregator).swap(swap, pathDefinition, executor, referralCode);
    }

    function _isAddressZero(address _address) internal pure returns (bool) {
        return _address == address(0);
    }

    function _invariantCheck() internal {
        // Validate storage
        address[] memory tokens = tokensToSwap.values();
        for (uint256 i; i < tokens.length; i++) {
            address token = tokens[i];
            if (amountsClaimedPerWallet[token][msg.sender] != 0) {
                revert InvariantCheckFailed();
            }
            tokensToSwap.remove(token);
        }

        if (tokensToSwap.length() > 0) {
            revert InvariantCheckFailed();
        }
    }
}
