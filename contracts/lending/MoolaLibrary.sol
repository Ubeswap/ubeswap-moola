// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

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

    /// @dev Address of the Celo registry
    address internal constant CELO_REGISTRY =
        0x000000000000000000000000000000000000ce10;

    bytes32 internal constant GOLD_TOKEN_REGISTRY_ID =
        keccak256(abi.encodePacked("GoldToken"));

    /// @notice Gets the address of CGLD
    function getGoldToken() internal view returns (address) {
        if (block.chainid == 31337) {
            // deployed via create2 in tests
            return
                IRegistry(0xd5Fd7f35752300C24cb6C2D4c954A34463070432)
                    .getAddressForOrDie(GOLD_TOKEN_REGISTRY_ID);
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
