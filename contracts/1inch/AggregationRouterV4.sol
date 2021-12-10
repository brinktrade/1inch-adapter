pragma solidity ^0.7.6;
pragma abicoder v2;

import './access/Ownable.sol';
import './helpers/EthReceiver.sol';
import './helpers/Permitable.sol';
import './UnoswapRouter.sol';
import './UnoswapV3Router.sol';
import './LimitOrderProtocolRFQ.sol';
import './ClipperRouter.sol';
import './helpers/UniERC20.sol';
import './interfaces/IAggregationExecutor.sol';

contract AggregationRouterV4 is Ownable, EthReceiver, Permitable, UnoswapRouter, UnoswapV3Router, LimitOrderProtocolRFQ, ClipperRouter {
    using SafeMath for uint256;
    using UniERC20 for IERC20;
    using SafeERC20 for IERC20;

    uint256 private constant _PARTIAL_FILL = 1 << 0;
    uint256 private constant _REQUIRES_EXTRA_ETH = 1 << 1;

    struct SwapDescription {
        IERC20 srcToken;
        IERC20 dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
        bytes permit;
    }

    constructor(address weth, IClipperExchangeInterface _clipperExchange)
        UnoswapV3Router(weth)
        LimitOrderProtocolRFQ(weth)
        ClipperRouter(weth, _clipperExchange)
    {}  // solhint-disable-line no-empty-blocks

    /// @notice Performs a swap, delegating all calls encoded in `data` to `caller`. See tests for usage examples
    /// @param caller Aggregation executor that executes calls described in `data`
    /// @param desc Swap description
    /// @param data Encoded calls that `caller` should execute in between of swaps
    /// @return returnAmount Resulting token amount
    /// @return spentAmount Source token amount
    /// @return gasLeft Gas left
    function swap(
        IAggregationExecutor caller,
        SwapDescription calldata desc,
        bytes calldata data
    )
        external
        payable
        returns (
            uint256 returnAmount,
            uint256 spentAmount,
            uint256 gasLeft
        )
    {
        require(desc.minReturnAmount > 0, "Min return should not be 0");
        require(data.length > 0, "data should not be empty");

        uint256 flags = desc.flags;
        IERC20 srcToken = desc.srcToken;
        IERC20 dstToken = desc.dstToken;

        bool srcETH = srcToken.isETH();

        if (flags & _REQUIRES_EXTRA_ETH != 0) {
            require(msg.value > (srcETH ? desc.amount : 0), "Invalid msg.value");
        } else {
            require(msg.value == (srcETH ? desc.amount : 0), "Invalid msg.value");
        }

        if (!srcETH) {
            _permit(address(srcToken), desc.permit);
            srcToken.safeTransferFrom(msg.sender, desc.srcReceiver, desc.amount);
        }

        {
            bytes memory callData = abi.encodePacked(caller.callBytes.selector, bytes12(0), msg.sender, data);
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, bytes memory result) = address(caller).call{value: msg.value}(callData);
            if (!success) {
                revert(RevertReasonParser.parse(result, "callBytes failed: "));
            }
        }

        spentAmount = desc.amount;
        returnAmount = dstToken.uniBalanceOf(address(this));

        if (flags & _PARTIAL_FILL != 0) {
            uint256 unspentAmount = srcToken.uniBalanceOf(address(this));
            if (unspentAmount > 0) {
                spentAmount = spentAmount.sub(unspentAmount);
                srcToken.uniTransfer(msg.sender, unspentAmount);
            }
            require(returnAmount.mul(desc.amount) >= desc.minReturnAmount.mul(spentAmount), "Return amount is not enough");
        } else {
            require(returnAmount >= desc.minReturnAmount, "Return amount is not enough");
        }

        address payable dstReceiver = (desc.dstReceiver == address(0)) ? msg.sender : desc.dstReceiver;
        dstToken.uniTransfer(dstReceiver, returnAmount);

        gasLeft = gasleft();
    }

    function rescueFunds(IERC20 token, uint256 amount) external onlyOwner {
        token.uniTransfer(msg.sender, amount);
    }

    function destroy() external onlyOwner {
        selfdestruct(msg.sender);
    }
}