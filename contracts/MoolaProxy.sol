// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IMoolaProxy.sol";
import "./interfaces/IAToken.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/ILendingPoolCore.sol";
import "./interfaces/IUbeswapRouter.sol";

/**
 * Proxy to deposit and withdraw into Moola.
 */
contract MoolaProxy is IMoolaProxy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Referral code to allow tracking Moola volume originating from Ubeswap.
    uint16 public constant UBESWAP_MOOLA_ROUTER_REFERRAL_CODE = 0x0420;

    /// @notice Moola lending pool
    ILendingPool public pool;

    /// @notice Moola lending core
    ILendingPoolCore public core;

    constructor(address pool_, address core_) {
        pool = ILendingPool(pool_);
        core = ILendingPoolCore(core_);
    }

    /**
     * Deposits tokens into Moola.
     * @param _reserve The token to deposit.
     * @param _amount The total amount of tokens to deposit.
     */
    function deposit(address _reserve, uint256 _amount) external override {
        IERC20(_reserve).safeTransferFrom(msg.sender, address(this), _amount);
        _convert(_reserve, _amount, true, Reason.DIRECT);
        IERC20(getReserveATokenAddress(_reserve)).safeTransfer(
            msg.sender,
            _amount
        );
    }

    /**
     * Withdraws tokens from Moola.
     * @param _reserve The token to withdraw.
     * @param _amount The total amount of tokens to withdraw.
     */
    function withdraw(address _reserve, uint256 _amount) external override {
        IERC20(getReserveATokenAddress(_reserve)).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        _convert(_reserve, _amount, false, Reason.DIRECT);
        IERC20(_reserve).safeTransfer(msg.sender, _amount);
    }

    /**
     * Converts tokens to/from their Moola representation.
     * @param _reserve The token to deposit or withdraw.
     * @param _amount The total amount of tokens to deposit or withdraw.
     * @param _deposit If true, deposit the aToken. Otherwise, withdraw.
     * @param _reason Reason for why the conversion happened.
     */
    function _convert(
        address _reserve,
        uint256 _amount,
        bool _deposit,
        Reason _reason
    ) internal nonReentrant {
        if (_deposit) {
            IERC20(_reserve).safeApprove(address(core), _amount);
            pool.deposit(_reserve, _amount, UBESWAP_MOOLA_ROUTER_REFERRAL_CODE);
            emit Deposited(_reserve, msg.sender, _reason, _amount);
        } else {
            IAToken(getReserveATokenAddress(_reserve)).redeem(_amount);
            emit Withdrawn(_reserve, msg.sender, _reason, _amount);
        }
    }

    /**
     * Gets the address of the aToken assocated with the reserve.
     */
    function getReserveATokenAddress(address _reserve)
        public
        view
        override
        returns (address)
    {
        address aToken = core.getReserveATokenAddress(_reserve);
        require(
            aToken != address(0),
            "MoolaProxy::getReserveATokenAddress: unknown reserve"
        );
        return aToken;
    }
}
