// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.6;
pragma abicoder v2;

import '../1inch/AggregationRouterV4.sol';
import './Withdrawable.sol';

contract OneInchAdapter is Withdrawable {
  constructor (address _owner) Withdrawable(_owner) { }

  
}