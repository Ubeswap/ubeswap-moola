// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface ILendingPoolCore {
    function getReserveATokenAddress(address _reserve)
        external
        view
        returns (address);
}
