pragma solidity ^0.7.6;

import '../token/IERC20.sol';

/// @title Clipper interface subset used in swaps
interface IClipperExchangeInterface {
    function sellTokenForToken(IERC20 inputToken, IERC20 outputToken, address recipient, uint256 minBuyAmount, bytes calldata auxiliaryData) external returns (uint256 boughtAmount);
    function sellEthForToken(IERC20 outputToken, address recipient, uint256 minBuyAmount, bytes calldata auxiliaryData) external payable returns (uint256 boughtAmount);
    function sellTokenForEth(IERC20 inputToken, address payable recipient, uint256 minBuyAmount, bytes calldata auxiliaryData) external returns (uint256 boughtAmount);
    function theExchange() external returns (address payable);
}