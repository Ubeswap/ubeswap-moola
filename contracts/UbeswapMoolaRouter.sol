// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

import "./LendingPoolWrapper.sol";
import "./interfaces/IAToken.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/ILendingPoolCore.sol";
import "./interfaces/IUbeswapRouter.sol";

/**
 * Router for allowing conversion to/from Moola before swapping.
 */
contract UbeswapMoolaRouter is LendingPoolWrapper, IUbeswapRouter {
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
        private
        returns (
            address _reserveIn,
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
        _reserveIn = reserveIn;
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

    // converts out tokens and computes the path amounts
    function _convertTokensOut(
        address _reserveOut,
        bool _depositOut,
        address _to,
        uint256 _amount
    ) private {
        if (_reserveOut != address(0)) {
            _convert(_reserveOut, _amount, _depositOut, Reason.CONVERT_OUT);
            IERC20(
                _depositOut ? getReserveATokenAddress(_reserveOut) : _reserveOut
            )
                .safeTransfer(_to, _amount);
        }
    }

    // computes the amounts given the amounts returned by the router
    function _computeAmounts(
        uint256[] memory routerAmounts,
        address _reserveIn,
        address _reserveOut
    ) private pure returns (uint256[] memory amounts) {
        uint256 startOffset = _reserveIn != address(0) ? 1 : 0;
        uint256 endOffset = _reserveOut != address(0) ? 1 : 0;
        uint256 length = routerAmounts.length + startOffset + endOffset;

        amounts = new uint256[](length);
        if (startOffset > 0) {
            amounts[0] = routerAmounts[0];
        }
        if (endOffset > 0) {
            amounts[length - 1] = routerAmounts[routerAmounts.length - 1];
        }
        for (uint256 i = 0; i < routerAmounts.length; i++) {
            amounts[i + startOffset] = routerAmounts[i];
        }
    }

    // TODO(igm): remove this once we get an audit
    // This should NEVER get triggered, but it's better to be safe than sorry
    function _assertNoTokensLeftOver(address[] calldata path) private view {
        for (uint256 i = 0; i < path.length; i++) {
            require(
                IERC20(path[i]).balanceOf(address(this)) == 0,
                "UbeswapMoolaRouter: tokens left over after swap"
            );
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        (
            address reserveIn,
            address reserveOut,
            bool depositOut,
            address[] calldata nextPath
        ) = _initSwap(path, amountIn, 0);

        amounts = _computeAmounts(
            router.swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                nextPath,
                address(this),
                deadline
            ),
            reserveIn,
            reserveOut
        );

        _convertTokensOut(
            reserveOut,
            depositOut,
            to,
            amounts[amounts.length - 1]
        );
        _assertNoTokensLeftOver(path);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        (
            address reserveIn,
            address reserveOut,
            bool depositOut,
            address[] calldata nextPath
        ) = _initSwap(path, 0, amountOut);

        amounts = _computeAmounts(
            router.swapTokensForExactTokens(
                amountOut,
                amountInMax,
                nextPath,
                address(this),
                deadline
            ),
            reserveIn,
            reserveOut
        );

        _convertTokensOut(
            reserveOut,
            depositOut,
            to,
            amounts[amounts.length - 1]
        );
        _assertNoTokensLeftOver(path);
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override {
        (, address reserveOut, bool depositOut, address[] calldata nextPath) =
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
        _assertNoTokensLeftOver(path);
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        (
            address reserveIn,
            ,
            address reserveOut,
            ,
            address[] calldata nextPath
        ) = computeSwap(path);
        amounts = _computeAmounts(
            router.getAmountsOut(amountIn, nextPath),
            reserveIn,
            reserveOut
        );
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        (
            address reserveIn,
            ,
            address reserveOut,
            ,
            address[] calldata nextPath
        ) = computeSwap(path);
        amounts = _computeAmounts(
            router.getAmountsIn(amountOut, nextPath),
            reserveIn,
            reserveOut
        );
    }
}
