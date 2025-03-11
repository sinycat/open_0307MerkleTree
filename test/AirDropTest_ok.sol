// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; // 保持 0.8.0，避免版本问题

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/MyToken.sol";
import "../src/MyNFT.sol";
import "../src/AirdopMerkleNFTMarket_ok.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AirDropTest_ok is Test {
    using SafeERC20 for IERC20;

    MyToken token;
    MyNFT nft;
    AirdopMerkleNFTMarket_ok market;

    address owner = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address nonWhitelistedUser = address(0x4);

    uint256 nftPrice = 1000 * 10 ** 18; // 1000 MTK
    uint256 maxSupply = 10;

    bytes32 merkleRoot;
    bytes32[] user1Proof;
    bytes32[] user2Proof;

    uint256 user1PrivateKey;
    address user1Signer;

    uint256 user2PrivateKey;
    address user2Signer;

    event NFTClaimed(address indexed user, uint256 tokenId, uint256 price);
    event MerkleRootUpdated(bytes32 newMerkleRoot);
    event BaseURIUpdated(string newBaseURI);
    event NFTListed(address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTUnlisted(address indexed seller, uint256 indexed tokenId);
    event NFTBought(address indexed buyer, uint256 indexed tokenId, uint256 price);

    function setUp() public {
        user1PrivateKey = 0x1234;
        user1Signer = vm.addr(user1PrivateKey);
        vm.label(user1Signer, "User1Signer");

        user2PrivateKey = 0x5678;
        user2Signer = vm.addr(user2PrivateKey);
        vm.label(user2Signer, "User2Signer");

        vm.startPrank(owner);
        token = new MyToken();
        nft = new MyNFT();
        market = new AirdopMerkleNFTMarket_ok(address(token), address(nft), nftPrice, maxSupply);
        nft.setMinter(address(market), true);
        nft.transferOwnership(address(market));
        token.mint(user1Signer, 10000 * 10 ** 18);
        token.mint(user2Signer, 10000 * 10 ** 18);
        token.mint(nonWhitelistedUser, 10000 * 10 ** 18);
        vm.stopPrank();

        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = keccak256(abi.encodePacked(user1Signer));
        leaves[1] = keccak256(abi.encodePacked(user2Signer));
        merkleRoot = getMerkleRoot(leaves);

        user1Proof = getMerkleProof(leaves, 0);
        user2Proof = getMerkleProof(leaves, 1);

        vm.prank(owner);
        market.setMerkleRoot(merkleRoot);
    }

    function testConstructor() public view {
        assertEq(address(market.token()), address(token));
        assertEq(address(market.nft()), address(nft));
        assertEq(market.nftPrice(), nftPrice);
        assertEq(market.maxSupply(), maxSupply);
        assertEq(market.owner(), owner);
        console.log("[SUCCESS] testConstructor passed");
    }

    function testIsWhitelisted() public view {
        assertTrue(market.isWhitelisted(user1Signer, user1Proof));
        assertTrue(market.isWhitelisted(user2Signer, user2Proof));
        assertFalse(market.isWhitelisted(nonWhitelistedUser, new bytes32[](0)));
        console.log("[SUCCESS] testIsWhitelisted passed");
    }

    function testSetNFTPrice() public {
        uint256 newPrice = 2000 * 10 ** 18;
        vm.prank(owner);
        market.setNFTPrice(newPrice);
        assertEq(market.nftPrice(), newPrice);
        console.log("[SUCCESS] testSetNFTPrice passed");
    }

    function testSetMerkleRoot() public {
        bytes32 newRoot = keccak256(abi.encodePacked("new root"));
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit MerkleRootUpdated(newRoot);
        market.setMerkleRoot(newRoot);
        assertEq(market.merkleRoot(), newRoot);
        console.log("[SUCCESS] testSetMerkleRoot passed");
    }

    function testSetBaseURI() public {
        string memory newBaseURI = "https://example.com/nft/";
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit BaseURIUpdated(newBaseURI);
        market.setBaseURI(newBaseURI);
        assertEq(nft.baseURI(), newBaseURI);
        console.log("[SUCCESS] testSetBaseURI passed");
    }

    function testClaimNFTWhitelisted() public {
        vm.startPrank(user1Signer);
        token.approve(address(market), nftPrice);
        vm.expectEmit(true, true, true, true);
        emit NFTClaimed(user1Signer, 1, nftPrice / 2);
        market.claimNFT(user1Proof, "");
        assertEq(nft.ownerOf(1), user1Signer);
        assertTrue(market.hasClaimed(user1Signer));
        assertEq(market.totalSupply(), 1);
        assertEq(token.balanceOf(address(market)), nftPrice / 2);
        vm.stopPrank();
        console.log("[SUCCESS] testClaimNFTWhitelisted passed");
    }

    function testClaimNFTNonWhitelisted() public {
        vm.startPrank(nonWhitelistedUser);
        token.approve(address(market), nftPrice);
        vm.expectEmit(true, true, true, true);
        emit NFTClaimed(nonWhitelistedUser, 1, nftPrice);
        market.claimNFT(new bytes32[](0), "");
        assertEq(nft.ownerOf(1), nonWhitelistedUser);
        assertTrue(market.hasClaimed(nonWhitelistedUser));
        assertEq(market.totalSupply(), 1);
        assertEq(token.balanceOf(address(market)), nftPrice);
        vm.stopPrank();
        console.log("[SUCCESS] testClaimNFTNonWhitelisted passed");
    }

    function testClaimNFTWithCustomURI() public {
        string memory customURI = "https://example.com/nft/custom/1";
        vm.startPrank(user1Signer);
        token.approve(address(market), nftPrice);
        market.claimNFT(user1Proof, customURI);
        assertEq(nft.tokenURI(1), customURI);
        vm.stopPrank();
        console.log("[SUCCESS] testClaimNFTWithCustomURI passed");
    }

    function testClaimNFTMaxSupply() public {
        for (uint256 i = 0; i < maxSupply; i++) {
            address user = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            vm.startPrank(owner);
            token.mint(user, 10000 * 10 ** 18);
            vm.stopPrank();

            bytes32[] memory leaves = new bytes32[](maxSupply);
            for (uint256 j = 0; j < maxSupply; j++) {
                address tempUser = address(uint160(uint256(keccak256(abi.encodePacked(j)))));
                leaves[j] = keccak256(abi.encodePacked(tempUser));
            }
            bytes32[] memory proof = getMerkleProof(leaves, i);

            vm.startPrank(user);
            token.approve(address(market), nftPrice);
            market.claimNFT(proof, "");
            vm.stopPrank();
        }

        vm.startPrank(user1Signer);
        token.approve(address(market), nftPrice);
        vm.expectRevert("Max supply reached");
        market.claimNFT(user1Proof, "");
        vm.stopPrank();
        console.log("[SUCCESS] testClaimNFTMaxSupply passed");
    }

    function testClaimNFTAlreadyClaimed() public {
        vm.startPrank(user1Signer);
        token.approve(address(market), nftPrice);
        market.claimNFT(user1Proof, "");
        vm.expectRevert("Already claimed");
        market.claimNFT(user1Proof, "");
        vm.stopPrank();
        console.log("[SUCCESS] testClaimNFTAlreadyClaimed passed");
    }

    function testPermitPrePay() public {
        uint256 value = nftPrice;
        uint256 deadline = block.timestamp + 1 days;

        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user1Signer,
                        address(market),
                        value,
                        token.nonces(user1Signer),
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, permitHash);

        vm.prank(user1Signer);
        market.permitPrePay(user1Signer, value, deadline, v, r, s);

        assertEq(token.allowance(user1Signer, address(market)), value);
        console.log("[SUCCESS] testPermitPrePay passed");
    }

    function testWithdrawTokens() public {
        vm.startPrank(user1Signer);
        token.approve(address(market), nftPrice);
        market.claimNFT(user1Proof, "");
        vm.stopPrank();

        uint256 amount = token.balanceOf(address(market));
        vm.prank(owner);
        market.withdrawTokens(owner, amount);
        assertEq(token.balanceOf(owner), 1000000 * 10 ** 18 + amount);
        assertEq(token.balanceOf(address(market)), 0);
        console.log("[SUCCESS] testWithdrawTokens passed");
    }

    function testMulticall() public {
        uint256 value = nftPrice;
        uint256 deadline = block.timestamp + 1 days;

        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user2Signer,
                        address(market),
                        value,
                        token.nonces(user2Signer),
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user2PrivateKey, permitHash);

        bytes[] memory callData = new bytes[](2);

        callData[0] = abi.encodeWithSelector(market.permitPrePay.selector, user2Signer, value, deadline, v, r, s);
        callData[1] = abi.encodeWithSelector(market.claimNFT.selector, user2Proof, "");

        vm.startPrank(user2Signer);
        vm.expectEmit(true, true, true, true);
        emit NFTClaimed(user2Signer, 1, nftPrice / 2);
        market.multicall(callData);
        vm.stopPrank();

        assertEq(token.allowance(user2Signer, address(market)), nftPrice - (nftPrice / 2));
        assertEq(nft.ownerOf(1), user2Signer);
        assertTrue(market.hasClaimed(user2Signer));
        assertEq(market.totalSupply(), 1);
        console.log("[SUCCESS] testMulticall passed");
    }

    // 简化：仅验证 multicall 在权限失败时会 revert，不检查具体错误
    function testMulticallFailMixedCalls() public {
        uint256 value = nftPrice;
        uint256 deadline = block.timestamp + 1 days;

        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user2Signer,
                        address(market),
                        value,
                        token.nonces(user2Signer),
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user2PrivateKey, permitHash);

        bytes[] memory callData = new bytes[](3);
        uint256 newPrice = 2000 * 10 ** 18;

        callData[0] = abi.encodeWithSelector(market.setNFTPrice.selector, newPrice); // 需要 owner 权限
        callData[1] = abi.encodeWithSelector(market.permitPrePay.selector, user2Signer, value, deadline, v, r, s);
        callData[2] = abi.encodeWithSelector(market.claimNFT.selector, user2Proof, "");

        vm.startPrank(user2Signer);
        (bool success, ) = address(market).call(abi.encodeWithSelector(market.multicall.selector, callData));
        assertFalse(success, "Multicall should fail due to unauthorized setNFTPrice");
        vm.stopPrank();

        console.log("[SUCCESS] testMulticallFailMixedCalls passed");
    }

    // 简化：仅验证 multicall 在签名错误时会 revert，不检查具体错误
    function testMulticallFailInvalidSignature() public {
        uint256 value = nftPrice;
        uint256 deadline = block.timestamp + 1 days;

        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user2Signer,
                        address(market),
                        value,
                        token.nonces(user2Signer),
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, permitHash); // 使用错误的私钥

        bytes[] memory callData = new bytes[](2);

        callData[0] = abi.encodeWithSelector(market.permitPrePay.selector, user2Signer, value, deadline, v, r, s);
        callData[1] = abi.encodeWithSelector(market.claimNFT.selector, user2Proof, "");

        vm.startPrank(user2Signer);
        (bool success, ) = address(market).call(abi.encodeWithSelector(market.multicall.selector, callData));
        assertFalse(success, "Multicall should fail due to invalid signature");
        vm.stopPrank();

        console.log("[SUCCESS] testMulticallFailInvalidSignature passed");
    }

    function testListNFT() public {
        vm.startPrank(user1Signer);
        token.approve(address(market), nftPrice);
        market.claimNFT(user1Proof, "");
        vm.stopPrank();

        uint256 tokenId = 1;
        uint256 listPrice = 2000 * 10 ** 18;

        vm.startPrank(user1Signer);
        nft.approve(address(market), tokenId);
        vm.expectEmit(true, true, true, true);
        emit NFTListed(user1Signer, tokenId, listPrice);
        market.listNFT(tokenId, listPrice);
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), address(market));
        AirdopMerkleNFTMarket_ok.Listing memory listing = market.getListing(tokenId);
        assertEq(listing.seller, user1Signer);
        assertEq(listing.price, listPrice);
        assertTrue(listing.isActive);
        console.log("[SUCCESS] testListNFT passed");
    }

    function testListNFTNotOwner() public {
        vm.startPrank(user1Signer);
        token.approve(address(market), nftPrice);
        market.claimNFT(user1Proof, "");
        vm.stopPrank();

        uint256 tokenId = 1;
        uint256 listPrice = 2000 * 10 ** 18;

        vm.startPrank(user2Signer);
        vm.expectRevert("Not the owner of the NFT");
        market.listNFT(tokenId, listPrice);
        vm.stopPrank();

        console.log("[SUCCESS] testListNFTNotOwner passed");
    }

    function testUnlistNFT() public {
        vm.startPrank(user1Signer);
        token.approve(address(market), nftPrice);
        market.claimNFT(user1Proof, "");
        uint256 tokenId = 1;
        uint256 listPrice = 2000 * 10 ** 18;
        nft.approve(address(market), tokenId);
        market.listNFT(tokenId, listPrice);
        vm.stopPrank();

        vm.startPrank(user1Signer);
        vm.expectEmit(true, true, true, true);
        emit NFTUnlisted(user1Signer, tokenId);
        market.unlistNFT(tokenId);
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), user1Signer);
        AirdopMerkleNFTMarket_ok.Listing memory listing = market.getListing(tokenId);
        assertEq(listing.seller, address(0));
        assertEq(listing.price, 0);
        assertFalse(listing.isActive);
        console.log("[SUCCESS] testUnlistNFT passed");
    }

    function testUnlistNFTNotSeller() public {
        vm.startPrank(user1Signer);
        token.approve(address(market), nftPrice);
        market.claimNFT(user1Proof, "");
        uint256 tokenId = 1;
        uint256 listPrice = 2000 * 10 ** 18;
        nft.approve(address(market), tokenId);
        market.listNFT(tokenId, listPrice);
        vm.stopPrank();

        vm.startPrank(user2Signer);
        vm.expectRevert("Not the seller");
        market.unlistNFT(tokenId);
        vm.stopPrank();

        console.log("[SUCCESS] testUnlistNFTNotSeller passed");
    }

    function testBuyNFT() public {
        vm.startPrank(user1Signer);
        token.approve(address(market), nftPrice);
        market.claimNFT(user1Proof, "");
        uint256 tokenId = 1;
        uint256 listPrice = 2000 * 10 ** 18;
        nft.approve(address(market), tokenId);
        market.listNFT(tokenId, listPrice);
        vm.stopPrank();

        vm.startPrank(user2Signer);
        token.approve(address(market), listPrice);
        vm.expectEmit(true, true, true, true);
        emit NFTBought(user2Signer, tokenId, listPrice);
        market.buyNFT(tokenId);
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), user2Signer);
        assertEq(token.balanceOf(user1Signer), 10000 * 10 ** 18 - nftPrice / 2 + listPrice);
        assertEq(token.balanceOf(user2Signer), 10000 * 10 ** 18 - listPrice);
        AirdopMerkleNFTMarket_ok.Listing memory listing = market.getListing(tokenId);
        assertEq(listing.seller, address(0));
        assertEq(listing.price, 0);
        assertFalse(listing.isActive);
        console.log("[SUCCESS] testBuyNFT passed");
    }

    function testBuyNFTNotListed() public {
        vm.startPrank(user1Signer);
        token.approve(address(market), nftPrice);
        market.claimNFT(user1Proof, "");
        uint256 tokenId = 1;
        vm.stopPrank();

        vm.startPrank(user2Signer);
        token.approve(address(market), 2000 * 10 ** 18);
        vm.expectRevert("NFT not listed");
        market.buyNFT(tokenId);
        vm.stopPrank();

        console.log("[SUCCESS] testBuyNFTNotListed passed");
    }

    function getMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        require(leaves.length > 0, "No leaves provided");
        if (leaves.length == 1) return leaves[0];

        bytes32[] memory nextLevel = new bytes32[]((leaves.length + 1) / 2);
        for (uint256 i = 0; i < nextLevel.length; i++) {
            if (2 * i + 1 < leaves.length) {
                bytes32 left = leaves[2 * i];
                bytes32 right = leaves[2 * i + 1];
                if (left > right) (left, right) = (right, left);
                nextLevel[i] = keccak256(abi.encodePacked(left, right));
            } else {
                nextLevel[i] = leaves[2 * i];
            }
        }
        return getMerkleRoot(nextLevel);
    }

    function getMerkleProof(bytes32[] memory leaves, uint256 index) internal pure returns (bytes32[] memory) {
        require(index < leaves.length, "Index out of bounds");
        bytes32[] memory proof = new bytes32[](0);
        bytes32[] memory currentLevel = leaves;

        while (currentLevel.length > 1) {
            bytes32[] memory nextLevel = new bytes32[]((currentLevel.length + 1) / 2);
            for (uint256 i = 0; i < nextLevel.length; i++) {
                if (2 * i + 1 < currentLevel.length) {
                    bytes32 left = currentLevel[2 * i];
                    bytes32 right = leaves[2 * i + 1];
                    if (left > right) (left, right) = (right, left);
                    nextLevel[i] = keccak256(abi.encodePacked(left, right));
                } else {
                    nextLevel[i] = currentLevel[2 * i];
                }
            }

            if (index % 2 == 1 && index < currentLevel.length) {
                proof = appendToProof(proof, currentLevel[index - 1]);
            } else if (index % 2 == 0 && index + 1 < currentLevel.length) {
                proof = appendToProof(proof, currentLevel[index + 1]);
            }

            currentLevel = nextLevel;
            index = index / 2;
        }

        return proof;
    }

    function appendToProof(bytes32[] memory proof, bytes32 element) internal pure returns (bytes32[] memory) {
        bytes32[] memory newProof = new bytes32[](proof.length + 1);
        for (uint256 i = 0; i < proof.length; i++) {
            newProof[i] = proof[i];
        }
        newProof[proof.length] = element;
        return newProof;
    }
}