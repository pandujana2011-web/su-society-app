const fs = require('fs');
const path = require('path');

const dbPath = path.join(__dirname, '..', 'database');
const files = fs.readdirSync(dbPath)
  .filter(f => f.startsWith('schema_slice') && f.endsWith('.sql'))
  .sort();

let out = "";
for (const file of files) {
  const content = fs.readFileSync(path.join(dbPath, file), 'utf-8');
  out += `\n\n--- FILE: ${file} ---\n`;
  const lines = content.split('\n');
  
  let currentTable = null;
  for (const line of lines) {
    const tableMatch = line.match(/CREATE TABLE(?: IF NOT EXISTS)? public\.([a-zA-Z0-9_]+)/i);
    if (tableMatch) {
      currentTable = tableMatch[1];
      out += `\nTABLE: ${currentTable}\n`;
      continue;
    }
    
    if (currentTable) {
      if (line.trim().startsWith(');') || line.trim() === ');') {
        currentTable = null;
        continue;
      }
      
      const colLine = line.trim();
      if (!colLine || colLine.startsWith('--')) continue;
      
      out += `  ${colLine}\n`;
    }
  }
}

fs.writeFileSync(path.join(__dirname, 'schema_inventory.txt'), out);
