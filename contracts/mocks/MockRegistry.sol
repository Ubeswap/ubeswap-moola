// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

/// @notice This mock address book never changes
contract MockRegistry {
    mapping(bytes32 => address) public getAddressForOrDie;

    constructor() // solhint-disable-next-line no-empty-blocks
    {

    }

    function setAddress(bytes32 _id, address _address) public {
        getAddressForOrDie[_id] = _address;
    }
}
