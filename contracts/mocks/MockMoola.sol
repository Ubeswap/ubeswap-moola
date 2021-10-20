// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../interfaces/IMoola.sol";
import "./MockERC20.sol";

contract MockAToken is ERC20 {
    address public immutable lendingPool;
    IERC20 public immutable underlying;

    constructor(
        address _lendingPool,
        IERC20 _underlying,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {
        lendingPool = _lendingPool;
        underlying = _underlying;
    }

    function mint(address _user, uint256 _amount) external {
        require(msg.sender == lendingPool, "MockMoola: minter not lendingPool");
        _mint(_user, _amount);
    }

    function burn(address _user, uint256 _amount) external {
        require(msg.sender == lendingPool, "MockMoola: burner not lendingPool");
        _burn(_user, _amount);
    }
}

contract MockDataProvider is IDataProvider {
    MockLendingPool public lendingPool;

    constructor(MockLendingPool _lendingPool) {
        lendingPool = _lendingPool;
    }

    function getReserveTokensAddresses(address asset)
        external
        view
        override
        returns (
            address aTokenAddress,
            address stableDebtTokenAddress,
            address variableDebtTokenAddress
        )
    {
        return (address(lendingPool.tokens(asset)), address(0), address(0));
    }
}

contract MockLendingPool is ILendingPool {
    MockGold public celo;
    MockERC20 public cusd;
    MockAToken public mcelo;
    MockAToken public mcusd;

    mapping(address => MockAToken) public tokens;

    constructor() {}

    function initialize() external {
        celo = new MockGold();
        cusd = new MockERC20("Celo Dollar", "cUSD");
        mcelo = new MockAToken(address(this), celo, "Moola Celo", "mCELO");
        mcusd = new MockAToken(address(this), cusd, "Moola cUSD", "mcUSD");
        tokens[address(celo)] = mcelo;
        tokens[address(cusd)] = mcusd;
        cusd.transfer(msg.sender, cusd.balanceOf(address(this)));
    }

    function deposit(
        address _reserve,
        uint256 _amount,
        address _onBehalfOf,
        uint16
    ) external override {
        IERC20(_reserve).transferFrom(msg.sender, address(this), _amount);
        tokens[_reserve].mint(msg.sender, _amount);
    }

    function withdraw(
        address _reserve,
        uint256 _amount,
        address _to
    ) external override {
        tokens[_reserve].burn(msg.sender, _amount);
        IERC20(_reserve).transfer(_to, _amount);
    }
}
