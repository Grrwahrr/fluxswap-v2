pragma solidity >=0.5.0;

interface IFluxCallee {
    function onFluxExchange(address sender, uint amountA, uint amountB, bytes calldata payload) external;
}
