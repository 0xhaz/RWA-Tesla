// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

interface IGetTslaReturnTypes {
    struct GetTslaReturnType {
        uint64 subId;
        string mintSource;
        string redeemSource;
        address functionsRouter;
        bytes32 donId;
    }
}
