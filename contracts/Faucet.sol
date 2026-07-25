// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Faucet — onchain test-token dispenser for the RWA Outlets demo (Base Sepolia)
/// @notice The faucet page (faucet.rwaoutlet.club) is a static site with no backend signer,
///         so dripping is fully onchain: anyone calls `drip()` (or `dripTo` for a fresh
///         wallet) and the contract mints every configured demo token, optionally mints the
///         ComplianceNFT KYC pass when missing, and tops up native gas while it holds ETH.
/// @dev The faucet must hold mint rights on the demo tokens: deploy them with the faucet as
///      owner, or grant it a minter role. For the ComplianceNFT it must be an operator.
interface IMintable {
    function mint(address to, uint256 amount) external;
}

interface IComplianceNFT {
    function mint(address to) external returns (uint256);
    function balanceOf(address holder) external view returns (uint256);
}

contract Faucet {
    struct Token {
        address token; // mintable ERC-20
        uint256 amount; // per-claim amount, in the token's own decimals
    }

    address public owner;
    uint256 public cooldown; // seconds between claims per recipient
    uint256 public gasStipend; // wei sent per claim while the faucet holds ETH (0 = off)
    address public complianceNFT; // optional soulbound KYC pass, minted when missing (0 = off)

    Token[] private _tokens;
    mapping(address recipient => uint256) public lastClaimAt;

    event Dripped(address indexed to, address indexed caller, uint256 timestamp);
    event TokensSet(uint256 count);
    event CooldownSet(uint256 cooldown);
    event GasStipendSet(uint256 stipend);
    event ComplianceNFTSet(address nft);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error CooldownActive(address to, uint256 readyAt);
    error NoTokensConfigured();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(uint256 cooldown_, uint256 gasStipend_) {
        owner = msg.sender;
        cooldown = cooldown_;
        gasStipend = gasStipend_;
    }

    /// @notice Fund the gas stipend pool.
    receive() external payable {}

    // ---------------------------------------------------------------- drip

    /// @notice Claim every configured token for yourself.
    function drip() external {
        _drip(msg.sender);
    }

    /// @notice Claim for a fresh wallet that has no gas yet (cooldown is keyed on `to`).
    function dripTo(address to) external {
        if (to == address(0)) revert ZeroAddress();
        _drip(to);
    }

    function _drip(address to) internal {
        uint256 n = _tokens.length;
        if (n == 0) revert NoTokensConfigured();
        uint256 readyAt = lastClaimAt[to] + cooldown;
        if (block.timestamp < readyAt) revert CooldownActive(to, readyAt);
        lastClaimAt[to] = block.timestamp;

        for (uint256 i; i < n; i++) {
            IMintable(_tokens[i].token).mint(to, _tokens[i].amount);
        }
        if (complianceNFT != address(0) && IComplianceNFT(complianceNFT).balanceOf(to) == 0) {
            IComplianceNFT(complianceNFT).mint(to);
        }
        if (gasStipend != 0 && address(this).balance >= gasStipend) {
            (bool ok,) = to.call{value: gasStipend}(""); // best-effort top-up
            ok;
        }
        emit Dripped(to, msg.sender, block.timestamp);
    }

    // --------------------------------------------------------------- views

    function allTokens() external view returns (Token[] memory) {
        return _tokens;
    }

    /// @notice Timestamp from which `to` can claim again (0-claims wallets are ready
    ///         whenever `cooldown` seconds have passed since the epoch — i.e. immediately).
    function nextClaimAt(address to) external view returns (uint256) {
        return lastClaimAt[to] + cooldown;
    }

    // --------------------------------------------------------------- admin

    function setTokens(Token[] calldata tokens_) external onlyOwner {
        delete _tokens;
        for (uint256 i; i < tokens_.length; i++) {
            if (tokens_[i].token == address(0)) revert ZeroAddress();
            _tokens.push(tokens_[i]);
        }
        emit TokensSet(tokens_.length);
    }

    function setCooldown(uint256 cooldown_) external onlyOwner {
        cooldown = cooldown_;
        emit CooldownSet(cooldown_);
    }

    function setGasStipend(uint256 stipend_) external onlyOwner {
        gasStipend = stipend_;
        emit GasStipendSet(stipend_);
    }

    function setComplianceNFT(address nft_) external onlyOwner {
        complianceNFT = nft_;
        emit ComplianceNFTSet(nft_);
    }

    function withdraw(uint256 amount) external onlyOwner {
        (bool ok,) = owner.call{value: amount}("");
        require(ok, "withdraw failed");
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
