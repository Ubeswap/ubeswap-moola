// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../interfaces/IMoola.sol";
import "./MockERC20.sol";

contract MockAToken is ERC20, IAToken {
    IERC20 public immutable underlying;

    constructor(
        IERC20 _underlying,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {
        underlying = _underlying;
    }

    function mint(uint256 _amount) external {
        underlying.transferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);
    }

    function redeem(uint256 _amount) external override {
        _burn(msg.sender, _amount);
        underlying.transfer(msg.sender, _amount);
    }
}

contract MockLendingPoolCore is ILendingPoolCore {
    MockGold public immutable celo;
    mapping(address => address) public tokens;

    /// @notice Mock CELO address to represent raw CELO tokens
    address public constant CELO_MAGIC_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor(
        address celo_,
        address cusd,
        address mcelo,
        address mcusd
    ) {
        celo = MockGold(celo_);
        tokens[CELO_MAGIC_ADDRESS] = mcelo;
        tokens[cusd] = mcusd;
    }

    function getReserveATokenAddress(address _reserve)
        external
        view
        override
        returns (address)
    {
        return address(tokens[_reserve]);
    }

    function deposit(
        address _sender,
        address _reserve,
        uint256 _amount
    ) external payable {
        if (_reserve == CELO_MAGIC_ADDRESS) {
            require(msg.value == _amount, "MockMoola: deposit mismatch");
            celo.wrap{value: _amount}();
            celo.approve(address(tokens[_reserve]), _amount);
        } else {
            IERC20(_reserve).transferFrom(_sender, address(this), _amount);
            IERC20(_reserve).approve(address(tokens[_reserve]), _amount);
        }
        MockAToken(tokens[_reserve]).mint(_amount);
        MockAToken(tokens[_reserve]).transfer(_sender, _amount);
    }
}

contract MockLendingPool is ILendingPool {
    MockLendingPoolCore public immutable core;

    mapping(address => MockAToken) public tokens;

    /// @notice Mock CELO address to represent raw CELO tokens
    address public constant CELO_MAGIC_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor(MockLendingPoolCore _core) {
        core = _core;
    }

    function deposit(
        address _reserve,
        uint256 _amount,
        uint16
    ) external payable override {
        if (_reserve == CELO_MAGIC_ADDRESS) {
            require(
                _amount == msg.value,
                "MockLendingPool: amount must equal msg.value"
            );
            core.deposit{value: _amount}(msg.sender, _reserve, _amount);
        } else {
            core.deposit(msg.sender, _reserve, _amount);
        }
    }
}
