// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {dTSLA} from "src/dTsla.sol";

contract DeployDTsla is Script {
    string constant alpacaMintSource = "./functions/sources/alpacaBalance.js";
    string constant alpacaRedeemSource = "";
    uint64 constant subId = 2468;

    function run() public {
        string memory mintSource = vm.readFile(alpacaMintSource);

        vm.startBroadcast();
        dTSLA dTsla = new dTSLA(mintSource, subId, alpacaRedeemSource);
        vm.stopBroadcast();
        console2.log("Deployed dTsla at address: ", address(dTsla));
    }
}
