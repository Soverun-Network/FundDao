// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract FundDao is ERC20, Ownable, Pausable  {
    IERC20 public usdtToken;

    // Variables
    uint256 public maxTotalFunding;
    uint256 public maxParticipants;
    uint256 public maxParticipation;
    uint256 public totalFunding;
    uint256 public currentParticipants;
    address[] public participants;
    // Proposal Variables
    uint256 public proposalDuration = 7 days;
    uint256 public nextProposalId;

    bool public fundingStage = true;

    struct Proposal {
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 endTime;
        bool executed;
        // mapping(address => bool) hasVoted;
    }

    // Mappings
    mapping(address => uint256) public usdtBalances;
    mapping(address => uint256) public pendingUsdtShares;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;


    // Events for the funding stage
    event FundingStageParamsUpdated(uint256 maxTotalFunding, uint256 maxParticipants, uint256 maxParticipation);
    event Participation(address indexed user, uint256 usdtAmount, uint256 governanceTokens);
    event USDTWithdrawn(address indexed admin, uint256 amount);


    // Events for the distribution stage
    event FundingStageToggled(bool isFundingStage);
    event DistributionUpdated(uint256 totalUsdt);
    event USDTClaimed(address indexed user, uint256 amount);

    // Events for proposals
    event ProposalCreated(uint256 indexed proposalId, string description, uint256 endTime);
    event ProposalVoted(uint256 indexed proposalId, address indexed voter, bool inFavor, uint256 governanceTokens);
    event ProposalExecuted(uint256 indexed proposalId);

    constructor(IERC20 _usdtToken) ERC20("DAO Token", "DAOT") {
        usdtToken = _usdtToken;
    }

    // FUND //

    /* @dev Admin only function that allow the configuration of the fund: 
     _maxTotalFunding defines how much we need to raise,
     _maxParticipants sets the amount of participats,
     _maxParticipation defines the amount required for every participant */
    function setFundingStageParams(
        uint256 _maxTotalFunding,
        uint256 _maxParticipants,
        uint256 _maxParticipation
    ) external onlyOwner {
        require(_maxTotalFunding > 0, "Max total funding should be greater than 0");
        require(_maxParticipants > 0, "Max participants should be greater than 0");
        require(_maxParticipation > 0, "Max participation should be greater than 0");

        maxTotalFunding = _maxTotalFunding;
        maxParticipants = _maxParticipants;
        maxParticipation = _maxParticipation;

        emit FundingStageParamsUpdated(_maxTotalFunding, _maxParticipants, _maxParticipation);
    }

    /* This function accepts USDT tokens from users and creates and transfer governance tokens, 
    with the ratio of 1:1, keeps track of the total amount of minted governance tokens
    and the amount of governance tokens in every wallet. */
    function participate(uint256 usdtAmount) external whenNotPaused {
        require(usdtAmount > 0, "USDT amount must be greater than 0");

        // This entire If / Else logic checks the stage of the Fund
        if (fundingStage) {
            require(msg.sender != owner(), "Admin cannot participate in funding stage");
            require(totalFunding + usdtAmount <= maxTotalFunding, "Total funding limit reached");
            require(balanceOf(msg.sender) + usdtAmount <= maxParticipation, "User's maximum participation reached");
            require(currentParticipants < maxParticipants, "Maximum number of participants reached");

            // Check if the user is a new participant
            bool isNewParticipant = balanceOf(msg.sender) == 0;

            usdtToken.transferFrom(msg.sender, address(this), usdtAmount);
            _mint(msg.sender, usdtAmount);

            totalFunding += usdtAmount;

            // Increment the number of participants if the user is a new participant
            if (isNewParticipant) {
                currentParticipants++;
            }

            emit Participation(msg.sender, usdtAmount, usdtAmount);
        } else {
            require(msg.sender == owner(), "Only admin can send USDT during distribution stage");
            usdtToken.transferFrom(msg.sender, address(this), usdtAmount);
        }
    }

    /* This function changes the stage of smartcontract from funding to distribution. */
    function toggleFundingStage() external onlyOwner {
        require(totalFunding >= maxTotalFunding, "Funding stage not complete");
        fundingStage = !fundingStage;
        emit FundingStageToggled(fundingStage);
    }

    /* This function allows the admin wallet to withdraw the USDT tokens from the smartcontract during the funding stage */
    function withdrawUSDT(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        uint256 contractUSDTBalance = usdtToken.balanceOf(address(this));
        require(amount <= contractUSDTBalance, "Insufficient contract USDT balance");

        usdtToken.transfer(owner(), amount);

        emit USDTWithdrawn(owner(), amount);
    }

    /*  This function calculates the USDT profit for every participant: 
    the mathematical function is USDT per user = (total USDT amount * user governance tokens) / total governance tokens issued). 
    Then it stores the result on an array so users can claim their profits */
    function calculateUsdtShares(uint256 totalUsdt) external onlyOwner {
        require(!fundingStage, "Distribution can only happen in distribution stage");
        require(totalUsdt > 0, "Total USDT must be greater than 0");
        uint256 contractUSDTBalance = usdtToken.balanceOf(address(this));
        require(totalUsdt <= contractUSDTBalance, "Insufficient contract USDT balance");

        for (uint256 i = 0; i < currentParticipants; i++) {
            address participant = address(uint160(i));
            uint256 userGovernanceTokens = balanceOf(participant);
            uint256 userUsdtShare = (totalUsdt * userGovernanceTokens) / totalSupply();
            pendingUsdtShares[participant] = userUsdtShare;
        }

        emit DistributionUpdated(totalUsdt);
    }

    /* This function allows the participants to claim their USDT */
    function claimUsdt() external {
        uint256 userUsdtShare = pendingUsdtShares[msg.sender];
        require(userUsdtShare > 0, "No pending USDT shares to claim");

        pendingUsdtShares[msg.sender] = 0;
        usdtToken.transfer(msg.sender, userUsdtShare);

        emit USDTClaimed(msg.sender, userUsdtShare);
    }

    /* This is an internal only, no gas fee function that returns the amount of pending USDT that users have to claim */
    function getPendingUsdtShare(address user) external view returns (uint256) {
        return pendingUsdtShares[user];
    }

    // PROPOSALS //

    function createProposal(string calldata description) external whenNotPaused onlyOwner {
        require(balanceOf(msg.sender) > 0, "Only the owner can create proposals");

        uint256 proposalId = nextProposalId;
        nextProposalId++;

        proposals[proposalId].description = description;
        proposals[proposalId].votesFor = 0;
        proposals[proposalId].votesAgainst = 0;
        proposals[proposalId].endTime = block.timestamp + proposalDuration;
        proposals[proposalId].executed = false;

        emit ProposalCreated(proposalId, description, proposals[proposalId].endTime);
        }

    function voteOnProposal(uint256 proposalId, bool inFavor) external whenNotPaused {
        require(proposals[proposalId].endTime > block.timestamp, "Proposal voting has ended");
        require(!proposals[proposalId].executed, "Proposal has been executed");
        require(!hasVoted[proposalId][msg.sender], "User has already voted on this proposal");
        require(balanceOf(msg.sender) > 0, "Only governance token holders can vote");

        uint256 userGovernanceTokens = balanceOf(msg.sender);

        if (inFavor) {
            proposals[proposalId].votesFor += userGovernanceTokens;
        } else {
            proposals[proposalId].votesAgainst += userGovernanceTokens;
        }

        hasVoted[proposalId][msg.sender] = true;

        emit ProposalVoted(proposalId, msg.sender, inFavor, userGovernanceTokens);
    }
    
    /*
    function executeProposal(uint256 proposalId) external onlyOwner {
        require(proposals[proposalId].endTime <= block.timestamp, "Proposal voting is still ongoing");
        require(!proposals[proposalId].executed, "Proposal has been executed");

        // Some execution logic based on the proposal's content

        proposals[proposalId].executed = true;

        emit ProposalExecuted(proposalId);
    }
    */

    // Function to get the total number of proposals
    function getProposalCount() external view returns (uint256) {
        return nextProposalId;
    }

    // Function to get the details of a specific proposal
    function getProposal(uint256 proposalId) external view returns (
        string memory description,
        uint256 votesFor,
        uint256 votesAgainst,
        uint256 endTime,
        bool executed
    ) {
        require(proposalId < nextProposalId, "Invalid proposal ID");

        Proposal storage proposal = proposals[proposalId];
        description = proposal.description;
        votesFor = proposal.votesFor;
        votesAgainst = proposal.votesAgainst;
        endTime = proposal.endTime;
        executed = proposal.executed;
    }

    // Function to check if a user has voted on a specific proposal
    function hasUserVoted(uint256 proposalId, address user) external view returns (bool) {
        require(proposalId < nextProposalId, "Invalid proposal ID");
        return hasVoted[proposalId][user];
    }

    // Pause / Unpause the FundDao
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Operational functions
    function getParticipants() external view returns (address[] memory) {
        return participants;
    }
}