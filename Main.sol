// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./Owner.sol";
import "./Guard.sol";
import "./ArrayLib.sol";

contract Main is Owner, Guard {
    enum StatusMatch {
        NONE,
        INITIALIZED,
        STARTED,
        FINISHED,
        FORCECLOSE,
        MATCHCLOSED
    }

    event MatchCreated(
        bytes32 indexed hashMatch,
        address indexed owner,
        uint256 indexed maxPlayers,
        uint256 bet,
        string title,
        uint256 startMatch,
        uint256 finishMatch,
        uint256[] symbols
    );
    event PlayerJoined(
        bytes32 indexed hashMatch,
        address indexed player,
        uint256 bet
    );
    event MatchFinished(
        bytes32 indexed hashMatch,
        address indexed winner,
        uint256 betPot
    );
    event LeaveMatch(
        bytes32 indexed hashMatch,
        address indexed player,
        uint256 payout,
        uint256 playerRemaining
    );
    event ChangeMatchStatus(bytes32 indexed hashMatch, StatusMatch status);
    event Withdrawal(bytes32 indexed hashMatch, address player, uint256 payout);
    using ArrayAddressLib for address[];

    struct Match {
        string title;
        address owner;
        StatusMatch status;
        uint256 startBet;
        uint256 startMatch;
        uint256 finishMatch;
        uint256 betPot;
        uint256 playerCount;
        uint256 maxPlayers;
        address[] players;
    }

    mapping(bytes32 => Match) private matchData;
    mapping(address => uint256) private balance;
    uint256 private ownerBalance;

    constructor() {}

    receive() external payable {}

    function createMatch(
        string calldata title,
        uint256 _maxPlayers,
        uint256 _startMatch,
        uint256 _finishMatch,
        uint256[] memory symbols
    ) external payable returns (bytes32 matchHash) {
        require(msg.value > 0, "No ether sent");
        matchHash = keccak256(
            abi.encodePacked(
                msg.sender,
                block.timestamp,
                blockhash(block.number - 1)
            )
        );
        Match storage matchInfo = matchData[matchHash];
        require(matchInfo.status == StatusMatch.NONE, "Match already exists");

        balance[msg.sender] += msg.value;

        matchInfo.title = title;
        matchInfo.owner = msg.sender;
        matchInfo.status = StatusMatch.INITIALIZED;
        matchInfo.startBet = msg.value;
        matchInfo.startMatch = _startMatch;
        matchInfo.finishMatch = _finishMatch;
        matchInfo.betPot = msg.value;
        matchInfo.maxPlayers = _maxPlayers;
        matchInfo.players.push(msg.sender);
        matchInfo.playerCount++;

        emit MatchCreated(
            matchHash,
            msg.sender,
            _maxPlayers,
            msg.value,
            title,
            _startMatch,
            _finishMatch,
            symbols
        );
    }

    function joinMatch(bytes32 _matchHash)
        external
        payable
        returns (bool started)
    {
        require(msg.value > 0, "No ether sent");
        Match storage matchInfo = matchData[_matchHash];
        require(
            msg.value == matchInfo.startBet,
            "You have to bet the same amount as the initial bet"
        );
        require(!matchInfo.players.indexOf(msg.sender), "Already joined");
        require(
            matchInfo.status == StatusMatch.INITIALIZED,
            "The match is not waiting for new players"
        );
        require(
            matchInfo.finishMatch > block.timestamp &&
                matchInfo.owner != msg.sender &&
                matchInfo.status == StatusMatch.INITIALIZED &&
                matchInfo.playerCount < matchInfo.maxPlayers,
            "Invalid match join conditions"
        );

        matchInfo.players.push(msg.sender);
        matchInfo.betPot += msg.value;
        matchInfo.playerCount++;
        balance[msg.sender] += msg.value;

        if (matchInfo.playerCount >= matchInfo.maxPlayers) {
            emit ChangeMatchStatus(_matchHash, StatusMatch.STARTED);
            matchInfo.status = StatusMatch.STARTED;
            started = true;
        }

        emit PlayerJoined(_matchHash, msg.sender, msg.value);
    }

    function leaveMatch(bytes32 _matchHash) external {
        Match storage matchInfo = matchData[_matchHash];
        require(matchInfo.players.indexOf(msg.sender), "You're not in lobby");
        require(
            matchInfo.finishMatch > block.timestamp &&
                matchInfo.status == StatusMatch.INITIALIZED,
            "Invalid match leave conditions"
        );

        if (matchInfo.owner == msg.sender) {
            matchInfo.status = StatusMatch.MATCHCLOSED;
            emit ChangeMatchStatus(_matchHash, StatusMatch.MATCHCLOSED);
            
            uint256 tempBetPot = matchInfo.betPot;

            matchInfo.betPot = 0;
            for (uint256 i = 0; i < matchInfo.players.length; i++) {
                if (balance[matchInfo.players[i]] >= matchInfo.startBet) {
                    if (tempBetPot >= matchInfo.startBet) {
                        balance[matchInfo.players[i]] -= matchInfo.startBet;

                        uint256 payout = (matchInfo.startBet * (1000 - 5)) /
                            1000;

                        ownerBalance += matchInfo.startBet - payout;
                        payable(matchInfo.players[i]).transfer(payout);

                        emit Withdrawal(_matchHash, matchInfo.players[i], payout);

                    }
                }
            }
            
        } else {
            require(
                balance[msg.sender] >= matchInfo.startBet,
                "You don't have enough money loaded"
            );
            require(
                matchInfo.betPot >= matchInfo.startBet,
                "There is not enough money in the lobby"
            );

            uint256 indexToRemove;
            for (uint256 i = 0; i < matchInfo.players.length; i++) {
                if (matchInfo.players[i] == msg.sender) {
                    indexToRemove = i;
                    break;
                }
            }
            matchInfo.players[indexToRemove] = matchInfo.players[
                matchInfo.players.length - 1
            ];
            matchInfo.players.pop();

            balance[msg.sender] -= matchInfo.startBet;
            matchInfo.betPot -= matchInfo.startBet;
            
            uint256 payout = (matchInfo.startBet * (1000 - 5)) / 1000;

            emit LeaveMatch(_matchHash, msg.sender, payout, matchInfo.players.length);

            ownerBalance += matchInfo.startBet - payout;
            payable(msg.sender).transfer(payout);
            emit Withdrawal(_matchHash, msg.sender, payout);

        }
    }

    function finishMatch(
        bytes32 _matchHash,
        address payable _winner,
        uint256 percentFee
    ) external isOwner {
        Match storage matchInfo = matchData[_matchHash];
        require(
            _winner != address(0) &&
                matchInfo.status == StatusMatch.STARTED &&
                matchInfo.players.indexOf(_winner),
            "Invalid match finish conditions"
        );

        emit ChangeMatchStatus(_matchHash, StatusMatch.FINISHED);
        matchInfo.status = StatusMatch.FINISHED;

        for (uint256 i = 0; i < matchInfo.players.length; i++) {
            balance[matchInfo.players[i]] -= matchInfo.startBet;
        }
        uint256 payout = (matchInfo.betPot * (1000 - percentFee)) / 1000;

        ownerBalance += matchInfo.betPot - payout;

        _winner.transfer(payout);

        emit Withdrawal(_matchHash, _winner, payout);
        emit MatchFinished(_matchHash, _winner, payout);
    }

    function forceClose(
        bytes32 _matchHash,
        address payable _winner,
        uint256 percentFee
    ) external isOwner {
        Match storage matchInfo = matchData[_matchHash];
        require(
            _winner != address(0) && matchInfo.status == StatusMatch.STARTED,
            "Invalid match finish conditions"
        );
        emit ChangeMatchStatus(_matchHash, StatusMatch.FORCECLOSE);
        matchInfo.status = StatusMatch.FORCECLOSE;

        for (uint256 i = 0; i < matchInfo.players.length; i++) {
            balance[matchInfo.players[i]] -= matchInfo.startBet;
        }
        uint256 payout = (matchInfo.betPot * (1000 - percentFee)) / 1000;
        ownerBalance += matchInfo.betPot - payout;
        matchInfo.betPot = 0;
        _winner.transfer(payout);

        emit Withdrawal(_matchHash, _winner, payout);
        emit MatchFinished(_matchHash, _winner, payout);
    }

    function getMatchStatus(bytes32 _matchHash)
        public
        view
        returns (StatusMatch status)
    {
        return matchData[_matchHash].status;
    }

    function getInfoMatch(bytes32 _matchHash)
        public
        view
        returns (Match memory)
    {
        Match storage matchInfo = matchData[_matchHash];
        return matchInfo;
    }
}
