pragma solidity =0.5.16;

import './interfaces/IFluxHub.sol';
import './FluxPair.sol';

contract FluxHub is IFluxHub {
    address public feeCollector;
    address public governance;

    mapping(address => mapping(address => address)) public getPool;
    address[] public allPools;

    event PoolCreated(address indexed tokenA, address indexed tokenB, address pool, uint);

    constructor(address _governance) public {
        governance = _governance;
    }

    function totalPools() external view returns (uint) {
        return allPools.length;
    }

    function deployPool(address tokenX, address tokenY) external returns (address pool) {
        require(tokenX != tokenY, 'FluxSwap: IDENTICAL_TOKENS');
        (address tA, address tB) = tokenX < tokenY ? (tokenX, tokenY) : (tokenY, tokenX);
        require(tA != address(0), 'FluxSwap: ZERO_ADDRESS');
        require(getPool[tA][tB] == address(0), 'FluxSwap: POOL_EXISTS');
        bytes memory bytecode = type(FluxPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(tA, tB));
        assembly {
            pool := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IFluxPair(pool).configure(tA, tB);
        getPool[tA][tB] = pool;
        getPool[tB][tA] = pool;
        allPools.push(pool);
        emit PoolCreated(tA, tB, pool, allPools.length);
    }

    function setFeeCollector(address _feeCollector) external {
        require(msg.sender == governance, 'FluxSwap: FORBIDDEN');
        feeCollector = _feeCollector;
    }

    function transferGovernance(address _governance) external {
        governance = _governance;
    }
}
