// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../interfaces/IUbeswapRouter.sol";
import "../interfaces/IMoola.sol";
import "../lending/MoolaLibrary.sol";

/// @notice Library for computing various router functions
library UbeswapMoolaRouterLibrary {
    /// @notice Plan for executing a swap on the router.
    struct SwapPlan {
        address reserveIn;
        address reserveOut;
        bool depositIn;
        bool depositOut;
        address[] nextPath;
    }

    /// @notice Computes the swap that will take place based on the path
    function computeSwap(IDataProvider _dataProvider, address[] calldata _path)
        internal
        view
        returns (SwapPlan memory _plan)
    {
        uint256 startIndex;
        uint256 endIndex = _path.length;

        // cAsset -> mcAsset (deposit)
        (address aTokenAddress0, , ) =
            _dataProvider.getReserveTokensAddresses(
                MoolaLibrary.getMoolaReserveToken(_path[0])
            );
        (address aTokenAddress1, , ) =
            _dataProvider.getReserveTokensAddresses(
                MoolaLibrary.getMoolaReserveToken(_path[1])
            );
        if (aTokenAddress0 == _path[1]) {
            _plan.reserveIn = _path[0];
            _plan.depositIn = true;
            startIndex += 1;
        }
        // mcAsset -> cAsset (withdraw)
        else if (_path[0] == aTokenAddress1) {
            _plan.reserveIn = _path[1];
            _plan.depositIn = false;
            startIndex += 1;
        }

        // only handle out path swap if the path is long enough
        if (
            _path.length >= 3 &&
            // if we already did a conversion and path length is 3, skip.
            !(_path.length == 3 && startIndex > 0)
        ) {
            (address aTokenAddressLast1, , ) =
                _dataProvider.getReserveTokensAddresses(
                    MoolaLibrary.getMoolaReserveToken(_path[_path.length - 2])
                );
            (address aTokenAddressLast0, , ) =
                _dataProvider.getReserveTokensAddresses(
                    MoolaLibrary.getMoolaReserveToken(_path[_path.length - 1])
                );
            // cAsset -> mcAsset (deposit)
            if (aTokenAddressLast1 == _path[_path.length - 1]) {
                _plan.reserveOut = _path[_path.length - 2];
                _plan.depositOut = true;
                endIndex -= 1;
            }
            // mcAsset -> cAsset (withdraw)
            else if (_path[_path.length - 2] == aTokenAddressLast0) {
                _plan.reserveOut = _path[_path.length - 1];
                endIndex -= 1;
                // not needed
                // _depositOut = false;
            }
        }

        _plan.nextPath = _path[startIndex:endIndex];
    }

    /// @notice Computes the amounts given the amounts returned by the router
    function computeAmountsFromRouterAmounts(
        uint256[] memory _routerAmounts,
        address _reserveIn,
        address _reserveOut
    ) internal pure returns (uint256[] memory amounts) {
        uint256 startOffset = _reserveIn != address(0) ? 1 : 0;
        uint256 endOffset = _reserveOut != address(0) ? 1 : 0;
        uint256 length = _routerAmounts.length + startOffset + endOffset;

        amounts = new uint256[](length);
        if (startOffset > 0) {
            amounts[0] = _routerAmounts[0];
        }
        if (endOffset > 0) {
            amounts[length - 1] = _routerAmounts[_routerAmounts.length - 1];
        }
        for (uint256 i = 0; i < _routerAmounts.length; i++) {
            amounts[i + startOffset] = _routerAmounts[i];
        }
    }

    function getAmountsOut(
        IDataProvider dataProvider,
        IUbeswapRouter router,
        uint256 amountIn,
        address[] calldata path
    ) internal view returns (uint256[] memory amounts) {
        SwapPlan memory plan = computeSwap(dataProvider, path);
        amounts = computeAmountsFromRouterAmounts(
            router.getAmountsOut(amountIn, plan.nextPath),
            plan.reserveIn,
            plan.reserveOut
        );
    }

    function getAmountsIn(
        IDataProvider dataProvider,
        IUbeswapRouter router,
        uint256 amountOut,
        address[] calldata path
    ) internal view returns (uint256[] memory amounts) {
        SwapPlan memory plan = computeSwap(dataProvider, path);
        amounts = computeAmountsFromRouterAmounts(
            router.getAmountsIn(amountOut, plan.nextPath),
            plan.reserveIn,
            plan.reserveOut
        );
    }
}
