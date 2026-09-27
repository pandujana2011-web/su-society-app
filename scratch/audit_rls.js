const fs = require('fs');

const slices = [1, 2, 3, 4, 5];
let tables = new Set();
let policies = {};

for (const slice of slices) {
    const content = fs.readFileSync(`database/schema_slice${slice}.sql`, 'utf8');
    const tableMatches = content.matchAll(/CREATE TABLE IF NOT EXISTS public\.([a-zA-Z0-9_]+)/g);
    for (const match of tableMatches) {
        tables.add(match[1]);
        if (!policies[match[1]]) policies[match[1]] = [];
    }

    const policyMatches = content.matchAll(/CREATE POLICY (\w+) ON public\.([a-zA-Z0-9_]+)/g);
    for (const match of policyMatches) {
        if (!policies[match[2]]) policies[match[2]] = [];
        policies[match[2]].push(match[1]);
    }
}

for (const table of tables) {
    console.log(`Table: ${table} - Policies: ${policies[table]?.length || 0}`);
}
