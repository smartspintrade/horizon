const EVerifierTest = artifacts.require('EProverTest');
const ReceiptProofs = require('./receiptProofs.json');
const {Receipt} = require('eth-object');

describe("EProverTest test", async accounts => {
    it("verify receipts", async () => {
        const eprover = await EProverTest.new();
        const keys = Object.keys(ReceiptProofs);
        for(let i = 0; i < keys.length; i++) {
            const key = keys[i];
            const proof = ReceiptProofs[key];
            const rlpReceipts = await eprover.ValidateMPTProof(proof.root, proof.key, proof.proof);
            const receipt = Receipt.fromHex(rlpReceipts);
            assert.equal(receipt.toHex(), rlpReceipts);
        }
    })
})

