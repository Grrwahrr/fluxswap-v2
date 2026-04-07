pragma solidity =0.5.16;

import './interfaces/IFluxPair.sol';
import './FluxERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IFluxHub.sol';
import './interfaces/IFluxCallee.sol';

contract FluxPair is IFluxPair, FluxERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    uint public constant SEED_LIQUIDITY = 10**3;
    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public hub;
    address public tokenA;
    address public tokenB;

    uint112 private poolBalanceA;
    uint112 private poolBalanceB;
    uint32  private lastUpdateTime;

    uint public cumulativePriceALast;
    uint public cumulativePriceBLast;
    uint public lastProduct;

    uint private _reentrancyStatus = 1;
    modifier nonReentrant() {
        require(_reentrancyStatus == 1, 'FluxSwap: LOCKED');
        _reentrancyStatus = 2;
        _;
        _reentrancyStatus = 1;
    }

    event Deposit(address indexed sender, uint amountA, uint amountB);
    event Withdraw(address indexed sender, uint amountA, uint amountB, address indexed to);
    event Exchange(
        address indexed sender,
        uint amountAIn,
        uint amountBIn,
        uint amountAOut,
        uint amountBOut,
        address indexed to
    );
    event PoolSync(uint112 poolBalanceA, uint112 poolBalanceB);

    constructor() public {
        hub = msg.sender;
    }

    function configure(address _tokenA, address _tokenB) external {
        require(msg.sender == hub, 'FluxSwap: FORBIDDEN');
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function getPoolBalances() public view returns (uint112 _poolBalanceA, uint112 _poolBalanceB, uint32 _lastUpdateTime) {
        _poolBalanceA = poolBalanceA;
        _poolBalanceB = poolBalanceB;
        _lastUpdateTime = lastUpdateTime;
    }

    function _pushTokens(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(TRANSFER_SELECTOR, to, value));
    }

    function _refreshBalances(uint balA, uint balB, uint112 _prevA, uint112 _prevB) private {
        require(balA <= uint112(-1) && balB <= uint112(-1), 'FluxSwap: OVERFLOW');
        uint32 currentTime = uint32(block.timestamp % 2**32);
        uint32 elapsed = currentTime - lastUpdateTime;
        if (elapsed > 0 && _prevA != 0 && _prevB != 0) {
            cumulativePriceALast += uint(UQ112x112.encode(_prevB).uqdiv(_prevA)) * elapsed;
            cumulativePriceBLast += uint(UQ112x112.encode(_prevA).uqdiv(_prevB)) * elapsed;
        }
        poolBalanceA = uint112(balA);
        poolBalanceB = uint112(balB);
        lastUpdateTime = currentTime;
        emit PoolSync(poolBalanceA, poolBalanceB);
    }

    function _collectProtocolFee(uint112 _balA, uint112 _balB) private returns (bool feeActive) {
        address collector = IFluxHub(hub).feeCollector();
        feeActive = collector != address(0);
        uint _lastProduct = lastProduct;
        if (feeActive) {
            if (_lastProduct != 0) {
                uint rootK = Math.sqrt(uint(_balA).mul(_balB));
                uint rootKPrev = Math.sqrt(_lastProduct);
                if (rootK > rootKPrev) {
                    uint num = totalSupply.mul(rootK.sub(rootKPrev));
                    uint den = rootK.mul(5).add(rootKPrev);
                    uint shares = num / den;
                    if (shares > 0) _mint(collector, shares);
                }
            }
        } else if (_lastProduct != 0) {
            lastProduct = 0;
        }
    }

    function deposit(address to) external nonReentrant returns (uint liquidity) {
        (uint112 _balA, uint112 _balB,) = getPoolBalances();
        uint currentA = IERC20(tokenA).balanceOf(address(this));
        uint currentB = IERC20(tokenB).balanceOf(address(this));
        uint deltaA = currentA.sub(_balA);
        uint deltaB = currentB.sub(_balB);

        bool feeActive = _collectProtocolFee(_balA, _balB);
        uint _supply = totalSupply;
        if (_supply == 0) {
            liquidity = Math.sqrt(deltaA.mul(deltaB));
        } else {
            liquidity = Math.min(deltaA.mul(_supply) / _balA, deltaB.mul(_supply) / _balB);
        }
        require(liquidity > 0, 'FluxSwap: INSUFFICIENT_LIQUIDITY_DEPOSITED');
        _mint(to, liquidity);

        _refreshBalances(currentA, currentB, _balA, _balB);
        if (feeActive) lastProduct = uint(poolBalanceA).mul(poolBalanceB);
        emit Deposit(msg.sender, deltaA, deltaB);
    }

    function withdraw(address to) external nonReentrant returns (uint amountA, uint amountB) {
        (uint112 _balA, uint112 _balB,) = getPoolBalances();
        address _tA = tokenA;
        address _tB = tokenB;
        uint currentA = IERC20(_tA).balanceOf(address(this));
        uint currentB = IERC20(_tB).balanceOf(address(this));
        uint shares = balanceOf[address(this)];

        bool feeActive = _collectProtocolFee(_balA, _balB);
        uint _supply = totalSupply;
        amountA = shares.mul(currentA) / _supply;
        amountB = shares.mul(currentB) / _supply;
        require(amountA > 0 && amountB > 0, 'FluxSwap: INSUFFICIENT_LIQUIDITY_WITHDRAWN');
        _burn(address(this), shares);
        _pushTokens(_tA, to, amountA);
        _pushTokens(_tB, to, amountB);
        currentA = IERC20(_tA).balanceOf(address(this));
        currentB = IERC20(_tB).balanceOf(address(this));

        _refreshBalances(currentA, currentB, _balA, _balB);
        if (feeActive) lastProduct = uint(poolBalanceA).mul(poolBalanceB);
        emit Withdraw(msg.sender, amountA, amountB, to);
    }

    function exchange(uint amountAOut, uint amountBOut, address to, bytes calldata data) external {
        require(amountAOut > 0 || amountBOut > 0, 'FluxSwap: INSUFFICIENT_OUTPUT');
        (uint112 _balA, uint112 _balB,) = getPoolBalances();
        require(amountAOut < _balA && amountBOut < _balB, 'FluxSwap: INSUFFICIENT_POOL_BALANCE');

        uint postA;
        uint postB;
        {
        address _tA = tokenA;
        address _tB = tokenB;
        require(to != _tA && to != _tB, 'FluxSwap: INVALID_RECIPIENT');
        if (amountAOut > 0) _pushTokens(_tA, to, amountAOut);
        if (amountBOut > 0) _pushTokens(_tB, to, amountBOut);
        if (data.length > 0) IFluxCallee(to).onFluxExchange(msg.sender, amountAOut, amountBOut, data);
        postA = IERC20(_tA).balanceOf(address(this));
        postB = IERC20(_tB).balanceOf(address(this));
        }
        uint inA = postA > _balA - amountAOut ? postA - (_balA - amountAOut) : 0;
        uint inB = postB > _balB - amountBOut ? postB - (_balB - amountBOut) : 0;
        require(inA > 0 || inB > 0, 'FluxSwap: NO_INPUT_AMOUNT');

        _refreshBalances(postA, postB, _balA, _balB);
        emit Exchange(msg.sender, inA, inB, amountAOut, amountBOut, to);
    }

    function recoverSurplus(address to) external nonReentrant {
        address _tA = tokenA;
        address _tB = tokenB;
        _pushTokens(_tA, to, IERC20(_tA).balanceOf(address(this)).sub(poolBalanceA));
        _pushTokens(_tB, to, IERC20(_tB).balanceOf(address(this)).sub(poolBalanceB));
    }

    function syncBalances() external nonReentrant {
        _refreshBalances(IERC20(tokenA).balanceOf(address(this)), IERC20(tokenB).balanceOf(address(this)), poolBalanceA, poolBalanceB);
    }

    function emergencyWithdraw(address token, address to, uint amount) external {
        _pushTokens(token, to, amount);
    }
}
