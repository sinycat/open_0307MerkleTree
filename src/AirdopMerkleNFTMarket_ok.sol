// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./MyToken.sol";
import "./MyNFT.sol";

contract AirdopMerkleNFTMarket_ok is Ownable, Multicall {
    using MerkleProof for bytes32[];

    MyToken public immutable token;
    MyNFT public immutable nft;
    uint256 public nftPrice;
    bytes32 public merkleRoot;
    mapping(address => bool) public hasClaimed;
    uint256 public totalSupply;
    uint256 public maxSupply;

    // NFT 市场相关状态变量
    struct Listing {
        address seller;
        uint256 price;
        bool isActive;
    }
    mapping(uint256 => Listing) public listings; // tokenId => Listing

    event NFTClaimed(address indexed user, uint256 tokenId, uint256 price);
    event MerkleRootUpdated(bytes32 newMerkleRoot);
    event BaseURIUpdated(string newBaseURI);
    event NFTListed(address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTUnlisted(address indexed seller, uint256 indexed tokenId);
    event NFTBought(address indexed buyer, uint256 indexed tokenId, uint256 price);

    constructor(
        address _token,
        address _nft,
        uint256 _nftPrice,
        uint256 _maxSupply
    ) Ownable(msg.sender) {
        token = MyToken(_token);
        nft = MyNFT(_nft);
        nftPrice = _nftPrice;
        maxSupply = _maxSupply;
    }

    function setNFTPrice(uint256 _nftPrice) external onlyOwner {
        nftPrice = _nftPrice;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
        emit MerkleRootUpdated(_merkleRoot);
    }

    function setBaseURI(string memory _baseURI) external onlyOwner {
        nft.setBaseURI(_baseURI);
        emit BaseURIUpdated(_baseURI);
    }

    function isWhitelisted(address user, bytes32[] calldata merkleProof) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(user));
        return MerkleProof.verify(merkleProof, merkleRoot, leaf);
    }

    function permitPrePay(
        address owner,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        token.permit(owner, address(this), value, deadline, v, r, s);
    }

    function claimNFT(bytes32[] calldata merkleProof, string calldata customURI) external {
        require(totalSupply < maxSupply, "Max supply reached");
        require(!hasClaimed[msg.sender], "Already claimed");

        bool whitelistStatus = isWhitelisted(msg.sender, merkleProof);
        uint256 finalPrice = whitelistStatus ? nftPrice / 2 : nftPrice;

        require(token.transferFrom(msg.sender, address(this), finalPrice), "Token transfer failed");

        string memory uri = bytes(customURI).length > 0 ? customURI : "";
        totalSupply += 1;
        uint256 tokenId = nft.mint(msg.sender, uri);
        hasClaimed[msg.sender] = true;

        emit NFTClaimed(msg.sender, tokenId, finalPrice);
    }

    function withdrawTokens(address to, uint256 amount) external onlyOwner {
        require(token.transfer(to, amount), "Token transfer failed");
    }

    // NFT 市场功能：上架 NFT
    function listNFT(uint256 tokenId, uint256 price) external {
        require(nft.ownerOf(tokenId) == msg.sender, "Not the owner of the NFT");
        require(price > 0, "Price must be greater than 0");
        require(!listings[tokenId].isActive, "NFT already listed");

        // 将 NFT 转移到合约中托管
        nft.transferFrom(msg.sender, address(this), tokenId);

        listings[tokenId] = Listing({
            seller: msg.sender,
            price: price,
            isActive: true
        });

        emit NFTListed(msg.sender, tokenId, price);
    }

    // NFT 市场功能：取消上架
    function unlistNFT(uint256 tokenId) external {
        Listing memory listing = listings[tokenId];
        require(listing.isActive, "NFT not listed");
        require(listing.seller == msg.sender, "Not the seller");

        // 将 NFT 转移回卖家
        nft.transferFrom(address(this), msg.sender, tokenId);

        // 删除上架信息
        delete listings[tokenId];

        emit NFTUnlisted(msg.sender, tokenId);
    }

    // NFT 市场功能：购买 NFT
    function buyNFT(uint256 tokenId) external {
        Listing memory listing = listings[tokenId];
        require(listing.isActive, "NFT not listed");

        // 转移代币给卖家
        require(token.transferFrom(msg.sender, listing.seller, listing.price), "Token transfer failed");

        // 转移 NFT 给买家
        nft.transferFrom(address(this), msg.sender, tokenId);

        // 删除上架信息
        delete listings[tokenId];

        emit NFTBought(msg.sender, tokenId, listing.price);
    }

    // 获取某个 NFT 的上架信息
    function getListing(uint256 tokenId) external view returns (Listing memory) {
        return listings[tokenId];
    }
}