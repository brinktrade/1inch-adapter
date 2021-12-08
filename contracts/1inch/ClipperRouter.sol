pragma solidity ^0.7.6;

import './helpers/EthReceiver.sol';
import './helpers/Permitable.sol';
import './token/SafeERC20.sol';
import './interfaces/IWETH.sol';
import './interfaces/IClipperExchangeInterface.sol';

/// @title Clipper router that allows to use `ClipperExchangeInterface` for swaps
contract ClipperRouter is EthReceiver, Permitable {
    using SafeERC20 for IERC20;

    IWETH private immutable _WETH;  // solhint-disable-line var-name-mixedcase
    IERC20 private constant _ETH = IERC20(address(0));
    bytes private constant _INCH_TAG = "1INCH";
    IClipperExchangeInterface private immutable _clipperExchange;
    address payable private immutable _clipperPool;

    constructor(
        address weth,
        IClipperExchangeInterface clipperExchange
    ) {
        _clipperExchange = clipperExchange;
        _clipperPool = clipperExchange.theExchange();
        _WETH = IWETH(weth);
    }

    /// @notice Same as `clipperSwapTo` but calls permit first,
    /// allowing to approve token spending and make a swap in one transaction.
    /// @param recipient Address that will receive swap funds
    /// @param srcToken Source token
    /// @param dstToken Destination token
    /// @param amount Amount of source tokens to swap
    /// @param minReturn Minimal allowed returnAmount to make transaction commit
    /// @param permit Should contain valid permit that can be used in `IERC20Permit.permit` calls.
    /// See tests for examples
    function clipperSwapToWithPermit(
        address payable recipient,
        IERC20 srcToken,
        IERC20 dstToken,
        uint256 amount,
        uint256 minReturn,
        bytes calldata permit
    ) external returns(uint256 returnAmount) {
        _permit(address(srcToken), permit);
        return clipperSwapTo(recipient, srcToken, dstToken, amount, minReturn);
    }

    /// @notice Same as `clipperSwapTo` but uses `msg.sender` as recipient
    /// @param srcToken Source token
    /// @param dstToken Destination token
    /// @param amount Amount of source tokens to swap
    /// @param minReturn Minimal allowed returnAmount to make transaction commit
    function clipperSwap(
        IERC20 srcToken,
        IERC20 dstToken,
        uint256 amount,
        uint256 minReturn
    ) external payable returns(uint256 returnAmount) {
        return clipperSwapTo(msg.sender, srcToken, dstToken, amount, minReturn);
    }

    /// @notice Performs swap using Clipper exchange. Wraps and unwraps ETH if required.
    /// Sending non-zero `msg.value` for anything but ETH swaps is prohibited
    /// @param recipient Address that will receive swap funds
    /// @param srcToken Source token
    /// @param dstToken Destination token
    /// @param amount Amount of source tokens to swap
    /// @param minReturn Minimal allowed returnAmount to make transaction commit
    function clipperSwapTo(
        address payable recipient,
        IERC20 srcToken,
        IERC20 dstToken,
        uint256 amount,
        uint256 minReturn
    ) public payable returns(uint256 returnAmount) {
        bool srcETH;
        if (srcToken == _WETH) {
            require(msg.value == 0, "CL1IN: msg.value should be 0");
            _WETH.transferFrom(msg.sender, address(this), amount);
            _WETH.withdraw(amount);
            srcETH = true;
        }
        else if (srcToken == _ETH) {
            require(msg.value == amount, "CL1IN: wrong msg.value");
            srcETH = true;
        }
        else {
            require(msg.value == 0, "CL1IN: msg.value should be 0");
            srcToken.safeTransferFrom(msg.sender, _clipperPool, amount);
        }

        if (srcETH) {
            _clipperPool.transfer(amount);
            returnAmount = _clipperExchange.sellEthForToken(dstToken, recipient, minReturn, _INCH_TAG);
        } else if (dstToken == _WETH) {
            returnAmount = _clipperExchange.sellTokenForEth(srcToken, address(this), minReturn, _INCH_TAG);
            _WETH.deposit{ value: returnAmount }();
            _WETH.transfer(recipient, returnAmount);
        } else if (dstToken == _ETH) {
            returnAmount = _clipperExchange.sellTokenForEth(srcToken, recipient, minReturn, _INCH_TAG);
        } else {
            returnAmount = _clipperExchange.sellTokenForToken(srcToken, dstToken, recipient, minReturn, _INCH_TAG);
        }
    }
}