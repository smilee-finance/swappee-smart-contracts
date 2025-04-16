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
        testFuzz_dumpIncentives_SingleUser(CLAIM_AMOUNT, PRICE);
    }

    function testFuzz_dumpIncentives_SingleUser(uint256 amount, uint256 price) public {
        amount = _bound(amount, 1, 100_000_000e18);
        price = _bound(price, 0.000001e18, 1_000_000e18);

        mockOBRouter.setPrice(price);

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

        uint256 expectedAmount = (amount * price) / 1e18;

        vm.prank(user1);
        swappee.swappee(claims, _routerParams, address(0));

        assertEq(mockERC20.balanceOf(address(mockOBRouter)), amount);
        assertEq(mockERC20.balanceOf(address(swappee)), 0);
        assertEq(mockERC20.balanceOf(user1), 0);

        assertApproxEqAbs(swappee.amounts(address(0), user1), expectedAmount, 1);
        assertEq(swappee.accruedFees(address(0)), 0); // no fees

        uint256 valuesLength = uint256(vm.load(address(swappee), bytes32(uint256(5))));
        assertEq(valuesLength, 0);
    }

    function testFuzz_dumpIncentives_SingleUser_WithFees(uint256 amount, uint256 price) public {
        amount = _bound(amount, 1, 100_000_000e18);
        price = _bound(price, 0.000001e18, 1_000_000e18);

        mockOBRouter.setPrice(price);

        vm.prank(owner);
        swappee.setPercentageFee(FEE);

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

        uint256 userPercentage = ONE_HUNDRED_PERCENT - FEE;
        uint256 expectedAmount = (amount * price) / 1e18;
        uint256 expectedAmountWithFees = (expectedAmount * userPercentage) / ONE_HUNDRED_PERCENT;
        uint256 expectedFees = (expectedAmount * FEE) / ONE_HUNDRED_PERCENT;

        vm.prank(user1);
        swappee.swappee(claims, _routerParams, address(0));

        assertEq(mockERC20.balanceOf(address(mockOBRouter)), amount);
        assertEq(mockERC20.balanceOf(address(swappee)), 0);
        assertEq(mockERC20.balanceOf(user1), 0);

        assertApproxEqAbs(swappee.amounts(address(0), user1), expectedAmountWithFees, 1);
        assertApproxEqAbs(swappee.accruedFees(address(0)), expectedFees, 1);

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

        ISwappee.RouterParams[] memory _routerParams = new ISwappee.RouterParams[](1);
        _routerParams[0] = routerParams;

        vm.prank(user2);
        vm.expectRevert(ISwappee.InvalidUser.selector);
        swappee.swappee(claims, _routerParams, address(0));
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

    function _deploySwappee() internal returns (Swappee) {
        Swappee swappeeImplementation = new Swappee();
        bytes memory data =
            abi.encodeCall(Swappee.initialize, (address(mockBGTIncentiveDistributor), address(mockOBRouter)));
        address payable swappeeProxy = payable(new ERC1967Proxy(address(swappeeImplementation), data));
        return Swappee(swappeeProxy);
    }
}
