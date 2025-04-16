// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IBGTIncentiveDistributor } from "../../src/interfaces/external/IBGTIncentiveDistributor.sol";
import { TestnetIncentiveToken } from "./TestnetIncentiveToken.sol";

contract TestnetIncetiveDistributor is IBGTIncentiveDistributor {
    TestnetIncentiveToken public incentiveToken;
    uint256 public delay;

    constructor() {
        incentiveToken = new TestnetIncentiveToken("IncentiveToken", "IT", 18);
    }

    function getIncentiveToken() external view returns (address) {
        return address(incentiveToken);
    }

    /// @dev Override to transfer tokens to users.
    function claim(Claim[] memory claims) external {
        address to;
        uint256 amount;
        for (uint256 i = 0; i < claims.length; i++) {
            to = claims[i].account;
            amount = claims[i].amount;
            incentiveToken.mint(to, amount);
        }
    }

    function rewards(bytes32 /*identifier*/ )
        external
        view
        override
        returns (address token, bytes32 merkleRoot, bytes32 proof, uint256 activeAt, bytes memory pubkey)
    {
        return (address(incentiveToken), bytes32(0), bytes32(0), block.timestamp, new bytes(0));
    }

    function incentiveTokensPerValidator(
        bytes calldata pubkey,
        address token
    )
        external
        view
        override
        returns (uint256)
    { }

    function setRewardClaimDelay(uint64 _delay) external override { }

    function receiveIncentive(bytes calldata pubkey, address token, uint256 _amount) external override { }

    function setPauseState(bool state) external override { }

    function updateRewardsMetadata(Distribution[] calldata _distributions) external override {
        uint256 activeAt;
        for (uint256 i = 0; i < _distributions.length; i++) {
            activeAt = block.timestamp + delay;
            emit RewardMetadataUpdated(
                _distributions[i].identifier,
                _distributions[i].pubkey,
                _distributions[i].token,
                _distributions[i].merkleRoot,
                _distributions[i].proof,
                activeAt
            );
        }
    }
}
