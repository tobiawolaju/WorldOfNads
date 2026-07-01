// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

contract WONsRegistry is Ownable {
    error RelayAlreadyRegistered();
    error RelayNotFound();
    error InvalidAddress();

    struct Relay {
        string wsUrl;
        bytes32 codeHash;
        bool active;
        uint256 registeredAt;
        uint256 lastHeartbeat;
    }

    string public frontendIpfsHash;
    address[] public relayAddresses;
    mapping(address => Relay) public relays;
    mapping(address => uint256) public relayIndex;

    event RelayRegistered(address indexed relay, string wsUrl, bytes32 codeHash);
    event RelayDeactivated(address indexed relay);
    event FrontendUpdated(string ipfsHash);

    constructor(address initialOwner, string memory initialIpfsHash) Ownable(initialOwner) {
        frontendIpfsHash = initialIpfsHash;
    }

    function registerRelay(string calldata wsUrl, bytes32 codeHash) external {
        if (relays[msg.sender].registeredAt != 0) revert RelayAlreadyRegistered();
        if (msg.sender == address(0)) revert InvalidAddress();
        require(bytes(wsUrl).length > 0, "URL required");

        relays[msg.sender] = Relay({
            wsUrl: wsUrl,
            codeHash: codeHash,
            active: true,
            registeredAt: block.timestamp,
            lastHeartbeat: block.timestamp
        });

        relayIndex[msg.sender] = relayAddresses.length;
        relayAddresses.push(msg.sender);

        emit RelayRegistered(msg.sender, wsUrl, codeHash);
    }

    function heartbeat() external {
        Relay storage relay = relays[msg.sender];
        if (relay.registeredAt == 0) revert RelayNotFound();
        relay.lastHeartbeat = block.timestamp;
        relay.active = true;
    }

    function deactivateRelay(address relayAddress) external onlyOwner {
        Relay storage relay = relays[relayAddress];
        if (relay.registeredAt == 0) revert RelayNotFound();
        relay.active = false;
        emit RelayDeactivated(relayAddress);
    }

    function updateFrontend(string calldata ipfsHash) external onlyOwner {
        frontendIpfsHash = ipfsHash;
        emit FrontendUpdated(ipfsHash);
    }

    function getActiveRelays() external view returns (address[] memory) {
        uint256 count;
        for (uint256 i = 0; i < relayAddresses.length; i++) {
            if (relays[relayAddresses[i]].active) count++;
        }

        address[] memory active = new address[](count);
        uint256 idx;
        for (uint256 i = 0; i < relayAddresses.length; i++) {
            if (relays[relayAddresses[i]].active) {
                active[idx] = relayAddresses[i];
                idx++;
            }
        }

        return active;
    }

    function getRelayCount() external view returns (uint256) {
        return relayAddresses.length;
    }
}
