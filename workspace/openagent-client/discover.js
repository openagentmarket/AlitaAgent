import 'dotenv/config';

const DISCOVER_API = "https://openagent.market/discover";

function hexToUtf8(hex) {
    if (!hex || !hex.startsWith('0x')) return hex;
    const clean = hex.slice(2);
    let str = '';
    for (let i = 0; i < clean.length; i += 2) {
        str += String.fromCharCode(parseInt(clean.substr(i, 2), 16));
    }
    return str;
}

async function main() {
    console.log('Discovering agents from openagent.market...\n');

    const res = await fetch(DISCOVER_API);
    if (!res.ok) {
        console.error(`Failed: ${res.status} ${res.statusText}`);
        process.exit(1);
    }

    const data = await res.json();
    const agents = data.items || data.agents || data;

    console.log(`Found ${agents.length} agents:\n`);

    const parsed = [];

    for (const agent of agents) {
        const reg = agent.registrationFile || {};
        const name = reg.name || 'Unknown';
        const desc = (reg.description || '').substring(0, 80);

        // Find XMTP address from metadata
        const xmtpMeta = (agent.metadata || []).find(m => m.key === 'xmtpAddress');
        const xmtpAddress = xmtpMeta ? hexToUtf8(xmtpMeta.value) : (agent.owner || '?');

        // Find pricing from metadata
        const pricingMeta = (agent.metadata || []).find(m => m.key === 'pricing');
        let price = 'Free';
        if (pricingMeta) {
            try { price = JSON.parse(hexToUtf8(pricingMeta.value)).amount || 'Free'; } catch { }
        }

        // Find skills from metadata
        const skillsMeta = (agent.metadata || []).find(m => m.key === 'skills');
        let skills = [];
        if (skillsMeta) {
            try { skills = JSON.parse(hexToUtf8(skillsMeta.value)); } catch { }
        }

        parsed.push({
            name,
            xmtpAddress,
            description: desc,
            price,
            skills,
            agentId: agent.agentId
        });

        console.log(`  🤖 ${name}`);
        console.log(`     XMTP: ${xmtpAddress}`);
        console.log(`     Price: ${price} USDC`);
        console.log(`     Skills: ${skills.join(', ') || 'chat'}`);
        console.log(`     ${desc}`);
        console.log('');
    }

    // Output JSON for programmatic use
    console.log('--- JSON ---');
    console.log(JSON.stringify(parsed, null, 2));
}

main().catch(console.error);
