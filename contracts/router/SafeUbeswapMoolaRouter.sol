// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "./UbeswapMoolaRouterBase.sol";
import "../util/RecoverERC20.sol";

/**
 * Router for allowing conversion to/from Moola before swapping,
 * with additional safety checks to ensure that balances don't change.
 */
contract SafeUbeswapMoolaRouter is UbeswapMoolaRouterBase, RecoverERC20 {
    using SafeERC20 for IERC20;

    /// @notice Referral code for the default Moola router
    uint16 public constant SAFE_MOOLA_ROUTER_REFERRAL_CODE = 0x0425;

    constructor(address router_, address owner_)
        UbeswapMoolaRouterBase(router_, SAFE_MOOLA_ROUTER_REFERRAL_CODE)
        RecoverERC20(owner_)
    // solhint-disable-next-line no-empty-blocks
    {

    }

    /// @dev Ensures that the ERC20 token balances of this contract before and after
    /// the swap are equal
    /// TODO(igm): remove this once we get an audit
    /// This should NEVER get triggered, but it's better to be safe than sorry
    modifier balanceUnchanged(address[] calldata _path, address _to) {
        // Populate initial balances for comparison later
        uint256[] memory _initialBalances = new uint256[](_path.length);
        for (uint256 i = 0; i < _path.length; i++) {
            _initialBalances[i] = IERC20(_path[i]).balanceOf(address(this));
        }
        _;
        for (uint256 i = 0; i < _path.length - 1; i++) {
            uint256 newBalance = IERC20(_path[i]).balanceOf(address(this));
            require(
                // if triangular arb, ignore
                _path[i] == _path[0] ||
                    _path[i] == _path[_path.length - 1] ||
                    // ensure tokens balances haven't changed
                    newBalance == _initialBalances[i],
                "SafeRouter: tokens left over after swap"
            );
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        public
        override
        balanceUnchanged(path, to)
        returns (uint256[] memory amounts)
    {
        return
            super.swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                path,
                to,
                deadline
            );
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        public
        override
        balanceUnchanged(path, to)
        returns (uint256[] memory amounts)
    {
        return
            super.swapTokensForExactTokens(
                amountOut,
                amountInMax,
                path,
                to,
                deadline
            );
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) public virtual override balanceUnchanged(path, to) {
        super.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
    }
}
