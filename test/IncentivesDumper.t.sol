// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";

import {IncentivesDumper} from "src/IncentivesDumper.sol";
import {IIncentivesDumper} from "src/interfaces/IIncentivesDumper.sol";
import {IBGTIncentiveDistributor} from "src/interfaces/external/IBGTIncentiveDistributor.sol";
import {IOBRouter} from "src/interfaces/external/IOBRouter.sol";
import {MockOBRouter} from "@mock/MockOBRouter.sol";
import {MockBGTIncentiveDistributor} from "@mock/MockBGTIncentiveDistributor.sol";
import {MockERC20} from "@mock/MockERC20.sol";

contract IncentivesDumperTest is Test {
    uint256 public constant PRICE = 1e18; // incentives 1 : 1 BERA
    uint256 public constant CLAIM_AMOUNT = 100e18;
    uint256 public constant INFINITE_ALLOWANCE = type(uint256).max - 1;

    IncentivesDumper public incentivesDumper;

    MockERC20 public mockERC20;
    MockOBRouter public mockOBRouter;
    MockBGTIncentiveDistributor public mockBGTIncentiveDistributor;

    address public owner = makeAddr("owner");
    address public operator = makeAddr("operator");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    IOBRouter.swapTokenInfo public _dummySwaps;
    bytes public _dummyPathDefinition;
    IIncentivesDumper.RouterParams public _dummyRouterParams;

    function setUp() public {
        mockERC20 = new MockERC20("MockERC20", "MRC20", 18);

        mockOBRouter = new MockOBRouter();
        mockOBRouter.setPrice(PRICE);

        mockBGTIncentiveDistributor = new MockBGTIncentiveDistributor();
        mockBGTIncentiveDistributor.setMockedToken(address(mockERC20));
        mockERC20.mint(address(mockBGTIncentiveDistributor), type(uint256).max);

        vm.startPrank(owner);
        incentivesDumper = new IncentivesDumper(address(mockBGTIncentiveDistributor), address(mockOBRouter));
        incentivesDumper.grantRole(incentivesDumper.OPERATOR_ROLE(), operator);
        vm.stopPrank();
    }

    function test_dumpIncentives() public {
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = CLAIM_AMOUNT;

        IBGTIncentiveDistributor.Claim[] memory claims = mockBGTIncentiveDistributor.getDummyClaims(users, amounts);

        vm.prank(user1);
        mockERC20.approve(address(incentivesDumper), INFINITE_ALLOWANCE);

        IIncentivesDumper.SwapInfo[] memory swapInfos = _buildSimpleSwapInfo(user1, CLAIM_AMOUNT);

        vm.prank(operator);
        vm.expectEmit();
        emit IIncentivesDumper.Accounted(user1, CLAIM_AMOUNT); // fees are 0
        incentivesDumper.dumpIncentives(3, claims, swapInfos);

        assertEq(mockERC20.balanceOf(address(mockOBRouter)), CLAIM_AMOUNT);
        assertEq(mockERC20.balanceOf(address(incentivesDumper)), 0);
        assertEq(mockERC20.balanceOf(user1), 0);

        assertEq(mockERC20.allowance(user1, address(incentivesDumper)), INFINITE_ALLOWANCE - CLAIM_AMOUNT);
        assertEq(incentivesDumper.amounts(user1), CLAIM_AMOUNT);
        assertEq(incentivesDumper.accruedFees(), 0); // no fees
    }

    function test_dumpIncentives_MultipleUsers(uint256 amountInUser1, uint256 amountInUser2, uint256 amountInUser3) public {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = _bound(amountInUser1, 1, 100_000_000e18);
        amounts[1] = _bound(amountInUser2, 1, 100_000_000e18);
        amounts[2] = _bound(amountInUser3, 1, 100_000_000e18);

        uint256 totalAmountIn = amounts[0] + amounts[1] + amounts[2];

        IBGTIncentiveDistributor.Claim[] memory claims = mockBGTIncentiveDistributor.getDummyClaims(users, amounts);

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            mockERC20.approve(address(incentivesDumper), INFINITE_ALLOWANCE);
        }


        IIncentivesDumper.SwapInfo[] memory swapInfos = _buildMultipleUsersSwapInfo(users, amounts, totalAmountIn);

        vm.prank(operator);
        vm.expectEmit();
        emit IIncentivesDumper.Accounted(user1, amounts[0]);
        emit IIncentivesDumper.Accounted(user2, amounts[1]);
        emit IIncentivesDumper.Accounted(user3, amounts[2]);
        incentivesDumper.dumpIncentives(3, claims, swapInfos);

        assertEq(mockERC20.balanceOf(address(mockOBRouter)), totalAmountIn);
        assertEq(mockERC20.balanceOf(address(incentivesDumper)), 0);
        assertEq(mockERC20.balanceOf(user1), 0);
        assertEq(mockERC20.balanceOf(user2), 0);
        assertEq(mockERC20.balanceOf(user3), 0);

        assertEq(mockERC20.allowance(user1, address(incentivesDumper)), INFINITE_ALLOWANCE - amounts[0]);
        assertEq(mockERC20.allowance(user2, address(incentivesDumper)), INFINITE_ALLOWANCE - amounts[1]);
        assertEq(mockERC20.allowance(user3, address(incentivesDumper)), INFINITE_ALLOWANCE - amounts[2]);
        assertEq(incentivesDumper.amounts(user1), amounts[0]);
        assertEq(incentivesDumper.amounts(user2), amounts[1]);
        assertEq(incentivesDumper.amounts(user3), amounts[2]);
        assertEq(incentivesDumper.accruedFees(), 0); // no fees
    }

    function _getRouterParams(IOBRouter.swapTokenInfo memory swapTokenInfo) internal view returns (IIncentivesDumper.RouterParams memory) {
        return IIncentivesDumper.RouterParams({
            swaps: swapTokenInfo,
            pathDefinition: _dummyPathDefinition,
            executor: address(0),
            referralCode: 0
        });
    }

    function _getSwapTokenInfo(uint256 amountIn, address token, address to) internal pure returns (IOBRouter.swapTokenInfo memory) {
        return IOBRouter.swapTokenInfo({
            inputToken: token,
            inputAmount: amountIn,
            outputToken: address(0),
            outputQuote: (amountIn * PRICE) / 1e18,
            outputMin: (amountIn * PRICE) / 1e18,
            outputReceiver: to
        });
    }

    function _getUserInfos(address[] memory users, uint256[] memory amountsIn) internal pure returns (IIncentivesDumper.UserInfo[] memory) {
        IIncentivesDumper.UserInfo[] memory _userInfos = new IIncentivesDumper.UserInfo[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            _userInfos[i] = IIncentivesDumper.UserInfo({user: users[i], amountIn: amountsIn[i]});
        }
        return _userInfos;
    }

    function _getSwapInfo(address inputToken, uint256 totalAmountIn, IIncentivesDumper.RouterParams memory routerParams, IIncentivesDumper.UserInfo[] memory userInfos) internal pure returns (IIncentivesDumper.SwapInfo memory) {
        return IIncentivesDumper.SwapInfo({
            inputToken: inputToken,
            totalAmountIn: totalAmountIn,
            routerParams: routerParams,
            userInfos: userInfos
        });
    }

    /// @dev Creates a simple swap info with a single user and amount in.
    function _buildSimpleSwapInfo(address user, uint256 amountIn) internal view returns (IIncentivesDumper.SwapInfo[] memory) {
        address[] memory users = new address[](1);
        users[0] = user;
        uint256[] memory amountsIn = new uint256[](1);
        amountsIn[0] = amountIn;

        IIncentivesDumper.UserInfo[] memory _userInfos = _getUserInfos(users, amountsIn);

        IOBRouter.swapTokenInfo memory _swapTokenInfo = _getSwapTokenInfo(amountIn, address(mockERC20), address(incentivesDumper));
        IIncentivesDumper.RouterParams memory _routerParams = _getRouterParams(_swapTokenInfo);

        IIncentivesDumper.SwapInfo[] memory swapInfos = new IIncentivesDumper.SwapInfo[](1);
        swapInfos[0] = _getSwapInfo(address(mockERC20), amountIn, _routerParams, _userInfos);

        return swapInfos;
    }

    function _buildMultipleUsersSwapInfo(address[] memory users, uint256[] memory amounts, uint256 totalAmountIn) internal view returns (IIncentivesDumper.SwapInfo[] memory) {
        IIncentivesDumper.UserInfo[] memory _userInfos = _getUserInfos(users, amounts);

        IOBRouter.swapTokenInfo memory _swapTokenInfo = _getSwapTokenInfo(totalAmountIn, address(mockERC20), address(incentivesDumper));
        IIncentivesDumper.RouterParams memory _routerParams = _getRouterParams(_swapTokenInfo);

        IIncentivesDumper.SwapInfo[] memory swapInfos = new IIncentivesDumper.SwapInfo[](1);
        swapInfos[0] = _getSwapInfo(address(mockERC20), totalAmountIn, _routerParams, _userInfos);

        return swapInfos;
    }
}
