// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../interfaces/IMoola.sol";
import "./MockERC20.sol";

contract MockAToken is ERC20, IAToken {
    MockLendingPoolCore public immutable core;
    IERC20 public immutable underlying;

    constructor(
        MockLendingPoolCore core_,
        IERC20 _underlying,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {
        core = core_;
        underlying = _underlying;
    }

    function mint(uint256 _amount) external {
        require(msg.sender == address(core), "MockMoola: minter not core");
        _mint(msg.sender, _amount);
    }

    function redeem(uint256 _amount) external override {
        _burn(msg.sender, _amount);
        core.redeemTo(msg.sender, _amount);
    }
}

contract MockLendingPoolCore is ILendingPoolCore {
    MockGold public celo;
    MockERC20 public cusd;
    MockAToken public mcelo;
    MockAToken public mcusd;

    mapping(address => address) public tokens;

    /// @notice Mock CELO address to represent raw CELO tokens
    address public constant CELO_MAGIC_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function initialize() external {
        celo = new MockGold();
        cusd = new MockERC20("Celo Dollar", "cUSD");
        mcelo = new MockAToken(this, celo, "Moola Celo", "mCELO");
        mcusd = new MockAToken(this, cusd, "Moola cUSD", "mcUSD");
        tokens[CELO_MAGIC_ADDRESS] = address(mcelo);
        tokens[address(cusd)] = address(mcusd);
        cusd.transfer(msg.sender, cusd.balanceOf(address(this)));
    }

    function redeemTo(address _user, uint256 _amount) external {
        require(
            msg.sender == address(mcelo) || msg.sender == address(mcusd),
            "MockMoola: invalid sender"
        );
        IERC20 underlying = MockAToken(msg.sender).underlying();
        if (underlying == celo) {
            celo.unwrapTestingOnly(_amount);
            Address.sendValue(payable(_user), _amount);
        } else {
            underlying.transfer(_user, _amount);
        }
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
        } else {
            IERC20(_reserve).transferFrom(_sender, address(this), _amount);
        }
        MockAToken(tokens[_reserve]).mint(_amount);
        MockAToken(tokens[_reserve]).transfer(_sender, _amount);
    }

    receive() external payable {
        require(
            msg.sender == address(celo),
            "MockMoola: must be celo to receive"
        );
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
