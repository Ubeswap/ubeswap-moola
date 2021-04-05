// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface ILendingPoolWrapper {
    enum InteractionType {DEPOSIT, WITHDRAW}
    enum Reason {DIRECT, CONVERT_IN, CONVERT_OUT}

    event Deposited(
        address indexed reserve,
        address indexed account,
        Reason indexed reason,
        uint256 amount
    );

    event Withdrawn(
        address indexed reserve,
        address indexed account,
        Reason indexed reason,
        uint256 amount
    );

    /**
     * Deposits tokens into the lending pool.
     * @param _reserve The token to deposit.
     * @param _amount The total amount of tokens to deposit.
     */
    function deposit(address _reserve, uint256 _amount) external;

    /**
     * Withdraws tokens from the lending pool.
     * @param _reserve The token to withdraw.
     * @param _amount The total amount of tokens to withdraw.
     */
    function withdraw(address _reserve, uint256 _amount) external;

    /**
     * Gets the address of the aToken assocated with the reserve.
     * @param _reserve The reserve token.
     */
    function getReserveATokenAddress(address _reserve)
        external
        view
        returns (address);
}
