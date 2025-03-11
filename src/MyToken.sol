// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyToken is ERC20, ERC20Permit, Ownable {
    uint256 public constant MAX_SUPPLY = 10_000_000 * 10 ** 18; // 添加最大供应量
    
    event TokensMinted(address indexed to, uint256 amount);

    constructor()
        ERC20("MyToken", "MTK")
        ERC20Permit("MyToken")
        Ownable(msg.sender)
    {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }
}