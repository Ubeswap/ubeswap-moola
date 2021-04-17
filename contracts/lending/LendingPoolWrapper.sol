// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ILendingPoolWrapper.sol";
import "../interfaces/IMoola.sol";
import "../interfaces/IUbeswapRouter.sol";
import "./MoolaLibrary.sol";

interface IWrappedTestingGold {
    function unwrapTestingOnly(uint256 _amount) external;
}

/**
 * Wrapper to deposit and withdraw into a lending pool.
 */
contract LendingPoolWrapper is ILendingPoolWrapper, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Lending pool
    ILendingPool public pool;

    /// @notice Lending core
    ILendingPoolCore public core;

    /// @dev Referral code to allow tracking Moola volume originating from Ubeswap.
    uint16 public immutable moolaReferralCode;

    /// @dev Celo Gold token
    address public immutable goldToken = MoolaLibrary.getGoldToken();

    constructor(uint16 moolaReferralCode_) {
        moolaReferralCode = moolaReferralCode_;
    }

    // initializes the pool (only used for deployment)
    function initialize(address _pool, address _core) external {
        require(
            address(pool) == address(0),
            "LendingPoolWrapper: pool already set"
        );
        require(
            address(core) == address(0),
            "LendingPoolWrapper: core already set"
        );
        pool = ILendingPool(_pool);
        core = ILendingPoolCore(_core);
    }

    function deposit(address _reserve, uint256 _amount) external override {
        IERC20(_reserve).safeTransferFrom(msg.sender, address(this), _amount);
        _convert(_reserve, _amount, true, Reason.DIRECT);
        IERC20(
            core.getReserveATokenAddress(
                MoolaLibrary.getMoolaReserveToken(_reserve)
            )
        )
            .safeTransfer(msg.sender, _amount);
    }

    function withdraw(address _reserve, uint256 _amount) external override {
        IERC20(
            core.getReserveATokenAddress(
                MoolaLibrary.getMoolaReserveToken(_reserve)
            )
        )
            .safeTransferFrom(msg.sender, address(this), _amount);
        _convert(_reserve, _amount, false, Reason.DIRECT);
        IERC20(_reserve).safeTransfer(msg.sender, _amount);
    }

    /**
     * Converts tokens to/from their Moola representation.
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
            if (
                MoolaLibrary.getMoolaReserveToken(_reserve) ==
                MoolaLibrary.CELO_MAGIC_ADDRESS
            ) {
                // hardhat -- doesn't have celo erc20 so we need to handle it differently
                if (block.chainid == 31337) {
                    IWrappedTestingGold(goldToken).unwrapTestingOnly(_amount);
                }
                pool.deposit{value: _amount}(
                    MoolaLibrary.CELO_MAGIC_ADDRESS,
                    _amount,
                    moolaReferralCode
                );
            } else {
                IERC20(_reserve).safeApprove(address(core), _amount);
                pool.deposit(_reserve, _amount, moolaReferralCode);
            }
            emit Deposited(_reserve, msg.sender, _reason, _amount);
        } else {
            IAToken(
                core.getReserveATokenAddress(
                    MoolaLibrary.getMoolaReserveToken(_reserve)
                )
            )
                .redeem(_amount);
            emit Withdrawn(_reserve, msg.sender, _reason, _amount);
        }
    }

    /**
     * @notice This is used to receive payments from CELO used on Hardhat
     */
    receive() external payable {
        require(block.chainid == 31337, "LendingPoolWrapper: not on hardhat");
    }
}
