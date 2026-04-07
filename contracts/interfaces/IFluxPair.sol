pragma solidity >=0.5.0;

interface IFluxPair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

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

    function SEED_LIQUIDITY() external pure returns (uint);
    function hub() external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function getPoolBalances() external view returns (uint112 poolBalanceA, uint112 poolBalanceB, uint32 lastUpdateTime);
    function cumulativePriceALast() external view returns (uint);
    function cumulativePriceBLast() external view returns (uint);
    function lastProduct() external view returns (uint);

    function deposit(address to) external returns (uint liquidity);
    function withdraw(address to) external returns (uint amountA, uint amountB);
    function exchange(uint amountAOut, uint amountBOut, address to, bytes calldata data) external;
    function recoverSurplus(address to) external;
    function syncBalances() external;

    function configure(address, address) external;
}
