// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.6;
pragma abicoder v2;

import '../1inch/AggregationRouterV4.sol';
import '../1inch/math/SafeMath.sol';
import '../1inch/token/SafeERC20.sol';
import '../1inch/helpers/UniERC20.sol';
import './Withdrawable.sol';

contract OneInchAdapter is Withdrawable {
  using SafeMath for uint256;
  using UniERC20 for IERC20;
  using SafeERC20 for IERC20;
  address constant AGG_ROUTER_V4 = 0x1111111254fb6c44bAC0beD2854e76F90643097d;

  constructor (address _owner) Withdrawable(_owner) {}

  function tokenToToken(bytes memory data, IERC20 tokenOut, uint tokenOutAmount, address payable account) external {
    assembly {
      let result := call(gas(), AGG_ROUTER_V4, callvalue(), add(data, 0x20), mload(data), 0, 0)
      returndatacopy(0, 0, returndatasize())
      switch result
      case 0 {
        revert(0, returndatasize())
      }
      default {
        return(0, returndatasize())
      }
    }
    tokenOut.uniTransfer(account, tokenOutAmount);
  }
}