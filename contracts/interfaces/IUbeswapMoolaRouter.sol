// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

/**
 * Ubeswap Router that allows withdrawing or depositing tokens into Moola before trading.
 */
interface IUbeswapMoolaRouter {
    /**
     * @param _reserves [_reserveIn, _reserveOut]
     * - _reserveIn Reserve token of the input. If zero, conversion is skipped.
     * - _reserveOut Reserve token of the output. If zero, conversion is skipped.
     * @param _directions [_depositIn _withdrawOut]
     * - _depositIn If true, deposit the input token to get the real input token (path[0]).
     * - _withdrawOut If true, withdraw the output token to get the actual output token (path[path.length - 1]).
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        // moola
        address[2] calldata _reserves,
        bool[2] calldata _directions
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline,
        // moola
        address[2] calldata _reserves,
        bool[2] calldata _directions
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        // moola
        address[2] calldata _reserves,
        bool[2] calldata _directions
    ) external;
}
