// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IAToken.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/ILendingPoolCore.sol";
import "./interfaces/IUbeswapRouter.sol";

/**
 * Router for allowing conversion to/from Moola before swapping.
 */
contract UbeswapMoolaRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Referral code to allow tracking Moola volume originating from Ubeswap.
    uint16 public constant UBESWAP_MOOLA_ROUTER_REFERRAL_CODE = 0x0420;

    /// @notice Ubeswap router
    IUbeswapRouter public router;

    /// @notice Moola lending pool
    ILendingPool public pool;

    /// @notice Moola lending core
    ILendingPoolCore public core;

    constructor(
        address router_,
        address pool_,
        address core_
    ) {
        router = IUbeswapRouter(router_);
        pool = ILendingPool(pool_);
        core = ILendingPoolCore(core_);
    }

    /**
     * Converts tokens to/from their Moola representation.
     * @param _reserve The token to deposit or withdraw.
     * @param _amount The total amount of tokens to deposit or withdraw.
     * @param _deposit If true, deposit the aToken. Otherwise, withdraw.
     */
    function _convert(
        address _reserve,
        uint256 _amount,
        bool _deposit
    ) internal nonReentrant {
        if (_deposit) {
            IERC20(_reserve).safeApprove(address(core), _amount);
            pool.deposit(_reserve, _amount, UBESWAP_MOOLA_ROUTER_REFERRAL_CODE);
        } else {
            IAToken(getReserveATokenAddress(_reserve)).redeem(_amount);
        }
    }

    /**
     * Gets the address of the aToken assocated with the reserve.
     */
    function getReserveATokenAddress(address _reserve)
        public
        view
        returns (address)
    {
        address aToken = core.getReserveATokenAddress(_reserve);
        require(
            aToken != address(0),
            "UbeswapMoolaRouter::getReserveATokenAddress: unknown reserve"
        );
        return aToken;
    }

    function _convertTokensIn(
        address _reserveIn,
        uint256 _amountIn,
        bool _depositIn
    ) internal {
        if (_reserveIn != address(0)) {
            address inToken =
                _depositIn ? _reserveIn : getReserveATokenAddress(_reserveIn);
            IERC20(inToken).safeTransferFrom(
                msg.sender,
                address(this),
                _amountIn
            );
            IERC20(inToken).safeApprove(address(router), _amountIn);
            _convert(_reserveIn, _amountIn, _depositIn);
        }
    }

    function _convertTokensOut(
        address _to,
        address _reserveOut,
        uint256 _amountOut,
        bool _depositOut
    ) internal {
        if (_reserveOut != address(0)) {
            _convert(_reserveOut, _amountOut, _depositOut);
            address outToken =
                _depositOut
                    ? _reserveOut
                    : getReserveATokenAddress(_reserveOut);
            IERC20(outToken).safeTransfer(_to, _amountOut);
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        // moola
        address _reserveIn,
        bool _depositIn,
        address _reserveOut,
        bool _depositOut
    ) external returns (uint256[] memory amounts) {
        amounts = router.getAmountsOut(amountIn, path);
        _convertTokensIn(_reserveIn, amounts[0], _depositIn);

        amounts = router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            deadline
        );

        _convertTokensOut(
            to,
            _reserveOut,
            amounts[amounts.length - 1],
            _depositOut
        );
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline,
        // moola
        address _reserveIn,
        bool _depositIn,
        address _reserveOut,
        bool _depositOut
    ) external returns (uint256[] memory amounts) {
        amounts = router.getAmountsIn(amountOut, path);
        _convertTokensIn(_reserveIn, amounts[0], _depositIn);

        amounts = router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            address(this),
            deadline
        );

        _convertTokensOut(
            to,
            _reserveOut,
            amounts[amounts.length - 1],
            _depositOut
        );
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        // moola
        address _reserveIn,
        bool _depositIn,
        address _reserveOut,
        bool _depositOut
    ) external {
        _convertTokensIn(_reserveIn, amountIn, _depositIn);

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            deadline
        );

        _convertTokensOut(
            to,
            _reserveOut,
            IERC20(path[path.length - 1]).balanceOf(address(this)),
            _depositOut
        );
    }
}
