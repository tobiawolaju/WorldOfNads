// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract WONsRewards is Ownable, ReentrancyGuard {
    error NoRewardsToClaim();
    error InsufficientFunds();
    error InvalidPlayer();

    mapping(address => uint256) public pendingRewards;
    mapping(address => uint256) public claimedRewards;
    mapping(bytes32 => bool) public batchCommitted;

    uint256 public totalRewardsDistributed;

    event RewardsAccrued(address indexed player, uint256 amount, bytes32 indexed batchId);
    event RewardsClaimed(address indexed player, uint256 amount);
    event BatchCommitted(bytes32 indexed batchId, uint256 totalAmount);
    event FundsDeposited(uint256 amount);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function commitBatch(
        bytes32 batchId,
        address[] calldata players,
        uint256[] calldata amounts
    ) external onlyOwner {
        require(players.length == amounts.length, "Length mismatch");
        require(!batchCommitted[batchId], "Batch already committed");

        batchCommitted[batchId] = true;

        uint256 total;
        for (uint256 i = 0; i < players.length; i++) {
            require(players[i] != address(0), "Invalid player");
            require(amounts[i] > 0, "Zero reward");
            pendingRewards[players[i]] += amounts[i];
            total += amounts[i];
        }

        emit BatchCommitted(batchId, total);
    }

    function claim() external nonReentrant {
        uint256 amount = pendingRewards[msg.sender];
        if (amount == 0) revert NoRewardsToClaim();

        pendingRewards[msg.sender] = 0;
        claimedRewards[msg.sender] += amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");

        totalRewardsDistributed += amount;
        emit RewardsClaimed(msg.sender, amount);
    }

    function getPendingReward(address player) external view returns (uint256) {
        return pendingRewards[player];
    }

    function getTotalClaimed(address player) external view returns (uint256) {
        return claimedRewards[player];
    }

    receive() external payable {}
}
