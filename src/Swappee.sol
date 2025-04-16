// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

import { IBGTIncentiveDistributor } from "src/interfaces/external/IBGTIncentiveDistributor.sol";
import { IOBRouter } from "src/interfaces/external/IOBRouter.sol";
import { ISwappee } from "src/interfaces/ISwappee.sol";

contract Swappee is ISwappee, AccessControlUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint16 public constant ONE_HUNDRED_PERCENT = 1e4;
    bytes32 public constant SWAP_ROLE = keccak256("SWAP_ROLE");

    address public bgtIncentivesDistributor;
    address public aggregator;
    uint16 public percentageFee;

    /// @dev token => amount
    mapping(address => uint256) public accruedFees;

    /// @dev token => user => amount
    mapping(address => mapping(address => uint256)) public amounts;

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
            IERC20(inputToken).transferFrom(msg.sender, address(this), amount);

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
                routerParam.referralCode,
                tokenOut
            );

            if (amountOut > 0) {
                uint256 fee = FixedPointMathLib.fullMulDiv(amountOut, percentageFee, ONE_HUNDRED_PERCENT);
                // Account for the fee
                accruedFees[outputToken] += fee;

                if (amountOut > fee) {
                    unchecked {
                        amounts[outputToken][msg.sender] += amountOut - fee;
                        emit Accounted(outputToken, msg.sender, amountOut - fee);
                    }
                }
            }
        }
    }

    /// @inheritdoc ISwappee
    function withdraw(address token, uint256 amount) public {
        uint256 amountWithdrawable = amounts[token][msg.sender];
        if (amountWithdrawable < amount) revert InvalidAmount();

        unchecked {
            amounts[token][msg.sender] -= amount;
        }

        if (token == address(0)) {
            (bool success,) = payable(msg.sender).call{ value: amount }("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).transfer(msg.sender, amount);
        }

        emit Withdraw(msg.sender, amount);
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
            IERC20(token).transfer(msg.sender, amount);
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
        uint32 referralCode,
        address tokenOut
    )
        internal
        returns (uint256)
    {
        swap.outputReceiver = address(this);
        swap.outputToken = tokenOut;
        return IOBRouter(aggregator).swap(swap, pathDefinition, executor, referralCode);
    }

    function _isAddressZero(address _address) internal pure returns (bool) {
        return _address == address(0);
    }

    function _invariantCheck() internal {
        // Validate storage
        for (uint256 i; i < tokensToSwap.length(); i++) {
            address token = tokensToSwap.at(i);
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
