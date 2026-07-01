// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/// @title WONSponsorArenaEscrow
/// @notice Sponsor-funded escrow for WONs matches with backend-authorized settlement.
/// @dev The game server is the trusted authority for winner selection in this MVP.
contract WONSponsorArenaEscrow is ERC1155, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_PARTICIPANTS = 64;

    error InvalidAuthority();
    error MatchAlreadyExists();
    error MatchNotFound();
    error MatchAlreadySettled();
    error MatchAlreadyCancelled();
    error PrizeAmountMustBePositive();
    error InvalidPrizeToken();
    error InvalidWinner();
    error InvalidParticipantCount();
    error DuplicateParticipant();
    error InvalidParticipant();
    error UnauthorizedAuthority();
    error SponsorMismatch();

    struct MatchConfig {
        address sponsor;
        address prizeToken;
        uint256 firstPlacePrize;
        uint256 winnerTokenId;
        uint256 participationTokenId;
        uint32 expectedParticipants;
        uint64 createdAt; // timestamp match was created
        uint64 startTime; // timestamp match is scheduled to start
        uint64 settledAt;
        bool settled;
        bool cancelled;
        string matchMetadataURI;
    }

    address public trustedAuthority;
    uint256 public nextTokenId = 1;

    mapping(bytes32 => MatchConfig) public matchesById;
    mapping(uint256 => string) private tokenURIs;

    event TrustedAuthorityUpdated(address indexed previousAuthority, address indexed newAuthority);
    event MatchCreated(
        bytes32 indexed matchId,
        address indexed sponsor,
        address indexed prizeToken,
        uint256 firstPlacePrize,
        uint256 winnerTokenId,
        uint256 participationTokenId,
        uint32 expectedParticipants,
        uint256 startTime,
        string matchMetadataURI
    );
    event MatchCancelled(bytes32 indexed matchId, address indexed sponsor, uint256 amountReturned);
    event MatchSettled(
        bytes32 indexed matchId,
        address indexed winner,
        address indexed prizeToken,
        uint256 firstPlacePrize,
        uint256 participantCount,
        bytes32 participantsHash
    );
    event ParticipationMinted(bytes32 indexed matchId, address indexed participant, uint256 indexed tokenId);

    modifier onlyTrustedAuthority() {
        if (msg.sender != trustedAuthority) {
            revert UnauthorizedAuthority();
        }
        _;
    }

    constructor(address initialOwner, address initialTrustedAuthority) ERC1155("") Ownable(initialOwner) {
        if (initialTrustedAuthority == address(0)) {
            revert InvalidAuthority();
        }
        trustedAuthority = initialTrustedAuthority;
        emit TrustedAuthorityUpdated(address(0), initialTrustedAuthority);
    }

    function createSponsoredMatch(
        bytes32 matchId,
        address prizeToken,
        uint256 firstPlacePrize,
        uint32 expectedParticipants,
        uint64 startTime,
        string calldata winnerTokenURI,
        string calldata participationTokenURI,
        string calldata matchMetadataURI
    ) external payable nonReentrant {
        if (matchesById[matchId].createdAt != 0) {
            revert MatchAlreadyExists();
        }
        if (firstPlacePrize == 0) {
            revert PrizeAmountMustBePositive();
        }

        // Handle native MON vs ERC20
        if (prizeToken == address(0)) {
            if (msg.value != firstPlacePrize) {
                revert PrizeAmountMustBePositive(); // Inaccurate error but reusing for simplicity
            }
        } else {
            if (msg.value > 0) {
                revert InvalidPrizeToken(); // Should not send ETH for ERC20 prize
            }
            IERC20(prizeToken).safeTransferFrom(msg.sender, address(this), firstPlacePrize);
        }

        uint256 winnerTokenId = nextTokenId++;
        uint256 participationTokenId = nextTokenId++;

        tokenURIs[winnerTokenId] = winnerTokenURI;
        tokenURIs[participationTokenId] = participationTokenURI;

        matchesById[matchId] = MatchConfig({
            sponsor: msg.sender,
            prizeToken: prizeToken,
            firstPlacePrize: firstPlacePrize,
            winnerTokenId: winnerTokenId,
            participationTokenId: participationTokenId,
            expectedParticipants: expectedParticipants,
            createdAt: uint64(block.timestamp),
            startTime: startTime,
            settledAt: 0,
            settled: false,
            cancelled: false,
            matchMetadataURI: matchMetadataURI
        });

        emit MatchCreated(
            matchId,
            msg.sender,
            prizeToken,
            firstPlacePrize,
            winnerTokenId,
            participationTokenId,
            expectedParticipants,
            startTime,
            matchMetadataURI
        );
    }

    function cancelSponsoredMatch(bytes32 matchId) external nonReentrant {
        MatchConfig storage matchConfig = matchesById[matchId];
        if (matchConfig.createdAt == 0) {
            revert MatchNotFound();
        }
        if (matchConfig.sponsor != msg.sender) {
            revert SponsorMismatch();
        }
        if (matchConfig.settled) {
            revert MatchAlreadySettled();
        }
        if (matchConfig.cancelled) {
            revert MatchAlreadyCancelled();
        }
        if (block.timestamp >= matchConfig.startTime) {
            revert MatchAlreadySettled(); // Match started, too late to cancel
        }

        matchConfig.cancelled = true;
        
        uint256 refundAmount = matchConfig.firstPlacePrize;
        if (matchConfig.prizeToken == address(0)) {
            (bool success, ) = payable(matchConfig.sponsor).call{value: refundAmount}("");
            require(success, "Transfer failed");
        } else {
            IERC20(matchConfig.prizeToken).safeTransfer(matchConfig.sponsor, refundAmount);
        }

        emit MatchCancelled(matchId, msg.sender, refundAmount);
    }

    function settleMatch(
        bytes32 matchId,
        address winner,
        address[] calldata participants
    ) external onlyTrustedAuthority nonReentrant {
        MatchConfig storage matchConfig = matchesById[matchId];
        if (matchConfig.createdAt == 0) {
            revert MatchNotFound();
        }
        if (matchConfig.cancelled) {
            revert MatchAlreadyCancelled();
        }
        if (matchConfig.settled) {
            revert MatchAlreadySettled();
        }
        if (winner == address(0)) {
            revert InvalidWinner();
        }
        if (participants.length == 0 || participants.length > MAX_PARTICIPANTS) {
            revert InvalidParticipantCount();
        }

        bool winnerFound = false;

        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            if (participant == address(0)) {
                revert InvalidParticipant();
            }

            for (uint256 j = i + 1; j < participants.length; j++) {
                if (participant == participants[j]) {
                    revert DuplicateParticipant();
                }
            }

            if (participant == winner) {
                winnerFound = true;
            } else {
                _mint(participant, matchConfig.participationTokenId, 1, "");
                emit ParticipationMinted(matchId, participant, matchConfig.participationTokenId);
            }
        }

        if (!winnerFound) {
            revert InvalidWinner();
        }

        matchConfig.settled = true;
        matchConfig.settledAt = uint64(block.timestamp);

        _mint(winner, matchConfig.winnerTokenId, 1, "");
        
        if (matchConfig.prizeToken == address(0)) {
            (bool success, ) = payable(winner).call{value: matchConfig.firstPlacePrize}("");
            require(success, "Transfer failed");
        } else {
            IERC20(matchConfig.prizeToken).safeTransfer(winner, matchConfig.firstPlacePrize);
        }

        emit MatchSettled(
            matchId,
            winner,
            matchConfig.prizeToken,
            matchConfig.firstPlacePrize,
            participants.length,
            keccak256(abi.encode(participants))
        );
    }

    function setTrustedAuthority(address newAuthority) external onlyOwner {
        if (newAuthority == address(0)) {
            revert InvalidAuthority();
        }

        address previousAuthority = trustedAuthority;
        trustedAuthority = newAuthority;
        emit TrustedAuthorityUpdated(previousAuthority, newAuthority);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return tokenURIs[tokenId];
    }
}
