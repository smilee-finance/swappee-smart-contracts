// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";

import {Swappee} from "src/Swappee.sol";
import {ISwappee} from "src/interfaces/ISwappee.sol";
import {IBGTIncentiveDistributor} from "src/interfaces/external/IBGTIncentiveDistributor.sol";
import {IOBRouter} from "src/interfaces/external/IOBRouter.sol";
import {MockOBRouter} from "@mock/MockOBRouter.sol";
import {MockBGTIncentiveDistributor} from "@mock/MockBGTIncentiveDistributor.sol";
import {MockERC20} from "@mock/MockERC20.sol";

contract SwappeeTest is Test {
    uint256 public constant PRICE = 1e18; // incentives 1 : 1 BERA
    uint256 public constant CLAIM_AMOUNT = 100e18;
    uint256 public constant INFINITE_ALLOWANCE = type(uint256).max - 1;
    uint8 public constant TYPE = 3; // 00000011
    uint16 public constant ONE_HUNDRED_PERCENT = 1e4;
    uint16 public constant FEE = 1000; // 10%

    Swappee public swappee;

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
    ISwappee.RouterParams public _dummyRouterParams;

    function setUp() public {
        mockERC20 = new MockERC20("MockERC20", "MRC20", 18);

        mockOBRouter = new MockOBRouter();
        mockOBRouter.setPrice(PRICE);

        mockBGTIncentiveDistributor = new MockBGTIncentiveDistributor();
        mockBGTIncentiveDistributor.setMockedToken(address(mockERC20));
        mockERC20.mint(address(mockBGTIncentiveDistributor), type(uint256).max);

        vm.startPrank(owner);
        swappee = new Swappee(address(mockBGTIncentiveDistributor), address(mockOBRouter));
        swappee.grantRole(swappee.OPERATOR_ROLE(), operator);
        vm.stopPrank();
    }

    function test_dumpIncentives() public {
        testFuzz_dumpIncentives(CLAIM_AMOUNT);
    }

    function testFuzz_dumpIncentives(uint256 amount) public {
        amount = _bound(amount, 1, 100_000_000e18);
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        IBGTIncentiveDistributor.Claim[] memory claims = mockBGTIncentiveDistributor.getDummyClaims(users, amounts);

        vm.prank(user1);
        mockERC20.approve(address(swappee), INFINITE_ALLOWANCE);

        ISwappee.SwapInfo[] memory swapInfos = _buildSimpleSwapInfo(user1, amount);

        vm.prank(operator);
        vm.expectEmit();
        emit ISwappee.Accounted(user1, amount); // fees are 0
        swappee.swappee(TYPE, claims, swapInfos);

        assertEq(mockERC20.balanceOf(address(mockOBRouter)), amount);
        assertEq(mockERC20.balanceOf(address(swappee)), 0);
        assertEq(mockERC20.balanceOf(user1), 0);

        assertEq(swappee.amounts(user1), amount);
        assertEq(swappee.accruedFees(), 0); // no fees
    }

    function test_dumpIncentives_MultipleUsers() public {
        testFuzz_dumpIncentives_MultipleUsers(100e18, 200e18, 300e18, PRICE);
    }

    function testFuzz_dumpIncentives_MultipleUsers(uint256 amountInUser1, uint256 amountInUser2, uint256 amountInUser3, uint256 price) public {
        amountInUser1 = _bound(amountInUser1, 1, 100_000_000e18);
        amountInUser2 = _bound(amountInUser2, 1, 100_000_000e18);
        amountInUser3 = _bound(amountInUser3, 1, 100_000_000e18);
        price = _bound(price, 0.000001e18, 1_000_000e18);

        mockOBRouter.setPrice(price);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountInUser1;
        amounts[1] = amountInUser2;
        amounts[2] = amountInUser3;

        uint256 totalAmountIn = amountInUser1 + amountInUser2 + amountInUser3;

        IBGTIncentiveDistributor.Claim[] memory claims = mockBGTIncentiveDistributor.getDummyClaims(users, amounts);

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            mockERC20.approve(address(swappee), INFINITE_ALLOWANCE);
        }


        ISwappee.SwapInfo[] memory swapInfos = _buildMultipleUsersSwapInfo(users, amounts, totalAmountIn);

        vm.prank(operator);
        swappee.swappee(TYPE, claims, swapInfos);

        assertEq(mockERC20.balanceOf(address(mockOBRouter)), totalAmountIn);
        assertEq(mockERC20.balanceOf(address(swappee)), 0);
        assertEq(mockERC20.balanceOf(user1), 0);
        assertEq(mockERC20.balanceOf(user2), 0);
        assertEq(mockERC20.balanceOf(user3), 0);

        assertApproxEqAbs(swappee.amounts(user1), (amountInUser1 * price) / 1e18, 1);
        assertApproxEqAbs(swappee.amounts(user2), (amountInUser2 * price) / 1e18, 1);
        assertApproxEqAbs(swappee.amounts(user3), (amountInUser3 * price) / 1e18, 1);
        assertEq(swappee.accruedFees(), 0); // no fees
    }

    function testFuzz_dumpIncentives_MultipleUsers_WithFees(uint256 amountInUser1, uint256 amountInUser2, uint256 amountInUser3, uint256 price) public {
        amountInUser1 = _bound(amountInUser1, 1, 100_000_000e18);
        amountInUser2 = _bound(amountInUser2, 1, 100_000_000e18);
        amountInUser3 = _bound(amountInUser3, 1, 100_000_000e18);
        price = _bound(price, 0.000001e18, 1_000_000e18);

        mockOBRouter.setPrice(price);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountInUser1;
        amounts[1] = amountInUser2;
        amounts[2] = amountInUser3;

        uint256 totalAmountIn = amountInUser1 + amountInUser2 + amountInUser3;

        IBGTIncentiveDistributor.Claim[] memory claims = mockBGTIncentiveDistributor.getDummyClaims(users, amounts);

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            mockERC20.approve(address(swappee), INFINITE_ALLOWANCE);
        }


        ISwappee.SwapInfo[] memory swapInfos = _buildMultipleUsersSwapInfo(users, amounts, totalAmountIn);

        vm.prank(owner);
        swappee.setPercentageFee(FEE);

        vm.prank(operator);
        swappee.swappee(TYPE, claims, swapInfos);

        assertEq(mockERC20.balanceOf(address(mockOBRouter)), totalAmountIn);
        assertEq(mockERC20.balanceOf(address(swappee)), 0);
        assertEq(mockERC20.balanceOf(user1), 0);
        assertEq(mockERC20.balanceOf(user2), 0);
        assertEq(mockERC20.balanceOf(user3), 0);

        uint256 userPercentage = ONE_HUNDRED_PERCENT - FEE;
        uint256 amountOutUser1 = (amountInUser1 * price) / 1e18;
        uint256 amountOutUser2 = (amountInUser2 * price) / 1e18;
        uint256 amountOutUser3 = (amountInUser3 * price) / 1e18;
        uint256 amountOutTotal = amountOutUser1 + amountOutUser2 + amountOutUser3;

        assertApproxEqAbs(swappee.amounts(user1), (amountOutUser1 * userPercentage) / ONE_HUNDRED_PERCENT, 2);
        assertApproxEqAbs(swappee.amounts(user2), (amountOutUser2 * userPercentage) / ONE_HUNDRED_PERCENT, 2);
        assertApproxEqAbs(swappee.amounts(user3), (amountOutUser3 * userPercentage) / ONE_HUNDRED_PERCENT, 2);
        assertApproxEqAbs(swappee.accruedFees(), (amountOutTotal * FEE) / ONE_HUNDRED_PERCENT, 2);
    }

    function _getRouterParams(IOBRouter.swapTokenInfo memory swapTokenInfo) internal view returns (ISwappee.RouterParams memory) {
        return ISwappee.RouterParams({
            swapTokenInfo: swapTokenInfo,
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

    function _getUserInfos(address[] memory users, uint256[] memory amountsIn) internal pure returns (ISwappee.UserInfo[] memory) {
        ISwappee.UserInfo[] memory _userInfos = new ISwappee.UserInfo[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            _userInfos[i] = ISwappee.UserInfo({user: users[i], amountIn: amountsIn[i]});
        }
        return _userInfos;
    }

    function _getSwapInfo(address inputToken, uint256 totalAmountIn, ISwappee.RouterParams memory routerParams, ISwappee.UserInfo[] memory userInfos) internal pure returns (ISwappee.SwapInfo memory) {
        return ISwappee.SwapInfo({
            inputToken: inputToken,
            totalAmountIn: totalAmountIn,
            routerParams: routerParams,
            userInfos: userInfos
        });
    }

    /// @dev Creates a simple swap info with a single user and amount in.
    function _buildSimpleSwapInfo(address user, uint256 amountIn) internal view returns (ISwappee.SwapInfo[] memory) {
        address[] memory users = new address[](1);
        users[0] = user;
        uint256[] memory amountsIn = new uint256[](1);
        amountsIn[0] = amountIn;

        ISwappee.UserInfo[] memory _userInfos = _getUserInfos(users, amountsIn);

        IOBRouter.swapTokenInfo memory _swapTokenInfo = _getSwapTokenInfo(amountIn, address(mockERC20), address(swappee));
        ISwappee.RouterParams memory _routerParams = _getRouterParams(_swapTokenInfo);

        ISwappee.SwapInfo[] memory swapInfos = new ISwappee.SwapInfo[](1);
        swapInfos[0] = _getSwapInfo(address(mockERC20), amountIn, _routerParams, _userInfos);

        return swapInfos;
    }

    function _buildMultipleUsersSwapInfo(address[] memory users, uint256[] memory amounts, uint256 totalAmountIn) internal view returns (ISwappee.SwapInfo[] memory) {
        ISwappee.UserInfo[] memory _userInfos = _getUserInfos(users, amounts);

        IOBRouter.swapTokenInfo memory _swapTokenInfo = _getSwapTokenInfo(totalAmountIn, address(mockERC20), address(swappee));
        ISwappee.RouterParams memory _routerParams = _getRouterParams(_swapTokenInfo);

        ISwappee.SwapInfo[] memory swapInfos = new ISwappee.SwapInfo[](1);
        swapInfos[0] = _getSwapInfo(address(mockERC20), totalAmountIn, _routerParams, _userInfos);

        return swapInfos;
    }
}
