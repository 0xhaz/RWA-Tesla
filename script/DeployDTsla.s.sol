// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {dTSLA} from "src/dTsla.sol";
import {HelperConfig} from "script/HelperConfig.sol";
import {IGetTslaReturnTypes} from "src/interfaces/IGetTslaReturnTypes.sol";

contract DeployDTsla is Script {
    string constant alpacaMintSource = "./functions/sources/alpacaBalance.js";
    string constant alpacaRedeemSource = "./functions/sources/alpacaBalance.js";

    function run() public {
        //    Get params
        IGetTslaReturnTypes.GetTslaReturnType memory tslaReturnType = getdTslaRequirements();

        vm.startBroadcast();
        deployDTSLA(
            tslaReturnType.subId,
            tslaReturnType.mintSource,
            tslaReturnType.redeemSource,
            tslaReturnType.functionsRouter,
            tslaReturnType.donId,
            tslaReturnType.tslaFeed,
            tslaReturnType.usdcFeed,
            tslaReturnType.redemptionCoin,
            tslaReturnType.secretVersion,
            tslaReturnType.secretSlot
        );
        vm.stopBroadcast();
    }

    function getdTslaRequirements() public returns (IGetTslaReturnTypes.GetTslaReturnType memory) {
        HelperConfig helperConfig = new HelperConfig();
        (
            address tslaFeed,
            address usdcFeed,
            ,
            address functionsRouter,
            bytes32 donId,
            uint64 subId,
            address redemptionCoin,
            ,
            ,
            ,
            uint64 secretVersion,
            uint8 secretSlot
        ) = helperConfig.activeNetworkConfig();

        if (
            tslaFeed == address(0) || usdcFeed == address(0) || functionsRouter == address(0) || donId == bytes32(0)
                || subId == 0
        ) {
            revert("Missing network config");
        }
        string memory mintSource = vm.readFile(alpacaMintSource);
        string memory redeemSource = vm.readFile(alpacaRedeemSource);

        return IGetTslaReturnTypes.GetTslaReturnType(
            subId,
            mintSource,
            redeemSource,
            functionsRouter,
            donId,
            tslaFeed,
            usdcFeed,
            redemptionCoin,
            secretVersion,
            secretSlot
        );
    }

    function deployDTSLA(
        uint64 subId,
        string memory mintSource,
        string memory redeemSource,
        address functionsRouter,
        bytes32 donId,
        address tslaFeed,
        address usdcFeed,
        address redemptionCoin,
        uint64 secretVersion,
        uint8 secretSlot
    ) public returns (dTSLA) {
        dTSLA dTsla = new dTSLA(
            subId,
            mintSource,
            redeemSource,
            functionsRouter,
            donId,
            tslaFeed,
            usdcFeed,
            redemptionCoin,
            secretVersion,
            secretSlot
        );
        return dTsla;
    }
}
