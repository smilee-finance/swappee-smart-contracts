// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IBGTIncentiveDistributor} from "../../src/interfaces/external/IBGTIncentiveDistributor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockBGTIncentiveDistributor is IBGTIncentiveDistributor, Test {
    address public mockedToken;
    uint256 public amountToTransfer;

    function setMockedToken(address token) external {
        mockedToken = token;
    }

    function setAmountToTransfer(uint256 amount) external {
        amountToTransfer = amount;
    }

    function getDummyClaims(
        address[] memory accounts
    ) public view returns (Claim[] memory) {
        Claim[] memory claims = new Claim[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            claims[i] = Claim({
                account: accounts[i],
                amount: amountToTransfer,
                identifier: bytes32(0),
                merkleProof: new bytes32[](0)
            });
        }
        return claims;
    }

    /// @dev Override to transfer tokens to users.
    function claim(Claim[] memory claims) external {
        address to;
        uint256 amount;
        for (uint256 i = 0; i < claims.length; i++) {
            to = claims[i].account;
            amount = claims[i].amount;
            IERC20(mockedToken).transfer(to, amount);
        }
    }

    function rewards(
        bytes32 /*identifier*/
    ) external view override returns (Reward memory) {
        return Reward({
            token: mockedToken,
            merkleRoot: bytes32(0),
            proof: bytes32(0),
            activeAt: block.timestamp,
            pubkey: new bytes(0)
        });
    }

    function incentiveTokensPerValidator(
        bytes calldata pubkey,
        address token
    ) external view override returns (uint256) {}

    function setRewardClaimDelay(uint64 _delay) external override {}

    function receiveIncentive(
        bytes calldata pubkey,
        address token,
        uint256 _amount
    ) external override {}

    function setPauseState(bool state) external override {}

    function updateRewardsMetadata(
        Distribution[] calldata _distributions
    ) external override {}
}
