// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyNFT is ERC721, Ownable {
    uint256 private _nextTokenId;
    mapping(address => bool) public minters;
    // 添加tokenId到URI的映射
    mapping(uint256 => string) private _tokenURIs;
    // 使用不同的名称以避免与 ERC721 的 _baseURI 函数冲突
    string private _baseTokenURI;

    event NFTMinted(address indexed to, uint256 tokenId, string uri);
    event BaseURIUpdated(string newBaseURI);

    constructor() ERC721("MyNFT", "MNFT") Ownable(msg.sender) {
        _nextTokenId = 1;
        _baseTokenURI = ""; // 默认 baseURI 为空
    }

    function setMinter(address minter, bool allowed) external onlyOwner {
        minters[minter] = allowed;
    }

    function setBaseURI(string memory baseURI_) external onlyOwner {
        _baseTokenURI = baseURI_;
        emit BaseURIUpdated(baseURI_);
    }

    function mint(address to, string memory uri) external returns (uint256) {
        require(minters[msg.sender], "Caller is not a minter");
        uint256 newTokenId = _nextTokenId;
        _nextTokenId += 1;
        _mint(to, newTokenId);
        // 设置token的URI
        _setTokenURI(newTokenId, uri);
        emit NFTMinted(to, newTokenId, uri);
        return newTokenId;
    }

    // 重写tokenURI函数以返回存储的URI
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "ERC721URIStorage: URI query for nonexistent token");
        string memory tokenSpecificURI = _tokenURIs[tokenId];
        string memory base = _baseTokenURI;

        // 如果没有设置特定的 URI，则使用 baseURI + tokenId
        if (bytes(tokenSpecificURI).length == 0) {
            return bytes(base).length > 0 ? string(abi.encodePacked(base, uint2str(tokenId))) : "";
        }
        // 如果有特定的 URI，则返回它
        return tokenSpecificURI;
    }

    // 内部函数用于设置token URI
    function _setTokenURI(uint256 tokenId, string memory uri) internal virtual {
        require(_ownerOf(tokenId) != address(0), "ERC721URIStorage: URI set of nonexistent token");
        _tokenURIs[tokenId] = uri;
    }

    // 返回当前的 baseURI
    function baseURI() public view returns (string memory) {
        return _baseTokenURI;
    }

    // 辅助函数：将 uint256 转换为字符串
    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        return string(bstr);
    }

    // 重写 _baseURI 函数以返回自定义的 _baseTokenURI
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }
}