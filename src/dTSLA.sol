// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title dTSLA
 * @notice This is our contract to make request to the Alpaca API to mint TSLA-backed dTSLA tokens
 * @dev This contract is meant for testing purposes only
 */
contract dTSLA is ConfirmedOwner, FunctionsClient, ERC20, Pausable {
    using FunctionsRequest for FunctionsRequest.Request;
    using OracleLib for AggregatorV3Interface;
    using Strings for uint256;

    error dTSLA__NotEnoughCollateral();
    error dTSLA__BelowMinimumRedemption();
    error dTSLA__RedemptionFailed();

    // Custom error type
    error UnexpectedRequestID(bytes32 requestId);

    enum MintOrRedeem {
        mint,
        redeem
    }

    struct dTslaRequest {
        uint256 amountOfToken;
        address requester;
        MintOrRedeem mintOrRedeem;
    }

    uint32 private constant GAS_LIMIT = 300_000;
    uint64 immutable i_subId;

    // Check to get the router address for your supported network
    // https://docs.chain.link/chainlink-functions/supported-networks
    address s_functionsRouter;
    string s_mintSource;
    string s_redeemSource;

    // Check to get the donID for your supported network https://docs.chain.link/chainlink-functions/supported-networks
    bytes32 s_donID;
    uint256 s_portfolioBalance;
    uint64 s_secretVersion;
    uint8 s_secretSlot;

    mapping(bytes32 requestId => dTslaRequest request) private s_requestIdToRequest;
    mapping(address user => uint256 amounntAvailableForWithdrawal) private s_userToWithdrawalAmount;

    address public i_tslaUsdFeed;
    address public i_usdcUsdFeed;
    address public i_redemptionCoin;

    // This hard-coded value isn't great engineering. Please check with your brokerage
    // and update accordingly
    // For example, for Alpaca: https://alpaca.markets/support/crypto-wallet-faq
    uint256 public constant MINIMUM_REDEMPTION_COIN_REDEMPTION_AMOUNT = 100e18;

    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 public constant PORTFOLIO_PRECISION = 1e18;
    uint256 public constant COLLATERAL_RATIO = 200; // 200% collateral ratio
    uint256 public constant COLLATERAL_PRECISION = 100;

    uint256 private constant TARGET_DECIMALS = 18;
    uint256 private constant PRECISION = 1e18;
    uint256 private immutable i_redemptionCoinDecimals;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Response(bytes32 indexed requestId, uint256 character, bytes response, bytes err);

    /*//////////////////////////////////////////////////////////////
                                 FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initializes the contract with the Chainlink router address and sets the contract owner
     */
    constructor(
        uint64 subId,
        string memory mintSource,
        string memory redeemSource,
        address functionsRouter,
        bytes32 donId,
        address tslaPriceFeed,
        address usdcPriceFeed,
        address redemptionCoin,
        uint64 secretVersion,
        uint8 secretSlot
    ) FunctionsClient(functionsRouter) ConfirmedOwner(msg.sender) ERC20("Backed TSLA", "bTSLA") {
        s_mintSource = mintSource;
        s_redeemSource = redeemSource;
        s_functionsRouter = functionsRouter;
        s_donID = donId;
        i_tslaUsdFeed = tslaPriceFeed;
        i_usdcUsdFeed = usdcPriceFeed;
        i_redemptionCoin = redemptionCoin;
        i_redemptionCoinDecimals = ERC20(redemptionCoin).decimals();

        s_secretVersion = secretVersion;
        s_secretSlot = secretSlot;
    }

    /**
     * @notice Sends an HTTP request for character information
     * @dev If you pass 0, that will act as a way to get an updated portfolio balance
     * @return requestId The ID of the request
     */
    function sendMintRequest(uint256 amountOfTokensToMint) external onlyOwner returns (bytes32 requestId) {
        // they want to mint $100 and the portfolio has $200
        if (_getCollateralRatioAdjustedTotalBalance(amountOfTokensToMint) > s_portfolioBalance) {
            revert dTSLA__NotEnoughCollateral();
        }
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_mintSource); // Initialize the request with JS code
        req.addDONHostedSecrets(s_secretSlot, s_secretVersion);

        // Send the request and store the request ID
        requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, s_donID);
        s_requestIdToRequest[requestId] = dTslaRequest(amountOfTokensToMint, msg.sender, MintOrRedeem.mint);
        return requestId;
    }

    /**
     * @notice User sends a Chainlink Functions request to sell TSLA for redemptionCoin
     * @notice This will put the redemptionCoin in a withdrawal queue that the user must call to redeem
     * @dev Burn dTSLA
     * @dev Sell TSLA on brokerage
     * @dev Buy USDC on brokerage
     * @dev Send USDC to this contract for user to withdraw
     *
     * @param amountdTsla The amount of dTSLA to redeem
     */
    function sendRedeemRequest(uint256 amountdTsla) external whenNotPaused returns (bytes32 requestId) {
        // Should be able to just always redeem?
        // @audit potential exploit here, where if a user can redeem more than the collateral amount
        // has 18 decimals
        uint256 amountTslaInUsdc = getUsdcValueOfUsd(getUsdValueOfTsla(amountdTsla));
        if (amountTslaInUsdc < MINIMUM_REDEMPTION_COIN_REDEMPTION_AMOUNT) {
            revert dTSLA__BelowMinimumRedemption();
        }

        // Internal Effects
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_redeemSource); // Initialize the request with JS code
        string[] memory args = new string[](2);
        args[0] = amountdTsla.toString();
        // The transaction will fail if it's outside of 2% slippage
        // This could be a future improvement to make the slippage a parameter by someone
        args[1] = amountTslaInUsdc.toString();
        req.setArgs(args);

        // Send the request and store the request ID
        // We are assuming requestId is unique
        requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, s_donID);
        s_requestIdToRequest[requestId] = dTslaRequest(amountdTsla, msg.sender, MintOrRedeem.redeem);

        // External Interaction
        _burn(msg.sender, amountdTsla);
    }

    /**
     * @notice Callback function for fulfilling a request
     * @param requestId The ID of the request to fulfill
     * @param response The HTTP response data
     *
     */
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory /* error */ )
        internal
        override
        whenNotPaused
    {
        if (s_requestIdToRequest[requestId].mintOrRedeem == MintOrRedeem.mint) {
            _mintFulFillRequest(requestId, response);
        } else {
            _redeemFulFillRequest(requestId, response);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adjusts the total balance of the portfolio to account for the collateral ratio
     * @param amountOfTokensToMint The number of tokens to mint
     * @return The adjusted total balance of the portfolio
     * @dev This function is used to check if the portfolio has enough collateral to mint new tokens
     */
    function _getCollateralRatioAdjustedTotalBalance(uint256 amountOfTokensToMint) internal view returns (uint256) {
        uint256 calculatedNewTotalValue = getCalculatedNewTotalValue(amountOfTokensToMint);
        return (calculatedNewTotalValue * COLLATERAL_RATIO) / COLLATERAL_PRECISION;
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW / PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // TSLA USD has 8 decimal places, so we add an additional 10 decimal places
    function getTslaPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(i_tslaUsdFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION;
    }

    function getUsdcPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(i_usdcUsdFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION;
    }

    /**
     * @notice Calculates the new total value of the portfolio after minting new tokens
     * @param addedNumberOfTsla The number of TSLA tokens to mint
     * @return The new total value of the portfolio
     * @dev This function is used to check if the portfolio has enough collateral to mint new tokens
     */
    function getCalculatedNewTotalValue(uint256 addedNumberOfTsla) public view returns (uint256) {
        return ((totalSupply() * addedNumberOfTsla) * getTslaPrice()) / PRECISION;
    }

    function getUsdValueOfTsla(uint256 tslaAmount) public view returns (uint256) {
        return (tslaAmount * getTslaPrice()) / PRECISION;
    }

    /**
     * Pass the USD amount with 18 decimals (WAD)
     * Return the redemptionCoin amonut with 18 decimals (WAD)
     *
     * @param usdAmount The amount of USD to convert to USDC in WAD
     * @return the amount of redemptionCoin with 18 decimals (WAD)
     */
    function getUsdcValueOfUsd(uint256 usdAmount) public view returns (uint256) {
        return (usdAmount * PRECISION) / getUsdcPrice();
    }
}
