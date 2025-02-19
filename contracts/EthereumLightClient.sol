// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7;
pragma experimental ABIEncoderV2;

import {SafeMath} from "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./EthereumLightClientStorage.sol";

import "./EthereumParser.sol";
import "./lib/EthUtils.sol";
import "./ethash/ethash.sol";

/// @title Ethereum light client
contract EthereumLightClient is EthereumLightClientStorage, Ethash {
    using SafeMath for uint256;

    struct HeaderInfo {
        uint256 total_difficulty;
        bytes32 parent_hash;
        uint64 number;
    }

    uint256 private constant DEFAULT_FINALITY_CONFIRMS = 13;

    uint256 public finalityConfirms;

    constructor(bytes memory _rlpHeader) public {
        finalityConfirms = DEFAULT_FINALITY_CONFIRMS;

        uint256 blockHash = EthereumParser.calcBlockHeaderHash(_rlpHeader);
        // Parse rlp-encoded block header into structure
        EthereumParser.BlockHeader memory header = EthereumParser
            .parseBlockHeader(_rlpHeader);
        // Save block header info
        StoredBlockHeader memory storedBlock = StoredBlockHeader({
            parentHash: header.parentHash,
            stateRoot: header.stateRoot,
            transactionsRoot: header.transactionsRoot,
            receiptsRoot: header.receiptsRoot,
            number: header.number,
            difficulty: header.difficulty,
            time: header.timestamp,
            hash: blockHash
        });
        _setFirstBlock(storedBlock);
    }

    //uint32 constant loopAccesses = 64;      // Number of accesses in hashimoto loop
    function addBlockHeader(
        bytes memory _rlpHeader,
        bytes32[4][loopAccesses] memory cache,
        bytes32[][loopAccesses] memory proofs
    ) public returns (bool) {
        // Calculate block header hash
        uint256 blockHash = EthereumParser.calcBlockHeaderHash(_rlpHeader);
        // Check block existing
        require(
            !blockExisting[blockHash],
            "Relay block failed: block already relayed"
        );

        // Parse rlp-encoded block header into structure
        EthereumParser.BlockHeader memory header = EthereumParser
            .parseBlockHeader(_rlpHeader);

        // Check the existence of parent block
        require(
            blockExisting[header.parentHash],
            "Relay block failed: parent block not relayed yet"
        );

        // Check block height
        require(
            header.number == blocks[header.parentHash].number.add(1),
            "Relay block failed: invalid block blockHeightMax"
        );

        // Check timestamp
        require(
            header.timestamp > blocks[header.parentHash].time,
            "Relay block failed: invalid timestamp"
        );

        // Check difficulty
        require(
            _checkDiffValidity(
                header.difficulty,
                blocks[header.parentHash].difficulty
            ),
            "Relay block failed: invalid difficulty"
        );

        // Verify block PoW
        uint256 sealHash = EthereumParser.calcBlockSealHash(_rlpHeader);
        bool rVerified = verifyEthash(
            bytes32(sealHash),
            uint64(header.nonce),
            uint64(header.number),
            cache,
            proofs,
            header.difficulty,
            header.mixHash
        );
        require(rVerified, "Relay block failed: invalid PoW");

        // Save block header info
        StoredBlockHeader memory storedBlock = StoredBlockHeader({
            parentHash: header.parentHash,
            stateRoot: header.stateRoot,
            transactionsRoot: header.transactionsRoot,
            receiptsRoot: header.receiptsRoot,
            number: header.number,
            difficulty: header.difficulty,
            time: header.timestamp,
            hash: blockHash
        });

        blocks[blockHash] = storedBlock;
        blockExisting[blockHash] = true;
        // verifiedBlocks[blockHash] = true;

        blocksByHeight[header.number].push(blockHash);
        blocksByHeightExisting[header.number] = true;

        if (header.number > blockHeightMax) {
            blockHeightMax = header.number;
        }

        return true;
    }

    function getBlockHeightMax() public view returns (uint256) {
        return blockHeightMax;
    }

    function getStateRoot(bytes32 blockHash) public view returns (bytes32) {
        return bytes32(blocks[uint256(blockHash)].stateRoot);
    }

    function getTxRoot(bytes32 blockHash) public view returns (bytes32) {
        return bytes32(blocks[uint256(blockHash)].transactionsRoot);
    }

    function getReceiptRoot(bytes32 blockHash) public view returns (bytes32) {
        return bytes32(blocks[uint256(blockHash)].receiptsRoot);
    }

    function VerifyReceiptsHash(bytes32 blockHash, bytes32 receiptsHash)
        external
        view
        returns (bool)
    {
        return bytes32(blocks[uint256(blockHash)].receiptsRoot) == receiptsHash;
    }

    // Check the difficulty of block is valid or not
    // (the block difficulty adjustment is described here: https://github.com/ethereum/EIPs/issues/100)
    // Note that this is only 'minimal check' because we do not have 'block uncles' information to calculate exactly.
    // 'Minimal check' is enough to prevent someone from spamming relaying blocks with quite small difficulties
    function _checkDiffValidity(uint256 diff, uint256 parentDiff)
        private
        pure
        returns (bool)
    {
        return diff >= parentDiff.sub((parentDiff / 10000) * 99);
    }

    function _setFirstBlock(StoredBlockHeader memory toSetBlock) private {
        firstBlock = toSetBlock.hash;

        blocks[toSetBlock.hash] = toSetBlock;
        blockExisting[toSetBlock.hash] = true;

        verifiedBlocks[toSetBlock.hash] = true;
        finalizedBlocks[toSetBlock.hash] = true;

        blocksByHeight[toSetBlock.number].push(toSetBlock.hash);
        blocksByHeightExisting[toSetBlock.number] = true;

        blockHeightMax = toSetBlock.number;

        longestBranchHead[toSetBlock.hash] = toSetBlock.hash;
    }

    // Set the first block
    function _defineFirstBlock()
        internal
        pure
        returns (StoredBlockHeader memory)
    {
        // Hard code the first block is #6419330
        StoredBlockHeader memory ret = StoredBlockHeader({
            parentHash: 0x65d283e7a4ea14e86404c9ad855d59b4a49a9ae4602dd80857c130a8a57de12d,
            stateRoot: 0x87c377f10bfda590c8e3bfa6a6cafeb9736a251439766196ac508cfcbc795a32,
            transactionsRoot: 0xf4cdf600a8b159e94c49f974ea2da5f05516098fab03dd231469e63982a2ab6e,
            receiptsRoot: 0xd8e77b10e522f5f2c1165c74baa0054fca5e90960cdf26b99892106f06f100f7,
            number: 6419330,
            difficulty: 2125760053,
            time: 1568874993,
            hash: 0xa73ab1a315660100b28ad2121ce7f9df8cd76d250048e5d0ff2f0f458573a1b8
        });

        return ret;
    }
}
