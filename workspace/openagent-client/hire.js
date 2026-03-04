import { OpenAgentClient } from '@openagentmarket/nodejs';
import { Wallet, JsonRpcProvider, Contract, parseUnits } from 'ethers';
import 'dotenv/config';

// Base USDC
const USDC_ADDRESS = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const USDC_ABI = [
    'function transfer(address to, uint256 amount) returns (bool)',
    'function balanceOf(address owner) view returns (uint256)',
    'function decimals() view returns (uint8)'
];
const BASE_RPC = process.env.BASE_RPC_URL || 'https://mainnet.base.org';

const agentAddress = process.argv[2];
const task = process.argv.slice(3).join(' ');

if (!agentAddress || !task) {
    console.error('Usage: node hire.js 0xAGENT "task description"');
    process.exit(1);
}

const TIMEOUT = parseInt(process.env.TIMEOUT || '60000');

async function sendUSDC(wallet, to, amount) {
    console.log(`💸 Sending $${amount} USDC to ${to} on Base...`);
    const provider = new JsonRpcProvider(BASE_RPC);
    const signer = wallet.connect(provider);
    const usdc = new Contract(USDC_ADDRESS, USDC_ABI, signer);
    const decimals = await usdc.decimals();
    const amountWei = parseUnits(String(amount), decimals);
    const balance = await usdc.balanceOf(wallet.address);
    console.log(`   Balance: ${(Number(balance) / 10 ** decimals).toFixed(4)} USDC`);
    if (balance < amountWei) {
        throw new Error(`Insufficient USDC. Need ${amount}, have ${(Number(balance) / 10 ** decimals).toFixed(4)}`);
    }
    const tx = await usdc.transfer(to, amountWei);
    console.log(`   Tx sent: ${tx.hash}`);
    await tx.wait();
    console.log(`   ✅ Confirmed!`);
    return tx.hash;
}

async function main() {
    const wallet = Wallet.fromPhrase(process.env.MNEMONIC);
    const client = await OpenAgentClient.create({
        mnemonic: process.env.MNEMONIC,
        env: 'production',
    });

    console.log(`🤖 Hiring agent ${agentAddress}`);
    console.log(`📋 Task: "${task}"`);
    console.log(`💰 Wallet: ${wallet.address}`);
    console.log(`⏱️  Timeout: ${TIMEOUT}ms\n`);

    // Listen for replies via stream
    let gotReply = false;
    await client.streamAllMessages((sender, content, convId) => {
        if (!content || !content.trim()) return;
        gotReply = true;

        // Check if PAYMENT_REQUIRED
        try {
            const json = JSON.parse(content);
            if (json.type === 'PAYMENT_REQUIRED' && json.payment) {
                const pay = json.payment;
                console.log(`⚡ Payment required: $${pay.amount} ${pay.currency} to ${pay.recipient}`);
                sendUSDC(wallet, pay.recipient, pay.amount).then(txHash => {
                    console.log(`🔄 Retrying with payment proof...`);
                    const retry = JSON.stringify({ method: 'query', params: { query: task }, payment: { txHash } });
                    client.sendMessage(agentAddress, retry);
                }).catch(err => {
                    console.error('❌ Payment failed:', err.message);
                    process.exit(1);
                });
                return;
            }
        } catch { }

        // Regular reply
        console.log(`📨 Agent reply:\n${content}\n`);
        setTimeout(() => process.exit(0), 2000);
    });

    // Send plain text message
    console.log('📤 Sending message...');
    await client.sendMessage(agentAddress, task);
    console.log('✅ Sent! Waiting for reply...\n');

    // Timeout
    setTimeout(() => {
        if (!gotReply) console.log('⚠️ No reply within timeout.');
        process.exit(gotReply ? 0 : 1);
    }, TIMEOUT);
}

main().catch(e => {
    console.error('❌ Error:', e.message);
    process.exit(1);
});
