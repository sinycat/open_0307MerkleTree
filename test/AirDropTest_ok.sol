// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // 引入 console.log 用于调试
import "../src/MyToken.sol";
import "../src/MyNFT.sol";
import "../src/AirdopMerkleNFTMarket.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AirDropTest_ok is Test {
    using SafeERC20 for IERC20;

    MyToken token;
    MyNFT nft;
    AirdopMerkleNFTMarket market;

    address owner = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address nonWhitelistedUser = address(0x4);

    uint256 nftPrice = 1000 * 10 ** 18; // 1000 MTK
    uint256 maxSupply = 10; // 降低最大供应量，便于测试

    // 模拟的白名单 Merkle 树数据
    bytes32 merkleRoot;
    bytes32[] user1Proof;
    bytes32[] user2Proof;

    // 离线签名所需的私钥（测试用，切勿在生产中使用）
    uint256 user1PrivateKey;
    address user1Signer;

    event NFTClaimed(address indexed user, uint256 tokenId, uint256 price);
    event MerkleRootUpdated(bytes32 newMerkleRoot);
    event BaseURIUpdated(string newBaseURI);

    function setUp() public {
        // 为 user1 生成私钥和地址
        user1PrivateKey = 0x1234;
        user1Signer = vm.addr(user1PrivateKey);
        vm.label(user1Signer, "User1Signer");

        // 部署 MyToken 合约
        vm.startPrank(owner);
        token = new MyToken();
        nft = new MyNFT();

        // 部署 AirdopMerkleNFTMarket 合约
        market = new AirdopMerkleNFTMarket(address(token), address(nft), nftPrice, maxSupply);

        // 设置 NFT 合约的 minter 为 market 合约
        nft.setMinter(address(market), true);

        // 将 MyNFT 的所有权转移给 market 合约，以便 market 可以调用 setBaseURI
        nft.transferOwnership(address(market));

        // 给测试用户分配代币
        token.mint(user1Signer, 10000 * 10 ** 18);
        token.mint(user2, 10000 * 10 ** 18);
        token.mint(nonWhitelistedUser, 10000 * 10 ** 18);
        vm.stopPrank();

        // 设置模拟的 Merkle 树（包含 user1Signer 和 user2 的白名单）
        // 修改叶子节点生成方式，与合约中的 keccak256(abi.encodePacked(user)) 一致
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = keccak256(abi.encodePacked(user1Signer));
        leaves[1] = keccak256(abi.encodePacked(user2));
        merkleRoot = getMerkleRoot(leaves);

        // 为 user1Signer 和 user2 生成 Merkle 证明
        user1Proof = getMerkleProof(leaves, 0);
        user2Proof = getMerkleProof(leaves, 1);

        // 设置 Merkle 树根
        vm.prank(owner);
        market.setMerkleRoot(merkleRoot);
    }

    // 调试函数：仅在需要时调用以打印 Merkle 树信息
    function debugMerkleTree() public view {
        console.log("Merkle Root:", uint256(merkleRoot));
        console.log("User1 Proof[0]:", uint256(user1Proof[0]));
        console.log("User2 Proof[0]:", uint256(user2Proof[0]));
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
        assertTrue(market.isWhitelisted(user2, user2Proof));
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
        // 使用不同的用户来测试最大供应量
        for (uint256 i = 0; i < maxSupply; i++) {
            address user = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            vm.startPrank(owner);
            token.mint(user, 10000 * 10 ** 18);
            vm.stopPrank();

            // 为每个用户生成白名单证明（假设所有用户都在白名单中）
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

        // 尝试再次领取，期望失败
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

        // 计算 permit 的哈希
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

        // 使用 user1 的私钥签名
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, permitHash);

        // 调用 permitPrePay
        vm.prank(user1Signer);
        market.permitPrePay(user1Signer, value, deadline, v, r, s);

        // 验证授权是否成功
        assertEq(token.allowance(user1Signer, address(market)), value);
        console.log("[SUCCESS] testPermitPrePay passed");
    }

    function testWithdrawTokens() public {
        // 先让 user1 购买一个 NFT，增加 market 合约的代币余额
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

    // 辅助函数：计算 Merkle 树根
    function getMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        require(leaves.length > 0, "No leaves provided");
        if (leaves.length == 1) return leaves[0];

        bytes32[] memory nextLevel = new bytes32[]((leaves.length + 1) / 2);
        for (uint256 i = 0; i < nextLevel.length; i++) {
            if (2 * i + 1 < leaves.length) {
                // 确保较小的哈希值在前
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

    // 辅助函数：生成 Merkle 证明
    function getMerkleProof(bytes32[] memory leaves, uint256 index) internal pure returns (bytes32[] memory) {
        require(index < leaves.length, "Index out of bounds");
        bytes32[] memory proof = new bytes32[](0);
        bytes32[] memory currentLevel = leaves;

        while (currentLevel.length > 1) {
            bytes32[] memory nextLevel = new bytes32[]((currentLevel.length + 1) / 2);
            for (uint256 i = 0; i < nextLevel.length; i++) {
                if (2 * i + 1 < currentLevel.length) {
                    bytes32 left = currentLevel[2 * i];
                    bytes32 right = currentLevel[2 * i + 1];
                    if (left > right) (left, right) = (right, left);
                    nextLevel[i] = keccak256(abi.encodePacked(left, right));
                } else {
                    nextLevel[i] = currentLevel[2 * i];
                }
            }

            // 如果当前索引是奇数，则需要前一个兄弟节点
            if (index % 2 == 1 && index < currentLevel.length) {
                proof = appendToProof(proof, currentLevel[index - 1]);
            }
            // 如果当前索引是偶数，则需要后一个兄弟节点
            else if (index % 2 == 0 && index + 1 < currentLevel.length) {
                proof = appendToProof(proof, currentLevel[index + 1]);
            }

            currentLevel = nextLevel;
            index = index / 2;
        }

        return proof;
    }

    // 辅助函数：将元素添加到证明数组中
    function appendToProof(bytes32[] memory proof, bytes32 element) internal pure returns (bytes32[] memory) {
        bytes32[] memory newProof = new bytes32[](proof.length + 1);
        for (uint256 i = 0; i < proof.length; i++) {
            newProof[i] = proof[i];
        }
        newProof[proof.length] = element;
        return newProof;
    }
}