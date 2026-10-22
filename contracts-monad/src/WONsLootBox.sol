// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract WONsLootBox is Ownable, ReentrancyGuard {
    error PoolExists();
    error PoolNotFound();
    error PoolDepleted();
    error NotMatchEngine();
    error NotTrustedCaller();
    error PoolNotSettled();
    error AlreadySettled();
    error EmptyClaim();
    error InvalidAmount();
    error NothingToWithdraw();

    uint256 public constant GAS_PER_STEAL = 0.001 ether;
    uint256 public constant STREAM_BATCH_LIMIT = 50;

    address public matchEngine;
    address public trustedCaller;

    /// Sum of every unsettled pool. `withdrawSurplus` can only take balance
    /// above this, so a funded pool can never be swept out from under a match.
    uint256 public totalPooled;

    struct Pool {
        uint256 remainingValue;
        address finalHolder;
        bool settled;
    }

    mapping(bytes32 => Pool) public pools;

    event PoolFunded(bytes32 indexed matchId, uint256 amount);
    event MONStreamed(bytes32 indexed matchId, address indexed player, uint256 amount, uint256 poolRemaining);
    event LootBoxStolen(bytes32 indexed matchId, address indexed newHolder, uint256 poolRemaining);
    event PoolSettled(bytes32 indexed matchId, address indexed finalHolder, uint256 payout);
    event PoolDrained(bytes32 indexed matchId, address indexed to, uint256 amount);

    modifier onlyMatchEngine() {
        if (msg.sender != matchEngine) revert NotMatchEngine();
        _;
    }

    modifier onlyTrustedCaller() {
        if (msg.sender != trustedCaller) revert NotTrustedCaller();
        _;
    }

    constructor(address initialOwner, address _matchEngine, address _trustedCaller) Ownable(initialOwner) {
        matchEngine = _matchEngine;
        trustedCaller = _trustedCaller;
    }

    function setMatchEngine(address _matchEngine) external onlyOwner {
        matchEngine = _matchEngine;
    }

    function setTrustedCaller(address _trustedCaller) external onlyOwner {
        trustedCaller = _trustedCaller;
    }

    function fundPool(bytes32 matchId, uint256 amount) external payable onlyMatchEngine {
        if (pools[matchId].remainingValue > 0) revert PoolExists();
        if (msg.value != amount) revert InvalidAmount();
        pools[matchId] = Pool({ remainingValue: amount, finalHolder: address(0), settled: false });
        totalPooled += amount;
        emit PoolFunded(matchId, amount);
    }

    function streamMON(bytes32 matchId, address player, uint256 amount) external onlyTrustedCaller nonReentrant {
        Pool storage pool = pools[matchId];
        if (pool.remainingValue == 0) revert PoolDepleted();
        if (amount > pool.remainingValue) amount = pool.remainingValue;
        if (amount == 0) return;
        pool.remainingValue -= amount;
        totalPooled -= amount;
        (bool success, ) = payable(player).call{value: amount}("");
        require(success, "Transfer failed");
        emit MONStreamed(matchId, player, amount, pool.remainingValue);
    }

    function batchStream(bytes32 matchId, address[] calldata players, uint256[] calldata amounts) external onlyTrustedCaller nonReentrant {
        uint256 len = players.length;
        if (len > STREAM_BATCH_LIMIT) len = STREAM_BATCH_LIMIT;
        Pool storage pool = pools[matchId];
        for (uint256 i = 0; i < len; i++) {
            uint256 amount = amounts[i];
            if (amount == 0) continue;
            if (amount > pool.remainingValue) amount = pool.remainingValue;
            if (amount == 0) break;
            pool.remainingValue -= amount;
            totalPooled -= amount;
            (bool success, ) = payable(players[i]).call{value: amount}("");
            if (success) {
                emit MONStreamed(matchId, players[i], amount, pool.remainingValue);
            }
        }
    }

    function steal(bytes32 matchId, address newHolder) external onlyTrustedCaller {
        Pool storage pool = pools[matchId];
        if (pool.remainingValue == 0) revert PoolDepleted();
        uint256 gasCost = GAS_PER_STEAL;
        if (gasCost >= pool.remainingValue) {
            totalPooled -= pool.remainingValue;
            pool.remainingValue = 0;
            emit LootBoxStolen(matchId, newHolder, 0);
            return;
        }
        pool.remainingValue -= gasCost;
        totalPooled -= gasCost;
        pool.finalHolder = newHolder;
        emit LootBoxStolen(matchId, newHolder, pool.remainingValue);
    }

    function settle(bytes32 matchId, address finalHolder) external onlyMatchEngine {
        Pool storage pool = pools[matchId];
        if (pool.settled) revert AlreadySettled();
        uint256 payout = pool.remainingValue;
        pool.remainingValue = 0;
        pool.finalHolder = finalHolder;
        pool.settled = true;
        if (payout > 0) {
            totalPooled -= payout;
            (bool success, ) = payable(finalHolder).call{value: payout}("");
            require(success, "Transfer failed");
        }
        emit PoolSettled(matchId, finalHolder, payout);
    }

    function drainPool(bytes32 matchId, address to) external onlyMatchEngine {
        Pool storage pool = pools[matchId];
        uint256 amount = pool.remainingValue;
        pool.remainingValue = 0;
        pool.settled = true;
        if (amount > 0) {
            totalPooled -= amount;
            (bool success, ) = payable(to).call{value: amount}("");
            require(success, "Transfer failed");
        }
        emit PoolDrained(matchId, to, amount);
    }

    function getPoolValue(bytes32 matchId) external view returns (uint256) {
        return pools[matchId].remainingValue;
    }

    /// Withdraws only the balance that is not backing an unsettled pool.
    function withdrawSurplus() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance <= totalPooled) revert NothingToWithdraw();
        (bool success, ) = payable(owner()).call{value: balance - totalPooled}("");
        require(success, "Transfer failed");
    }

    receive() external payable {}
}
