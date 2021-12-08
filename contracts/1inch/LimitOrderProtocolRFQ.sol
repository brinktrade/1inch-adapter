pragma solidity ^0.7.6;
pragma abicoder v2;

import './token/SafeERC20.sol';
import './math/SafeMath.sol';
import './helpers/EthReceiver.sol';
import './helpers/Permitable.sol';
import './drafts/EIP712.sol';
import './interfaces/IWETH.sol';
import './helpers/ECDSA.sol';
import './interfaces/IERC1271.sol';

contract LimitOrderProtocolRFQ is EthReceiver, EIP712("1inch RFQ", "2"), Permitable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event OrderFilledRFQ(
        bytes32 orderHash,
        uint256 makingAmount
    );

    struct OrderRFQ {
        // lowest 64 bits is the order id, next 64 bits is the expiration timestamp
        // highest bit is unwrap WETH flag which is set on taker's side
        // [unwrap eth(1 bit) | unused (127 bits) | expiration timestamp(64 bits) | orderId (64 bits)]
        uint256 info;
        IERC20 makerAsset;
        IERC20 takerAsset;
        address maker;
        address allowedSender;  // equals to Zero address on public orders
        uint256 makingAmount;
        uint256 takingAmount;
    }

    bytes32 constant public LIMIT_ORDER_RFQ_TYPEHASH = keccak256(
        "OrderRFQ(uint256 info,address makerAsset,address takerAsset,address maker,address allowedSender,uint256 makingAmount,uint256 takingAmount)"
    );
    uint256 private constant _UNWRAP_WETH_MASK = 1 << 255;

    IWETH private immutable _WETH;  // solhint-disable-line var-name-mixedcase
    mapping(address => mapping(uint256 => uint256)) private _invalidator;

    constructor(address weth) {
        _WETH = IWETH(weth);
    }

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns(bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Returns bitmask for double-spend invalidators based on lowest byte of order.info and filled quotes
    /// @return Result Each bit represents whenever corresponding quote was filled
    function invalidatorForOrderRFQ(address maker, uint256 slot) external view returns(uint256) {
        return _invalidator[maker][slot];
    }

    /// @notice Cancels order's quote
    function cancelOrderRFQ(uint256 orderInfo) external {
        _invalidateOrder(msg.sender, orderInfo);
    }

    /// @notice Fills order's quote, fully or partially (whichever is possible)
    /// @param order Order quote to fill
    /// @param signature Signature to confirm quote ownership
    /// @param makingAmount Making amount
    /// @param takingAmount Taking amount
    function fillOrderRFQ(
        OrderRFQ memory order,
        bytes calldata signature,
        uint256 makingAmount,
        uint256 takingAmount
    ) external payable returns(uint256 /* actualMakingAmount */, uint256 /* actualTakingAmount */) {
        return fillOrderRFQTo(order, signature, makingAmount, takingAmount, payable(msg.sender));
    }

    /// @notice Fills Same as `fillOrderRFQ` but calls permit first,
    /// allowing to approve token spending and make a swap in one transaction.
    /// Also allows to specify funds destination instead of `msg.sender`
    /// @param order Order quote to fill
    /// @param signature Signature to confirm quote ownership
    /// @param makingAmount Making amount
    /// @param takingAmount Taking amount
    /// @param target Address that will receive swap funds
    /// @param permit Should consist of abiencoded token address and encoded `IERC20Permit.permit` call.
    /// See tests for examples
    function fillOrderRFQToWithPermit(
        OrderRFQ memory order,
        bytes calldata signature,
        uint256 makingAmount,
        uint256 takingAmount,
        address payable target,
        bytes calldata permit
    ) external returns(uint256 /* actualMakingAmount */, uint256 /* actualTakingAmount */) {
        _permit(address(order.takerAsset), permit);
        return fillOrderRFQTo(order, signature, makingAmount, takingAmount, target);
    }

    /// @notice Same as `fillOrderRFQ` but allows to specify funds destination instead of `msg.sender`
    /// @param order Order quote to fill
    /// @param signature Signature to confirm quote ownership
    /// @param makingAmount Making amount
    /// @param takingAmount Taking amount
    /// @param target Address that will receive swap funds
    function fillOrderRFQTo(
        OrderRFQ memory order,
        bytes calldata signature,
        uint256 makingAmount,
        uint256 takingAmount,
        address payable target
    ) public payable returns(uint256 /* actualMakingAmount */, uint256 /* actualTakingAmount */) {
        address maker = order.maker;
        bool unwrapWETH = (order.info & _UNWRAP_WETH_MASK) > 0;
        order.info = order.info & (_UNWRAP_WETH_MASK - 1);  // zero-out unwrap weth flag as it is taker-only
        {  // Stack too deep
            uint256 info = order.info;
            // Check time expiration
            uint256 expiration = uint128(info) >> 64;
            require(expiration == 0 || block.timestamp <= expiration, "LOP: order expired");  // solhint-disable-line not-rely-on-time
            _invalidateOrder(maker, info);
        }

        {  // stack too deep
            uint256 orderMakingAmount = order.makingAmount;
            uint256 orderTakingAmount = order.takingAmount;
            // Compute partial fill if needed
            if (takingAmount == 0 && makingAmount == 0) {
                // Two zeros means whole order
                makingAmount = orderMakingAmount;
                takingAmount = orderTakingAmount;
            }
            else if (takingAmount == 0) {
                require(makingAmount <= orderMakingAmount, "LOP: making amount exceeded");
                takingAmount = orderTakingAmount.mul(makingAmount).add(orderMakingAmount - 1).div(orderMakingAmount);
            }
            else if (makingAmount == 0) {
                require(takingAmount <= orderTakingAmount, "LOP: taking amount exceeded");
                makingAmount = orderMakingAmount.mul(takingAmount).div(orderTakingAmount);
            }
            else {
                revert("LOP: one of amounts should be 0");
            }
        }

        require(makingAmount > 0 && takingAmount > 0, "LOP: can't swap 0 amount");

        // Validate order
        require(order.allowedSender == address(0) || order.allowedSender == msg.sender, "LOP: private order");
        bytes32 orderHash = _hashTypedDataV4(keccak256(abi.encode(LIMIT_ORDER_RFQ_TYPEHASH, order)));
        _validate(maker, orderHash, signature);

        // Maker => Taker
        if (order.makerAsset == _WETH && unwrapWETH) {
            order.makerAsset.safeTransferFrom(maker, address(this), makingAmount);
            _WETH.withdraw(makingAmount);
            target.transfer(makingAmount);
        } else {
            order.makerAsset.safeTransferFrom(maker, target, makingAmount);
        }
        // Taker => Maker
        if (order.takerAsset == _WETH && msg.value > 0) {
            require(msg.value == takingAmount, "LOP: wrong msg.value");
            _WETH.deposit{ value: takingAmount }();
            _WETH.transfer(maker, takingAmount);
        } else {
            require(msg.value == 0, "LOP: wrong msg.value");
            order.takerAsset.safeTransferFrom(msg.sender, maker, takingAmount);
        }

        emit OrderFilledRFQ(orderHash, makingAmount);
        return (makingAmount, takingAmount);
    }

    function _validate(address signer, bytes32 orderHash, bytes calldata signature) private view {
        if (ECDSA.tryRecover(orderHash, signature) != signer) {
            (bool success, bytes memory result) = signer.staticcall(
                abi.encodeWithSelector(IERC1271.isValidSignature.selector, orderHash, signature)
            );
            require(success && result.length == 32 && abi.decode(result, (bytes4)) == IERC1271.isValidSignature.selector, "LOP: bad signature");
        }
    }

    function _invalidateOrder(address maker, uint256 orderInfo) private {
        uint256 invalidatorSlot = uint64(orderInfo) >> 8;
        uint256 invalidatorBit = 1 << uint8(orderInfo);
        mapping(uint256 => uint256) storage invalidatorStorage = _invalidator[maker];
        uint256 invalidator = invalidatorStorage[invalidatorSlot];
        require(invalidator & invalidatorBit == 0, "LOP: invalidated order");
        invalidatorStorage[invalidatorSlot] = invalidator | invalidatorBit;
    }
}