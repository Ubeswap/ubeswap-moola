// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ILendingPoolWrapper.sol";
import "../interfaces/IMoola.sol";
import "./MoolaLibrary.sol";
import "../util/UsesGold.sol";

/**
 * @notice Wrapper to deposit and withdraw into a lending pool.
 */
contract LendingPoolWrapper is ILendingPoolWrapper, ReentrancyGuard, UsesGold {
    using SafeERC20 for IERC20;

    /// @notice Lending pool
    ILendingPool public pool;

    /// @notice Moola DataProvider
    IDataProvider public dataProvider;

    /// @notice Referral code to allow tracking Moola volume originating from Ubeswap.
    uint16 public immutable moolaReferralCode;

    constructor(uint16 moolaReferralCode_) {
        moolaReferralCode = moolaReferralCode_;
    }

    /// @notice initializes the pool (only used for deployment)
    function initialize(address _pool, address _dataProvider) external {
        require(
            address(pool) == address(0),
            "LendingPoolWrapper: pool already set"
        );
        require(
            address(dataProvider) == address(0),
            "LendingPoolWrapper: dataProvider already set"
        );
        pool = ILendingPool(_pool);
        dataProvider = IDataProvider(_dataProvider);
    }

    function deposit(address _reserve, uint256 _amount) external override {
        IERC20(_reserve).safeTransferFrom(msg.sender, address(this), _amount);
        _convert(_reserve, _amount, true, Reason.DIRECT);
        (address aTokenAddress, , ) =
            dataProvider.getReserveTokensAddresses(_reserve);
        IERC20(aTokenAddress).safeTransfer(msg.sender, _amount);
    }

    function withdraw(address _reserve, uint256 _amount) external override {
        (address aTokenAddress, , ) =
            dataProvider.getReserveTokensAddresses(_reserve);
        IERC20(aTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        _convert(_reserve, _amount, false, Reason.DIRECT);
        IERC20(_reserve).safeTransfer(msg.sender, _amount);
    }

    /**
     * @notice Converts tokens to/from their Moola representation.
     * @param _reserve The token to deposit or withdraw.
     * @param _amount The total amount of tokens to deposit or withdraw.
     * @param _deposit If true, deposit the token for aTokens. Otherwise, withdraw aTokens to tokens.
     * @param _reason Reason for why the conversion happened.
     */
    function _convert(
        address _reserve,
        uint256 _amount,
        bool _deposit,
        Reason _reason
    ) internal nonReentrant {
        if (_deposit) {
            IERC20(_reserve).safeApprove(address(pool), _amount);
            pool.deposit(_reserve, _amount, address(this), moolaReferralCode);
            emit Deposited(_reserve, msg.sender, _reason, _amount);
        } else {
            pool.withdraw(_reserve, _amount, address(this));
            emit Withdrawn(_reserve, msg.sender, _reason, _amount);
        }
    }
}
