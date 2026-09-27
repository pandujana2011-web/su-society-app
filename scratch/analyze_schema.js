const fs = require('fs');
const path = require('path');

const dbPath = path.join(__dirname, '..', 'database');
const files = fs.readdirSync(dbPath)
  .filter(f => f.startsWith('schema_slice') && f.endsWith('.sql'))
  .sort();

let tables = {};
let currentTable = null;

for (const file of files) {
  const content = fs.readFileSync(path.join(dbPath, file), 'utf-8');
  const lines = content.split('\n');
  
  for (const line of lines) {
    const tableMatch = line.match(/CREATE TABLE(?: IF NOT EXISTS)? public\.([a-zA-Z0-9_]+)/i);
    if (tableMatch) {
      currentTable = tableMatch[1];
      tables[currentTable] = { columns: [], file: file, constraints: [] };
      continue;
    }
    
    if (currentTable) {
      if (line.trim().startsWith(');') || line.trim() === ');') {
        currentTable = null;
        continue;
      }
      
      const colLine = line.trim();
      if (!colLine || colLine.startsWith('--')) continue;
      
      if (colLine.startsWith('CONSTRAINT')) {
         tables[currentTable].constraints.push(colLine);
      } else {
         tables[currentTable].columns.push(colLine);
      }
    }
  }
}

console.log(JSON.stringify(tables, null, 2));
