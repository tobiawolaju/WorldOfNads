// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WONsXP is ERC20, Ownable {
    error TransferNotAllowed();
    error NotAuthorized();

    mapping(address => bool) public minters;

    event MinterUpdated(address indexed minter, bool active);

    modifier onlyMinter() {
        if (!minters[msg.sender]) revert NotAuthorized();
        _;
    }

    constructor(address initialOwner) ERC20("World of Nads XP", "WXP") Ownable(initialOwner) {}

    function setMinter(address minter, bool active) external onlyOwner {
        minters[minter] = active;
        emit MinterUpdated(minter, active);
    }

    function mintXP(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) revert TransferNotAllowed();
        super._update(from, to, value);
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(owner()).call{value: balance}("");
            require(success, "Transfer failed");
        }
    }
}
