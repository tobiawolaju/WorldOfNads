// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

interface ILootBox {
    function fundPool(bytes32 matchId, uint256 amount) external payable;
    function settle(bytes32 matchId, address finalHolder) external;
    function drainPool(bytes32 matchId, address to) external;
}

interface IXP {
    function mintXP(address to, uint256 amount) external;
}

contract WONsMatchEngine is ERC1155, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_PARTICIPANTS = 64;
    uint256 public constant WINNER_SHARE_BPS = 8000;
    uint256 public constant LOOTBOX_SHARE_BPS = 2000;
    uint256 public constant FEE_BPS = 1000;

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
    error SponsorMismatch();
    error NotEnoughForLootBox();
    error ShareMismatch();
    error MainWalletNotSet();

    struct MatchConfig {
        address sponsor;
        address prizeToken;
        uint256 winnerPrize;
        uint256 lootBoxPool;
        uint256 winnerTokenId;
        uint256 participationTokenId;
        uint32 expectedParticipants;
        uint64 createdAt;
        uint64 startTime;
        uint64 settledAt;
        bool settled;
        bool cancelled;
        string matchMetadataURI;
    }

    address public trustedAuthority;
    address public lootBox;
    address public xpToken;
    address public mainWallet;
    uint256 public nextTokenId = 1;

    mapping(bytes32 => MatchConfig) public matchesById;
    mapping(uint256 => string) private tokenURIs;

    event TrustedAuthorityUpdated(address indexed previousAuthority, address indexed newAuthority);
    event MatchCreated(
        bytes32 indexed matchId,
        address indexed sponsor,
        address indexed prizeToken,
        uint256 totalPrize,
        uint256 winnerPrize,
        uint256 lootBoxPool,
        uint256 winnerTokenId,
        uint256 participationTokenId,
        uint32 expectedParticipants,
        uint64 startTime,
        string matchMetadataURI
    );
    event MatchCancelled(bytes32 indexed matchId, address indexed sponsor, uint256 amountReturned);
    event MatchSettled(
        bytes32 indexed matchId,
        address indexed winner,
        address indexed prizeToken,
        uint256 winnerPrize,
        uint256 participantCount,
        bytes32 participantsHash
    );
    event ParticipationMinted(bytes32 indexed matchId, address indexed participant, uint256 indexed tokenId);
    event LootBoxContractUpdated(address indexed lootBox);
    event XPTokenUpdated(address indexed xpToken);
    event MainWalletUpdated(address indexed previousWallet, address indexed newWallet);

    modifier onlyTrustedAuthority() {
        if (msg.sender != trustedAuthority) revert InvalidAuthority();
        _;
    }

    constructor(
        address initialOwner,
        address initialTrustedAuthority,
        address _lootBox,
        address _xpToken,
        address _mainWallet
    ) ERC1155("") Ownable(initialOwner) {
        if (initialTrustedAuthority == address(0)) revert InvalidAuthority();
        if (_mainWallet == address(0)) revert MainWalletNotSet();
        trustedAuthority = initialTrustedAuthority;
        lootBox = _lootBox;
        xpToken = _xpToken;
        mainWallet = _mainWallet;
        emit TrustedAuthorityUpdated(address(0), initialTrustedAuthority);
        emit MainWalletUpdated(address(0), _mainWallet);
    }

    function setTrustedAuthority(address newAuthority) external onlyOwner {
        if (newAuthority == address(0)) revert InvalidAuthority();
        address previousAuthority = trustedAuthority;
        trustedAuthority = newAuthority;
        emit TrustedAuthorityUpdated(previousAuthority, newAuthority);
    }

    function setLootBox(address _lootBox) external onlyOwner {
        lootBox = _lootBox;
        emit LootBoxContractUpdated(_lootBox);
    }

    function setXPToken(address _xpToken) external onlyOwner {
        xpToken = _xpToken;
        emit XPTokenUpdated(_xpToken);
    }

    function setMainWallet(address _mainWallet) external onlyOwner {
        if (_mainWallet == address(0)) revert MainWalletNotSet();
        address previousWallet = mainWallet;
        mainWallet = _mainWallet;
        emit MainWalletUpdated(previousWallet, _mainWallet);
    }

    function createSponsoredMatch(
        bytes32 matchId,
        address prizeToken,
        uint256 totalPrize,
        uint32 expectedParticipants,
        uint64 startTime,
        string calldata winnerTokenURI,
        string calldata participationTokenURI,
        string calldata matchMetadataURI
    ) external payable nonReentrant {
        if (matchesById[matchId].createdAt != 0) revert MatchAlreadyExists();
        if (totalPrize == 0) revert PrizeAmountMustBePositive();

        if (prizeToken == address(0)) {
            if (msg.value != totalPrize) revert PrizeAmountMustBePositive();
        } else {
            if (msg.value > 0) revert InvalidPrizeToken();
            IERC20(prizeToken).safeTransferFrom(msg.sender, address(this), totalPrize);
        }

        uint256 mainWalletFee = (totalPrize * FEE_BPS) / 10000;
        uint256 netPrize = totalPrize - mainWalletFee;

        if (mainWalletFee > 0) {
            if (prizeToken == address(0)) {
                (bool feeSuccess, ) = payable(mainWallet).call{value: mainWalletFee}("");
                require(feeSuccess, "Fee transfer failed");
            } else {
                IERC20(prizeToken).safeTransfer(mainWallet, mainWalletFee);
            }
        }

        uint256 winnerPrize = (netPrize * WINNER_SHARE_BPS) / 10000;
        uint256 lootBoxPool = netPrize - winnerPrize;

        uint256 winnerTokenId = nextTokenId++;
        uint256 participationTokenId = nextTokenId++;

        tokenURIs[winnerTokenId] = winnerTokenURI;
        tokenURIs[participationTokenId] = participationTokenURI;

        matchesById[matchId] = MatchConfig({
            sponsor: msg.sender,
            prizeToken: prizeToken,
            winnerPrize: winnerPrize,
            lootBoxPool: lootBoxPool,
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

        if (lootBoxPool > 0) {
            ILootBox(lootBox).fundPool{value: lootBoxPool}(matchId, lootBoxPool);
        }

        emit MatchCreated(
            matchId,
            msg.sender,
            prizeToken,
            totalPrize,
            winnerPrize,
            lootBoxPool,
            winnerTokenId,
            participationTokenId,
            expectedParticipants,
            startTime,
            matchMetadataURI
        );
    }

    function settleMatch(
        bytes32 matchId,
        address winner,
        address[] calldata participants,
        address lootBoxFinalHolder,
        uint256 gasCompensation
    ) external onlyTrustedAuthority nonReentrant {
        MatchConfig storage matchConfig = matchesById[matchId];
        if (matchConfig.createdAt == 0) revert MatchNotFound();
        if (matchConfig.cancelled) revert MatchAlreadyCancelled();
        if (matchConfig.settled) revert MatchAlreadySettled();
        if (winner == address(0)) revert InvalidWinner();
        if (participants.length == 0 || participants.length > MAX_PARTICIPANTS) revert InvalidParticipantCount();

        bool winnerFound = false;

        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            if (participant == address(0)) revert InvalidParticipant();

            for (uint256 j = i + 1; j < participants.length; j++) {
                if (participant == participants[j]) revert DuplicateParticipant();
            }

            if (participant == winner) {
                winnerFound = true;
            } else {
                _mint(participant, matchConfig.participationTokenId, 1, "");
                emit ParticipationMinted(matchId, participant, matchConfig.participationTokenId);
            }
        }

        if (!winnerFound) revert InvalidWinner();

        matchConfig.settled = true;
        matchConfig.settledAt = uint64(block.timestamp);

        _mint(winner, matchConfig.winnerTokenId, 1, "");

        uint256 winnerPayout = matchConfig.winnerPrize;

        if (matchConfig.prizeToken == address(0)) {
            (bool success, ) = payable(winner).call{value: winnerPayout}("");
            require(success, "Transfer failed");
        } else {
            IERC20(matchConfig.prizeToken).safeTransfer(winner, winnerPayout);
        }

        ILootBox(lootBox).settle(matchId, lootBoxFinalHolder);

        emit MatchSettled(
            matchId,
            winner,
            matchConfig.prizeToken,
            winnerPayout,
            participants.length,
            keccak256(abi.encode(participants))
        );
    }

    function cancelSponsoredMatch(bytes32 matchId) external nonReentrant {
        MatchConfig storage matchConfig = matchesById[matchId];
        if (matchConfig.createdAt == 0) revert MatchNotFound();
        if (matchConfig.sponsor != msg.sender) revert SponsorMismatch();
        if (matchConfig.settled) revert MatchAlreadySettled();
        if (matchConfig.cancelled) revert MatchAlreadyCancelled();
        if (block.timestamp >= matchConfig.startTime) revert MatchAlreadySettled();

        matchConfig.cancelled = true;

        uint256 refundAmount = matchConfig.winnerPrize;
        if (matchConfig.prizeToken == address(0)) {
            (bool success, ) = payable(matchConfig.sponsor).call{value: refundAmount}("");
            require(success, "Transfer failed");
        } else {
            IERC20(matchConfig.prizeToken).safeTransfer(matchConfig.sponsor, refundAmount);
        }

        ILootBox(lootBox).drainPool(matchId, matchConfig.sponsor);

        emit MatchCancelled(matchId, msg.sender, matchConfig.winnerPrize + matchConfig.lootBoxPool);
    }

    function getMatch(bytes32 matchId) external view returns (MatchConfig memory) {
        return matchesById[matchId];
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return tokenURIs[tokenId];
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(owner()).call{value: balance}("");
            require(success, "Transfer failed");
        }
    }

    receive() external payable {}
}
