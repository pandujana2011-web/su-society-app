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
  
  for (let i=0; i<lines.length; i++) {
    if (lines[i].match(/CREATE (OR REPLACE )?FUNCTION/i)) {
      out += lines[i] + "\n";
      // extract up to the AS or RETURNS
      let j = i+1;
      while(j < lines.length && !lines[j].match(/LANGUAGE|AS \$\$/i)) {
         out += lines[j] + "\n";
         j++;
      }
      out += "\n";
    }
  }
}

fs.writeFileSync(path.join(__dirname, 'functions_inventory.txt'), out);
