pragma solidity ^0.7.6;

import '../token/IERC20.sol';

/// @title Interface for WETH tokens
interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}