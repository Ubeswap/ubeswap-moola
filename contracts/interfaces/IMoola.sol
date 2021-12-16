// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

// Interfaces in this file come from Moola.

interface IDataProvider {
    function getReserveTokensAddresses(address asset)
        external
        view
        returns (
            address aTokenAddress,
            address stableDebtTokenAddress,
            address variableDebtTokenAddress
        );
}

interface ILendingPool {
    function deposit(
        address _reserve,
        uint256 _amount,
        address _onBehalfOf,
        uint16 _referralCode
    ) external;

    function withdraw(
        address _reserve,
        uint256 _amount,
        address _to
    ) external;
}
