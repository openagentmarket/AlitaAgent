#!/usr/bin/env node
/**
 * hire.mjs — Send a message to an agent via XMTP and handle x402 payments.
 *
 * Usage: node hire.mjs <agent-address> "<message>" [timeout-ms]
 *
 * Requires MNEMONIC in .env
 *
 * If the agent responds with a payment request (x402):
 *   1. Parses the amount and recipient
 *   2. Sends USDC on Base chain
 *   3. Sends the tx hash back
 *   4. Returns the agent's final response
 */

import { OpenAgentClient } from '@openagentmarket/nodejs';
import { Wallet, JsonRpcProvider, Contract, parseUnits } from 'ethers';
import 'dotenv/config';

const USDC_ADDRESS = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const USDC_ABI = [
    'function transfer(address,uint256) returns (bool)',
    'function decimals() view returns (uint8)',
    'function balanceOf(address) view returns (uint256)',
];
const BASE_RPC = 'https://mainnet.base.org';

async function payUSDC(recipientAddress, amount) {
    const wallet = Wallet.fromPhrase(process.env.MNEMONIC);
    const provider = new JsonRpcProvider(BASE_RPC);
    const signer = wallet.connect(provider);
    const usdc = new Contract(USDC_ADDRESS, USDC_ABI, signer);

    const decimals = Number(await usdc.decimals());
    const balance = await usdc.balanceOf(wallet.address);
    const amountWei = parseUnits(String(amount), decimals);

    if (balance < amountWei) {
        throw new Error(`Insufficient USDC. Have: ${Number(balance) / 10 ** decimals}, Need: ${amount}`);
    }

    console.error(`💸 Sending $${amount} USDC to ${recipientAddress.slice(0, 12)}...`);
    const tx = await usdc.transfer(recipientAddress, amountWei);
    console.error(`📡 Tx: ${tx.hash}`);
    await tx.wait();
    console.error(`✅ Confirmed`);
    return tx.hash;
}

function parsePaymentRequest(text) {
    // Try JSON format
    try {
        const json = JSON.parse(text);
        if (json.type === 'PAYMENT_REQUIRED' || json.result?.type === 'PAYMENT_REQUIRED') {
            const payment = json.payment || json.result?.payment;
            return { amount: payment.amount, recipient: payment.recipient };
        }
    } catch { }

    // Try natural language: "Send $0.055 USDC to 0x..."
    const match = text.match(/\$?([\d.]+)\s*USDC.*?(0x[a-fA-F0-9]{40})/i);
    if (match) return { amount: parseFloat(match[1]), recipient: match[2] };

    // Try: "Payment required" + amount + address patterns
    if (/payment.?required|pay.*to|send.*usdc/i.test(text)) {
        const amtMatch = text.match(/([\d.]+)\s*USDC/i);
        const addrMatch = text.match(/(0x[a-fA-F0-9]{40})/);
        if (amtMatch && addrMatch) {
            return { amount: parseFloat(amtMatch[1]), recipient: addrMatch[1] };
        }
    }

    return null;
}

async function main() {
    const [, , agentAddress, message, timeoutStr] = process.argv;

    if (!agentAddress || !message) {
        console.error('Usage: node hire.mjs <agent-address> "<message>" [timeout-ms]');
        process.exit(1);
    }

    if (!process.env.MNEMONIC) {
        console.error('❌ MNEMONIC not set in .env');
        process.exit(1);
    }

    const timeout = timeoutStr ? parseInt(timeoutStr) : 60000;

    const client = await OpenAgentClient.create({
        mnemonic: process.env.MNEMONIC,
        env: 'production',
    });

    console.error(`📡 Sending to ${agentAddress.slice(0, 12)}...`);

    // Send message and collect reply
    await client.sendMessage(agentAddress, message);

    const reply = await new Promise((resolve) => {
        const timer = setTimeout(() => resolve(null), timeout);
        client.streamAllMessages((sender, content) => {
            if (sender.toLowerCase() === agentAddress.toLowerCase()) {
                clearTimeout(timer);
                resolve(content);
            }
        });
    });

    if (!reply) {
        console.log('⏱️ No response within timeout.');
        process.exit(1);
    }

    // Check for payment request
    const paymentReq = parsePaymentRequest(reply);
    if (paymentReq) {
        console.error(`💰 Payment required: $${paymentReq.amount} USDC to ${paymentReq.recipient}`);

        const txHash = await payUSDC(paymentReq.recipient, paymentReq.amount);

        // Send tx hash back
        console.error(`📡 Sending tx hash to agent...`);
        await client.sendMessage(agentAddress, txHash);

        // Wait for final response
        const finalReply = await new Promise((resolve) => {
            const timer = setTimeout(() => resolve(null), timeout);
            client.streamAllMessages((sender, content) => {
                if (sender.toLowerCase() === agentAddress.toLowerCase()) {
                    clearTimeout(timer);
                    resolve(content);
                }
            });
        });

        if (finalReply) {
            console.log(finalReply);
        } else {
            console.log('⏱️ Agent verified payment but no data returned within timeout.');
        }
    } else {
        // Free agent — direct response
        console.log(reply);
    }

    process.exit(0);
}

main().catch(err => {
    console.error('❌', err.message);
    process.exit(1);
});
