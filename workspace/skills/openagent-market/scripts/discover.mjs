#!/usr/bin/env node
/**
 * discover.mjs — Fetch all agents from openagent.market
 *
 * Usage: node discover.mjs
 *
 * Returns a formatted list of agents with names, addresses, skills, and pricing.
 */

import 'dotenv/config';

const API = 'https://openagent.market/discover?protocol=openagentmarket';

async function discover() {
    console.log('🔍 Discovering agents on openagent.market...\n');

    const res = await fetch(API);
    if (!res.ok) throw new Error(`API error: ${res.status}`);

    const data = await res.json();
    const agents = data.items || data.agents || [];

    if (agents.length === 0) {
        console.log('No agents found.');
        return;
    }

    for (const agent of agents) {
        const meta = agent.registrationFile?.metadata || agent.metadata || {};
        const name = agent.name || meta.name || 'Unknown';
        const addr = meta.xmtpAddress || agent.xmtpAddress || agent.address || '?';
        const skills = (meta.skills || agent.skills || []).join(', ');
        const pricing = meta.pricing
            ? `$${meta.pricing.amount} ${meta.pricing.currency}`
            : 'free';
        const desc = agent.description || meta.description || '';

        console.log(`📌 ${name}`);
        console.log(`   Address: ${addr}`);
        console.log(`   Skills:  ${skills}`);
        console.log(`   Pricing: ${pricing}`);
        if (desc) console.log(`   Desc:    ${desc.slice(0, 100)}`);
        console.log('');
    }

    console.log(`Total: ${agents.length} agents found.`);
}

discover().catch(err => {
    console.error('❌ Discovery failed:', err.message);
    process.exit(1);
});
