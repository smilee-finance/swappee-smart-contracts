/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { Swappee } from "src/Swappee.sol";
import { ISwappee } from "src/interfaces/ISwappee.sol";
import { IOBRouter } from "src/interfaces/external/IOBRouter.sol";
import { IBGTIncentiveDistributor } from "src/interfaces/external/IBGTIncentiveDistributor.sol";

/// This is an e2e test template, leave it commented out to avoid running it on CI.
contract E2ETest is Test {
// address constant CONTRACT_ADDRESS = 0xc6e7DF5E7b4f2A278906862b61205850344D4e7d;
// function setUp() public {
//     vm.createSelectFork("http://localhost:8545");
// }

// function test_2e2() public {
//     bytes32[] memory merkleProof = new bytes32[](12);

//     merkleProof[0] = 0x5e48e49dded12d6147cd6f17013db4fa9fb767730254f86e9a80d21f13e72f91;
//     merkleProof[1] = 0xf0e4cceeb7c281a16af5fc1619678696a4245c0b17caa1cc5f5dfee1f8405644;
//     merkleProof[2] = 0xfea7556f0a75b5baa3d21c32ee131b8bb9241bb4e1038056164ea4f8010fe32e;
//     merkleProof[3] = 0xf487134b2b71996e8b1113e5baa6bc826b149f4b080c6fcb35876c03e969e847;
//     merkleProof[4] = 0xbbdd437f4a1c70ebc4ee5c018f4b9e74e677dd2f93d2e1f2a19a1ab3230a4297;
//     merkleProof[5] = 0x48c046f44090908248e22d5b60ecd18aebf3b256423de3aa3704ca1f785563a1;
//     merkleProof[6] = 0xad2a866e9cb57b0eb83dc600a5ab3a476eb5e06d08e3ddefe362fccab3d97ecd;
//     merkleProof[7] = 0xb610a63fb58e33cee2d17bf28eb9858846afb4e28c703e835766ed5d77d945a9;
//     merkleProof[8] = 0xa5ae0089acff6f3d0105c6d4922787e9db53b3e81085d1b4825a01b8e16467d4;
//     merkleProof[9] = 0x51e5d5e9005535a16ade319e08213c5cc4a7ad5b429cd6493054ad5b5a1aa5da;
//     merkleProof[10] = 0x8d472e4d6234866a312f7ae36731cb7f0e7730d81cdca6098db63463a3a234f2;
//     merkleProof[11] = 0xa95a9c997c43e4dfead8f6d3fbec5c1b68be765db27f9856a21f66b2ea9ce114;

//     IBGTIncentiveDistributor.Claim[] memory claims = new IBGTIncentiveDistributor.Claim[](1);
//     claims[0] = IBGTIncentiveDistributor.Claim({
//         identifier: 0xfdb4325fefc3f372cb9869a39da91d54d6752fb862773f54699e182b448b9c65,
//         account: 0x7E8D41FFDbfB8Bdb5D3D4F74a9FC872496f9246e,
//         amount: 5294435604730205903,
//         merkleProof: merkleProof
//     });

//     ISwappee.UserInfo[] memory userInfos = new ISwappee.UserInfo[](1);
//     userInfos[0] = ISwappee.UserInfo({
//         user: 0x7E8D41FFDbfB8Bdb5D3D4F74a9FC872496f9246e,
//         amountIn: 5294435604730205903
//     });

//     bytes memory pathDefinition =
// hex'0000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000057dc0304f62125000000000000000000000000000000000000000000000000000768d5dae6d6110000000000000000000000000000000000000000000000000057b2aa4e57a390016536cEAD649249cae42FC9bfb1F999429b3ec75501ffff0160FfF1E9d3D16A995dF2A43c3f2E6358Aa13Cd9600a700f8e594098a3607fFb603c91e9DFd37017Cf7010555E30da8f98308EdB960aa94C0Db47230d2B9c01ffff0162b53f8E78F34170a47fA89E1CF3133f8Fc1124001a700f8e594098a3607fFb603c91e9DFd37017Cf701FCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce051e1e094Be03f781C497A489E3cB0287833452cA9B9E80B4defbe94124cdf35db12e4cad1c6f5648806f59b00000000000000000000006f2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590a700f8e594098a3607fFb603c91e9DFd37017Cf7555400ACFBaA2Dd79818c32804c5d79ec63079D1291E8300a700f8e594098a3607fFb603c91e9DFd37017Cf7000bb8199901345B4f6ec45CB6c39D7BebD9f73D2081BdE65D3700a700f8e594098a3607fFb603c91e9DFd37017Cf78e3901C4A2a9d35496e6A78379Fb4DA96228146Eb8Bc2300a700f8e594098a3607fFb603c91e9DFd37017Cf7ffff094Be03f781C497A489E3cB0287833452cA9B9E80B3510cb559f62ab74f624fb8e98443ecc4271ba1c000200000000000000000067ac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6ba700f8e594098a3607fFb603c91e9DFd37017Cf701ac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b01ffff094Be03f781C497A489E3cB0287833452cA9B9E80B1207c619086a52edef4a4b7af881b5ddd367a9190002000000000000000000066969696969696969696969696969696969696969a700f8e594098a3607fFb603c91e9DFd37017Cf7012F6F07CDcf3588944Bf4C42aC74ff24bF56e759001ffff01Cda0ca7C3a609773067261D86E817bf777a2870d01a700f8e594098a3607fFb603c91e9DFd37017Cf701696969696969696969696969696969696969696901ffff0200a700f8e594098a3607fFb603c91e9DFd37017Cf7';

//     ISwappee.SwapInfo[] memory swapInfos = new ISwappee.SwapInfo[](1);
//     swapInfos[0] = ISwappee.SwapInfo({
//         inputToken: 0x6536cEAD649249cae42FC9bfb1F999429b3ec755,
//         totalAmountIn: 5294435604730205903,
//         routerParams: ISwappee.RouterParams({
//             swapTokenInfo: IOBRouter.swapTokenInfo({
//                 inputToken: 0x6536cEAD649249cae42FC9bfb1F999429b3ec755,
//                 inputAmount: 5294435604730205903,
//                 outputToken: 0x0000000000000000000000000000000000000000,
//                 outputQuote: 24730228500078885,
//                 outputMin: 19784182800063108,
//                 outputReceiver: 0xc6e7DF5E7b4f2A278906862b61205850344D4e7d
//             }),
//             pathDefinition: pathDefinition,
//             executor: 0xa700f8e594098a3607fFb603c91e9DFd37017Cf7,
//             referralCode: 0
//         }),
//         userInfos: userInfos
//     });

//     Swappee(payable(CONTRACT_ADDRESS)).dumpIncentives(3, claims, swapInfos);
// }
}
