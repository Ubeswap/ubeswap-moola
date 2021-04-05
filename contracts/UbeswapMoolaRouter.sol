// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

import "./MoolaProxy.sol";
import "./interfaces/IUbeswapMoolaRouter.sol";

import "./interfaces/IAToken.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/ILendingPoolCore.sol";
import "./interfaces/IUbeswapRouter.sol";

/**
 * Router for allowing conversion to/from Moola before swapping.
 */
contract UbeswapMoolaRouter is MoolaProxy, IUbeswapMoolaRouter {
    using SafeERC20 for IERC20;

    /// @notice Ubeswap router
    IUbeswapRouter public router;

    constructor(
        address router_,
        address pool_,
        address core_
    ) MoolaProxy(pool_, core_) {
        router = IUbeswapRouter(router_);
    }

    // Checks if the path is valid with the given reserves.
    // Also converts the input amount from the user, if specified.
    function _initSwap(
        address[] calldata _path,
        address[2] calldata _reserves,
        bool[2] calldata _directions,
        uint256 _inAmount
    ) internal returns (address _outToken) {
        require(
            _inAmount > 0,
            "UbeswapMoolaRouter::_initSwap: _inAmount must be > 0"
        );

        if (_reserves[1] == address(0)) {
            _outToken = _directions[1]
                ? _reserves[1]
                : getReserveATokenAddress(_reserves[1]);
            require(
                (
                    _directions[1]
                        ? getReserveATokenAddress(_reserves[1])
                        : _reserves[1]
                ) == _path[_path.length - 1],
                "UbeswapMoolaRouter::_initSwap: end mismatch"
            );
            require(
                _outToken != address(0),
                "UbeswapMoolaRouter::_initSwap: out token not found"
            );
        }

        if (_reserves[0] != address(0)) {
            address inToken =
                _directions[0]
                    ? _reserves[0]
                    : getReserveATokenAddress(_reserves[0]);
            require(
                (
                    _directions[0]
                        ? getReserveATokenAddress(_reserves[0])
                        : _reserves[0]
                ) == _path[0],
                "UbeswapMoolaRouter::_initSwap: start mismatch"
            );
            require(
                inToken != address(0),
                "UbeswapMoolaRouter::_initSwap: in token not found"
            );

            // If inToken is found, pull it and convert the token.
            IERC20(inToken).safeTransferFrom(
                msg.sender,
                address(this),
                _inAmount
            );
            IERC20(inToken).safeApprove(address(router), _inAmount);
            _convert(
                _reserves[0],
                _inAmount,
                _directions[0],
                Reason.CONVERT_IN
            );
        }
    }

    function _convertTokensOut(
        address _to,
        address _outToken,
        address _reserve,
        uint256 _amount,
        bool _withdrawOut
    ) internal {
        if (_outToken != address(0)) {
            _convert(_reserve, _amount, !_withdrawOut, Reason.CONVERT_OUT);
            IERC20(_outToken).safeTransfer(_to, _amount);
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        // moola
        address[2] calldata _reserves,
        bool[2] calldata _directions
    ) external override returns (uint256[] memory amounts) {
        uint256 inAmount = router.getAmountsOut(amountIn, path)[0];
        address outToken = _initSwap(path, _reserves, _directions, inAmount);

        amounts = router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            deadline
        );

        _convertTokensOut(
            to,
            outToken,
            _reserves[1],
            amounts[amounts.length - 1],
            _directions[1]
        );
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline,
        // moola
        address[2] calldata _reserves,
        bool[2] calldata _directions
    ) external override returns (uint256[] memory amounts) {
        uint256 inAmount = router.getAmountsIn(amountOut, path)[0];
        address outToken = _initSwap(path, _reserves, _directions, inAmount);

        amounts = router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            address(this),
            deadline
        );

        _convertTokensOut(
            to,
            outToken,
            _reserves[1],
            amounts[amounts.length - 1],
            _directions[1]
        );
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        // moola
        address[2] calldata _reserves,
        bool[2] calldata _directions
    ) external override {
        address outToken = _initSwap(path, _reserves, _directions, amountIn);

        uint256 balanceBefore =
            IERC20(path[path.length - 1]).balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            deadline
        );
        uint256 balanceAfter =
            IERC20(path[path.length - 1]).balanceOf(address(this));

        _convertTokensOut(
            to,
            outToken,
            _reserves[1],
            balanceAfter - balanceBefore,
            _directions[1]
        );
    }
}
