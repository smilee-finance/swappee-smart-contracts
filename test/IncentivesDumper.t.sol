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
        mockBGTIncentiveDistributor.setAmountToTransfer(CLAIM_AMOUNT);
        mockERC20.mint(address(mockBGTIncentiveDistributor), type(uint256).max);

        vm.prank(owner);
        incentivesDumper = new IncentivesDumper(address(mockBGTIncentiveDistributor), address(mockOBRouter));
    }

    function test_dumpIncentives() public {
        address[] memory users = new address[](1);
        users[0] = user1;

        IBGTIncentiveDistributor.Claim[] memory claims = mockBGTIncentiveDistributor.getDummyClaims(users);

        vm.prank(user1);
        mockERC20.approve(address(incentivesDumper), INFINITE_ALLOWANCE);

        IIncentivesDumper.SwapInfo[] memory swapInfos = _buildSimpleSwapInfo(user1, CLAIM_AMOUNT);

        vm.prank(owner);
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

    /// @dev Creates a simple swap info with a single user and amount in.
    function _buildSimpleSwapInfo(address user, uint256 amountIn) internal view returns (IIncentivesDumper.SwapInfo[] memory) {
        IIncentivesDumper.UserInfo[] memory _userInfos = new IIncentivesDumper.UserInfo[](1);
        _userInfos[0] = IIncentivesDumper.UserInfo({user: user, amountIn: amountIn});
        IOBRouter.swapTokenInfo memory _swapTokenInfo = IOBRouter.swapTokenInfo({
            inputToken: address(mockERC20),
            inputAmount: amountIn,
            outputToken: address(0),
            outputQuote: (amountIn * PRICE) / 1e18,
            outputMin: (amountIn * PRICE) / 1e18,
            outputReceiver: address(incentivesDumper)
        });

        IIncentivesDumper.RouterParams memory _routerParams = IIncentivesDumper.RouterParams({
            swaps: _swapTokenInfo,
            pathDefinition: bytes(""),
            executor: address(0),
            referralCode: 0
        });

        IIncentivesDumper.SwapInfo[] memory swapInfos = new IIncentivesDumper.SwapInfo[](1);
        swapInfos[0] = IIncentivesDumper.SwapInfo({
            inputToken: address(mockERC20),
            totalAmountIn: amountIn,
            routerParams: _routerParams,
            userInfos: _userInfos
        });

        return swapInfos;
    }
}
