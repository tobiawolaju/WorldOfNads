// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title WONSponsorClickMock
/// @notice Temporary contract for sponsor dashboard payment clicks before escrow deployment.
contract WONSponsorClickMock {
    event MatchClicked(bytes32 indexed matchId, address indexed sender, uint256 amount);

    function clickCreateMatch(bytes32 matchId) external payable {
        require(msg.value > 0, "value required");
        emit MatchClicked(matchId, msg.sender, msg.value);
    }
}
