// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract WONsBridge is Ownable, ReentrancyGuard {
    error InsufficientBalance();
    error ExceedsDailyLimit();
    error WithdrawalPaused();

    uint256 public constant WITHDRAWAL_DELAY = 1 days;
    uint256 public constant MAX_DAILY_WITHDRAWAL = 50 ether;

    mapping(address => uint256) public realBalance;
    mapping(address => uint256) public testnetBalance;
    mapping(address => uint256) public lastWithdrawalTime;
    mapping(address => uint256) public withdrawnToday;

    bool public paused;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event TestnetCredited(address indexed user, uint256 amount);
    event Paused(bool paused);

    constructor(address initialOwner) Ownable(initialOwner) {}

    modifier notPaused() {
        require(!paused, "Bridge paused");
        _;
    }

    function deposit() external payable notPaused nonReentrant {
        require(msg.value > 0, "Must deposit MON");

        realBalance[msg.sender] += msg.value;
        testnetBalance[msg.sender] += msg.value;

        emit Deposited(msg.sender, msg.value);
        emit TestnetCredited(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external notPaused nonReentrant {
        if (testnetBalance[msg.sender] < amount) revert InsufficientBalance();
        if (amount > MAX_DAILY_WITHDRAWAL) revert ExceedsDailyLimit();

        uint256 today = block.timestamp / WITHDRAWAL_DELAY;
        if (lastWithdrawalTime[msg.sender] < today) {
            withdrawnToday[msg.sender] = 0;
            lastWithdrawalTime[msg.sender] = today;
        }

        if (withdrawnToday[msg.sender] + amount > MAX_DAILY_WITHDRAWAL) revert ExceedsDailyLimit();

        testnetBalance[msg.sender] -= amount;
        realBalance[msg.sender] -= amount;
        withdrawnToday[msg.sender] += amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    function spendTestnet(address user, uint256 amount) external onlyOwner {
        require(testnetBalance[user] >= amount, "Insufficient testnet balance");
        testnetBalance[user] -= amount;
    }

    function creditTestnet(address user, uint256 amount) external onlyOwner {
        testnetBalance[user] += amount;
        emit TestnetCredited(user, amount);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    receive() external payable {}
}
