// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";

import { Swappee } from "src/Swappee.sol";
import { ISwappee } from "src/interfaces/ISwappee.sol";
import { IBGTIncentiveDistributor } from "src/interfaces/external/IBGTIncentiveDistributor.sol";
import { IOBRouter } from "src/interfaces/external/IOBRouter.sol";
import { MockOBRouter } from "@mock/MockOBRouter.sol";
import { MockBGTIncentiveDistributor } from "@mock/MockBGTIncentiveDistributor.sol";
import { MockERC20 } from "@mock/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SwappeeTest is Test {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant PRICE = 1e18; // incentives 1 : 1 BERA
    uint256 public constant CLAIM_AMOUNT = 100e18;
    uint256 public constant INFINITE_ALLOWANCE = type(uint256).max - 1;
    uint16 public constant ONE_HUNDRED_PERCENT = 1e4;
    uint16 public constant FEE = 1000; // 10%

    Swappee public swappee;

    MockERC20 public mockERC20;
    MockOBRouter public mockOBRouter;
    MockBGTIncentiveDistributor public mockBGTIncentiveDistributor;

    address public owner = makeAddr("owner");
    address public swapper = makeAddr("swapper");
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
        swappee = _deploySwappee();
        swappee.grantRole(swappee.SWAP_ROLE(), swapper);
        vm.stopPrank();
    }

    function test_dumpIncentives_SingleUser() public {
        testFuzz_dumpIncentives_SingleUser(CLAIM_AMOUNT);
    }

    function testFuzz_dumpIncentives_SingleUser(uint256 amount) public {
        amount = _bound(amount, 1, 100_000_000e18);
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        IBGTIncentiveDistributor.Claim[] memory claims = mockBGTIncentiveDistributor.getDummyClaims(users, amounts);

        vm.prank(user1);
        mockERC20.approve(address(swappee), INFINITE_ALLOWANCE);

        IOBRouter.swapTokenInfo memory swapTokenInfo =
            _getSwapTokenInfo(amount, address(mockERC20), address(swappee), address(0));
        ISwappee.RouterParams memory routerParams = _getRouterParams(swapTokenInfo);

        ISwappee.RouterParams[] memory _routerParams = new ISwappee.RouterParams[](1);
        _routerParams[0] = routerParams;

        vm.prank(user1);
        vm.expectEmit();
        emit ISwappee.Accounted(address(0), user1, amount); // fees are 0
        swappee.swappee(claims, _routerParams, address(0));

        assertEq(mockERC20.balanceOf(address(mockOBRouter)), amount);
        assertEq(mockERC20.balanceOf(address(swappee)), 0);
        assertEq(mockERC20.balanceOf(user1), 0);

        assertEq(swappee.amounts(address(0), user1), amount);
        assertEq(swappee.accruedFees(address(0)), 0); // no fees

        uint256 valuesLength = uint256(vm.load(address(swappee), bytes32(uint256(5))));
        assertEq(valuesLength, 0);
    }

    // Given user params are invalid and storage values are not reset at the and of the function,
    // the function should revert
    function testFuzz_dumpIncentives_SingleUser_InvalidRouterParams(uint256 amount) public {
        amount = _bound(amount, 1, 100_000_000e18);
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        IBGTIncentiveDistributor.Claim[] memory claims = mockBGTIncentiveDistributor.getDummyClaims(users, amounts);

        vm.prank(user1);
        mockERC20.approve(address(swappee), INFINITE_ALLOWANCE);

        // Empty swap info array
        ISwappee.RouterParams[] memory _routerParams = new ISwappee.RouterParams[](0);

        vm.prank(user1);
        vm.expectRevert(ISwappee.InvariantCheckFailed.selector);
        swappee.swappee(claims, _routerParams, address(0));
    }

    function testFuzz_dumpIncentives_SingleUser_FailInvalidUser(uint256 amount) public {
        amount = _bound(amount, 1, 100_000_000e18);
        address[] memory users = new address[](1);
        users[0] = user1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        IBGTIncentiveDistributor.Claim[] memory claims = mockBGTIncentiveDistributor.getDummyClaims(users, amounts);

        vm.prank(user1);
        mockERC20.approve(address(swappee), INFINITE_ALLOWANCE);

        IOBRouter.swapTokenInfo memory swapTokenInfo =
            _getSwapTokenInfo(amount, address(mockERC20), address(swappee), address(0));
        ISwappee.RouterParams memory routerParams = _getRouterParams(swapTokenInfo);

        ISwappee.SwapInfo[] memory swapInfos = new ISwappee.SwapInfo[](1);
        swapInfos[0] = _getSwapInfo(routerParams, _getUserInfos(users, amounts));

        bytes32 role = keccak256("SWAP_ROLE");
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user2, role));
        swappee.swappee(claims, swapInfos, address(0));
    }

    function test_dumpIncentives_MultipleUsers() public {
        testFuzz_dumpIncentives_MultipleUsers(100e18, 200e18, 300e18, PRICE);
    }

    function testFuzz_dumpIncentives_MultipleUsers(
        uint256 amountInUser1,
        uint256 amountInUser2,
        uint256 amountInUser3,
        uint256 price
    )
        public
    {
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

        _swappee(users, amounts, address(0));

        assertEq(mockERC20.balanceOf(address(mockOBRouter)), totalAmountIn);
        assertEq(mockERC20.balanceOf(address(swappee)), 0);
        assertEq(mockERC20.balanceOf(user1), 0);
        assertEq(mockERC20.balanceOf(user2), 0);
        assertEq(mockERC20.balanceOf(user3), 0);

        assertApproxEqAbs(swappee.amounts(address(0), user1), (amountInUser1 * price) / 1e18, 2);
        assertApproxEqAbs(swappee.amounts(address(0), user2), (amountInUser2 * price) / 1e18, 2);
        assertApproxEqAbs(swappee.amounts(address(0), user3), (amountInUser3 * price) / 1e18, 2);
        assertEq(swappee.accruedFees(address(0)), 0); // no fees
    }

    function testFuzz_dumpIncentives_MultipleUsers_WithFees(
        uint256 amountInUser1,
        uint256 amountInUser2,
        uint256 amountInUser3,
        uint256 price
    )
        public
    {
        amountInUser1 = _bound(amountInUser1, 1, 100_000_000e18);
        amountInUser2 = _bound(amountInUser2, 1, 100_000_000e18);
        amountInUser3 = _bound(amountInUser3, 1, 100_000_000e18);
        price = _bound(price, 0.000001e18, 1_000_000e18);

        mockOBRouter.setPrice(price);

        vm.prank(owner);
        swappee.setPercentageFee(FEE);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountInUser1;
        amounts[1] = amountInUser2;
        amounts[2] = amountInUser3;

        uint256 totalAmountIn = amountInUser1 + amountInUser2 + amountInUser3;

        _swappee(users, amounts, address(0));

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

        assertApproxEqAbs(
            swappee.amounts(address(0), user1), (amountOutUser1 * userPercentage) / ONE_HUNDRED_PERCENT, 2
        );
        assertApproxEqAbs(
            swappee.amounts(address(0), user2), (amountOutUser2 * userPercentage) / ONE_HUNDRED_PERCENT, 2
        );
        assertApproxEqAbs(
            swappee.amounts(address(0), user3), (amountOutUser3 * userPercentage) / ONE_HUNDRED_PERCENT, 2
        );
        assertApproxEqAbs(swappee.accruedFees(address(0)), (amountOutTotal * FEE) / ONE_HUNDRED_PERCENT, 2);
    }

    function testFuzz_dumpIncentives_MultipleUsers_MultipleTokens(
        uint256 amountInUser1,
        uint256 amountInUser2,
        uint256 amountInUser3,
        uint256 price
    )
        public
    {
        amountInUser1 = _bound(amountInUser1, 1, 100_000_000e18);
        amountInUser2 = _bound(amountInUser2, 1, 100_000_000e18);
        amountInUser3 = _bound(amountInUser3, 1, 100_000_000e18);
        price = _bound(price, 0.000001e18, 1_000_000e18);

        mockOBRouter.setPrice(price);

        vm.prank(owner);
        swappee.setPercentageFee(FEE);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[0] = amountInUser1;
        amountsIn[1] = amountInUser2;
        amountsIn[2] = amountInUser3;

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            mockERC20.approve(address(swappee), INFINITE_ALLOWANCE);
        }

        // USER1 and USER2 will swap to native token, USER3 will swap to ERC20
        address[] memory usersSwapToNative = new address[](2);
        usersSwapToNative[0] = user1;
        usersSwapToNative[1] = user2;

        address[] memory usersSwapToERC20 = new address[](1);
        usersSwapToERC20[0] = user3;

        uint256[] memory amountsInNative = new uint256[](2);
        amountsInNative[0] = amountInUser1;
        amountsInNative[1] = amountInUser2;

        uint256[] memory amountsInERC20 = new uint256[](1);
        amountsInERC20[0] = amountInUser3;

        _swappee(usersSwapToNative, amountsInNative, address(0));

        _swappee(usersSwapToERC20, amountsInERC20, 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce);

        assertEq(mockERC20.balanceOf(address(mockOBRouter)), amountInUser1 + amountInUser2 + amountInUser3);
        assertEq(mockERC20.balanceOf(address(swappee)), 0);
        assertEq(mockERC20.balanceOf(user1), 0);
        assertEq(mockERC20.balanceOf(user2), 0);
        assertEq(mockERC20.balanceOf(user3), 0);

        uint256 userPercentage = ONE_HUNDRED_PERCENT - FEE;
        uint256 amountOutUser1 = (amountInUser1 * price) / 1e18;
        uint256 amountOutUser2 = (amountInUser2 * price) / 1e18;
        uint256 amountOutUser3 = (amountInUser3 * price) / 1e18;
        assertApproxEqAbs(
            swappee.amounts(address(0), user1), (amountOutUser1 * userPercentage) / ONE_HUNDRED_PERCENT, 2
        );
        assertApproxEqAbs(
            swappee.amounts(address(0), user2), (amountOutUser2 * userPercentage) / ONE_HUNDRED_PERCENT, 2
        );
        assertApproxEqAbs(
            swappee.amounts(0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce, user3),
            (amountOutUser3 * userPercentage) / ONE_HUNDRED_PERCENT,
            2
        );

        assertApproxEqAbs(
            swappee.accruedFees(address(0)), (amountOutUser1 + amountOutUser2) * FEE / ONE_HUNDRED_PERCENT, 2
        );
        assertApproxEqAbs(
            swappee.accruedFees(0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce),
            amountOutUser3 * FEE / ONE_HUNDRED_PERCENT,
            2
        );

        vm.startPrank(user1);
        swappee.withdraw(address(0), swappee.amounts(address(0), user1));
        assertApproxEqAbs(user1.balance, (amountOutUser1 * userPercentage) / ONE_HUNDRED_PERCENT, 2);
        vm.stopPrank();

        vm.startPrank(user2);
        swappee.withdraw(address(0), swappee.amounts(address(0), user2));
        assertApproxEqAbs(user2.balance, (amountOutUser2 * userPercentage) / ONE_HUNDRED_PERCENT, 2);
        vm.stopPrank();

        // vm.prank(user3);
        // swappee.withdraw(0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce, (amountsInERC20[0] * price) / 1e18);
        // assertApproxEqAbs(IERC20(0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce).balanceOf(user3), (amountsInERC20[0] *
        // price) / 1e18, 1);
    }

    function _getRouterParams(IOBRouter.swapTokenInfo memory swapTokenInfo)
        internal
        view
        returns (ISwappee.RouterParams memory)
    {
        return ISwappee.RouterParams({
            swapTokenInfo: swapTokenInfo,
            pathDefinition: _dummyPathDefinition,
            executor: address(0),
            referralCode: 0
        });
    }

    function _getSwapTokenInfo(
        uint256 amountIn,
        address token,
        address to,
        address outputToken
    )
        internal
        pure
        returns (IOBRouter.swapTokenInfo memory)
    {
        return IOBRouter.swapTokenInfo({
            inputToken: token,
            inputAmount: amountIn,
            outputToken: outputToken,
            outputQuote: (amountIn * PRICE) / 1e18,
            outputMin: (amountIn * PRICE) / 1e18,
            outputReceiver: to
        });
    }

    function _getUserInfos(
        address[] memory users,
        uint256[] memory amountsIn
    )
        internal
        pure
        returns (ISwappee.UserInfo[] memory)
    {
        ISwappee.UserInfo[] memory _userInfos = new ISwappee.UserInfo[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            _userInfos[i] = ISwappee.UserInfo({ user: users[i], amountIn: amountsIn[i] });
        }
        return _userInfos;
    }

    function _getSwapInfo(
        ISwappee.RouterParams memory routerParams,
        ISwappee.UserInfo[] memory userInfos
    )
        internal
        pure
        returns (ISwappee.SwapInfo memory)
    {
        return ISwappee.SwapInfo({ routerParams: routerParams, userInfos: userInfos });
    }

    /// @dev Creates a simple swap info with a single user and amount in.
    function _buildSimpleSwapInfo(address user, uint256 amountIn) internal view returns (ISwappee.SwapInfo[] memory) {
        address[] memory users = new address[](1);
        users[0] = user;
        uint256[] memory amountsIn = new uint256[](1);
        amountsIn[0] = amountIn;

        ISwappee.UserInfo[] memory _userInfos = _getUserInfos(users, amountsIn);

        IOBRouter.swapTokenInfo memory _swapTokenInfo =
            _getSwapTokenInfo(amountIn, address(mockERC20), address(swappee), address(0));
        ISwappee.RouterParams memory _routerParams = _getRouterParams(_swapTokenInfo);

        ISwappee.SwapInfo[] memory swapInfos = new ISwappee.SwapInfo[](1);
        swapInfos[0] = _getSwapInfo(_routerParams, _userInfos);

        return swapInfos;
    }

    function _buildMultipleUsersSwapInfo(
        address[] memory users,
        uint256[] memory amounts,
        uint256 totalAmountIn,
        address outputToken
    )
        internal
        view
        returns (ISwappee.SwapInfo memory)
    {
        ISwappee.UserInfo[] memory _userInfos = _getUserInfos(users, amounts);

        IOBRouter.swapTokenInfo memory _swapTokenInfo =
            _getSwapTokenInfo(totalAmountIn, address(mockERC20), address(swappee), outputToken);
        ISwappee.RouterParams memory _routerParams = _getRouterParams(_swapTokenInfo);

        return _getSwapInfo(_routerParams, _userInfos);
    }

    function _swappee(address[] memory users, uint256[] memory amounts, address outputToken) internal {
        for (uint256 i = 0; i < users.length; i++) {
            address[] memory _users = new address[](1);
            _users[0] = users[i];
            uint256[] memory _amounts = new uint256[](1);
            _amounts[0] = amounts[i];

            IBGTIncentiveDistributor.Claim[] memory _claims =
                mockBGTIncentiveDistributor.getDummyClaims(_users, _amounts);
            ISwappee.SwapInfo[] memory _swapInfos = _buildSimpleSwapInfo(users[i], amounts[i]);

            vm.prank(users[i]);
            mockERC20.approve(address(swappee), INFINITE_ALLOWANCE);
            vm.prank(swapper);
            swappee.swappee(_claims, _swapInfos, outputToken);
        }
    }

    function _deploySwappee() internal returns (Swappee) {
        Swappee swappeeImplementation = new Swappee();
        bytes memory data =
            abi.encodeCall(Swappee.initialize, (address(mockBGTIncentiveDistributor), address(mockOBRouter)));
        address payable swappeeProxy = payable(new ERC1967Proxy(address(swappeeImplementation), data));
        return Swappee(swappeeProxy);
    }
}
