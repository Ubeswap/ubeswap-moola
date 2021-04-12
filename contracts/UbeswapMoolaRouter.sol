// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

import "./LendingPoolWrapper.sol";
import "./interfaces/ITokenRouter.sol";

import "./interfaces/IAToken.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/ILendingPoolCore.sol";
import "./interfaces/IUbeswapRouter.sol";

/**
 * Router for allowing conversion to/from Moola before swapping.
 */
contract UbeswapMoolaRouter is LendingPoolWrapper, ITokenRouter {
    using SafeERC20 for IERC20;

    /// @notice Ubeswap router
    IUbeswapRouter public immutable router;

    constructor(address router_, address registry_)
        LendingPoolWrapper(registry_)
    {
        router = IUbeswapRouter(router_);
    }

    // Computes the swap that will take place based on the path
    function computeSwap(address[] calldata _path)
        public
        view
        returns (
            address _reserveIn,
            bool _depositIn,
            address _reserveOut,
            bool _depositOut,
            address[] calldata _nextPath
        )
    {
        uint256 startIndex;
        uint256 endIndex = _path.length;

        // cAsset -> mcAsset (deposit)
        if (getReserveATokenAddress(_path[0]) == _path[1]) {
            _reserveIn = _path[0];
            _depositIn = true;
            startIndex += 1;
        }
        // mcAsset -> cAsset (withdraw)
        else if (_path[0] == getReserveATokenAddress(_path[1])) {
            _reserveIn = _path[1];
            _depositIn = false;
            startIndex += 1;
        }

        // only handle out path swap if the path is long enough
        if (
            _path.length >= 3 &&
            // if we already did a conversion and path length is 3, skip.
            !(_path.length == 3 && startIndex > 0)
        ) {
            // cAsset -> mcAsset (deposit)
            if (
                getReserveATokenAddress(_path[_path.length - 2]) ==
                _path[_path.length - 1]
            ) {
                _reserveOut = _path[_path.length - 2];
                _depositOut = true;
                endIndex -= 1;
            }
            // mcAsset -> cAsset (withdraw)
            else if (
                _path[_path.length - 2] ==
                getReserveATokenAddress(_path[_path.length - 1])
            ) {
                _reserveOut = _path[_path.length - 1];
                endIndex -= 1;
                // not needed
                // _depositOut = false;
            }
        }

        _nextPath = _path[startIndex:endIndex];
    }

    function _initSwap(
        address[] calldata _path,
        uint256 _inAmount,
        uint256 _outAmount
    )
        internal
        returns (
            address _reserveOut,
            bool _depositOut,
            address[] calldata _nextPath
        )
    {
        (
            address reserveIn,
            bool depositIn,
            address reserveOut,
            bool depositOut,
            address[] calldata nextPath
        ) = computeSwap(_path);
        _reserveOut = reserveOut;
        _depositOut = depositOut;
        _nextPath = nextPath;

        // if out amount is specified, compute the in amount from it
        if (_outAmount != 0) {
            _inAmount = router.getAmountsIn(_outAmount, _nextPath)[0];
        }

        if (reserveIn != address(0)) {
            IERC20(depositIn ? getReserveATokenAddress(reserveIn) : reserveIn)
                .safeTransferFrom(msg.sender, address(this), _inAmount);
            _convert(reserveIn, _inAmount, depositIn, Reason.CONVERT_IN);
        }
    }

    function _convertTokensOut(
        address _reserveOut,
        bool _depositOut,
        address _to,
        uint256 _amount
    ) internal {
        if (_reserveOut != address(0)) {
            _convert(_reserveOut, _amount, _depositOut, Reason.CONVERT_OUT);
            IERC20(
                _depositOut ? getReserveATokenAddress(_reserveOut) : _reserveOut
            )
                .safeTransfer(_to, _amount);
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        (address reserveOut, bool depositOut, address[] calldata nextPath) =
            _initSwap(path, amountIn, 0);

        amounts = router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            nextPath,
            address(this),
            deadline
        );

        _convertTokensOut(
            reserveOut,
            depositOut,
            to,
            amounts[amounts.length - 1]
        );
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        (address reserveOut, bool depositOut, address[] calldata nextPath) =
            _initSwap(path, 0, amountOut);

        amounts = router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            nextPath,
            address(this),
            deadline
        );

        _convertTokensOut(
            reserveOut,
            depositOut,
            to,
            amounts[amounts.length - 1]
        );
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override {
        (address reserveOut, bool depositOut, address[] calldata nextPath) =
            _initSwap(path, amountIn, 0);

        uint256 balanceBefore =
            IERC20(path[path.length - 1]).balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            nextPath,
            address(this),
            deadline
        );
        uint256 balanceAfter =
            IERC20(path[path.length - 1]).balanceOf(address(this));

        _convertTokensOut(
            reserveOut,
            depositOut,
            to,
            balanceAfter - balanceBefore
        );
    }
}
