pragma solidity >=0.5.0;

interface IFluxHub {
    event PoolCreated(address indexed tokenA, address indexed tokenB, address pool, uint);

    function feeCollector() external view returns (address);
    function governance() external view returns (address);

    function getPool(address tokenA, address tokenB) external view returns (address pool);
    function allPools(uint) external view returns (address pool);
    function totalPools() external view returns (uint);

    function deployPool(address tokenA, address tokenB) external returns (address pool);

    function setFeeCollector(address) external;
    function transferGovernance(address) external;
}
