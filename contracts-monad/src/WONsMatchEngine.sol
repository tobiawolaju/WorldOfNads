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
    /// A match that is never settled can be refunded to its sponsor once this
    /// window (measured from the start time) has passed. Without it, a server
    /// that dies mid-match locks the prize forever.
    uint64 public constant SETTLE_WINDOW = 6 hours;
    /// A split round pays at most this many winners (holder + progress leader).
    uint256 public constant MAX_WINNERS = 8;

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
    error MatchNotStarted();
    error SettleDeadlineNotReached();
    error InvalidWinners();
    error InvalidShareTotal();
    error NothingToWithdraw();

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
    /// When an unsettled match becomes refundable (start time + SETTLE_WINDOW).
    mapping(bytes32 => uint64) public settleDeadlineOf;
    /// Prize money still owed to open matches, per currency (address(0) = MON).
    /// `withdrawSurplus` can only ever take balance above this, so escrow can
    /// never be swept out from under a match again.
    mapping(address => uint256) public totalEscrowed;

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
    event WinnerPaid(bytes32 indexed matchId, address indexed winner, uint256 amount, uint16 shareBps);
    event MatchSettledSplit(bytes32 indexed matchId, uint256 winnerPrize, uint256 participantCount, uint256 winnerCount);

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

        settleDeadlineOf[matchId] = startTime + SETTLE_WINDOW;
        totalEscrowed[prizeToken] += winnerPrize;

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
        if (block.timestamp < matchConfig.startTime) revert MatchNotStarted();
        if (winner == address(0)) revert InvalidWinner();
        _validateParticipants(participants);

        bool winnerFound = false;

        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i] == winner) {
                winnerFound = true;
            } else {
                _mint(participants[i], matchConfig.participationTokenId, 1, "");
                emit ParticipationMinted(matchId, participants[i], matchConfig.participationTokenId);
            }
        }

        if (!winnerFound) revert InvalidWinner();

        matchConfig.settled = true;
        matchConfig.settledAt = uint64(block.timestamp);

        _mint(winner, matchConfig.winnerTokenId, 1, "");

        uint256 winnerPayout = matchConfig.winnerPrize;
        totalEscrowed[matchConfig.prizeToken] -= winnerPayout;

        _pay(matchConfig.prizeToken, winner, winnerPayout);

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

    /**
     * Settles a round whose prize is shared between several winners.
     *
     * The game's rule is: the chicken holder and the progress leader split the
     * winner pool in proportion to their possession time. The plain `settleMatch`
     * can only pay one address, so a split round used to be recorded off-chain
     * and never paid. `sharesBps` must add up to 10000 (100%).
     */
    function settleMatchSplit(
        bytes32 matchId,
        address[] calldata winners,
        uint16[] calldata sharesBps,
        address[] calldata participants,
        address lootBoxFinalHolder
    ) external onlyTrustedAuthority nonReentrant {
        MatchConfig storage matchConfig = matchesById[matchId];
        if (matchConfig.createdAt == 0) revert MatchNotFound();
        if (matchConfig.cancelled) revert MatchAlreadyCancelled();
        if (matchConfig.settled) revert MatchAlreadySettled();
        if (block.timestamp < matchConfig.startTime) revert MatchNotStarted();
        if (winners.length == 0 || winners.length > MAX_WINNERS) revert InvalidWinners();
        if (winners.length != sharesBps.length) revert InvalidWinners();
        _validateParticipants(participants);

        uint256 totalBps;
        uint256 winnersFound;
        for (uint256 i = 0; i < winners.length; i++) {
            if (winners[i] == address(0)) revert InvalidWinner();
            for (uint256 j = i + 1; j < winners.length; j++) {
                if (winners[i] == winners[j]) revert InvalidWinner();
            }
            totalBps += sharesBps[i];

            for (uint256 k = 0; k < participants.length; k++) {
                if (participants[k] == winners[i]) {
                    winnersFound += 1;
                    break;
                }
            }
        }
        if (totalBps != 10000) revert InvalidShareTotal();
        if (winnersFound != winners.length) revert InvalidWinner();

        for (uint256 i = 0; i < participants.length; i++) {
            if (_isWinner(winners, participants[i])) continue;
            _mint(participants[i], matchConfig.participationTokenId, 1, "");
            emit ParticipationMinted(matchId, participants[i], matchConfig.participationTokenId);
        }

        matchConfig.settled = true;
        matchConfig.settledAt = uint64(block.timestamp);

        uint256 winnerPrize = matchConfig.winnerPrize;
        totalEscrowed[matchConfig.prizeToken] -= winnerPrize;

        uint256 distributed;
        for (uint256 i = 0; i < winners.length; i++) {
            uint256 amount = (winnerPrize * sharesBps[i]) / 10000;
            distributed += amount;
            _mint(winners[i], matchConfig.winnerTokenId, 1, "");
            _pay(matchConfig.prizeToken, winners[i], amount);
            emit WinnerPaid(matchId, winners[i], amount, sharesBps[i]);
        }

        // Integer division can leave a few wei behind: give the dust to the
        // first winner instead of stranding it in the contract.
        if (distributed < winnerPrize) {
            _pay(matchConfig.prizeToken, winners[0], winnerPrize - distributed);
        }

        ILootBox(lootBox).settle(matchId, lootBoxFinalHolder);

        emit MatchSettledSplit(matchId, winnerPrize, participants.length, winners.length);
    }

    function cancelSponsoredMatch(bytes32 matchId) external nonReentrant {
        MatchConfig storage matchConfig = matchesById[matchId];
        if (matchConfig.createdAt == 0) revert MatchNotFound();
        if (matchConfig.sponsor != msg.sender) revert SponsorMismatch();
        if (matchConfig.settled) revert MatchAlreadySettled();
        if (matchConfig.cancelled) revert MatchAlreadyCancelled();
        if (block.timestamp >= matchConfig.startTime) revert MatchAlreadySettled();

        _refund(matchId, matchConfig);
    }

    /**
     * Reclaims the prize of a match that was never settled.
     *
     * Anyone may call this once `SETTLE_WINDOW` has passed since the start time.
     * Without it a crashed room server would lock the sponsor's prize forever.
     * The refund always goes to the sponsor, so calling it is not profitable.
     */
    function refundExpired(bytes32 matchId) external nonReentrant {
        MatchConfig storage matchConfig = matchesById[matchId];
        if (matchConfig.createdAt == 0) revert MatchNotFound();
        if (matchConfig.settled) revert MatchAlreadySettled();
        if (matchConfig.cancelled) revert MatchAlreadyCancelled();

        uint64 deadline = settleDeadlineOf[matchId];
        if (deadline == 0 || block.timestamp <= deadline) revert SettleDeadlineNotReached();

        _refund(matchId, matchConfig);
    }

    function getMatch(bytes32 matchId) external view returns (MatchConfig memory) {
        return matchesById[matchId];
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return tokenURIs[tokenId];
    }

    /**
     * Withdraws only the balance that is not backing an open match.
     *
     * The old `withdraw()` drained the whole contract, which is how the live
     * escrow ended up 9 MON short. This can never touch `totalEscrowed`.
     */
    function withdrawSurplus(address token) external onlyOwner nonReentrant {
        uint256 balance = token == address(0)
            ? address(this).balance
            : IERC20(token).balanceOf(address(this));
        uint256 escrowed = totalEscrowed[token];
        if (balance <= escrowed) revert NothingToWithdraw();

        _pay(token, owner(), balance - escrowed);
    }

    receive() external payable {}

    // -- internal helpers ---------------------------------------------------

    function _refund(bytes32 matchId, MatchConfig storage matchConfig) internal {
        matchConfig.cancelled = true;

        uint256 refundAmount = matchConfig.winnerPrize;
        totalEscrowed[matchConfig.prizeToken] -= refundAmount;

        _pay(matchConfig.prizeToken, matchConfig.sponsor, refundAmount);
        ILootBox(lootBox).drainPool(matchId, matchConfig.sponsor);

        emit MatchCancelled(matchId, matchConfig.sponsor, refundAmount + matchConfig.lootBoxPool);
    }

    function _pay(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (token == address(0)) {
            (bool success, ) = payable(to).call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function _validateParticipants(address[] calldata participants) internal pure {
        if (participants.length == 0 || participants.length > MAX_PARTICIPANTS) {
            revert InvalidParticipantCount();
        }
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i] == address(0)) revert InvalidParticipant();
            for (uint256 j = i + 1; j < participants.length; j++) {
                if (participants[i] == participants[j]) revert DuplicateParticipant();
            }
        }
    }

    function _isWinner(address[] calldata winners, address account) internal pure returns (bool) {
        for (uint256 i = 0; i < winners.length; i++) {
            if (winners[i] == account) return true;
        }
        return false;
    }
}
