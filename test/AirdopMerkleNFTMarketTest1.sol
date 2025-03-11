// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/MyToken.sol";
import "../src/MyNFT.sol";
import "../src/AirdopMerkleNFTMarket.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AirdopMerkleNFTMarketTest1 is Test {
    MyToken token;
    MyNFT nft;
    AirdopMerkleNFTMarket market;
    address owner;
    address user1;
    address user2;
    address user3;
    uint256 nftPrice;
    uint256 maxSupply;
    string baseURI;

    event NFTClaimed(address indexed user, uint256 tokenId, uint256 price);
    event MerkleRootUpdated(bytes32 newMerkleRoot);
    event BaseURIUpdated(string newBaseURI);

    function setUp() public {
        owner = address(this);
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        user3 = vm.addr(3);

        token = new MyToken();
        console.log("Token owner:", token.owner());
        console.log("Current address:", address(this));

        nft = new MyNFT();

        nftPrice = 100 ether;
        maxSupply = 10;
        baseURI = "https://example.com/nft/";

        market = new AirdopMerkleNFTMarket(
            address(token),
            address(nft),
            nftPrice,
            maxSupply
        );

        nft.setMinter(address(market), true);
        nft.setBaseURI(baseURI);
        nft.transferOwnership(address(market));

        vm.startPrank(owner);
        for (uint256 i = 1; i <= maxSupply; i++) {
            token.mint(vm.addr(i), 1000 ether);
        }
        vm.stopPrank();
    }

    function testDeployment() public {
        assertEq(address(market.token()), address(token));
        assertEq(address(market.nft()), address(nft));
        assertEq(market.nftPrice(), nftPrice);
        assertEq(market.maxSupply(), maxSupply);
        assertEq(nft.baseURI(), baseURI);
    }

    function testSetMerkleRoot() public {
        bytes32 newMerkleRoot = keccak256("new root");
        vm.expectEmit(true, true, true, true);
        emit MerkleRootUpdated(newMerkleRoot);
        market.setMerkleRoot(newMerkleRoot);
        assertEq(market.merkleRoot(), newMerkleRoot);
    }

    function testSetMerkleRootNonOwner() public {
        bytes32 newMerkleRoot = keccak256("new root");
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        market.setMerkleRoot(newMerkleRoot);
    }

    function testSetBaseURI() public {
        string memory newBaseURI = "https://newexample.com/nft/";
        vm.expectEmit(true, true, true, true);
        emit BaseURIUpdated(newBaseURI);
        market.setBaseURI(newBaseURI);
        assertEq(nft.baseURI(), newBaseURI);
    }

    function testSetBaseURINonOwner() public {
        string memory newBaseURI = "https://newexample.com/nft/";
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        market.setBaseURI(newBaseURI);
    }

    function testClaimNFTWhitelistedWithBaseURI() public {
        address[] memory whitelist = new address[](2);
        whitelist[0] = user1;
        whitelist[1] = user2;

        bytes32 merkleRoot = generateMerkleTree(whitelist);
        bytes32[] memory proofForUser1 = generateProof(whitelist, user1);

        market.setMerkleRoot(merkleRoot);

        (uint8 v, bytes32 r, bytes32 s) = generatePermitSignature(user1, address(market), nftPrice / 2, block.timestamp + 1 hours);

        vm.prank(user1);
        market.permitPrePay(user1, nftPrice / 2, block.timestamp + 1 hours, v, r, s);

        vm.expectEmit(true, true, true, true);
        emit NFTClaimed(user1, 1, nftPrice / 2);
        vm.prank(user1);
        market.claimNFT(proofForUser1, "");

        assertTrue(market.hasClaimed(user1));
        assertEq(market.totalSupply(), 1);
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.tokenURI(1), string(abi.encodePacked(baseURI, "1")));
    }

    function testClaimNFTWhitelistedWithCustomURI() public {
        address[] memory whitelist = new address[](2);
        whitelist[0] = user1;
        whitelist[1] = user2;

        bytes32 merkleRoot = generateMerkleTree(whitelist);
        bytes32[] memory proofForUser1 = generateProof(whitelist, user1);

        market.setMerkleRoot(merkleRoot);

        (uint8 v, bytes32 r, bytes32 s) = generatePermitSignature(user1, address(market), nftPrice / 2, block.timestamp + 1 hours);

        vm.prank(user1);
        market.permitPrePay(user1, nftPrice / 2, block.timestamp + 1 hours, v, r, s);

        string memory customURI = "https://custom.com/nft/1.json";
        vm.expectEmit(true, true, true, true);
        emit NFTClaimed(user1, 1, nftPrice / 2);
        vm.prank(user1);
        market.claimNFT(proofForUser1, customURI);

        assertTrue(market.hasClaimed(user1));
        assertEq(market.totalSupply(), 1);
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.tokenURI(1), customURI);
    }

    function testClaimNFTNonWhitelisted() public {
        address[] memory whitelist = new address[](2);
        whitelist[0] = user1;
        whitelist[1] = user2;

        bytes32 merkleRoot = generateMerkleTree(whitelist);
        market.setMerkleRoot(merkleRoot);

        (uint8 v, bytes32 r, bytes32 s) = generatePermitSignature(user3, address(market), nftPrice, block.timestamp + 1 hours);

        vm.prank(user3);
        market.permitPrePay(user3, nftPrice, block.timestamp + 1 hours, v, r, s);

        bytes32[] memory emptyProof = new bytes32[](0);
        vm.expectEmit(true, true, true, true);
        emit NFTClaimed(user3, 1, nftPrice);
        vm.prank(user3);
        market.claimNFT(emptyProof, "");

        assertTrue(market.hasClaimed(user3));
        assertEq(market.totalSupply(), 1);
        assertEq(nft.ownerOf(1), user3);
        assertEq(nft.tokenURI(1), string(abi.encodePacked(baseURI, "1")));
    }

    function testPreventDoubleClaim() public {
        address[] memory whitelist = new address[](2);
        whitelist[0] = user1;
        whitelist[1] = user2;

        bytes32 merkleRoot = generateMerkleTree(whitelist);
        bytes32[] memory proofForUser1 = generateProof(whitelist, user1);

        market.setMerkleRoot(merkleRoot);

        (uint8 v, bytes32 r, bytes32 s) = generatePermitSignature(user1, address(market), nftPrice / 2, block.timestamp + 1 hours);

        vm.prank(user1);
        market.permitPrePay(user1, nftPrice / 2, block.timestamp + 1 hours, v, r, s);

        vm.prank(user1);
        market.claimNFT(proofForUser1, "");

        vm.prank(user1);
        vm.expectRevert("Already claimed");
        market.claimNFT(proofForUser1, "");
    }

    function testMaxSupply() public {
        address[] memory whitelist = new address[](maxSupply);
        for (uint256 i = 0; i < maxSupply; i++) {
            whitelist[i] = vm.addr(i + 1);
            console.log("Whitelist[%s] = %s", i, whitelist[i]);
        }

        bytes32 merkleRoot = generateMerkleTree(whitelist);
        market.setMerkleRoot(merkleRoot);
        console.log("Set Merkle Root: %s", uint256(merkleRoot));

        bytes32[][] memory proofs = new bytes32[][](maxSupply);
        for (uint256 i = 0; i < maxSupply; i++) {
            proofs[i] = generateProof(whitelist, whitelist[i]);
            console.log("User %s Proof length: %s", i, proofs[i].length);
            for (uint256 j = 0; j < proofs[i].length; j++) {
                console.log("Proof[%s] = %s", j, uint256(proofs[i][j]));
            }
            bytes32 leaf = keccak256(abi.encodePacked(whitelist[i]));
            bool isValid = MerkleProof.verify(proofs[i], merkleRoot, leaf);
            console.log("User %s Leaf = %s", i, uint256(leaf));
            console.log("User %s isWhitelisted: %s", i, isValid);
            require(isValid, "Proof invalid for user");
        }

        for (uint256 i = 0; i < maxSupply; i++) {
            address claimant = whitelist[i];
            bytes32[] memory claimantProof = proofs[i];
            (uint8 v_, bytes32 r_, bytes32 s_) = generatePermitSignature(claimant, address(market), nftPrice / 2, block.timestamp + 1 hours);
            vm.prank(claimant);
            market.permitPrePay(claimant, nftPrice / 2, block.timestamp + 1 hours, v_, r_, s_);
            vm.prank(claimant);
            market.claimNFT(claimantProof, "");
        }

        address firstUser = whitelist[0];
        bytes32[] memory firstProof = proofs[0];
        (uint8 v, bytes32 r, bytes32 s) = generatePermitSignature(firstUser, address(market), nftPrice / 2, block.timestamp + 1 hours);
        vm.prank(firstUser);
        market.permitPrePay(firstUser, nftPrice / 2, block.timestamp + 1 hours, v, r, s);
        vm.prank(firstUser);
        vm.expectRevert("Max supply reached");
        market.claimNFT(firstProof, "");
    }

    function testWithdrawTokens() public {
        address[] memory whitelist = new address[](2);
        whitelist[0] = user1;
        whitelist[1] = user2;

        bytes32 merkleRoot = generateMerkleTree(whitelist);
        bytes32[] memory proofForUser1 = generateProof(whitelist, user1);

        market.setMerkleRoot(merkleRoot);

        (uint8 v, bytes32 r, bytes32 s) = generatePermitSignature(user1, address(market), nftPrice / 2, block.timestamp + 1 hours);
        vm.prank(user1);
        market.permitPrePay(user1, nftPrice / 2, block.timestamp + 1 hours, v, r, s);
        vm.prank(user1);
        market.claimNFT(proofForUser1, "");

        uint256 balanceBefore = token.balanceOf(owner);
        market.withdrawTokens(owner, nftPrice / 2);
        uint256 balanceAfter = token.balanceOf(owner);
        assertEq(balanceAfter - balanceBefore, nftPrice / 2);
    }

    function testWithdrawTokensNonOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        market.withdrawTokens(user1, 100);
    }

    function generateMerkleTree(address[] memory addresses) internal pure returns (bytes32) {
        bytes32[] memory leaves = new bytes32[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(addresses[i]));
            console.log("Leaf[%s] = %s", i, uint256(leaves[i]));
        }
        uint256 n = leaves.length;
        if (n == 0) {
            return bytes32(0);
        }
        while (n > 1) {
            uint256 m = (n + 1) / 2;
            bytes32[] memory temp = new bytes32[](m);
            for (uint256 i = 0; i < m; i++) {
                if (2 * i + 1 < n) {
                    bytes32 left = leaves[2 * i];
                    bytes32 right = leaves[2 * i + 1];
                    if (left < right) {
                        temp[i] = keccak256(abi.encodePacked(left, right));
                    } else {
                        temp[i] = keccak256(abi.encodePacked(right, left));
                    }
                    console.log("Node[%s] = %s", i, uint256(temp[i]));
                } else {
                    temp[i] = leaves[2 * i];
                    console.log("Node[%s] = %s (odd)", i, uint256(temp[i]));
                }
            }
            leaves = temp;
            n = m;
        }
        console.log("Merkle Root = %s", uint256(leaves[0]));
        return leaves[0];
    }

    function generateProof(address[] memory addresses, address target) internal pure returns (bytes32[] memory) {
        bytes32[] memory leaves = new bytes32[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(addresses[i]));
        }
        bytes32 leaf = keccak256(abi.encodePacked(target));
        console.log("Target Leaf = %s", uint256(leaf));

        uint256 n = leaves.length;
        require(n > 0, "Empty whitelist");

        // 找到目标 leaf 的索引
        uint256 index = 0;
        bool found = false;
        for (uint256 i = 0; i < n; i++) {
            if (leaves[i] == leaf) {
                index = i;
                found = true;
                break;
            }
        }
        require(found, "Target not in whitelist");

        // 计算 Proof
        uint256 height = 0;
        uint256 temp = n;
        while (temp > 1) {
            height++;
            temp = (temp + 1) / 2;
        }
        bytes32[] memory proof = new bytes32[](height);
        uint256 proofIndex = 0;

        while (n > 1) {
            bytes32[] memory nextLeaves = new bytes32[]((n + 1) / 2);
            for (uint256 i = 0; i < n / 2; i++) {
                bytes32 left = leaves[2 * i];
                bytes32 right = leaves[2 * i + 1];
                if (index == 2 * i) {
                    proof[proofIndex] = right;
                    console.log("Proof[%s] = %s (right sibling)", proofIndex, uint256(right));
                    proofIndex++;
                } else if (index == 2 * i + 1) {
                    proof[proofIndex] = left;
                    console.log("Proof[%s] = %s (left sibling)", proofIndex, uint256(left));
                    proofIndex++;
                }
                nextLeaves[i] = left < right ? keccak256(abi.encodePacked(left, right)) : keccak256(abi.encodePacked(right, left));
            }
            if (n % 2 == 1) {
                nextLeaves[n / 2] = leaves[n - 1];
                if (index == n - 1 && n > 1) {
                    proof[proofIndex] = leaves[n - 2];
                    console.log("Proof[%s] = %s (odd sibling)", proofIndex, uint256(leaves[n - 2]));
                    proofIndex++;
                }
            }
            leaves = nextLeaves;
            index = index / 2;
            n = (n + 1) / 2;
        }

        bytes32[] memory finalProof = new bytes32[](proofIndex);
        for (uint256 i = 0; i < proofIndex; i++) {
            finalProof[i] = proof[i];
        }
        return finalProof;
    }

    function generatePermitSignature(address tokenOwner, address spender, uint256 value, uint256 deadline) internal returns (uint8, bytes32, bytes32) {
        uint256 privateKey;
        if (tokenOwner == user1) privateKey = 1;
        else if (tokenOwner == user2) privateKey = 2;
        else if (tokenOwner == user3) privateKey = 3;
        else if (tokenOwner == vm.addr(4)) privateKey = 4;
        else if (tokenOwner == vm.addr(5)) privateKey = 5;
        else if (tokenOwner == vm.addr(6)) privateKey = 6;
        else if (tokenOwner == vm.addr(7)) privateKey = 7;
        else if (tokenOwner == vm.addr(8)) privateKey = 8;
        else if (tokenOwner == vm.addr(9)) privateKey = 9;
        else if (tokenOwner == vm.addr(10)) privateKey = 10;
        else revert("Unknown user");

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("MyToken")),
                keccak256(bytes("1")),
                block.chainid,
                address(token)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                tokenOwner,
                spender,
                value,
                token.nonces(tokenOwner),
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return (v, r, s);
    }
}