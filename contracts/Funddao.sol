// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Funddao is ERC20 {
    using SafeMath for uint256;

    address public admin;
    IERC20 public usdtToken;
    uint256 public totalDepositedUSDT;

    mapping(address => uint256) public depositedUSDT;

    bytes32 public merkleRoot;
    mapping(address => bool) public claimed;

    constructor(address _usdtToken) ERC20("FunddaoGovernanceToken", "FDGT") {
        admin = msg.sender;
        usdtToken = IERC20(_usdtToken);
    }

    function deposit(uint256 usdtAmount, uint256 governanceTokensToMint) external {
        require(usdtAmount > 0, "Deposit amount must be greater than 0");
        require(governanceTokensToMint > 0, "Governance tokens to mint must be greater than 0");

        // Transfer USDT from the user to the contract
        usdtToken.transferFrom(msg.sender, address(this), usdtAmount);
        totalDepositedUSDT = totalDepositedUSDT.add(usdtAmount);
        depositedUSDT[msg.sender] = depositedUSDT[msg.sender].add(usdtAmount);

        _mint(msg.sender, governanceTokensToMint);
    }

    // function getParticipation(address user) external view returns (uint256 userDepositedUSDT, uint256 userGovernanceTokens) {
    //     userDepositedUSDT = depositedUSDT[user];
    //     userGovernanceTokens = userGovernanceTokens[user];
    // }

    function setAdmin(address newAdmin) external {
        require(msg.sender == admin, "Only the current admin can change the admin role");
        require(newAdmin != address(0), "Invalid new admin address");
        admin = newAdmin;
    }

    function withdrawUSDT(uint256 amount) external {
        require(msg.sender == admin, "Only the admin can withdraw USDT");
        require(amount <= totalDepositedUSDT, "Insufficient USDT balance in the contract");

        totalDepositedUSDT = totalDepositedUSDT.sub(amount);
        usdtToken.transfer(admin, amount);
    }

    function depositUSDTForUsers(uint256 amount) external {
        require(msg.sender == admin, "Only the admin can deposit USDT for users");
        require(amount > 0, "Deposit amount must be greater than 0");

        usdtToken.transferFrom(admin, address(this), amount);
        totalDepositedUSDT = totalDepositedUSDT.add(amount);
    }

    function setMerkleRoot(bytes32 _merkleRoot) external {
        require(msg.sender == admin, "Only the admin can set the Merkle root");
        merkleRoot = _merkleRoot;
    }

     function splitUSDT(bytes32[] calldata merkleProof) external {
        // Verify the user's Merkle proof
        bytes32 node = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), "Invalid Merkle proof");

        // Ensure the user has not already claimed their share
        require(!claimed[msg.sender], "Share already claimed");
        claimed[msg.sender] = true;

        // Calculate the user's share based on their governance tokens
        uint256 userShare = depositedUSDT[address(this)].mul(balanceOf(msg.sender)).div(totalSupply());

        // Update the user's deposited USDT balance
        depositedUSDT[msg.sender] = depositedUSDT[msg.sender].add(userShare);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "Withdraw amount must be greater than 0");
        require(depositedUSDT[msg.sender] >= amount, "Insufficient deposited USDT balance");

        depositedUSDT[msg.sender] = depositedUSDT[msg.sender].sub(amount);
        totalDepositedUSDT = totalDepositedUSDT.sub(amount);

        usdtToken.transfer(msg.sender, amount);
    }
}