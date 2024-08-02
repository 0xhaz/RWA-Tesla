// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {DeployDTsla, dTSLA} from "script/DeployDTsla.s.sol";
import {MockFunctionsRouter} from "src/mocks/MockFunctionsRouter.sol";
import {IGetTslaReturnTypes} from "src/interfaces/IGetTslaReturnTypes.sol";

abstract contract Base_Test is Test {
    DeployDTsla public deployDTsla;
    address public nonOwner = makeAddr("nonOwner");
    uint256 public constant STARTING_PORTFOLIO_BALANCE = 100_000e18;

    dTSLA public dtsla;
    MockFunctionsRouter public mockFunctionsRouter;

    function setUp() public virtual {
        deployDTsla = new DeployDTsla();

        IGetTslaReturnTypes.GetTslaReturnType memory tslaReturnValues = deployDTsla.getdTslaRequirements();
        mockFunctionsRouter = MockFunctionsRouter(tslaReturnValues.functionsRouter);
        dtsla = deployDTsla.deployDTSLA(
            tslaReturnValues.subId,
            tslaReturnValues.mintSource,
            tslaReturnValues.redeemSource,
            tslaReturnValues.functionsRouter,
            tslaReturnValues.donId,
            tslaReturnValues.tslaFeed,
            tslaReturnValues.usdcFeed,
            tslaReturnValues.redemptionCoin,
            tslaReturnValues.secretVersion,
            tslaReturnValues.secretSlot
        );
    }

    function test_CanSendMintRequest_WithTslaBalance() public {
        uint256 amountToRequest = 0;
        vm.prank(dtsla.owner());
        bytes32 requestId = dtsla.sendMintRequest(amountToRequest);
        assert(requestId != 0);
    }

    function test_NonOwnerCannotSend_MintRequest() public {
        uint256 amountToRequest = 0;

        vm.prank(nonOwner);
        vm.expectRevert();
        dtsla.sendMintRequest(amountToRequest);
    }

    function test_MintFails_WithoutInitialBalance() public {
        uint256 amountToRequest = 1e18;

        vm.prank(dtsla.owner());
        vm.expectRevert(dTSLA.dTSLA__NotEnoughCollateral.selector);
        dtsla.sendMintRequest(amountToRequest);
    }

    function test_OracleCanUpdate_Portfolio() public {
        uint256 amountToRequest = 0;

        vm.prank(dtsla.owner());
        bytes32 requestId = dtsla.sendMintRequest(amountToRequest);

        mockFunctionsRouter.handleOracleFulfillment(
            address(dtsla), requestId, abi.encodePacked(STARTING_PORTFOLIO_BALANCE), hex""
        );
        assert(dtsla.getPortfolioBalance() == STARTING_PORTFOLIO_BALANCE);
    }
}
