// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ILendingPoolWrapper.sol";
import "../interfaces/IMoola.sol";
import "../interfaces/IUbeswapRouter.sol";

interface IRegistry {
    function getAddressForOrDie(bytes32) external view returns (address);
}

/**
 * Library for interacting with Moola.
 */
library MoolaLibrary {
    /// @dev Mock CELO address to represent raw CELO tokens
    address internal constant CELO_MAGIC_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev Referral code to allow tracking Moola volume originating from Ubeswap.
    uint16 internal constant UBESWAP_MOOLA_ROUTER_REFERRAL_CODE = 0x0420;

    /// @dev Address of the Celo registry
    address internal constant CELO_REGISTRY =
        0x000000000000000000000000000000000000ce10;

    bytes32 internal constant GOLD_TOKEN_REGISTRY_ID =
        keccak256(abi.encodePacked("GoldToken"));

    /// @notice Gets the address of CGLD
    function getGoldToken() internal view returns (address) {
        if (block.chainid == 31337) {
            // deployed via create2 in tests
            return 0x3F735F0E3bdcFaA6e53FD0D9C844a3fcd3CCC81b;
        }
        return
            IRegistry(CELO_REGISTRY).getAddressForOrDie(GOLD_TOKEN_REGISTRY_ID);
    }

    /// @notice Gets the token that Moola requests, supporting the gold token.
    function getMoolaReserveToken(address _reserve)
        internal
        view
        returns (address)
    {
        if (_reserve == getGoldToken()) {
            _reserve = CELO_MAGIC_ADDRESS;
        }
        return _reserve;
    }
}
