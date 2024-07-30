// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {
    IFunctionsRouter,
    FunctionsResponse
} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/interfaces/IFunctionsRouter.sol";
import {IFunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/interfaces/IFunctionsClient.sol";

contract MockFunctionsRouter is IFunctionsRouter {
    function handleOracleFulfillment(address who, bytes32 requestId, bytes memory response, bytes memory err)
        external
    {
        IFunctionsClient(who).handleOracleFulfillment(requestId, response, err);
    }

    /// @notice The identifier of the route to retrieve the address of the access control contract
    /// The access control contract controls which accounts can manage subscription
    /// @return id - bytes32 id that can be passed to the "getContractById" of the Router
    function getAllowListId() external pure returns (bytes32) {
        return bytes32(0);
    }

    /// @notice Set the identifier of the route to retrieve the address of the access control contract
    /// The access control contract controls which accounts can manage subscription
    function setAllowListId(bytes32 allowListId) external {}
}
