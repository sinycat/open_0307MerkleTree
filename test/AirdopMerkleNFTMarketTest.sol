// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AirdopMerkleNFTMarket.sol";
import "../src/MyToken.sol";
import "../src/MyNFT.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract AirdopMerkleNFTMarketTest is Test {
    AirdopMerkleNFTMarket market;
    MyToken token;
    MyNFT nft;
    uint256 constant maxSupply = 10;
    uint256 constant nftPrice = 1000 * 10**18; // 假设 1000 tokens，18 decimals
    address owner = address(this);

    function setUp() public {
        // 部署 MyToken 和 MyNFT
        token = new MyToken();
        nft = new MyNFT(); // 假设 MyNFT 有 name 和 symbol

        // 部署 AirdopMerkleNFTMarket
        market = new AirdopMerkleNFTMarket(address(token), address(nft), nftPrice, maxSupply);

        // 为 owner 分配一些 token 用于测试
        token.mint(owner, 100000 * 10**18); // 给 owner 足够的 token
    }

    function testMaxSupply() public {
        // 生成白名单地址
        address[] memory whitelist = new address[](maxSupply);
        for (uint256 i = 0; i < maxSupply; i++) {
            whitelist[i] = vm.addr(i + 1);
            console.log("Whitelist[%s] = %s", i, whitelist[i]);
        }

        // 生成叶节点
        bytes32[] memory leaves = new bytes32[](maxSupply);
        for (uint256 i = 0; i < maxSupply; i++) {
            leaves[i] = keccak256(abi.encodePacked(whitelist[i]));
            console.log("Leaf[%s] = %s", i, uint256(leaves[i]));
        }

        // 生成 Merkle Root
        bytes32 merkleRoot = generateMerkleRoot(leaves);
        market.setMerkleRoot(merkleRoot);
        console.log("Set Merkle Root: %s", uint256(merkleRoot));

        // 为每个用户生成 Proof 并验证
        for (uint256 i = 0; i < maxSupply; i++) {
            bytes32[] memory proof = generateProof(leaves, i);
            bytes32 leaf = leaves[i];
            console.log("User %s Proof length: %s", i, proof.length);
            bool isValid = MerkleProof.verify(proof, merkleRoot, leaf);
            console.log("User %s isWhitelisted: %s", i, isValid);
            if (!isValid) {
                console.log("User %s Leaf = %s", i, uint256(leaf));
                for (uint256 j = 0; j < proof.length; j++) {
                    console.log("Proof[%s] = %s", j, uint256(proof[j]));
                }
                bytes32 computedHash = leaf;
                for (uint256 j = 0; j < proof.length; j++) {
                    computedHash = keccak256(abi.encodePacked(computedHash, proof[j]));
                    console.log("Computed Hash after step %s: %s", j, uint256(computedHash));
                }
                console.log("Final Computed Hash: %s", uint256(computedHash));
                console.log("Expected Merkle Root: %s", uint256(merkleRoot));
            }
            assertTrue(isValid, "Proof invalid for user");
        }

        // 为每个用户分配 token 并授权
        for (uint256 i = 0; i < maxSupply; i++) {
            token.mint(whitelist[i], nftPrice); // 给用户足够的 token
            vm.startPrank(whitelist[i]);
            token.approve(address(market), nftPrice); // 授权 market
            vm.stopPrank();
        }

        // 模拟每个用户领取 NFT
        for (uint256 i = 0; i < maxSupply; i++) {
            bytes32[] memory proof = generateProof(leaves, i);
            vm.prank(whitelist[i]);
            market.claimNFT(proof, ""); // 使用空 URI
            assertEq(market.nft().ownerOf(i), whitelist[i], "NFT not minted to correct user");
        }

        // 检查总供应量
        assertEq(market.totalSupply(), maxSupply, "Total supply mismatch");
    }

    // 生成 Merkle Root
    function generateMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        if (leaves.length == 0) return bytes32(0);
        if (leaves.length == 1) return leaves[0];

        bytes32[] memory currentLayer = leaves;
        while (currentLayer.length > 1) {
            bytes32[] memory nextLayer = new bytes32[]((currentLayer.length + 1) / 2);
            for (uint256 i = 0; i < currentLayer.length / 2; i++) {
                nextLayer[i] = keccak256(abi.encodePacked(currentLayer[2 * i], currentLayer[2 * i + 1]));
            }
            if (currentLayer.length % 2 == 1) {
                nextLayer[nextLayer.length - 1] = currentLayer[currentLayer.length - 1];
            }
            currentLayer = nextLayer;
        }
        return currentLayer[0];
    }

    // 生成 Proof
    function generateProof(bytes32[] memory leaves, uint256 index) internal pure returns (bytes32[] memory) {
        require(index < leaves.length, "Index out of bounds");

        bytes32[] memory currentLayer = leaves;
        bytes32[] memory proof = new bytes32[](0);
        uint256 currentIndex = index;

        while (currentLayer.length > 1) {
            bytes32[] memory nextLayer = new bytes32[]((currentLayer.length + 1) / 2);
            bytes32[] memory tempProof = new bytes32[](proof.length + 1);

            // 复制现有 Proof
            for (uint256 j = 0; j < proof.length; j++) {
                tempProof[j] = proof[j];
            }

            // 添加当前层的兄弟节点
            if (currentIndex % 2 == 0 && currentIndex + 1 < currentLayer.length) {
                tempProof[proof.length] = currentLayer[currentIndex + 1]; // Right sibling
            } else if (currentIndex % 2 == 1) {
                tempProof[proof.length] = currentLayer[currentIndex - 1]; // Left sibling
            }

            proof = tempProof;

            // 计算下一层
            for (uint256 i = 0; i < currentLayer.length / 2; i++) {
                nextLayer[i] = keccak256(abi.encodePacked(currentLayer[2 * i], currentLayer[2 * i + 1]));
            }
            if (currentLayer.length % 2 == 1) {
                nextLayer[nextLayer.length - 1] = currentLayer[currentLayer.length - 1];
            }

            currentLayer = nextLayer;
            currentIndex = currentIndex / 2;
        }

        return proof;
    }
}