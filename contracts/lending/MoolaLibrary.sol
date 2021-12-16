// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

interface IRegistry {
    function getAddressForOrDie(bytes32) external view returns (address);
}
